#!/usr/bin/env python3
"""HTTP API. Every screen is JSON from sp_api_request."""

import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from lib.auth import AuthError, describe_rejected_bearer, verify_bearer  # noqa: E402
from lib.db import load_env, request  # noqa: E402


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, payload):
        out = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def _user(self):
        header = self.headers.get("Authorization")
        try:
            return verify_bearer(header)
        except AuthError as exc:
            ticket = self.headers.get("ticket-token")
            sys.stderr.write(
                "auth fail %s %s %s ticket=%s reason=%s\n"
                % (
                    self.command,
                    urlsplit(self.path).path or "/",
                    describe_rejected_bearer(header),
                    "yes" if ticket else "no",
                    exc,
                )
            )
            self._json(401, {"error": "Unauthorized"})
            return None

    def do_GET(self):
        self._dispatch()

    def do_POST(self):
        self._dispatch()

    def _header_value(self, name):
        value = self.headers.get(name)
        if value is None or value in ("", "null", "undefined"):
            return None
        return value

    def _dispatch(self):
        user = self._user()
        if user is None:
            return
        parts = urlsplit(self.path)
        path = parts.path or "/"
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length) if length else b""
        body = {}
        if raw:
            try:
                parsed = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "Request body is not JSON"})
                return
            if isinstance(parsed, dict):
                body = parsed
        try:
            if path == "/api/request":
                values = body.get("values")
                payload = request(
                    session=self._session_token(user),
                    pathname=body.get("pathname") or "/",
                    posted=body.get("posted") or {},
                    action=body.get("action"),
                    id=body.get("id"),
                    ids=body.get("ids"),
                    close=bool(body.get("close")),
                    user_email=user["email"],
                    user_sub=user["sub"],
                    save=bool(body.get("save")),
                    values=values if isinstance(values, dict) else None,
                    delete=bool(body.get("delete")),
                    roles=user.get("roles") or [],
                )
            else:
                posted = {}
                action = None
                nested = body.get("api_action_post")
                if isinstance(nested, dict):
                    action = nested.get("action") or nested.get("name")
                    for key, value in nested.items():
                        if not isinstance(value, (dict, list)):
                            posted[key] = value
                for key, value in body.items():
                    if key == "api_action_post" or isinstance(value, (dict, list)):
                        continue
                    posted[key] = value
                payload = request(
                    session=self._session_token(user),
                    pathname=path,
                    posted=posted,
                    action=action,
                    id=self._header_value("agfx-selected-id"),
                    ids=self._header_value("agfx-selected-ids"),
                    close=False,
                    user_email=user["email"],
                    user_sub=user["sub"],
                    roles=user.get("roles") or [],
                )
            self._json(200, payload)
        except Exception as exc:
            sys.stderr.write("request failed: %s\n" % exc)
            self._json(500, {"error": "Request failed"})

    def _session_token(self, user):
        return hashlib.sha256(("id3:" + user["sub"]).encode("utf-8")).hexdigest()[:64]

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    env = load_env()
    port = int(os.environ.get("PORT") or env.get("PORT") or 8765)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"http://127.0.0.1:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
