#!/usr/bin/env python3
"""End-to-end checks for the modal loop and the card cache builder."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from lib.db import connect, execute, fetch_one, request  # noqa: E402

SQLCMD = "/opt/mssql-tools18/bin/sqlcmd"
passed = 0


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def apply(script):
    env = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    cmd = [
        SQLCMD,
        "-S", env["SQL_SERVER"],
        "-C",
        "-U", env["SQL_USER"],
        "-P", env["SQL_PASSWORD"],
        "-b",
        "-f", "65001",
        "-i", str(ROOT / "sql" / script),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{script} failed\n{result.stdout}\n{result.stderr}")


def apply_all():
    for name in sorted(p.name for p in (ROOT / "sql").glob("*.sql")):
        print(f"apply {name}")
        apply(name)


def controls(payload):
    return (payload.get("modal") or {}).get("controls") or []


def texts(payload):
    return [item.get("text") for item in controls(payload) if item.get("kind") == "text"]


def toast_text(payload):
    return [item.get("text") for item in payload.get("toasts") or []]


def note_count(note=None):
    if note is None:
        row = fetch_one("SELECT COUNT(*) AS n FROM demo.dbo.customer_note")
    else:
        row = fetch_one(
            "SELECT COUNT(*) AS n FROM demo.dbo.customer_note WHERE note = ?",
            [note],
        )
    return row["n"]


def card_id(name="customer"):
    return fetch_one("SELECT id FROM dbo.api_card WHERE name = ?", [name])["id"]


def test_cache_shape():
    row = fetch_one(
        """
        SELECT list_select_cache, select_cache, declare_cache, error
        FROM dbo.api_card WHERE name = N'customer'
        """
    )
    check(row["error"] is None, row["error"])
    check("place_label" in row["list_select_cache"], "list cache missing place_label")
    check("CONCAT(customer_name, N' - ', city)" in row["list_select_cache"], "expression not compiled")
    check("FROM [demo].[dbo].[v_customer] AS t" in row["list_select_cache"], "list source")
    check("WHERE (1 = 1)" in row["list_select_cache"], "list predicate")
    check("DECLARE @id int;" in row["declare_cache"], "id declare")
    check("DECLARE @credit_limit decimal(18,2);" in row["declare_cache"], "decimal declare")
    check("DECLARE @customer_name nvarchar(200);" in row["declare_cache"], "name declare")
    check("DECLARE @place_label" not in row["declare_cache"], "list-only field leaked into declare")
    check("TRY_CONVERT(int, @id_text)" in row["select_cache"], "id bind")
    check("WHERE t.[id] = @id" in row["select_cache"], "form predicate")
    check("place_label" not in row["select_cache"], "list-only field leaked into select")
    synonym = fetch_one(
        "SELECT base_object_name FROM sys.synonyms WHERE name = N'v_customer'"
    )
    check(synonym is not None, "synonym missing")
    check("demo" in synonym["base_object_name"].lower(), synonym["base_object_name"])
    check("v_customer" in synonym["base_object_name"].lower(), synonym["base_object_name"])


def test_no_id():
    execute(
        """
        INSERT INTO dbo.api_card (name, tablename, id_column)
        VALUES (N'no_id_card', N'v_customer', NULL)
        """
    )
    cid = card_id("no_id_card")
    failed = False
    try:
        with connect() as conn:
            conn.cursor().execute(
                "EXEC dbo.sp_api_card_create_cache @card_id = ?, @toast = 0",
                cid,
            )
    except Exception as exc:
        failed = True
        check("sp_api_card_create_cache NO ID!" in str(exc), str(exc))
    check(failed, "missing id_column should raise")
    row = fetch_one("SELECT error, list_select_cache FROM dbo.api_card WHERE id = ?", [cid])
    check(row["error"] == "sp_api_card_create_cache NO ID!", row["error"])
    check(row["list_select_cache"] is None, "cache should stay empty")
    execute("DELETE FROM dbo.api_card WHERE id = ?", [cid])


def test_cache_is_what_runs_and_invalid_field_keeps_old_sql():
    payload = request(pathname="/customer")
    rows = payload["data"]
    check(len(rows) == 3, rows)
    check([row["customer_name"] for row in rows] == ["Ada Lovegrove", "Ben Hart", "Chi Ortega"], rows)
    ada = rows[0]
    check(ada["place_label"] == "Ada Lovegrove - Amsterdam", ada)
    check(any(view["comp"] == "Listview" for view in payload["views"]), payload["views"])
    check(any(field["name"] == "place_label" and field["is_hid"] is False for field in payload["def"]), payload["def"])
    check(any(field["name"] == "id" and field["is_hid"] is True for field in payload["def"]), "id should be hidden on the list")

    cid = card_id()
    before = fetch_one("SELECT list_select_cache FROM dbo.api_card WHERE id = ?", [cid])["list_select_cache"]
    execute(
        """
        UPDATE dbo.api_card_fields
        SET sql = N'CONCAT(customer_name, N'' / '', city)'
        WHERE card_id = ? AND name = N'place_label'
        """,
        [cid],
    )
    stale = request(pathname="/customer")
    check(stale["data"][0]["place_label"] == "Ada Lovegrove - Amsterdam", stale["data"][0])

    execute(
        """
        INSERT INTO dbo.api_card_fields (card_id, name, list_order, detail_order)
        VALUES (?, N'nope', 20, 0)
        """,
        [cid],
    )
    failed = False
    try:
        with connect() as conn:
            conn.cursor().execute("EXEC dbo.sp_api_card_create_cache @card_id = ?, @toast = 0", cid)
    except Exception as exc:
        failed = True
        check("nope" in str(exc), str(exc))
    check(failed, "unknown field should fail the build")
    after = fetch_one("SELECT list_select_cache, error FROM dbo.api_card WHERE id = ?", [cid])
    check(after["list_select_cache"] == before, "failed build replaced the cache")
    check(after["error"] and "nope" in after["error"], after["error"])

    execute("DELETE FROM dbo.api_card_fields WHERE card_id = ? AND name = N'nope'", [cid])
    execute(
        """
        UPDATE dbo.api_card_fields
        SET sql = N'CONCAT(customer_name, N'' / '', city)'
        WHERE card_id = ? AND name = N'place_label'
        """,
        [cid],
    )
    with connect() as conn:
        conn.cursor().execute("EXEC dbo.sp_api_card_create_cache @card_id = ?, @toast = 0", cid)
    rebuilt = request(pathname="/customer")
    check(rebuilt["data"][0]["place_label"] == "Ada Lovegrove / Amsterdam", rebuilt["data"][0])

    execute(
        "UPDATE dbo.api_card SET reducer = N'status = N''open''' WHERE id = ?",
        [cid],
    )
    with connect() as conn:
        conn.cursor().execute("EXEC dbo.sp_api_card_create_cache @card_id = ?, @toast = 0", cid)
    cached = fetch_one("SELECT list_select_cache FROM dbo.api_card WHERE id = ?", [cid])["list_select_cache"]
    check("status = N'open'" in cached, cached)
    opened = request(pathname="/customer")
    check([row["customer_name"] for row in opened["data"]] == ["Ada Lovegrove", "Chi Ortega"], opened["data"])

    execute("UPDATE dbo.api_card SET reducer = NULL WHERE id = ?", [cid])
    execute(
        """
        UPDATE dbo.api_card_fields
        SET sql = N'CONCAT(customer_name, N'' - '', city)'
        WHERE card_id = ? AND name = N'place_label'
        """,
        [cid],
    )
    with connect() as conn:
        conn.cursor().execute("EXEC dbo.sp_api_card_create_cache @card_id = ?, @toast = 0", cid)


def test_form_uses_select_cache():
    listed = request(pathname="/customer")
    ada_id = listed["data"][0]["id"]
    form = request(pathname=f"/customer/{ada_id}")
    check(any(view["comp"] == "Detailview" for view in form["views"]), form["views"])
    check(form["data"][0]["customer_name"] == "Ada Lovegrove", form["data"])
    check(form["data"][0]["credit_limit"] == 1200.5, form["data"])
    check("place_label" not in form["data"][0], form["data"])
    check(any(field["name"] == "customer_name" and field["is_hid"] is False for field in form["def"]), form["def"])
    missing = request(pathname="/customer/99999")
    check(missing["data"] == [], missing["data"])


def test_modal_loop():
    session = request(pathname="/customer")["session"]
    first = request(session=session, pathname="/customer", action="sp_example_minimal_modal", id=1)
    kinds = [item["kind"] for item in controls(first)]
    check(kinds[0] == "modal", kinds)
    check("text" in kinds and "input" in kinds and "button" in kinds, kinds)
    inputs = [item for item in controls(first) if item["kind"] == "input"]
    check(inputs[0]["name"] == "@my_value", inputs[0])
    check(inputs[0]["value"] is None, inputs[0])
    check(first["modal"] is not None and first["cleared"] is False, first)
    check(note_count() == 0, "note written on first paint")

    empty = request(
        session=session,
        pathname="/customer",
        posted={"@my_value": "", "@btn_save": "Save"},
        id=1,
    )
    check(empty["cleared"] is False, empty)
    check("Value is required" in toast_text(empty), empty["toasts"])
    check(any(item["kind"] == "input" for item in controls(empty)), "modal did not re-render")
    check(note_count() == 0, "empty submit wrote a note")

    saved = request(
        session=session,
        pathname="/customer",
        posted={"@my_value": "café note", "@btn_save": "Save"},
        id=1,
    )
    check(saved["cleared"] is True, saved)
    check(saved["modal"] is None, saved["modal"])
    check("Saved successfully" in toast_text(saved), saved["toasts"])
    check(note_count("café note") == 1, "saved note missing")

    fresh = request(session=session, pathname="/customer", action="sp_example_minimal_modal", id=1)
    again = [item for item in controls(fresh) if item["kind"] == "input"]
    check(again[0]["value"] is None, again[0])
    check(fresh["cleared"] is False, fresh)


def test_render_before_read_loses_click():
    cid = card_id()
    execute(
        """
        INSERT INTO dbo.api_card_actions (card_id, name, display_name, action, sql, type, action_order)
        VALUES (?, N'sp_bad_order', N'Bad order', N'stored_procedure', ?, N'list', 90)
        """,
        [cid, """
