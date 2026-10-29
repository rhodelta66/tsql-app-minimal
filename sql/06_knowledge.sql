-- Agent memory for this box. Not a product card and not served by sp_api_request.
-- knowledge.entry holds the prose. knowledge.topic (NODE) and knowledge.link
-- (EDGE) hold the same keys and the relations between them.
-- The rows below are the source of truth. A full scripts/apply.sh recreates them
-- because sql/00_databases.sql drops demo_proj. Re-running this file alone
-- updates these keys and leaves any other knowledge.entry rows in place.
-- Seed edges (origin = seed) are replaced. Edges with any other origin stay.
USE demo_proj;
GO

IF SCHEMA_ID(N'knowledge') IS NULL
    EXEC(N'CREATE SCHEMA knowledge');
GO

IF OBJECT_ID(N'knowledge.entry', N'U') IS NULL
BEGIN
    CREATE TABLE knowledge.entry (
        entry_key   nvarchar(128) NOT NULL CONSTRAINT pk_knowledge_entry PRIMARY KEY,
        kind        nvarchar(32)  NOT NULL,
        title       nvarchar(200) NOT NULL,
        body        nvarchar(max) NOT NULL,
        updated_at  datetime2     NOT NULL CONSTRAINT df_knowledge_entry_updated DEFAULT (SYSUTCDATETIME())
    );
END
GO

CREATE OR ALTER VIEW knowledge.v_entry
AS
SELECT entry_key, kind, title, body, updated_at
FROM knowledge.entry;
GO

DECLARE @seed TABLE (
    entry_key nvarchar(128) NOT NULL PRIMARY KEY,
    kind      nvarchar(32)  NOT NULL,
    title     nvarchar(200) NOT NULL,
    body      nvarchar(max) NOT NULL
);

INSERT INTO @seed (entry_key, kind, title, body) VALUES
(N'map.layout', N'map', N'Hosts, databases, and ports',
 N'demo_proj holds framework metadata. demo holds business data. SQL Server 2025 Express listens on localhost,41300. The public host is miss-piggy, address 91.107.229.46. The API process is systemd unit tsql-app-api.service, python3 client/server.py bound to 127.0.0.1:8765. Do not start a second copy. Logs: journalctl -u tsql-app-api. Restart that unit only when client/server.py or lib/ changes. The public client is https://client.miss-piggy.tsql.app. The API origin is https://miss-piggy.tsql.app. The domains row for client.miss-piggy.tsql.app has api https://miss-piggy.tsql.app and redirect_hostname null. The SQL login is still sa. The password lives only in /root/tsql-app-minimal/.env, mode 600. Do not reset the sa password. Do not commit unless asked. scripts/apply.sh drops both databases via sql/00_databases.sql.'),
(N'map.nginx', N'map', N'Nginx, DNS, and firewall',
 N'Client vhost /etc/nginx/sites-available/client-miss-piggy serves /var/www/client-miss-piggy for GET and HEAD. location ^~ /api/ returns 404 and is not proxied. API vhost /etc/nginx/sites-available/miss-piggy proxies to 127.0.0.1:8765. CORS allow-origin is https://client.miss-piggy.tsql.app. OPTIONS on any API path returns 204. GET / is proxied. The old location = / { return 404; } was removed. The certificate /etc/letsencrypt/live/miss-piggy.tsql.app/ covers both names until 2027-01-25. DNS: miss-piggy.tsql.app and client.miss-piggy.tsql.app are A 91.107.229.46. A wildcard does not cover the two-level client name. UFW allows 22/tcp and 41300/tcp only from master 88.99.15.115 and office 109.109.124.114. Ports 80 and 443 are open. The API IP allow list was lifted.'),
