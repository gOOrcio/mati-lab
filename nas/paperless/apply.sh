#!/bin/bash
# Create or update the paperless-ngx catalogue app with secrets substituted on the NAS.
#
# Runs as root (via the temp-cron channel, see nas/paperless/notes.md). Reads the
# committed config with __FROM_PM__<pm-label> placeholders from /tmp/paperless-app.json
# and the values from VALUES (lines `<pm-label>=<value>`, root 0600). Secret values
# never reach stdout: the log in /tmp/paperless-apply.out is redacted.
#
# Usage: bash apply.sh create|update
set -uo pipefail
MODE="${1:?usage: apply.sh create|update}"
VALUES=/mnt/fast/databases/paperless-apply/values.conf
CFG=/tmp/paperless-app.json
OUT=/tmp/paperless-apply.out
exec > "$OUT" 2>&1
trap 'rm -f "$CFG" /tmp/paperless-app.rendered.json; chmod 644 "$OUT"' EXIT

python3 - "$MODE" "$VALUES" "$CFG" <<'PY'
import json, re, subprocess, sys
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
if mode == "create":
    args = ["midclt", "call", "-j", "app.create", json.dumps(cfg)]
elif mode == "update":
    args = ["midclt", "call", "-j", "app.update", cfg["app_name"], json.dumps({"values": cfg["values"]})]
else:
    sys.exit("mode must be create or update")
r = subprocess.run(args, capture_output=True, text=True)
log = r.stdout[-3000:] + r.stderr[-3000:]
for v in vals.values():
    if v:
        log = log.replace(v, "<redacted>")
print(log)
print(f"apply.sh {mode}: exit {r.returncode}")
sys.exit(r.returncode)
PY
