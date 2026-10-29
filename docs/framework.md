# Data-driven framework

This is the state of the minimal TSQL.APP-style framework on miss-piggy, and the plan for what stays out of it until someone asks. The date of this description is 2026-10-28.

SQL Server owns the screen. A card is a row of metadata. A click posts names the server already chose. `dbo.sp_api_request` returns one JSON payload, the screenplay. The browser paints that payload and does not know the business rules.

The working memory for this box is the `knowledge` schema in `demo_proj`. It stores fishing gear: queries, invariants, and where to look. It does not store fish. Row values, credits, note text, session ids, and key ids belong in a `SELECT` or at the URL that publishes them. Read `knowledge.v_entry` and `knowledge.v_link` before changing the client or the dispatcher. When an invariant changes, update the matching entry and this file together.

## Where it runs

| Piece | Value |
| --- | --- |
| Public client | `https://client.miss-piggy.tsql.app` |
| API origin | `https://miss-piggy.tsql.app` |
| Host address | `91.107.229.46` |
| SQL Server | 2025 Express, `localhost,41300` |
| Framework database | `demo_proj` |
| Business database | `demo` |
| API process | systemd unit `tsql-app-api.service` runs `python3 client/server.py` on `127.0.0.1:8765`. Do not start a second copy. Logs: `journalctl -u tsql-app-api` |
| API log | `/tmp/tsql-app-logs/server.log` |
| Project root | `/root/tsql-app-minimal` |
| Deployed client files | `/var/www/client-miss-piggy` |
| SQL login | `sa`, password only in `/root/tsql-app-minimal/.env` (mode 600) |

Do not reset the `sa` password. Do not commit unless asked. Do not store the password in `knowledge` or in this file.

`dbo.main_db()` returns `SESSION_CONTEXT(N'main_db')` when that key is set, otherwise `DB_NAME()` with a trailing `_proj` removed. On this box that is `demo`.

## Request path

```text
browser
  POST https://miss-piggy.tsql.app/api/request
    Authorization: Bearer <id3 access token>
nginx (miss-piggy vhost)
  proxy to 127.0.0.1:8765
client/server.py
  verify the bearer, then call dbo.sp_api_request
SQL Server
  one JSON object
browser
  screenFrom reads it, view paints it
```

The client vhost serves files only. `location ^~ /api/` on that vhost returns 404, so the browser must call the API origin. A hostname that starts with `client.` discovers the API as `https://` plus the host with `client.` removed, and discovers sign-in as `https://id3.tsql.app`.

A SQL or static-file change does not need an API restart. Restart with `systemctl restart tsql-app-api.service` only when `client/server.py` or `lib/` changes. Do not start the process by hand. Copy changed `client/web/js/` and `client/web/css/` to `/var/www/client-miss-piggy/` and `chmod 644`. Those locations are sent with `Cache-Control: no-cache`.

`scripts/apply.sh` globs `sql/*.sql` and starts with `sql/00_databases.sql`, which drops `demo` and `demo_proj`. Run it only when that drop is intended. Do not run `sql/01_tables.sql` against the live databases: the `CREATE TABLE` statements are not guarded. Do not run `sql/05_sample.sql` whole: it drops and reseeds `demo.dbo.customer`. `sql/02_modal.sql`, `sql/03_cache.sql`, and `sql/04_dispatch.sql` are `CREATE OR ALTER` and are safe to apply. Do not call `sp_api_card_create_cache` for every card just to test. `sql/06_knowledge.sql` merges knowledge and is safe. `sql/08_relations.sql` merges its example rows and leaves the others. `sql/09_crud_delete.sql` sets `crud_delete` to `1=0` only where it is still NULL. `sql/10_ide_role.sql` adds `ide_role` if it is missing and fills a blank `ide_action` value with `admin`. `sql/11_is_system.sql` adds `is_system` with default `0` and sets it from the table database in both directions. `{main_db}_proj` is a system card. The business database is not. `sql/12_label.sql` inserts the customer Label action only when that name is absent. `sql/07_ide.sql` deletes and recreates only the cards named `ide`, `ide_field`, and `ide_action`, sets `ide_action.ide_role` back to `admin`, and marks those three `is_system`. Run `07` only when that reset is the task.