(N'auth.id3', N'fact', N'id3 bearer checks',
 N'Validate Authorization: Bearer against https://id3.tsql.app/.well-known/oauth2/certs. Read the current signing key from that URL. The issuer must be exactly https://id3.tsql.app. Algorithm RS256. Kid match is case-insensitive. A token with no kid uses the single published signing key. Audience is not checked, matching Tracy. The token claim role is a string or an array of strings, the same claim the Tracy client reads. A string is one role name. Those names are passed to sp_api_request as caller roles. The request body cannot set them. When api_card.is_system is 1, those names are compared with api_card.ide_role. The UI reads the token claim role and shows the card only when a claim matches a listed role. A blank ide_role does not restrict the card. is_system 0 does not consult ide_role. The columns role and deny_role are still not enforced. Expiry is checked with 120 seconds of leeway. The subject is sub, otherwise uid. The email is the email claim, otherwise preferred_username, otherwise the subject. The SQL session token is the first 64 hex chars of SHA-256 of the text id3: plus the subject. The request body cannot choose the identity. A missing or rejected bearer returns HTTP 401 and {"error":"Unauthorized"} before any SQL. lib/auth.py logs the failure class, alg, iss, and claim names, and does not log the token.'),
(N'client.poc', N'fact', N'Application-agnostic client',
 N'The public client is /root/tsql-app-minimal/client/web, native browser ES modules, not React. It is a document interpreter: screenFrom reads the payload, the view paints it, and posts go to POST {api}/api/request with the names the server already chose. A hostname that starts with client. uses https://{the rest} as the API and https://id3.tsql.app for sign-in. The bearer is kept in sessionStorage. Home with an empty def is a menu. is_form 1 is a form. Other cards with fields are lists. A list has a New button that opens the current list base plus /new. Double-click or Enter opens that same base plus the id, so a related list stays under its parent. A list has one cursor. It starts on the first row, holds the keyboard focus, and moves by click or by Arrow Up and Arrow Down. The cursor row is painted in the accent color with light text. A card action posts that row primary key as @id. On a form the path record is @id, because that screen shows one record. On a child list the cursor is the child row and the parent id stays @parent_id. An empty list posts a null @id. The cursor stays when the same list is shown again and that id is still present. A different list starts on its first row. A new form leaves the list cursor in place. The home menu has no record cursor. The toolbar Related menu reads relations. A bound item stays disabled until a list row is selected or a form is open. On a form, fields with is_upd and not is_id are inputs. typ selects number, checkbox, date, datetime-local, textarea for nvarchar max, varchar max, and varbinary max, or text. A max field whose name is sql is a Monaco SQL editor. The editor is vendored at client/web/vendor/monaco and served from /vendor/monaco/vs. Monaco 0.34.1. Other max fields stay textareas. Save posts save true and values. Delete posts delete true and no values. Enter in a one-line form field saves. Enter in a textarea or in the SQL editor does not. Ctrl+S or Cmd+S still saves, including from inside the editor. A form shows Delete only when settings can_delete is 1 and the record is not new. After a delete the address returns to the current list base. After a created row comes back, the address keeps the current list base and adds the new id. Modal controls are text, input, and button. An input type chooses the control, including textarea, select, radio, checkbox, file, and hidden. Options are a comma list or a JSON array. A file value is the data URL of the chosen file. The client paints the label on that control and uses the input name as its id. A control with kind modal is the dialog itself and is not painted again inside it. An unknown kind is shown, not dropped. Enter submits the button marked Enter, or the only button. Escape closes unless a button is marked Escape. The earlier vanilla file client/static is not served. The Tracy copy is archived at /root/backups/client-miss-piggy-tracy and is not served.'),
