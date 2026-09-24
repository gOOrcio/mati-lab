#!/usr/bin/env python3
"""Shared checklist state for the Wysowa family site (plan.html) — one JSON file, stdlib only.

  GET  /api/stan               -> {"stan": {id: {"v": bool, "kto": str, "kiedy": iso}}}
  POST /api/stan {"id", "v"}   -> same, after setting one checkbox

Who ticked it comes from the Cf-Access-Authenticated-User-Email header that
Cloudflare Access adds; nginx is reachable only through the mapa tunnel, so the
header can't come from anywhere else. Every change is also appended to
historia.jsonl (audit trail, never rewritten).

CLI (same file lock, so safe next to the server):
  docker exec mapa-stan python /app/stan.py pokaz
  docker exec mapa-stan python /app/stan.py ustaw f1_gison 1 [--kto claude]
"""
import fcntl
import json
import os
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA = Path(os.environ.get("STAN_DIR", "/data"))
PLIK = DATA / "stan.json"
HISTORIA = DATA / "historia.jsonl"
LOCK = DATA / ".lock"
ID_OK = re.compile(r"^[a-z0-9_]{1,64}$")


def _czytaj():
    try:
        return json.loads(PLIK.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def pokaz():
    with open(LOCK, "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_SH)
        return _czytaj()


def ustaw(id_, v, kto):
    wpis = {"v": bool(v), "kto": kto, "kiedy": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    with open(LOCK, "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        stan = _czytaj()
        stan[id_] = wpis
        tmp = PLIK.with_suffix(".tmp")
        tmp.write_text(json.dumps(stan, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
        os.replace(tmp, PLIK)
        with open(HISTORIA, "a", encoding="utf-8") as h:
            h.write(json.dumps({"id": id_, **wpis}, ensure_ascii=False) + "\n")
        return stan


class Handler(BaseHTTPRequestHandler):
    server_version = "stan"
    sys_version = ""

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?")[0] != "/api/stan":
            return self._json(404, {"blad": "nie ma"})
        self._json(200, {"stan": pokaz()})

    def do_POST(self):
        if self.path != "/api/stan":
            return self._json(404, {"blad": "nie ma"})
        # JSON-only: a cross-site form can't send this content type without a CORS preflight.
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            return self._json(415, {"blad": "tylko application/json"})
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n > 1024:
                raise ValueError
            req = json.loads(self.rfile.read(n))
            id_, v = req["id"], req["v"]
            if not isinstance(id_, str) or not ID_OK.match(id_) or not isinstance(v, bool):
                raise ValueError
        except (ValueError, KeyError, TypeError):
            return self._json(400, {"blad": "zle dane"})
        kto = self.headers.get("Cf-Access-Authenticated-User-Email", "") or "nieznany"
        self._json(200, {"stan": ustaw(id_, v, kto)})

    def log_message(self, fmt, *args):  # one line per request to stdout (Promtail picks it up)
        sys.stdout.write("%s %s\n" % (self.headers.get("Cf-Access-Authenticated-User-Email", "-") if hasattr(self, "headers") else "-", fmt % args))
        sys.stdout.flush()


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    if args[:1] == ["pokaz"]:
        print(json.dumps(pokaz(), ensure_ascii=False, indent=1, sort_keys=True))
    elif args[:1] == ["ustaw"] and len(args) >= 3 and ID_OK.match(args[1]) and args[2] in ("0", "1"):
        kto = args[4] if len(args) >= 5 and args[3] == "--kto" else "cli"
        ustaw(args[1], args[2] == "1", kto)
        print(f"{args[1]} = {args[2]} ({kto})")
    elif not args:
        ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
