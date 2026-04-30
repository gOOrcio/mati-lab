#!/usr/bin/env bash
# Phase 8 Task 6 — daily NAS health probe.
#
# Runs once a day. Silent on green; ntfys on:
#   - any pool not ONLINE
#   - any pool >= 80% full
#   - any disk reporting SMART failure
#   - heartbeat to Kuma push URL on every clean run
#
# Doesn't depend on Prometheus or any exporter — reaches into ZFS state
# directly via `zpool` / `midclt`. Cheap, no metric round-trip.

set -uo pipefail

NTFY_URL="${NTFY_URL:-https://ntfy.mati-lab.online/homelab-alerts}"
NTFY_TOKEN_FILE=/mnt/bulk/backups/.secrets/ntfy-token

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_ZFS_HEALTH:-}"

# Capability checks — fail loud if the tools moved
command -v zpool   >/dev/null || { echo "no zpool in PATH" >&2; exit 2; }
command -v midclt  >/dev/null || { echo "no midclt in PATH" >&2; exit 2; }
command -v curl    >/dev/null || { echo "no curl in PATH"   >&2; exit 2; }

BAD_POOLS=$(zpool list -H -o name,health 2>&1 | awk -F'\t' '$2 != "ONLINE" {print "  " $1 " = " $2}')
FULL_POOLS=$(zpool list -H -o name,capacity 2>&1 \
  | awk -F'\t' '{ gsub(/%/,"",$2); if ($2+0 >= 80) print "  " $1 " = " $2 "% full" }')

BAD_SMART=$(midclt call disk.query 2>/dev/null | python3 -c "
import sys, json
try:
  for d in json.load(sys.stdin):
    if d.get('passed_smart_test') is False:
      print(f\"  {d.get('name','?')} = SMART failed\")
except Exception:
  pass" || true)

if [ -n "$BAD_POOLS$FULL_POOLS$BAD_SMART" ]; then
  MSG=$(printf 'Pools not ONLINE:\n%s\n\nPools >= 80%% full:\n%s\n\nSMART:\n%s\n' \
    "${BAD_POOLS:-  (none)}" "${FULL_POOLS:-  (none)}" "${BAD_SMART:-  (none)}")
  HDRS=(-H "Title: NAS health alert" -H "Priority: high" -H "Tags: warning,zfs")
  if [ -f "$NTFY_TOKEN_FILE" ]; then
    HDRS+=(-H "Authorization: Bearer $(cat "$NTFY_TOKEN_FILE")")
  fi
  curl -fsS -m 10 "${HDRS[@]}" -d "$MSG" "$NTFY_URL" >/dev/null || true
  echo "$(date -u +%FT%TZ) ALERT fired"
  echo "$MSG"
  exit 1
fi

# Heartbeat: only when fully green, so a missed Kuma push = something
# above failed (or the cron never ran).
[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true
echo "$(date -u +%FT%TZ) zfs health green"