## Authentication

`lib/auth.py` checks `Authorization: Bearer` against `https://id3.tsql.app/.well-known/oauth2/certs`.

- Issuer must be exactly `https://id3.tsql.app`.
- Algorithm RS256. Read the current signing key from the JWKS URL. Kid match is case-insensitive. A token with no kid uses the single published signing key.
- Expiry allows 120 seconds of leeway.
- Audience is not checked, matching Tracy.
- The token claim `role` is one string or an array of strings, the same claim the Tracy client reads. A string is a single role name. Those names are passed to `sp_api_request`. The request body cannot set them.
- `api_card.role` and `deny_role` are not enforced. `api_card.is_system` is `0` on a business card. When it is `1` and `ide_role` names roles, the UI compares the token claim `role` with that list, and the server withholds the card unless the caller has one of those roles. A blank `ide_role` does not restrict the card.
- Subject is `sub`, otherwise `uid`. Email is `email`, otherwise `preferred_username`, otherwise the subject.
- The SQL session token is the first 64 hex characters of SHA-256 of the text `id3:` plus the subject. The request body cannot choose the identity.
- A missing or rejected bearer returns HTTP 401 and `{"error":"Unauthorized"}` before any SQL. The failure log records the class, `alg`, `iss`, and claim names. It does not record the token.

Sign-in is `POST {auth}/login` with `{username, password}`. A `needs_2fa` result continues at `POST /login/verify` with `{username, code}`. Refresh is `POST {auth}/refresh` with `{uid, token}`. The browser keeps `{access, refresh, uid, exp}` in `sessionStorage` under `tsql.auth`. Paths that start with `/account` are replaced with `/`. Who is signed in is `api_session`. Do not copy those rows into this file.

## One screenplay

`dbo.sp_api_request` is the only client entry. Parameters:

| Parameter | Meaning |
| --- | --- |
| `@session_token` | 64-character session id. A new token inserts `api_session`. |
| `@pathname` | Address the client is showing. |
| `@posted_json` | Object of modal posts, keyed by control name. |
| `@action` | `api_card_actions.name` to run. Null re-enters an open modal when the path matches. |
| `@id`, `@ids` | The list cursor, or the one record open on a form. `@ids` is that same id. |
| `@close` | Close the modal without running its action. |
| `@caller_email`, `@caller_sub` | Taken from the verified token, not from the body. |
| `@caller_roles` | JSON array of role names from the token claim `role`. The body cannot set it. |
| `@save`, `@values_json` | Form write. `values` is one object. |

The final `SELECT` returns one object. `FOR JSON` escapes a JSON text column unless `JSON_QUERY` is the outer expression. `relations` and action `params` both use that shape. A `CASE` wrapped around `JSON_QUERY` leaves the client a string.

| Key | Role |
| --- | --- |
| `data` | Rows. Home uses the same array as the menu. |
| `def` | Field definitions. |
| `actions` | Toolbar buttons. Null on home, because an empty array is still truthy and would paint the bar twice. |
| `relations` | Related cards for the current card. Null on home. |
| `header` | Menu rows on home, action rows on a card. |
| `settings` | `{k, v}` rows: `cardname`, `user`, `main_db`, `id_column`, `record_limit`, `auto_refresh_seconds`, `is_form`, `is_list`, `is_system`, `ide_role`. `is_form`, `is_list`, and `is_system` are the strings `"0"` and `"1"`. |
| `breadcrumbs` | `{disp, card_name, pathname, search}`. The client adds Home when it is missing. |
| `views` | Home: `Actions` over `header`. A card: `Listview` or `Detailview` only. |
| `statusbar`, `querystring` | Empty arrays. |
| `modal` | `{class, controls, edit, is_system, ide_role}` or null. `edit` is `/ide_action/` plus the open action id. The client paints Edit when that path is safe and, if `is_system` is `1`, the token claim `role` matches `ide_role`. |
| `toasts` | `{text, class}`. |
| `cleared` | True after `sp_api_modal_clear`. The client drops the dialog. |
| `error` | One message, or null. |
| `session` | The token. The debug panel strips it before display. |