(N'client.react', N'fact', N'Existing Tracy client, archived',
 N'This was a copy of the existing Tracy React client, not a client built for this proof of concept. It is archived at /root/backups/client-miss-piggy-tracy and is not served. The old public path was /var/www/client-miss-piggy. index.html loads static/js/main.8fd199a0.js. The untouched build main.1de9db12.js is still on disk. Hashed files under /static/ are cached immutable for one year, so a script change needs a new file name and an index.html edit. config.js sets staticApiBaseUrl empty and pins both auth servers to https://id3.tsql.app. A hostname that starts with client. probes GET https://{host without client.}/ . Status 200, 400, or 401 means that origin is the API. The screen fetch sends Authorization: Bearer from the module bearer or the React state bearer, and otherwise a ticket-token header. Settings are objects {k, v}. The shell paints one breadcrumb and the json.actions buttons whenever actions is truthy. An empty array is truthy, so the home screen sends actions null. The Actions view paints header items as links to /{name} and then paints that same bar again, so a card does not include it. Home views are Actions only. A card view is Detailview when is_form is 1, otherwise Listview. Menu header items are {id, name, disp, keycode}. List def.att must be a string. Modalview is omitted because its item shape does not match our modal controls. An authenticated user is not redirected to /account/login. That redirect runs only while the auth state is unauthenticated.'),
(N'modal.loop', N'rule', N'Read, then act, then render',
 N'The same procedure runs on every post. Declare every variable at the top of the batch. Assign every argument to a variable before calling any sp_api_* procedure. Read posted values with sp_api_modal_get_value before any render. Act when a button variable is not null. On success call sp_api_modal_clear and RETURN. Then render with sp_api_modal_modal, text, input, and button. A caption is the label parameter of sp_api_modal_input, not a separate procedure. The type parameter chooses the control: an HTML input type, textarea, select, radio, checkbox, file, or hidden. Options are a comma-separated list or a JSON array of id and name. Multiple posts the chosen ids separated by commas. A checkbox with no options posts 1 or 0. A file posts the data URL of the chosen file. A hidden field is posted and not shown. The client paints the caption on that control and uses the input name as its id. Rendering a button copies the click into @out and clears that posted slot, so a later get_value loses the click. sp_api_modal_clear does not stop the batch and does not delete toasts or api_session_storage. sp_api_modal_set and sp_api_modal_get survive clear. Input overwrites @value only when a post row exists. The first call, with no post, falls through to render. After clear, the next call is a fresh one. sp_api_request re-enters the open modal action when is_open is 1, the stored path matches, and the request has no explicit action. A different path closes the modal. When the open modal has an action id, the modal JSON includes edit as /ide_action/ plus that id, plus is_system and ide_role from that card. The client paints Edit when edit is a path and, if is_system is 1, the token claim role matches a value in ide_role. A blank ide_role leaves the button in. The client does not contain a role name. The form there edits the action, and the sql field is the button code. For a stored_procedure action, a non-blank api_card_actions.sql value is the batch that runs. A blank sql falls back to EXEC dbo.[name]. A live edit of that column replaces the seed script until the row is updated again.'),
(N'card.from_table', N'rule', N'sp_api_card_from_table',
 N'EXEC dbo.sp_api_card_from_table @table = N''customer_note'' creates an api_card from a table or view and then calls sp_api_card_create_cache. The card name defaults to the object name. Pass @name to choose another. id_column defaults to a column named id, then a single-column primary key, then an identity column. A missing id throws before the card row is inserted. tablename is the object name when the source is in the main database dbo, otherwise a schema or three-part name. basetable is set when the source is a user table in the main database dbo, so the form can save. A view leaves basetable empty unless @basetable names a user table there. is_system is 1 when the source database is dbo.main_db() plus _proj, and 0 for the business database. in_main_menu defaults to 1 and record_limit to 50. An existing card name throws. The cache builder seeds one field per column and hides the id field. Do not write the card or the caches by hand.'),
(N'cache.builder', N'rule', N'sp_api_card_create_cache',
 N'Build caches only with EXEC dbo.sp_api_card_create_cache @card_id, @toast = 1. Never write list_select_cache, select_cache, or declare_cache by hand. Set id_column before building. A NULL id_column updates api_card.error and then throws the exact text sp_api_card_create_cache NO ID! from outside the TRY. Look up the card id by name. Do not use SCOPE_IDENTITY across batches. Rebuild after a change to fields, field sql, tablename, reducer, or the view. The list statement is SELECT ... FROM [demo].[dbo].[view] AS t WHERE (1 = 1) AND (reducer), with no TOP or ORDER BY inside the cache. The dispatcher applies record_limit and sorting_order. Validation runs the same text with WHERE (1 = 0). declare_cache declares one variable per field, id first. select_cache assigns those variables for t.[id] = @id. Semicolons are rejected in field sql, reducer, sorting, and crud_read. If the card has no field rows, the builder inserts one row per source column inside the successful transaction. Create the card row with sp_api_card_from_table, which then calls this builder.'),
