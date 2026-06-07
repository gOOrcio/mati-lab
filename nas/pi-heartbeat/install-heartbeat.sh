#!/usr/bin/env bash
# One-shot installer for the off-Pi heartbeat. Run as root on the NAS:
#   sudo bash /tmp/install-heartbeat.sh
# Idempotent: safe to re-run. Generates the ntfy topic once and prints it.
set -euo pipefail
SRC=/tmp/pi-heartbeat.sh
DEST=/mnt/bulk/backups/.scripts/pi-heartbeat.sh
ENVF=/root/.backup-env

[ -f "$SRC" ] || { echo "missing $SRC — scp pi-heartbeat.sh to the NAS /tmp first"; exit 1; }

# Topic: generate once, keep if already set.
if ! grep -q '^NTFY_HEARTBEAT_TOPIC=' "$ENVF" 2>/dev/null; then
  echo "NTFY_HEARTBEAT_TOPIC=mati-pi-hb-$(python3 -c 'import secrets;print(secrets.token_hex(10))')" >> "$ENVF"
fi
TOPIC="$(grep '^NTFY_HEARTBEAT_TOPIC=' "$ENVF" | cut -d= -f2)"

mkdir -p "$(dirname "$DEST")"
install -m 0755 -o root -g root "$SRC" "$DEST"
"$DEST" || true   # run once; Pi is up -> resets state, sends nothing

# Cron every 2 min (idempotent).
if midclt call cronjob.query '[["command","~","pi-heartbeat"]]' | grep -q pi-heartbeat; then
  echo "cron: already present"
else
  midclt call cronjob.create '{"user":"root","command":"'"$DEST"'","description":"Off-Pi heartbeat: alert if network Pi (.252) goes silent","enabled":true,"stdout":true,"stderr":true,"schedule":{"minute":"*/2","hour":"*","dom":"*","month":"*","dow":"*"}}' >/dev/null
  echo "cron: created (*/2 min)"
fi

# Test notification so the subscription can be confirmed.
ip="$(dig +short +time=3 +tries=1 @1.0.0.1 ntfy.sh A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)"
curl -fsS --max-time 10 ${ip:+--resolve "ntfy.sh:443:$ip"} -H "Title: heartbeat test" -H "Tags: test_tube" \
  -d "Off-Pi heartbeat is live on the NAS." "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 \
  && echo "test ntfy: SENT" || echo "test ntfy: FAILED (check NAS internet)"

echo
echo "=================================================================="
echo "  ntfy topic:  $TOPIC"
echo "  Subscribe:   ntfy app -> add subscription -> server ntfy.sh -> topic above"
echo "=================================================================="