`def` columns the client uses: `name`, `disp`, `typ`, `att`, `is_id`, `is_upd`, `is_hid`, `cls`, `fid`, `id`. `att` is an empty string. `id` is repeated as `fid`. `is_upd` is 1 only when the field is not the id, `detail_order` is above 0, and field `sql` is blank. `is_hid` is 1 when the active order is 0 (`detail_order` on a form, `list_order` on a list). `typ` is `data_type` when set, otherwise the base-column type.

The client does not read `views`. It infers the screen:

- `is_form` 1 and visible fields: form.
- Visible fields: list.
- Empty `def` and every data row has `name`: home menu.
- Otherwise a list inferred from the row keys, or an empty screen.

## Addresses

| Path | Screen |
| --- | --- |
| `/` | Home menu. Cards with `in_main_menu = 1`, ordered by name. |
| `/{card}` | List. |
| `/{card}/{id}` | Form. |
| `/{card}/new` | Blank form. The breadcrumb says New. |
| `/{parent}/{id}/{child}` | Child list. |
| `/{parent}/{id}/{child}/{record}` | Child form, including `new`. |
| `/{parent}/-/{child}` | Unbound child list when no parent row is selected. |

The client builds a related URL from the current card, the open or selected id, and `relations[].name`. The payload does not carry a concrete pathname, because the selected row is client state. After a created row returns, the address keeps the current list base and adds the new id, so a child insert stays under its parent.

Opening a list row uses that same base. On `/customer/2/customer_note`, double-click opens `/customer/2/customer_note/{id}` and New opens `.../new`.

## Metadata

All of these tables are in `demo_proj.dbo`.

| Table | Holds |
| --- | --- |
| `api_session` | Token, user name, user id. |
| `api_session_storage` | Values set with `sp_api_modal_set`. They survive `clear`. |
| `api_modal_state` | Whether a modal is open, which action, which path. |
| `api_modal_post` | Posted names and values for this request. |
| `api_modal_render` | Control JSON emitted during the action. |
| `api_toast` | Toasts for this request. |
| `api_card` | One card: source, id column, menu, limit, sort, reducer, and the three caches. |
| `api_card_fields` | Columns and computed expressions. |
| `api_card_actions` | Buttons. `card_id` NULL would show the action on every card. Do not use that for IDE or relations. |
| `api_card_children` | Related cards. |

`api_card.tablename` is what the cache reads. `basetable` is what a form writes. A view leaves `basetable` empty unless it names a real user table. Customer reads `v_customer` and writes `customer` in `demo`.

### Building a card from a table

```sql
EXEC dbo.sp_api_card_from_table @table = N'customer_note';
```

The procedure checks that the object is a table or a view, chooses `id` or a single-column primary key or an identity, inserts `api_card`, and calls `sp_api_card_create_cache`. `@name` overrides the card name. `@id_column` overrides the id. A missing id throws before the insert. A duplicate name throws. `in_main_menu` defaults to 1 and `record_limit` to 50. Do not write the card row or the three cache columns by hand.

### Cache

```sql
DECLARE @card_id int = (SELECT id FROM dbo.api_card WHERE name = N'customer');
DECLARE @toast bit = 0;
EXEC dbo.sp_api_card_create_cache @card_id = @card_id, @toast = @toast;
```

Look up the id by name. Do not use `SCOPE_IDENTITY` across batches. A null `id_column` writes `api_card.error` and then throws the exact text `sp_api_card_create_cache NO ID!` from outside the `TRY`.

The list cache is `SELECT ... FROM [database].[dbo].[object] AS t WHERE (1 = 1) AND (reducer)`. It has no `TOP` and no `ORDER BY`. The dispatcher applies `record_limit` as `TOP` and `sorting_order` as the outer `ORDER BY`. Validation runs the same text with `WHERE (1 = 0)`. `declare_cache` declares one variable per field, id first. `select_cache` assigns those variables for `t.[id] = @id`. A field `sql` value is the select expression. Semicolons are rejected in field `sql`, the card reducer, `sorting_order`, and `crud_read`.