(N'sql.pitfalls', N'pitfall', N'THROW, session context, and pooling',
 N'THROW messages must be nvarchar(2048), not nvarchar(4000) or max. Every THROW argument is a literal, or every argument is a variable. Mixing them is a syntax error. End the statement before THROW with a semicolon. An IF without BEGIN/END owns only the next statement, so a following THROW runs even when the IF is false. CATCH uses ;THROW, and the saved message is LEFT(ERROR_MESSAGE(), 2048). sp_set_session_context rejects NULL and nvarchar(max). Skip NULL keys and cast long strings to nvarchar(4000). pyodbc pooling is on. sp_api_request clears id, ids, card_name, card_id, action_id, tablename, basetable, sub, parent_id, parent_card_name, and parent_card_id with a named NULL before writing the current request, because a pooled connection would otherwise keep them. A positional NULL is rejected. Each browser click was an OPTIONS preflight plus a POST. The API sends Access-Control-Max-Age 7200 so the browser can skip the repeat preflight. dbo.main_db() returns SESSION_CONTEXT(main_db) or DB_NAME() with a trailing _proj removed. Trusted metadata may be executed. Client input is bound through OPENJSON and is never concatenated. FOR JSON escapes a JSON text column. JSON_QUERY has to be the outer expression, so action params uses JSON_QUERY around the CASE that checks ISJSON. A CASE around JSON_QUERY leaves the client a string, and pathname navigation then has no path. EXEC arguments must be variables or literals. A CASE expression in that argument list is a syntax error. JSON_MODIFY requires a string literal for its path.'),
(N'sample.customer', N'fact', N'Customer sample',
 N'Sample cards are metadata plus business tables. Read dbo.api_card, dbo.api_card_fields, and dbo.api_card_actions for the live shape. Read demo for the business rows. Do not copy either result into this graph. sql/05_sample.sql is a seed and it drops demo.dbo.customer. Live rows may differ from that seed. Do not overwrite them to match the script. A field with its own sql is computed and is not written. detail_order 0 hides a field on the form. list_order 0 hides it on the list. Hello, Note, Wizard, and Label are stored_procedure actions. Their contract is read, then act, then render, with every sp_api_* argument assigned first. Hello reads demo.dbo.customer.customer_name for @id and shows an h1 of hello plus that name. A missing row toasts Choose a customer. Label shows the heading The input Element, a text field captioned First name:, and Submit. An empty name toasts First name is required and the dialog stays open. A name toasts First name: plus that value, then clears the modal and returns. Label does not write a customer or note row and does not require a selected row. sql/12_label.sql inserts that action when the name is absent and does not change an existing row. The live api_card_actions.sql column can diverge from the seed file. Read that column and the procedure definition. customer_note is a card created with sp_api_card_from_table. A list-only column keeps the table default.'),
