"""Drive the live modal loop with the posts the new client would send."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from lib.auth import roles_from_claims  # noqa: E402
from lib.db import execute, fetch_all, fetch_one, request  # noqa: E402

WEB = Path(__file__).resolve().parents[1]
NODE = r"""
import { readFileSync } from "node:fs";
import { modalPosted, screenFrom } from "./js/contract.js";
const payload = JSON.parse(readFileSync(0, "utf8"));
const fill = process.argv[1] ? JSON.parse(process.argv[1]) : null;
const roles = process.argv[2] ? JSON.parse(process.argv[2]) : [];
const screen = screenFrom(payload, Object.assign(fill ? { values: fill } : {}, { roles }));
const controls = screen.modal ? screen.modal.controls : [];
let posted = null;
if (fill) {
  const button = controls.find((control) => control.kind === "button" && control.name === fill.__button);
  const values = { ...fill };
  delete values.__button;
  posted = modalPosted(controls, values, button);
}
console.log(JSON.stringify({
  kind: screen.kind,
  columns: screen.columns.map((column) => column.name),
  actions: screen.actions.map((action) => [action.name, action.label, action.keycode]),
  menu: screen.menu.map((item) => [item.pathname, item.keycode]),
  modal: controls.map((control) => control.kind + ":" + (control.name || control.tag || "")),
  edit: screen.modal && screen.modal.edit || "",
  toasts: screen.toasts.map((toast) => toast.text),
  error: screen.error,
  posted,
}));
"""


def interpret(payload, fill=None, roles=None):
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            NODE,
            json.dumps(fill) if fill else "",
            json.dumps(roles) if roles is not None else "",
        ],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        cwd=WEB,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    return json.loads(proc.stdout)


def main():
    assert roles_from_claims({"role": "admin"}) == ["admin"]
    assert roles_from_claims({"role": ["user", "admin"]}) == ["user", "admin"]
    assert roles_from_claims({"role": "user"}) == ["user"]
    assert roles_from_claims({"roles": ["admin"]}) == []
    assert roles_from_claims({"role": "admin,user"}) == []
    assert roles_from_claims({}) == []
    classified = fetch_all(
        """
        SELECT name, is_system,
               CASE WHEN PARSENAME(tablename, 3) = dbo.main_db() + N'_proj' THEN 1 ELSE 0 END AS expect
        FROM dbo.api_card
        """
    )
    for row in classified:
        actual = 1 if row["is_system"] in (1, True) else 0
        assert actual == row["expect"], row

    ada = fetch_one(
        "SELECT id FROM dbo.customer WHERE customer_name = N'Ada Lovegrove'",
        database="demo",
    )
    if not ada:
        raise SystemExit("Ada Lovegrove is missing")
    ada_id = str(ada["id"])
    session = "client-web-loop"
    email = "ada@example.com"

    home = request(session=session, pathname="/", user_email=email)
    seen = interpret(home)
    assert seen["kind"] == "menu", seen
    assert ["/customer", "C"] in seen["menu"], seen

    card = request(session=session, pathname="/customer", user_email=email)
    seen = interpret(card)
    assert seen["kind"] == "list", seen
    assert "customer_name" in seen["columns"] and "id" not in seen["columns"], seen
    assert ["sp_example_minimal_modal", "Note", "Alt+N"] in seen["actions"], seen

    form = request(session=session, pathname="/customer/" + ada_id, user_email=email)
    seen = interpret(form)
    assert seen["kind"] == "form", seen
    assert seen["columns"] == ["customer_name", "status", "city", "credit_limit"], seen

    opened = request(
        session=session,
        pathname="/customer",
        action="sp_example_minimal_modal",
        id=ada_id,
        user_email=email,
    )
    seen = interpret(opened)
    assert "input:@my_value" in seen["modal"], seen
    assert "button:@btn_save" in seen["modal"], seen
    empty = interpret(opened, {"@my_value": "", "__button": "@btn_save"})["posted"]
    rejected = request(
        session=session,
        pathname="/customer",
        posted=empty,
        id=ada_id,
        user_email=email,
    )
    seen = interpret(rejected)
    assert "Value is required" in seen["toasts"], seen
    assert "button:@btn_save" in seen["modal"], seen

    marker = "client-web-loop café"
    saved_post = interpret(rejected, {"@my_value": marker, "__button": "@btn_save"})["posted"]
    saved = request(
        session=session,
        pathname="/customer",
        posted=saved_post,
        id=ada_id,
        user_email=email,
    )
    seen = interpret(saved)
    assert saved.get("cleared") is True, saved
    assert "Saved successfully" in seen["toasts"], seen
    assert seen["modal"] == [], seen

    wizard = request(
        session=session,
        pathname="/customer",
        action="sp_example_wizard",
        id=ada_id,
        user_email=email,
    )
    missing = interpret(wizard, {"@name": "", "__button": "@btn_next"})["posted"]
    step = request(session=session, pathname="/customer", posted=missing, id=ada_id, user_email=email)
    assert "Name is required" in interpret(step)["toasts"], interpret(step)
    forward = interpret(step, {"@name": "Ada", "__button": "@btn_next"})["posted"]
    step = request(session=session, pathname="/customer", posted=forward, id=ada_id, user_email=email)
    assert "text:h3" in interpret(step)["modal"], interpret(step)
    back = interpret(step, {"__button": "@btn_back"})["posted"]
    step = request(session=session, pathname="/customer", posted=back, id=ada_id, user_email=email)
    assert "input:@name" in interpret(step)["modal"], interpret(step)
    forward = interpret(step, {"@name": "Ada", "__button": "@btn_next"})["posted"]
    step = request(session=session, pathname="/customer", posted=forward, id=ada_id, user_email=email)
    done_post = interpret(step, {"@email": "ada@example.com", "__button": "@btn_save"})["posted"]
    done = request(session=session, pathname="/customer", posted=done_post, id=ada_id, user_email=email)
    assert done.get("cleared") is True, done
    assert "Wizard saved" in interpret(done)["toasts"], interpret(done)

    hello = request(
        session=session,
        pathname="/customer",
        action="hello",
        id=ada_id,
        user_email=email,
    )
    texts = [c for c in (hello.get("modal") or {}).get("controls") or [] if c.get("kind") == "text"]
    buttons = [c for c in (hello.get("modal") or {}).get("controls") or [] if c.get("kind") == "button"]
    hello_row = fetch_one("SELECT id FROM dbo.api_card_actions WHERE name = N'hello'")
    editor_path = "/ide_action/" + str(hello_row["id"])
    assert texts and "Ada Lovegrove" in (texts[0].get("text") or "") and texts[0].get("class") == "h1", hello
    assert (hello.get("modal") or {}).get("edit") == editor_path, hello
    assert (hello.get("modal") or {}).get("ide_role") == "admin", hello
    assert interpret(hello)["edit"] == ""
    assert interpret(hello, None, ["admin"])["edit"] == editor_path
    admin_hello = request(
        session=session,
        pathname="/customer",
        action="hello",
        id=ada_id,
        user_email=email,
        roles=["admin"],
    )
    assert (admin_hello.get("modal") or {}).get("edit") == editor_path, admin_hello
    assert interpret(admin_hello, None, ["admin"])["edit"] == editor_path
    user_hello = request(
        session=session,
        pathname="/customer",
        action="hello",
        id=ada_id,
        user_email=email,
        roles=["user"],
    )
    assert (user_hello.get("modal") or {}).get("edit") == editor_path, user_hello
    assert interpret(user_hello, None, ["user"])["edit"] == ""
    assert buttons and buttons[0].get("name") == "@btn_ok" and buttons[0].get("value") == "OK", hello
    ok_post = interpret(hello, {"__button": "@btn_ok"})["posted"]
    closed = request(
        session=session,
        pathname="/customer",
        posted=ok_post,
        id=ada_id,
        user_email=email,
    )
    assert closed.get("cleared") is True, closed
    assert interpret(closed)["modal"] == [], interpret(closed)
    again = request(
        session=session,
        pathname="/customer",
        action="hello",
        id=ada_id,
        user_email=email,
    )
    again_text = [c for c in (again.get("modal") or {}).get("controls") or [] if c.get("kind") == "text"]
    assert again_text and "Ada Lovegrove" in (again_text[0].get("text") or ""), again
    assert interpret(again)["edit"] == ""
    assert interpret(again, None, ["admin"])["edit"] == editor_path

    editor = editor_path
    code = fetch_one("SELECT sql FROM dbo.api_card_actions WHERE id = ?", [hello_row["id"]])
    marker = "@customer_name"
    assert code and marker in (code.get("sql") or ""), "hello action has no marker"
    before = code["sql"]
    opened = request(session=session, pathname=editor, user_email=email, roles=["user"])
    assert opened.get("error") == "Code editing requires the role admin.", opened
    assert marker not in json.dumps(opened), "denied payload leaked action sql"
    assert opened.get("data") in (None, []), opened
    assert interpret(opened, None, ["user"])["kind"] == "empty"
    listing = request(session=session, pathname="/ide_action", user_email=email, roles=["user"])
    assert listing.get("error") == "Code editing requires the role admin.", listing
    assert marker not in json.dumps(listing)
    kept = request(
        session=session,
        pathname=editor,
        user_email=email,
        roles=["user"],
        save=True,
        values={"sql": "SELECT 1"},
    )
    assert kept.get("error") == "Code editing requires the role admin.", kept
    assert "Saved" not in interpret(kept, None, ["user"])["toasts"], interpret(kept, None, ["user"])
    assert marker not in json.dumps(kept)
    after_save = fetch_one("SELECT sql FROM dbo.api_card_actions WHERE id = ?", [hello_row["id"]])
    assert after_save and after_save["sql"] == before
    removed = request(
        session=session,
        pathname=editor,
        user_email=email,
        roles=["user"],
        delete=True,
    )
    assert removed.get("error") == "Code editing requires the role admin.", removed
    after_delete = fetch_one("SELECT sql FROM dbo.api_card_actions WHERE id = ?", [hello_row["id"]])
    assert after_delete and after_delete["sql"] == before
    allowed = request(session=session, pathname=editor, user_email=email, roles=["user", "admin"])
    assert not allowed.get("error"), allowed
    assert marker in json.dumps(allowed.get("data")), "admin editor did not return the action sql"
    assert interpret(allowed, None, ["user", "admin"])["kind"] == "form"

    prior = fetch_one("SELECT ide_role, is_system FROM dbo.api_card WHERE name = N'customer'")
    previous_role = prior["ide_role"] if prior else None
    previous_system = 1 if prior and prior["is_system"] in (1, True) else 0
    execute("UPDATE dbo.api_card SET ide_role = N'admin', is_system = 0 WHERE name = N'customer'")
    try:
        business = request(session=session, pathname="/customer", user_email=email, roles=["user"])
        assert not business.get("error"), business
        assert business.get("data"), business
        business_form = request(
            session=session,
            pathname="/customer/" + ada_id,
            user_email=email,
            roles=["user"],
        )
        assert not business_form.get("error"), business_form
        assert interpret(business_form, None, ["user"])["kind"] == "form", interpret(business_form, None, ["user"])
        execute("UPDATE dbo.api_card SET is_system = 1 WHERE name = N'customer'")
        blocked = request(session=session, pathname="/customer", user_email=email, roles=["user"])
        assert blocked.get("error") == "Code editing requires the role admin.", blocked
        assert not blocked.get("data"), blocked
        opened_admin = request(session=session, pathname="/customer", user_email=email, roles=["admin"])
        assert not opened_admin.get("error"), opened_admin
        assert opened_admin.get("data"), opened_admin
    finally:
        if previous_role is None:
            execute(
                "UPDATE dbo.api_card SET ide_role = NULL, is_system = ? WHERE name = N'customer'",
                [previous_system],
            )
        else:
            execute(
                "UPDATE dbo.api_card SET ide_role = ?, is_system = ? WHERE name = N'customer'",
                [previous_role, previous_system],
            )

    execute(
        "DELETE FROM dbo.customer_note WHERE note IN (?, ?)",
        [marker, "Ada <ada@example.com>"],
        database="demo",
    )
    print("loop ok", ada_id)


if __name__ == "__main__":
    main()