If the card has no field rows, the builder inserts one row per source column inside the successful transaction. The id field gets list and detail order 0. Other columns are ordered from the source. Rebuild after a change to fields, field `sql`, `tablename`, reducer, or the view. `record_limit` and `sorting_order` are read live by the dispatcher, so they do not need a rebuild.

A synonym `demo_proj.dbo.{object}` points at `[demo].[dbo].[{object}]` only when that object is not already in `demo_proj`. `api_card` already exists in `demo_proj`, so the IDE cards read `[demo_proj].[dbo].[api_card]`.

### Save

`POST` with `save: true` and `values` calls `dbo.sp_api_card_save`. Writable columns are the intersection of `sys.columns` and `api_card_fields` where `detail_order > 0`, field `sql` is blank, and the column is not the id, an identity, or computed. Values stay in parameters. Client text is never concatenated into the SQL.

A missing or invalid value returns `{name} is missing or not valid.` A bit accepts `0`, `1`, `true`, and `false`. An update with a blank id returns `Choose a record to update.` Zero rows updated returns `Record was not found.` No editable fields returns `This card has no editable fields.`

A three-part `tablename` may name `DB_NAME()` or `dbo.main_db()`. Any other database returns `This card cannot be saved.` No database part keeps the main database, so customer still writes `demo`. After a successful write to `api_card` or `api_card_fields` in `demo_proj`, the save rebuilds that card with `@toast = 0`. The rebuilt id is the saved card, or the `card_id` of a saved field. A blank `id_column` or `tablename` skips the rebuild. A cache failure replaces the Saved toast with the error text. Action `sql` is read live and is not rebuilt. The request loads `select_cache` before the save, so the form just saved still used the old cache. The next request sees the rebuild.

`crud_read`, `crud_create`, `crud_update`, and `crud_delete` are optional predicates. NULL or blank means allowed. `1=0` denies with `Read is not allowed for this card.`, `Create is not allowed for this card.`, `Update is not allowed for this card.`, or `Delete is not allowed for this card.`

`POST` with `delete: true` calls the same procedure with its delete flag. It does not require a values object. A blank id returns `Choose a record to delete.` Zero rows deleted returns `Record was not found.` A predicate that is not one expression returns `The save rule is not a single expression.` A predicate that throws returns `The save rule failed.` Success toasts `Deleted` and the payload is the list for that card, including a parent prefix when the form was a related card. A failed delete keeps the form and returns the error. Deleting an `api_card_fields` row rebuilds that field's card. Deleting `api_card` or `api_card_actions` does not rebuild a cache. Action `sql` stays read live.

`sql/09_crud_delete.sql` sets `crud_delete` to `1=0` on `customer` and `customer_note` only where the column is still NULL. The IDE cards leave it NULL, so those rows can be deleted. Settings `can_delete` is the string `1` or `0` from the same predicate. NULL or blank is `1`.

### IDE

Home card `ide` (keycode `I`) lists `demo_proj.dbo.api_card`. The form edits `name`, `tablename`, `basetable`, `id_column`, `in_main_menu`, `menu_keycode`, `record_limit`, `sorting_order`, and `reducer`. `error` is on the list only. `reducer` is a textarea because the column is `nvarchar(max)` and the field name is not `sql`. The action field `sql` is button code. A `nvarchar(max)`, `varchar(max)`, or `varbinary(max)` field named `sql` is a Monaco SQL editor. Other max fields stay textareas.

`ide_field` and `ide_action` are not on the home menu. `ide` has pathname actions Fields (`/ide_field`, keycode `F`) and Actions (`/ide_action`, keycode `A`). Each of those cards has a pathname action Cards back to `/ide`. The params object is `{"pathname":"..."}`. The server does not run kind `pathname`. The client navigates.

There is no IDE card for relations.