(N'dispatch.json', N'fact', N'JSON the client reads',
 N'Payload keys are data, def, actions, relations, settings, breadcrumbs, views, statusbar, querystring, plus session, modal, toasts, cleared, error, and header. relations is null on home and an array on a card. Each item has name, disp, keycode, unbound, and ref. A nested path /parent/id/child opens the child list. /parent/id/child/record opens that child form. The id token - means there is no parent record. def columns used by the client are name, disp, typ, att, is_id, is_upd, is_hid, cls, fid, and id. att is an empty string rather than NULL, and id is repeated as fid. settings rows are {k, v} and include cardname, user, main_db, id_column, record_limit, auto_refresh_seconds, is_form, is_list, and can_delete. can_delete is the string 1 or 0. is_form and is_list are the strings 0 and 1. is_list is 0 on a form. Breadcrumb items use disp, card_name, pathname, and search. The client adds the Home crumb itself. Home actions is null and views is Actions over header. A card actions array feeds the shell buttons, and views is only Listview or Detailview. crud_read NULL means allowed. The predicate 1=0 denies the read with the text Read is not allowed for this card. The path token new is a blank form and its breadcrumb says New. def.typ is data_type when that is set, otherwise the base-column type name. is_upd is 1 only when the field is not the id, detail_order is above 0, and field sql is empty. POST save 1 with values calls sp_api_card_save, which writes the base table through parameters. A failed save returns that object as data plus an error of the form {name} is missing or not valid. Success toasts Saved. A save does not re-enter an open modal. POST delete 1 calls the same procedure with its delete flag and does not require values. Success toasts Deleted and returns the list. A failed delete keeps the form and the error.'),
(N'verified.login', N'verified', N'How to verify a screen',
 N'A verification is a procedure, not a snapshot. Re-run client/web/test/contract.test.mjs and client/web/test/loop_check.py. Drive one screen with dbo.sp_api_request or the deployed client. Record a new invariant here only when the code contract changes. Do not record row values, session ids, or who was signed in. tests/run_tests.py expects a menu path the dispatcher does not emit. Do not use it as a health check. Home must send actions null, or the shell paints the toolbar twice. A card view is Listview or Detailview only. A missing or rejected bearer returns 401 before SQL.'),
(N'ide.card', N'rule', N'Card metadata IDE',
 N'Menu card ide edits api_card. ide_field and ide_action edit api_card_fields and api_card_actions and stay off the home menu. Read those cards for the current columns, labels, and keycodes. A nvarchar(max) field named sql is a Monaco SQL editor. Any other nvarchar(max) field is a textarea. Delete posts delete true. sp_api_card_save reads crud_delete. NULL or blank means allowed. The predicate 1=0 denies with the text Delete is not allowed for this card. A blank id returns Choose a record to delete. Zero rows returns Record was not found. A bad predicate returns The save rule is not a single expression. or The save rule failed. Settings can_delete is the string 1 or 0 from that same predicate. After a deleted api_card_fields row, the save rebuilds that field card. Deleting api_card or api_card_actions does not rebuild a cache. Action sql stays read live. Sample business cards customer and customer_note are denied delete by sql/09_crud_delete.sql, which sets crud_delete to 1=0 only where it is still NULL. The IDE cards leave crud_delete NULL, so their rows can be deleted. ide reaches the other two with pathname actions, and each child card has a pathname action back to ide. The server does not run kind pathname. The client navigates to params.pathname. sp_api_card_save writes dbo.basetable in the database named by a three-part tablename when that database is DB_NAME() or the main database. Any other database is rejected with the text This card cannot be saved. A tablename with no database part still writes the main database, so customer stays on demo. After a successful write to api_card or api_card_fields in the project database, the save rebuilds that card with sp_api_card_create_cache and toast 0. The rebuilt id is the saved api_card row, or the card_id of a saved field row. A blank id_column or tablename skips the rebuild. A cache failure returns the error text instead of the Saved toast. Action sql is read live and is not rebuilt. The seed is sql/07_ide.sql. It deletes and recreates only those three cards. api_card.is_system defaults to 0. When it is 1 and ide_role names roles, the UI checks the token claim role and the server withholds the card unless the caller has one listed role. A blank ide_role does not restrict the card. is_system 0 does not consult ide_role, so a business card stays usable. A card is a system card when the database in tablename is the project database, dbo.main_db() plus _proj. A table in the business database is not a system card. A name without a database is the business database. sql/11_is_system.sql applies that rule. sp_api_card_from_table and sp_api_card_create_cache set the bit the same way. Read the column for the live value. sql/10_ide_role.sql adds the column and, when ide_action.ide_role is blank, sets it to admin. sql/07_ide.sql writes that same value when it recreates the card. The IDE form does not include ide_role or is_system, so a save of card ide cannot clear them. The client does not contain a role name. A full apply runs that file after the sample script because the names sort that way.'),