DECLARE @captured nvarchar(128);
DECLARE @seen nvarchar(128);
EXEC dbo.sp_api_modal_modal;
DECLARE @n nvarchar(128) = N'@btn_save';
DECLARE @v nvarchar(128) = N'Save';
DECLARE @c nvarchar(128) = N'btn-primary';
EXEC dbo.sp_api_modal_button @name = @n, @value = @v, @out = @captured OUTPUT, @class = @c;
EXEC dbo.sp_api_modal_get_value @name = @n, @value = @seen OUTPUT;
DECLARE @msg nvarchar(200);
IF @captured IS NOT NULL AND @seen IS NULL
    SET @msg = N'click-lost';
ELSE
    SET @msg = N'unexpected';
EXEC dbo.sp_api_toast @text = @msg;
"""],
    )
    opened = request(pathname="/customer", action="sp_bad_order")
    posted = request(
        session=opened["session"],
        pathname="/customer",
        posted={"@btn_save": "Save"},
    )
    check("click-lost" in toast_text(posted), posted["toasts"])
    execute("DELETE FROM dbo.api_card_actions WHERE name = N'sp_bad_order'")


def test_pre_declare():
    cid = card_id()
    execute(
        """
        INSERT INTO dbo.api_card_actions (
            card_id, name, display_name, action, sql, pre_declare, type, action_order
        )
        VALUES (?, N'sp_pre', N'Pre', N'stored_procedure', ?, N'@my_value, @btn_save', N'list', 91)
        """,
        [cid, """