`api_card.is_system` is a bit, default `0`. A card is a system card when the database in `tablename` is the project database, `dbo.main_db()` plus `_proj`. A table in the business database is not a system card. A name without a database is the business database. `sql/11_is_system.sql` applies that rule. `sp_api_card_from_table` and `sp_api_card_create_cache` set the bit the same way. When the bit is `1` and `ide_role` names roles, the UI reads the token claim `role` and shows the card only when a claim value matches. The server withholds the rows unless the caller has one of those roles. A blank `ide_role` does not restrict the card. `is_system` `0` does not consult `ide_role`, so a business card stays usable even when `ide_role` is set. The live value is on the row. `sql/10_ide_role.sql` sets `ide_action` to `admin` only when the column is blank. The IDE form includes neither column, so saving card `ide` cannot clear them. The client contains no role name. The claim `role` is one string or an array of strings. A comma inside one string is not a list. `ide_role` is the comma-separated list.

## Actions and the modal loop

An action row has `name`, `display_name`, `action` (the kind), `sql`, `pre_declare`, `keycode`, `type`, and `action_order`. The toolbar skips a type that contains `hidden`. The label is `display_name`.

| Kind | What runs |
| --- | --- |
| `stored_procedure` | The only kind the server executes. Non-blank `sql` is the batch. Blank `sql` falls back to `EXEC dbo.[name]`. |
| `pathname` | The server ignores it. The client navigates to `params.pathname`. |
| `reducer` | Named in the original task. The server does not execute it. This is not the card-level reducer. |
| `sql` | Would not run. |

The same procedure runs on every post. The order is fixed.

1. **Read.** `sp_api_modal_get_value` fills a variable from the post. `sp_api_modal_input` overwrites `@value` only when a post row exists. Session values use `sp_api_modal_get` and `sp_api_modal_set`.
2. **Act** when a button variable is not null. On success call `sp_api_modal_clear`, toast, and `RETURN`.
3. **Render** with `sp_api_modal_modal`, `sp_api_modal_text`, `sp_api_modal_input`, and `sp_api_modal_button`. A field caption is the input's `@label`. The same procedure paints every form control. `@type` chooses it: an HTML input type, `textarea`, `select`, `radio`, `checkbox`, `file`, or `hidden`. `@options` is a comma-separated list, or a JSON array of strings or `{id, name}` objects. `@multiple` posts the chosen ids separated by commas. A checkbox with no options posts `1` or `0`. A file posts the data URL of the chosen file. A hidden field is posted and not shown. There is no separate procedure per control.

`sp_api_modal_button` copies the click into `@out` and clears that posted slot. A later `get_value` no longer sees the click. Read before render.

`sp_api_modal_clear` sets the modal closed and deletes posts and render rows. It does not stop the batch, and it does not delete toasts or session storage. Render after clear paints the dialog again, so return after clear. Forgetting clear leaves the modal open.

Declare every variable at the top of the batch. Assign every `sp_api_*` argument to a variable before the call. Do not pass a literal or an expression into those procedures. `RETURN` inside an action returns from `sp_executesql`, not from `sp_api_request`.

`pre_declare` such as `@my_value nvarchar(200), @company_id int` is split, declared, and filled from the post before the action body. Names the dispatcher already injects are skipped: `@id`, `@ids`, `@card_name`, `@card_id`, `@user`, `@user_name`, `@user_id`, `@main_db`, `@path`, `@previous_path`, `@parent_id`, `@parent_card_name`, `@parent_card_id`, `@is_form`, `@tablename`, `@basetable`, `@identity_column`.

On a child screen those parent variables come from the path. `@parent_id` is an `int` (`TRY_CONVERT` of the parent record). The session-context keys `parent_id`, `parent_card_name`, and `parent_card_id` are set the same way as `id` and `card_name`.

Re-entry: if the modal is open, the stored path equals the normalized pathname, the request has no explicit action, and `close` is not set, the same action runs again. An explicit action clears the previous modal first. A save forces the modal closed and does not run an action. A different path also closes the modal.

When that modal has an action id, the payload includes `edit` as `/ide_action/` plus that id, and `is_system` and `ide_role` from the action card. The dialog header paints Edit when `edit` is a path and, if `is_system` is `1`, the token claim `role` matches a value in `ide_role`. A blank `ide_role` leaves the button in. The client contains no role name. The form there is the action row, and its `sql` field is the button code.

Control JSON:

| Kind | Fields |
| --- | --- |
| `modal` | `class`. The dialog itself. The client does not paint it again inside the dialog. |
| `text` | `text`, `class`. A class token `h1`, `h2`, or `h3` becomes that element. Text is assigned with `textContent`. |
| `input` | `name`, `type`, `value`, `placeholder`, `focus`, `label`, `options`, `multiple`. `type` is the control. `options` is an array of `{id, name}`. `label` is the caption, painted on that control. `name` is the input `id`. |
| `button` | `name`, `value`, `class`, `key`. |

An unknown kind is shown, not dropped. Enter submits the button whose key is Enter, otherwise the only button. Escape posts a button keyed Esc or Escape, otherwise `close: true`. The client also paints a Close button that posts `close: true` and skips the SQL act step.

`sp_api_request` clears session-context keys with a named `@value = NULL` before writing the current request. The keys are `id`, `ids`, `card_name`, `card_id`, `action_id`, `tablename`, `basetable`, `sub`, `parent_id`, `parent_card_name`, and `parent_card_id`. A positional NULL is rejected. `nvarchar(max)` is rejected, so long strings are cast to `nvarchar(4000)`. Pooling is on, and a pooled connection would otherwise keep the previous request.

## Related cards

`api_card_children` is the relation. `parent` is the card the user is on and deletes cascade. `child` is the card the menu opens and uses `ON DELETE NO ACTION`, because SQL Server rejects two cascade paths back to `api_card`. The unique key is `(parent, child, unbound)`.

| Column | Meaning |
| --- | --- |
| `display_name` | Menu label. The client falls back to the child card name. |
| `keycode` | Optional shortcut. Leave it null. Enter already opens the selected list row. |
| `ref` | Child output column for a bound relation. A plain identifier, then `QUOTENAME`. |
| `unbound` | 0 filters `ref` to the parent record. 1 uses `reducer` instead. |
| `reducer` | A single `WHERE` expression on list output names. `;`, `--`, and `/*` are rejected. |
| `is_hidden` | The navigation exists, but the menu omits the row. |
| `action_order` | Menu order. |

The list query wraps the child cache as `cached`. Bound SQL is `WHERE CONVERT(nvarchar(128), cached.[ref]) = @parent_id`. The parent id is a parameter. Unbound SQL is `WHERE (reducer)` on that same outer query. Write `status`, not `t.status`, because `t` is inside the cache. If both a bound and an unbound row share one child, the lookup keeps the bound row. Two different labels cannot share one child card, because the URL is `/{parent}/{id}/{child}` and cannot tell them apart.

The Related menu is a `<details>` in the list and form toolbar. Each item shows a muted `bound` or `unbound`. A bound item stays disabled until a list row is selected or a form is open. An unbound item with no id navigates with `-`. A bound path with `-` or an empty id returns `Choose a record to open this related card.`

| Situation | Exact error |
| --- | --- |
| No matching `api_card_children` row | `Unknown relation: {parent} / {child}` |
| Bound, and no parent record | `Choose a record to open this related card.` |
| Bound, and `ref` is missing or not an identifier | `This relation has no link column.` |
| Unbound reducer is not one expression | `The relation filter is not a single expression.` |
| Bound form, and the link is missing or differs | `This record is not part of the related card.` |

An unknown relation is resolved before the card lookup, so the error is not replaced by `Unknown card`. A failed child path does not fall through to the home menu. `FOR JSON` omits nulls, so a null link fails closed. A new bound form prefills the link with `JSON_MODIFY`. The path argument of `JSON_MODIFY` must be a string literal, so the checked `ref` is pasted into its own batch. `EXEC` arguments must be variables or literals too. A `CASE` expression in that argument list is a syntax error.

Breadcrumbs on a child screen are parent card, parent id (the dash is omitted), child card, then New or the record id.

The seed is `sql/08_relations.sql`. It merges the example relations and leaves every other row in place. Read `dbo.api_card_children` joined to `dbo.api_card` for the live menu. A bound row filters on `ref`. An unbound row filters on `reducer`.

## The client