(N'relation.cards', N'rule', N'Related cards',
 N'api_card_children stores a related card. parent and child are api_card ids. Bound (unbound 0) filters the child list with WHERE the ref column equals the parent record id. Unbound (unbound 1) uses the reducer expression instead of that link. The list is still opened at /parent/id/child. A dash in place of the id means there is no parent record, which only an unbound relation allows. is_hidden rows are omitted from the menu. The client shows them in a Related menu. A bound item stays disabled until a list row is selected or a form is open. The seed is sql/08_relations.sql. It merges example relations and leaves every other row in place. Read dbo.api_card_children for the live menu. A new child row prefills the link column. Saving a new child keeps the parent path. The child list wraps the cache as cached and filters with output column names, so a reducer writes status rather than t.status. The parent id is a parameter. Keycodes stay null so Enter still opens the selected row. Two relations that share one child card collide in the path, and the lookup keeps the bound row. Exact errors are Unknown relation, Choose a record to open this related card, This relation has no link column, The relation filter is not a single expression, and This record is not part of the related card. A bound form whose link is missing or differs returns the last of those and an empty data array. JSON_MODIFY needs a literal path, so the checked ref is pasted into its own batch.'),
(N'open.work', N'open', N'Left undone on purpose',
 N'The public client renders modal text, input, and button. A caption is the input label parameter, not another procedure. The input type covers textarea, select, radio, checkbox, file, and hidden. Action kinds pathname and reducer are named in the task. The server executes only stored_procedure. The client navigates when the action kind is pathname and params.pathname is set. A result grid procedure is not built. A dropdown is an input with type select. A dedicated low-privilege SQL login was requested by the operator and is not created. api_card.role and deny_role are not enforced. api_card.is_system 1 makes the UI verify the token claim role against ide_role. is_system 0 leaves regular card use open. Audience is ignored on purpose so the check matches Tracy. The archived Tracy copy does not follow later master deploys.'),
(N'ops.paths', N'map', N'Where things live',
 N'Project root /root/tsql-app-minimal. The project is the private git repository https://github.com/rhodelta66/tsql-app-minimal on account rhodelta66. The agent procedure is /root/tsql-app-minimal/.grok/skills/miss-piggy/SKILL.md. /root/.grok/skills/miss-piggy is a symlink to that directory. .env stays untracked. API log /tmp/tsql-app-logs/server.log. Apply with scripts/apply.sh only when a drop of demo and demo_proj is intended. Operator mailbox /beheer/vps-manager/in-box and out-box. The file name is the tag, and the reply uses the same tag. Questions already answered: Q-261027-client-vhost, Q-261027-api-vhost, Q-261027-lift-api-acl. Nginx backups /root/backups/nginx-miss-piggy.before-api-front and /root/backups/nginx-miss-piggy.before-lift-acl. Query prose with SELECT entry_key, kind, title, body FROM knowledge.v_entry ORDER BY kind, entry_key. Walk relations with SELECT from_key, rel, to_key, note FROM knowledge.v_link ORDER BY from_key, rel. The framework document is /root/tsql-app-minimal/docs/framework.md.'),
(N'doc.framework', N'map', N'Framework documentation',
 N'The state and the plan live in /root/tsql-app-minimal/docs/framework.md. The file is markdown. It follows the invariants in knowledge.v_entry. When an invariant changes, update the matching entry and that file together. Do not copy queryable rows into either place. Do not put the SQL password in the file.'),
