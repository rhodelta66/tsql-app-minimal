---
name: miss-piggy
description: >
  Build and maintain the miss-piggy TSQL.APP framework at /root/tsql-app-minimal.
  Use when changing the client, the SQL dispatcher, modal actions, cards, the
  knowledge graph, or the public site client.miss-piggy.tsql.app. Use when the
  user runs /miss-piggy or mentions tsql-app-minimal, demo_proj, sp_api_request,
  api_card, or the miss-piggy framework.
when-to-use: >
  miss-piggy, tsql-app-minimal, TSQL.APP action script, sp_api_request,
  api_card, demo_proj, client.miss-piggy.tsql.app, modal loop, card IDE
metadata:
  short-description: Maintain the miss-piggy TSQL.APP framework
---

# Miss-piggy framework

SQL Server owns the screen. The browser paints the JSON from `dbo.sp_api_request` and does not know the business rules.

This file is the procedure. Product behavior lives in `/root/tsql-app-minimal/docs/framework.md` and in `demo_proj` `knowledge.v_entry` / `knowledge.v_link`. Read both before you change behavior. If this skill, the doc, and a live object disagree, trust the live object, then update the doc and the matching knowledge entry together.

Update this skill only when the procedure changes: what you may run, where the process lives, or which live rows you must leave alone. When a product invariant changes, update `docs/framework.md` and `sql/06_knowledge.sql` together and apply only that SQL file. Store fishing gear: the query, the invariant, and where to look. Do not store fish: row values, credits, note text, passwords, tokens, session ids, or a JWKS kid.

## Read first

1. `docs/framework.md`. The Knowledge section has the queries.
2. `knowledge.v_entry` and `knowledge.v_link` on database `demo_proj`.
3. The live row or procedure you are about to change. A seed file is not the live column.

## Where it runs

Project `/root/tsql-app-minimal` is the private git repository `https://github.com/rhodelta66/miss-piggy`. This procedure is `.grok/skills/miss-piggy/SKILL.md` in that repo. `/root/.grok/skills/miss-piggy` is a symlink to that directory so a session started in `/root` still loads it. Metadata database `demo_proj`. Business database `demo`. Public client `https://client.miss-piggy.tsql.app`. API `https://miss-piggy.tsql.app`, proxied to `127.0.0.1:8765`. `.env` stays untracked.

The API is systemd unit `tsql-app-api.service`. Do not start a second Python process. Logs: `journalctl -u tsql-app-api`. A public HTTP 502 means that unit is not accepting connections. An unauthenticated `POST /api/request` returns 401 when the process is up.

The SQL login is `sa`. The password is only in `/root/tsql-app-minimal/.env`. Do not print it, reset it, or copy it into a file. Do not commit unless asked. Do not reboot unless asked. Do not put the API IP allow list back. Audience is not checked.

`dbo.main_db()` is `SESSION_CONTEXT(N'main_db')` when set, otherwise `DB_NAME()` with a trailing `_proj` removed. On this box that is `demo`. The project database is that name plus `_proj`.

## Change

Keep the client dumb. Add a screen with metadata and, when it needs behavior, action SQL that reads, then acts, then renders.

Follow the modal contract in the framework doc:

- Declare every variable at the top of the batch. Do not redeclare names the dispatcher already injects, including `@id`.
- Assign every `sp_api_*` argument before the call. Do not pass a literal or an expression.
- Read with `sp_api_modal_get_value` before any render. On success, toast, call `sp_api_modal_clear`, then `RETURN`. Clear does not stop the batch.
- The server executes only `stored_procedure`. `pathname` is client navigation. An action kind `reducer` does not run. `api_card.reducer` is a card filter, not an action kind.
- Give an already-JSON fragment to `JSON_QUERY`. A `CASE` around `JSON_QUERY` leaves the client a string.

Keep the procedure set small. Do not add a modal procedure when a parameter of an existing one says the same thing. A caption is `sp_api_modal_input` `@label`. Every form control is that same procedure: `@type` chooses an HTML input, `textarea`, `select`, `radio`, `checkbox`, `file`, or `hidden`, and `@options` supplies the choices. There is no `sp_api_modal_label` and no `sp_api_modal_select`. Leave `sp_api_modal_table` unbuilt unless asked. Related cards are a menu, not a sub-grid.

Do not put a role name in client JavaScript. The claim key is `role`, one string or an array of strings. A comma inside one string is not a list. `api_card.ide_role` is a comma-separated OR list and applies only when `is_system` is 1. `is_system` 0 does not consult `ide_role`. A card is a system card when the database in `tablename` is the project database. Those two columns are not IDE form fields. `role` and `deny_role` stay unused.

Leave these unbuilt unless asked: the full roles model, tasks, reports, files, history, seek, record states, a relation editor, and a low-privilege SQL login.

`Q-261028-monaco-crud` is unanswered in `/beheer/vps-manager/out-box`. Leave Monaco and Delete as deployed. Do not write that reply. A new product question goes in `/beheer/vps-manager/in-box` under the same filename as the tag, and waits.

The list New button and the modal Close button stay hardcoded unless asked.

## Apply

Source `.env`, then run sqlcmd. Do not expand the password into the command text.

```bash
set -a && source /root/tsql-app-minimal/.env && set +a
/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER" -C -U "$SQL_USER" -P "$SQL_PASSWORD" -d demo_proj -b -f 65001 -i FILE
```

The per-file rules are in `docs/framework.md` under Where it runs. These are the stops:

- `scripts/apply.sh` and `sql/00_databases.sql` drop `demo` and `demo_proj`.
- `sql/01_tables.sql` is unguarded `CREATE TABLE`. Do not run it live.
- `sql/05_sample.sql` drops `demo.dbo.customer`. Do not run it live. Live rows may differ from that seed.
- `sql/07_ide.sql` deletes and recreates `ide`, `ide_field`, and `ide_action`. Run it only when that reset is the task.

Do not overwrite live Hello action SQL, customer rows, or note rows to match a seed. `sql/12_label.sql` inserts the customer Label action only when that name is absent. Query action ids. Do not hardcode them.

Copy changed files from `client/web/js/` and `client/web/css/` to `/var/www/client-miss-piggy/` and `chmod 644`. `client/static` is not served. The Tracy tree under `/root/backups/client-miss-piggy-tracy` is not served.

Restart with `systemctl restart tsql-app-api.service` only when `client/server.py` or `lib/` changes.

## Prove

From `client/web`:

```bash
node --test test/contract.test.mjs
python3 test/loop_check.py
```

`loop_check.py` deletes only the notes it creates. Do not use `tests/run_tests.py` as a health check.

For a change the user can see, drive `https://client.miss-piggy.tsql.app`. Route `https://miss-piggy.tsql.app/api/request` to `lib.db.request` with a probe session token. A fake JWT belongs only in `sessionStorage` under `tsql.auth`: store `JSON.stringify` of the session object, and `access` must have three segments. Fulfill OPTIONS with CORS origin `https://client.miss-piggy.tsql.app`. Delete that probe `api_session` row when finished. Do not use the signed-in user's session. Do not delete the session `loop_check.py` uses.

A toolbar button's accessible name includes its keycode, with no space before the `kbd`. A menu card's accessible name includes its keycode too.

Do not log tokens, emails, session ids, or a JWKS kid.