Source is `client/web`. It is native browser ES modules, not React. Deployed files are the `js/`, `css/`, and `vendor/monaco/` copies under `/var/www/client-miss-piggy`. `package.json` is not deployed. The editor is Monaco 0.34.1, vendored from the archived Tracy tree at `client/web/vendor/monaco/vs`, and the client origin serves `/vendor/monaco/vs`. `client/static` is the earlier vanilla experiment and is not served. The Tracy React copy is archived at `/root/backups/client-miss-piggy-tracy` and is not served.

| Module | Job |
| --- | --- |
| `js/config.js` | Discover API and auth from the hostname. |
| `js/auth.js` | Login, verify, refresh, and the stored session. |
| `js/api.js` | `POST /api/request`. |
| `js/contract.js` | Pure reading of one payload. No card names and no DOM. |
| `js/view.js` | Paint with `textContent`. |
| `js/editor.js` | Monaco for a max field named `sql`. Dispose models on each repaint. |
| `js/main.js` | Navigation, list cursor, save, delete, and keyboard. |
| `css/app.css` | The page. |

The list toolbar has a hardcoded New button. The form saves when a column is editable. `fieldInput` returns `textarea` for `nvarchar(max)`, `varchar(max)`, and `varbinary(max)` before it strips parentheses. `fieldEditor` returns `sql` only when that textarea field is named `sql`. The view mounts Monaco for that field and keeps a textarea for every other max field. Enter in a one-line field saves. Enter in a textarea or in Monaco does not. Ctrl+S or Cmd+S still saves. Monaco registers that chord itself, because the editor can swallow the document handler. Checkbox values post as `"1"` and `"0"`.

Delete is a button on an existing form when `can_delete` is `1`. The client asks for confirmation, posts `delete: true` without values, and on success replaces the address with the current list base. A new form does not show Delete. A card with `can_delete` `0` does not show it either.

Shortcuts match the keycode and its modifiers. They are ignored while typing, while a modal is open, and when Meta is held, except the form save keys. The home menu uses `api_card.menu_keycode`. Card actions use `api_card_actions.keycode`. Read those columns. Do not copy the current letters into this file.

A list has one cursor. It starts on the first row and holds the keyboard focus. Click, Arrow Up, or Arrow Down moves it. The cursor row is `tr.selected`. Its cells use the accent fill and the light accent text, so the pointed-at row is a different color from the other rows. It reads `handlers.selectedId`. Double-click or Enter opens that row. A card action posts the cursor id as `@id`. On a form, `@id` is the record in the path, because the form shows that one record. On a child list the path record id is null, so `@id` is the child row under the cursor and `@parent_id` stays the parent. An empty list posts a null `@id`. The cursor stays when the same list is shown again and that id is still there. A different list starts on its first row. A new form leaves the list cursor in place. The home menu has no record cursor.

## Sample

The sample is a card plus the business tables it points at. Read the card. Do not paste the rows into this file.

```sql
SELECT name, tablename, basetable, id_column, record_limit, sorting_order, menu_keycode, reducer
FROM demo_proj.dbo.api_card
WHERE name IN (N'customer', N'customer_note');

SELECT name, display_name, list_order, detail_order, sql
FROM demo_proj.dbo.api_card_fields
WHERE card_id = (SELECT id FROM demo_proj.dbo.api_card WHERE name = N'customer');

SELECT name, display_name, action, keycode
FROM demo_proj.dbo.api_card_actions
WHERE card_id = (SELECT id FROM demo_proj.dbo.api_card WHERE name = N'customer');
```

`sql/05_sample.sql` is a seed, and it drops `demo.dbo.customer`. Live rows may differ from that seed. Do not overwrite them to match the script. A field with its own `sql` is computed and is not written. `detail_order` 0 hides it on the form. `list_order` 0 hides it on the list.

Hello, Note, Wizard, and Label are `stored_procedure` actions. Their contract is read, then act, then render, with every `sp_api_*` argument assigned first. Hello reads `demo.dbo.customer.customer_name` for `@id` and shows an `h1` of `hello` plus that name. A missing row toasts `Choose a customer.` Label shows the heading `The input Element`, a text field captioned `First name:`, and Submit. An empty name toasts `First name is required` and the dialog stays open. A name toasts `First name:` plus that value, then clears the modal and returns. Label does not write a customer or note row and does not require a selected row. `sql/12_label.sql` inserts that action when the name is absent and does not change an existing row. The live `api_card_actions.sql` column can diverge from the seed file. Read that column, and read the procedure definition, when you need the current screenplay. `customer_note` was created with `sp_api_card_from_table`. A list-only column keeps the table default.