(N'graph.query', N'map', N'How to walk the knowledge graph',
 N'Topics live in knowledge.topic, a NODE table, one row per knowledge.entry. Links live in knowledge.link, an EDGE table, with rel, origin, and note. origin seed is replaced when this script runs. Any other origin stays. Read SELECT from_key, rel, to_key, note FROM knowledge.v_link ORDER BY from_key, rel. Neighbors of one key: SELECT rel, to_key AS other FROM knowledge.v_link WHERE from_key = N''client.poc'' UNION ALL SELECT rel, from_key FROM knowledge.v_link WHERE to_key = N''client.poc''. Join v_link.to_key to knowledge.entry.entry_key for the prose. Add a lasting relation with INSERT INTO knowledge.link ($from_id, $to_id, rel, origin, note) SELECT f.$node_id, t.$node_id, N''rel'', N''note'', N''why'' FROM knowledge.topic AS f JOIN knowledge.topic AS t ON t.entry_key = N''target'' WHERE f.entry_key = N''source''. Read knowledge.v_entry and knowledge.v_link before changing the client or the dispatcher. Store fishing gear: the query, the invariant, and where to look. Do not store fish: row values, credits, note text, session ids, or a key id that a URL or a SELECT returns. When an invariant changes, update that entry here and run this script again. Leave edges whose origin is not seed in place.');

MERGE knowledge.entry AS t
USING @seed AS s
    ON t.entry_key = s.entry_key
WHEN MATCHED AND (t.kind <> s.kind OR t.title <> s.title OR t.body <> s.body) THEN
    UPDATE SET kind = s.kind, title = s.title, body = s.body, updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (entry_key, kind, title, body)
    VALUES (s.entry_key, s.kind, s.title, s.body);
GO

IF OBJECT_ID(N'knowledge.topic', N'U') IS NULL
    CREATE TABLE knowledge.topic (
        entry_key nvarchar(128) NOT NULL CONSTRAINT pk_knowledge_topic PRIMARY KEY,
        kind      nvarchar(32)  NOT NULL,
        title     nvarchar(200) NOT NULL
    ) AS NODE;
GO

IF OBJECT_ID(N'knowledge.link', N'U') IS NULL
    CREATE TABLE knowledge.link (
        rel    nvarchar(64)  NOT NULL,
        origin nvarchar(16)  NOT NULL CONSTRAINT df_knowledge_link_origin DEFAULT (N'seed'),
        note   nvarchar(400) NULL,
        CONSTRAINT ec_knowledge_link CONNECTION (knowledge.topic TO knowledge.topic) ON DELETE CASCADE
    ) AS EDGE;
GO

MERGE knowledge.topic AS t
USING (
    SELECT entry_key, kind, title
    FROM knowledge.entry
) AS s
    ON t.entry_key = s.entry_key
WHEN MATCHED AND (t.kind <> s.kind OR t.title <> s.title) THEN
    UPDATE SET kind = s.kind, title = s.title
WHEN NOT MATCHED BY TARGET THEN
    INSERT (entry_key, kind, title)
    VALUES (s.entry_key, s.kind, s.title);
GO

DELETE FROM knowledge.link WHERE origin = N'seed';
GO

DECLARE @links TABLE (
    from_key nvarchar(128) NOT NULL,
    rel      nvarchar(64)  NOT NULL,
    to_key   nvarchar(128) NOT NULL,
    note     nvarchar(400) NULL,
    PRIMARY KEY (from_key, rel, to_key)
);

