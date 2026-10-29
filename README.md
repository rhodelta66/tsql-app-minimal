# tsql-app-minimal

SQL Server owns the screen. `dbo.sp_api_request` returns one JSON payload, and the browser paints it. The client does not contain the business rules.

A card is a row. A button is T-SQL that reads, acts, and renders. The vocabulary stays small: a caption is `@label` on `sp_api_modal_input`, and a dropdown is that same procedure with `@type` `select`. Demo asks for a name, shows `hello` plus that name, and closes. Label is the same loop for a form. A new HTML tag does not become a new procedure.

The knowledge graph in `demo_proj` keeps the map and the rules. It stores queries, invariants, and where to look. Row values, sessions, and the SQL password stay out of it.

The product is this loop, the card cache, and a client that paints the next payload. Roles, tasks, reports, files, history, and seek wait until they are asked for. The full statement is in [docs/framework.md](docs/framework.md) under Plan.

The live client is [https://client.miss-piggy.tsql.app](https://client.miss-piggy.tsql.app). The API is [https://miss-piggy.tsql.app](https://miss-piggy.tsql.app). Sign-in is [https://id3.tsql.app](https://id3.tsql.app). A hostname that starts with `client.` calls `https://` plus the rest of that host.

The behavior, the SQL safety rules, and the plan are in [docs/framework.md](docs/framework.md). The agent procedure is [.grok/skills/miss-piggy/SKILL.md](.grok/skills/miss-piggy/SKILL.md).

## Layout

| Path | Role |
| --- | --- |
| `sql/` | Framework, sample, and knowledge scripts |
| `client/server.py` | API. Listens on `127.0.0.1` and the `PORT` from `.env` |
| `lib/` | Bearer check and the SQL call |
| `client/web/` | Native ES-module client |
| `docs/framework.md` | State of this framework |
| `.grok/skills/miss-piggy/` | Procedure for changing it |

`client/static/` is an old client and is not served.

## Configure

Copy the example and set the SQL password locally. Do not commit `.env`.

```bash
cp .env.example .env
```

`.env.example` names `SQL_SERVER`, `SQL_USER`, `SQL_PASSWORD`, `SQL_DATABASE`, and `PORT`. On this box the server is `localhost,41300`, the database is `demo_proj`, and the port is `8765`.

Install the API libraries:

```bash
python3 -m pip install 'pyodbc==5.1.0' 'PyJWT==2.7.0' 'cryptography==41.0.7'
```

`sqlcmd` from `mssql-tools18` applies the scripts. The client checks use Node.

## Databases

`scripts/apply.sh` runs every file in `sql/` and starts with `sql/00_databases.sql`, which drops `demo` and `demo_proj`. Run it only when that drop is intended.

On a live database, apply one file at a time. `sql/01_tables.sql` and `sql/05_sample.sql` are not safe to re-run. `sql/07_ide.sql` recreates the IDE cards. The per-file rules are in [docs/framework.md](docs/framework.md) under Where it runs.

```bash
set -a && source .env && set +a
/opt/mssql-tools18/bin/sqlcmd -S "$SQL_SERVER" -C -U "$SQL_USER" -P "$SQL_PASSWORD" -d demo_proj -b -f 65001 -i sql/06_knowledge.sql
```

Do not print the password.

Business tables live in `demo`. Framework metadata lives in `demo_proj`.

## API and client

The API process on this host is systemd unit `tsql-app-api.service`. Do not start a second copy. Logs are `journalctl -u tsql-app-api`.

```bash
systemctl restart tsql-app-api.service
```

Restart only when `client/server.py` or `lib/` changes. A SQL or static-file change does not need a restart.

For a local process instead of the unit:

```bash
python3 client/server.py
```

It listens on `127.0.0.1`. An unauthenticated `POST /api/request` returns `401` and `{"error":"Unauthorized"}` when the process is up.

The browser files are `client/web/`. On this host they are copied to `/var/www/client-miss-piggy/` and mode `644`:

```bash
cp -a client/web/js client/web/css /var/www/client-miss-piggy/
chmod -R a+rX /var/www/client-miss-piggy/js /var/www/client-miss-piggy/css
```

The deployed files are sent with `Cache-Control: no-cache`.

## Checks

From `client/web`:

```bash
node --test test/contract.test.mjs
python3 test/loop_check.py
```

`loop_check.py` deletes only the notes it creates. `tests/run_tests.py` is not a health check. It still expects a menu `path` the dispatcher does not emit.

## License

[MIT](LICENSE)