## Knowledge

`knowledge.entry` holds the prose. `knowledge.topic` is a NODE table, one row per entry. `knowledge.link` is an EDGE table with `rel`, `origin`, and `note`. Re-running `sql/06_knowledge.sql` updates matching keys and does not delete extra entry rows. Seed edges (`origin = seed`) are replaced. Any other origin stays, including the note edge `graph.query —documents→ ops.paths`.

Store the query and the invariant. A customer name, a credit, a note, a session id, or the current JWKS kid is a query result. Leave it in the table or at the JWKS URL.

```sql
SELECT entry_key, kind, title, body
FROM knowledge.v_entry
ORDER BY kind, entry_key;

SELECT from_key, rel, to_key, note
FROM knowledge.v_link
ORDER BY from_key, rel;
```

Neighbors of one key:

```sql
SELECT rel, to_key AS other
FROM knowledge.v_link
WHERE from_key = N'client.poc'
UNION ALL
SELECT rel, from_key
FROM knowledge.v_link
WHERE to_key = N'client.poc';
```

Query with database `demo_proj`. A query against `master` cannot see these views.

## Checks that are safe

From `client/web`:

```bash
node --test test/contract.test.mjs
python3 test/loop_check.py
```

`loop_check.py` drives Note and Wizard. It deletes only the notes it creates for that run. It does not restore customer rows.

`tests/run_tests.py` still expects menu rows to carry a `path` the dispatcher does not emit. Do not run it as a health check.

## Plan

The product is the loop, the cache, and a client that paints whatever the payload says. It is not the full Tracy application. Later subsystems stay out until they are asked for: roles, tasks, reports, files, history, seek, and record states.

### In place

- Session, modal state, posts, render rows, toasts, and session storage.
- `sp_api_modal_get_value`, `clear`, `modal`, `text`, `input`, `button`, `toast`, `set`, and `get`. Every form control is `sp_api_modal_input`. `@type` and `@options` choose the widget. A caption is `@label`.
- `sp_api_request` as the only screen entry, including save and the nested child path.
- Cache builder and `sp_api_card_from_table`.
- List, form, and the home menu, driven by metadata.
- Hello, Note, Wizard, and Label as metadata actions whose code is T-SQL.
- id3 login, the two vhosts, and CORS `Access-Control-Max-Age: 7200`.
- The card IDE, including Monaco for button `sql`, a textarea for other `nvarchar(max)` fields, delete gated by `crud_delete`, and a cache rebuild after a metadata save or a field delete.
- Bound and unbound related cards, shown in a Related menu.
- The `knowledge` graph.

### Left open on purpose

- `sp_api_modal_table` is not built. A dropdown is `sp_api_modal_input` with `@type` `select`, not a separate procedure. Related cards are a menu, not a sub-grid.
- The server executes only `stored_procedure`. `pathname` is navigation. `reducer`, as an action kind, does not run.
- No low-privilege SQL login. The operator asked for one. It is not created.
- `api_card.role` and `deny_role` stay unused. `is_system` plus `ide_role` is the only role check. A business card stays open. Audience stays unchecked so the check matches Tracy.
- No IDE editor for `api_card_children`. Add a relation by inserting a row, or by extending `sql/08_relations.sql` without deleting unrelated rows.
- The archived Tracy tree does not follow later master deploys.
- The list New button and the modal Close button are still hardcoded in the client.

### When extending it

Keep the client dumb. Add a screen by adding metadata and, when the screen needs behavior, a stored procedure that reads, acts, and renders. Give every new payload fragment to `JSON_QUERY` when the fragment is already JSON. Prefer a new `knowledge.entry` over a comment. Do not drop the databases to prove a change, and do not overwrite live customer or note rows to match the sample script.