IF @btn_save IS NOT NULL
BEGIN
    EXEC dbo.sp_api_toast @text = @my_value;
    EXEC dbo.sp_api_modal_clear;
    RETURN;
END
EXEC dbo.sp_api_modal_modal;
"""],
    )
    opened = request(pathname="/customer", action="sp_pre")
    done = request(
        session=opened["session"],
        pathname="/customer",
        posted={"@my_value": "from-predeclare", "@btn_save": "Save"},
    )
    check(done["cleared"] is True, done)
    check("from-predeclare" in toast_text(done), done["toasts"])
    execute("DELETE FROM dbo.api_card_actions WHERE name = N'sp_pre'")


def test_wizard_and_session_survival():
    execute(
        """
        INSERT INTO dbo.api_card_actions (card_id, name, display_name, action, sql, type, action_order)
        VALUES (?, N'sp_keep', N'Keep', N'stored_procedure', N'EXEC dbo.sp_api_modal_set @name = N''keep_me'', @value = N''yes'';', N'hidden', 92)
        """,
        [card_id()],
    )
    started = request(pathname="/customer", action="sp_keep", id=1)
    session = started["session"]
    step1 = request(session=session, pathname="/customer", action="sp_example_wizard", id=1)
    check(any(item.get("text") == "Step 1 - name" for item in controls(step1)), texts(step1))

    missing = request(session=session, pathname="/customer", posted={"@name": "", "@btn_next": "Next"}, id=1)
    check("Name is required" in toast_text(missing), missing["toasts"])
    check(any(item.get("text") == "Step 1 - name" for item in controls(missing)), texts(missing))

    step2 = request(
        session=session,
        pathname="/customer",
        posted={"@name": "Ada", "@btn_next": "Next"},
        id=1,
    )
    check(any(item.get("text") == "Name: Ada" for item in controls(step2)), texts(step2))

    back = request(session=session, pathname="/customer", posted={"@btn_back": "Back"}, id=1)
    name_input = [item for item in controls(back) if item.get("kind") == "input"]
    check(name_input and name_input[0]["value"] == "Ada", name_input)

    request(session=session, pathname="/customer", posted={"@name": "Ada", "@btn_next": "Next"}, id=1)
    saved = request(
        session=session,
        pathname="/customer",
        posted={"@email": "ada@example.com", "@btn_save": "Save"},
        id=1,
    )
    check(saved["cleared"] is True, saved)
    check("Wizard saved" in toast_text(saved), saved["toasts"])
    check(note_count("Ada <ada@example.com>") == 1, "wizard note missing")
    stored = fetch_one(
        """
        SELECT COUNT(*) AS n
        FROM dbo.api_session_storage AS s
        JOIN dbo.api_session AS sess ON sess.id = s.session_id
        WHERE sess.token = ? AND s.name IN (N'wizard_step', N'wizard_name')
        """,
        [session],
    )
    check(stored["n"] == 0, "wizard keys survived a successful clear")
    kept = fetch_one(
        """
        SELECT s.value
        FROM dbo.api_session_storage AS s
        JOIN dbo.api_session AS sess ON sess.id = s.session_id
        WHERE sess.token = ? AND s.name = N'keep_me'
        """,
        [session],
    )
    check(kept and kept["value"] == "yes", kept)
    execute("DELETE FROM dbo.api_card_actions WHERE name = N'sp_keep'")


def test_crud_gate_and_menu():
    cid = card_id()
    execute("UPDATE dbo.api_card SET crud_read = N'1=0' WHERE id = ?", [cid])
    denied = request(pathname="/customer")
    check(denied["error"] == "Read is not allowed for this card.", denied)
    check(denied["data"] == [], denied["data"])
    execute("UPDATE dbo.api_card SET crud_read = NULL WHERE id = ?", [cid])
    menu = request(pathname="/")
    check(menu["views"][0]["comp"] == "Actions", menu["views"])
    check(any(row["name"] == "customer" and row["path"] == "/customer" for row in menu["data"]), menu["data"])


def main():
    global passed
    apply_all()
    tests = [
        test_cache_shape,
        test_no_id,
        test_cache_is_what_runs_and_invalid_field_keeps_old_sql,
        test_form_uses_select_cache,
        test_modal_loop,
        test_render_before_read_loses_click,
        test_pre_declare,
        test_wizard_and_session_survival,
        test_crud_gate_and_menu,
    ]
    try:
        for test in tests:
            print(f"run {test.__name__}")
            test()
            passed += 1
            print(f"  ok")
    finally:
        print("restore sample")
        apply("05_sample.sql")
    print(f"{passed} tests passed")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAILED after {passed} tests: {exc}", file=sys.stderr)
        sys.exit(1)