INSERT INTO @links (from_key, rel, to_key, note) VALUES
(N'client.poc', N'authenticates_with', N'auth.id3', N'POST /login and /login/verify. Bearer JWT. Issuer must be https://id3.tsql.app.'),
(N'client.poc', N'reads', N'dispatch.json', N'POST /api/request. Settings are {k, v}. Modal controls use kind.'),
(N'client.poc', N'served_by', N'map.nginx', N'client.miss-piggy.tsql.app serves /var/www/client-miss-piggy. API is https://miss-piggy.tsql.app.'),
(N'client.poc', N'renders', N'modal.loop', N'text, input, and button. An input type chooses the control. Options are choices on that same input. kind modal is the dialog. Unknown kinds are shown.'),
(N'client.poc', N'edits', N'sample.customer', N'Form mode posts save and values. A list opens the current base plus the id. New opens that base plus /new. A related list keeps the parent prefix.'),
(N'map.nginx', N'proxies', N'map.layout', N'API vhost proxies to 127.0.0.1:8765.'),
(N'dispatch.json', N'describes', N'sample.customer', N'Customer list and form payload.'),
(N'cache.builder', N'materializes', N'sample.customer', N'list_select_cache, select_cache, and declare_cache.'),
(N'cache.builder', N'creates', N'card.from_table', N'sp_api_card_from_table inserts the card, then create_cache seeds fields and compiles the three caches.'),
(N'modal.loop', N'drives', N'sample.customer', N'Note and Wizard call back into the same procedure. Label is inline action SQL for the captioned input example.'),
(N'sql.pitfalls', N'constrains', N'cache.builder', N'THROW width, WHERE 1=0 validation, no hand-written cache.'),
(N'sql.pitfalls', N'constrains', N'modal.loop', N'Clear does not stop the batch. Read before render.'),
(N'verified.login', N'observed', N'client.react', N'A card sends Listview or Detailview only, so the shell does not paint the toolbar twice.'),
(N'verified.login', N'observed', N'sample.customer', N'Query the business tables when you need the rows. Do not copy them into this graph.'),
(N'verified.login', N'observed', N'client.poc', N'Re-run the contract tests and loop_check.py. Do not archive their output here.'),
(N'ops.paths', N'locates', N'map.layout', N'Project root, databases, and the apply script.'),
(N'ops.paths', N'locates', N'map.nginx', N'Vhost files and nginx backups.'),
(N'ops.paths', N'locates', N'doc.framework', N'The markdown state and plan.'),
(N'doc.framework', N'describes', N'client.poc', N'The file covers the client, the dispatcher, cards, relations, and the work still open.'),
(N'auth.id3', N'gates', N'dispatch.json', N'A rejected bearer returns 401 before any SQL.'),
(N'auth.id3', N'gates', N'ide.card', N'Caller roles come from the token claim role. A system card, is_system 1, is shown only when a claim matches ide_role. The body cannot set roles.'),
(N'client.poc', N'edits', N'ide.card', N'Home card ide edits api_card. Fields and Actions are pathname links.'),
(N'ide.card', N'rebuilds', N'cache.builder', N'A save of api_card or api_card_fields calls sp_api_card_create_cache.'),
(N'client.poc', N'reads', N'relation.cards', N'The Related menu reads the relations array and opens /parent/id/child.'),
(N'relation.cards', N'filters', N'sample.customer', N'Join api_card_children to api_card. A bound row filters on ref. An unbound row filters on reducer.'),
(N'verified.login', N'observed', N'relation.cards', N'Prove a relation by requesting the nested path. Do not record which rows came back.'),
(N'open.work', N'bounds', N'client.poc', N'What stays unbuilt. Read this before adding a subsystem.'),
(N'sql.pitfalls', N'constrains', N'relation.cards', N'JSON_QUERY must wrap the relations array. EXEC arguments cannot be CASE. JSON_MODIFY path must be a literal.');

INSERT INTO knowledge.link ($from_id, $to_id, rel, origin, note)
SELECT f.$node_id, t.$node_id, s.rel, N'seed', s.note
FROM @links AS s
JOIN knowledge.topic AS f ON f.entry_key = s.from_key
JOIN knowledge.topic AS t ON t.entry_key = s.to_key
WHERE NOT EXISTS (
    SELECT 1
    FROM knowledge.link AS already
    WHERE already.$from_id = f.$node_id
      AND already.$to_id = t.$node_id
      AND already.rel = s.rel
);
GO

CREATE OR ALTER VIEW knowledge.v_link
AS
SELECT
    f.entry_key AS from_key,
    f.kind AS from_kind,
    l.rel,
    l.note,
    l.origin,
    t.entry_key AS to_key,
    t.kind AS to_kind
FROM knowledge.topic AS f,
     knowledge.link AS l,
     knowledge.topic AS t
WHERE MATCH(f-(l)->t);
GO
