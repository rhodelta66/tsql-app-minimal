"""SQL Server access for the minimal TSQL.APP loop."""

import json
import os
from pathlib import Path

import pyodbc

# Session context is connection-scoped. sp_api_request clears the keys it
# might skip before it writes the current request, so pooled connections
# do not carry the previous id, card, or action.
pyodbc.pooling = True

ROOT = Path(__file__).resolve().parents[1]


def load_env(path=None):
    vals = {}
    env_path = Path(path) if path else ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            vals[key.strip()] = value.strip().strip('"').strip("'")
    return vals


def connect(database=None):
    env = load_env()
    db = database or os.environ.get("SQL_DATABASE") or env.get("SQL_DATABASE") or "demo_proj"
    server = os.environ.get("SQL_SERVER") or env.get("SQL_SERVER") or "localhost,41300"
    user = os.environ.get("SQL_USER") or env.get("SQL_USER") or "sa"
    password = os.environ.get("SQL_PASSWORD") or env.get("SQL_PASSWORD") or ""
    connection_string = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};"
        f"UID={user};"
        f"PWD={password};"
        f"DATABASE={db};"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(connection_string, autocommit=True, timeout=30)


def fetch_all(sql, params=None, database=None):
    with connect(database) as conn:
        cur = conn.cursor()
        cur.execute(sql, params or [])
        if cur.description is None:
            return []
        columns = [col[0] for col in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]


def fetch_one(sql, params=None, database=None):
    rows = fetch_all(sql, params, database)
    return rows[0] if rows else None


def execute(sql, params=None, database=None):
    with connect(database) as conn:
        cur = conn.cursor()
        cur.execute(sql, params or [])
        return cur.rowcount


def _roles_json(roles):
    """JSON array of role names. None means the caller did not supply any."""
    if roles is None:
        return None
    if isinstance(roles, str):
        names = [roles]
    else:
        names = [name for name in roles if isinstance(name, str)]
    clean = []
    seen = set()
    for name in names:
        text = name.strip()[:128]
        if not text or text.casefold() in seen:
            continue
        seen.add(text.casefold())
        clean.append(text)
    return json.dumps(clean)


def request(session=None, pathname="/", posted=None, action=None, id=None, ids=None, close=False, user_email=None, user_sub=None, save=False, values=None, delete=False, roles=None):
    posted_json = json.dumps(posted if posted is not None else {})
    values_json = None if values is None else json.dumps(values)
    roles_json = _roles_json(roles)
    sql = """
SET NOCOUNT ON;
DECLARE @token nvarchar(64) = ?;
DECLARE @path nvarchar(400) = ?;
DECLARE @posted nvarchar(max) = ?;
DECLARE @action nvarchar(128) = ?;
DECLARE @id nvarchar(max) = ?;
DECLARE @ids nvarchar(max) = ?;
DECLARE @close bit = ?;
DECLARE @caller_email nvarchar(256) = ?;
DECLARE @caller_sub nvarchar(256) = ?;
DECLARE @save bit = ?;
DECLARE @values nvarchar(max) = ?;
DECLARE @delete bit = ?;
DECLARE @roles nvarchar(max) = ?;
EXEC dbo.sp_api_request
    @session_token = @token,
    @pathname = @path,
    @posted_json = @posted,
    @action = @action,
    @id = @id,
    @ids = @ids,
    @close = @close,
    @caller_email = @caller_email,
    @caller_sub = @caller_sub,
    @save = @save,
    @values_json = @values,
    @delete = @delete,
    @caller_roles = @roles;
"""
    with connect() as conn:
        cur = conn.cursor()
        cur.setinputsizes(
            [
                (pyodbc.SQL_WVARCHAR, 64, 0),
                (pyodbc.SQL_WVARCHAR, 400, 0),
                (pyodbc.SQL_WVARCHAR, 0, 0),
                (pyodbc.SQL_WVARCHAR, 128, 0),
                (pyodbc.SQL_WVARCHAR, 0, 0),
                (pyodbc.SQL_WVARCHAR, 0, 0),
                (pyodbc.SQL_BIT, 1, 0),
                (pyodbc.SQL_WVARCHAR, 256, 0),
                (pyodbc.SQL_WVARCHAR, 256, 0),
                (pyodbc.SQL_BIT, 1, 0),
                (pyodbc.SQL_WVARCHAR, 0, 0),
                (pyodbc.SQL_BIT, 1, 0),
                (pyodbc.SQL_WVARCHAR, 0, 0),
            ]
        )
        cur.execute(
            sql,
            session,
            pathname or "/",
            posted_json,
            action,
            None if id is None else str(id),
            None if ids is None else str(ids),
            1 if close else 0,
            user_email,
            user_sub,
            1 if save else 0,
            values_json,
            1 if delete else 0,
            roles_json,
        )
        row = None
        while True:
            if cur.description is not None:
                row = cur.fetchone()
                break
            if not cur.nextset():
                break
    if row is None or row[0] is None:
        raise RuntimeError("sp_api_request returned no payload")
    return json.loads(row[0])
