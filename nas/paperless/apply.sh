#!/bin/bash
# Create or update the paperless-ngx catalogue app with secrets substituted on the NAS.
#
# Runs as root (via the temp-cron channel, see nas/paperless/notes.md). Reads the
# committed config with __FROM_PM__<pm-label> placeholders from STAGE/app.json
# and the values from VALUES (lines `<pm-label>=<value>`, root 0600). Secret values
# never reach stdout or argv: the payload goes over the middleware socket
# (truenas_api_client), and the log in STAGE/apply.out is redacted.
#
# Usage: bash apply.sh create|update   (STAGE = directory this script lives in)
set -uo pipefail
MODE="${1:?usage: apply.sh create|update}"
VALUES=/mnt/fast/databases/paperless-apply/values.conf
STAGE="$(cd "$(dirname "$0")" && pwd)"
CFG="$STAGE/app.json"
OUT="$STAGE/apply.out"
OWNER=truenas_admin
# Refuse a staging dir anyone but the operator could have tampered with.
for f in "$STAGE" "$0" "$CFG"; do
  [ "$(stat -c %U "$f")" = "$OWNER" ] || { echo "refusing: $f not owned by $OWNER" >&2; exit 2; }
  [ $(( 0$(stat -c %a "$f") & 022 )) -eq 0 ] || { echo "refusing: $f is group/world-writable" >&2; exit 2; }
done
exec > "$OUT" 2>&1
trap 'rm -f "$CFG"; chown "$OWNER" "$OUT"; chmod 600 "$OUT"' EXIT

python3 - "$MODE" "$VALUES" "$CFG" <<'PY'
import json, re, sys
mode, values_path, cfg_path = sys.argv[1:4]
vals = {}
for line in open(values_path):
    line = line.rstrip("\n")
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        vals[k.strip()] = v
text = open(cfg_path).read()
for k, v in vals.items():
    # values are inserted inside JSON strings, sometimes doubly nested (SOCIALACCOUNT_PROVIDERS)
    if not re.fullmatch(r"[A-Za-z0-9_.~-]+", v):
        sys.exit(f"value for {k} has characters other than [A-Za-z0-9_.~-]; regenerate with openssl rand -hex")
    text = text.replace("__FROM_PM__" + k, v)
left = sorted(set(re.findall(r"__FROM_PM__[A-Za-z0-9/_.-]+", text)))
if left:
    sys.exit("missing values for: " + ", ".join(left))
cfg = json.loads(text)
from truenas_api_client import Client
rc, log = 0, ""
try:
    with Client() as c:
        if mode == "create":
            res = c.call("app.create", cfg, job=True)
        elif mode == "update":
            res = c.call("app.update", cfg["app_name"], {"values": cfg["values"]}, job=True)
        else:
            sys.exit("mode must be create or update")
        log = "state: " + str((res or {}).get("state"))
except Exception as e:
    rc, log = 1, f"{type(e).__name__}: {e}"[-3000:]
for v in vals.values():
    if v:
        log = log.replace(v, "<redacted>")
print(log)
print(f"apply.sh {mode}: exit {rc}")
sys.exit(rc)
PY
