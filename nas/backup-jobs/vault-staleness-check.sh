#!/usr/bin/env bash
# Obsidian vault staleness check (NAS, root cron, daily).
#
# The vault reaches the NAS via two decoupled paths:
#   devices → CouchDB (obsidian-livesync)           — "the truth"
#   Mac → Syncthing → /mnt/bulk/obsidian-vault      — what rag-watcher indexes
# The 2026-09-06 sweep found the Syncthing copy 4 months stale while
# everything looked green. This check compares the two paths:
#
#   ALERT if CouchDB's update_seq has advanced since the last run
#   but the newest file in the Syncthing copy is older than STALE_HOURS —
#   i.e. notes are changing somewhere, and the indexed copy isn't moving.
#
# Also alerts if CouchDB itself is unreachable. Quiet when nothing is
# being edited (no seq movement = nothing to sync = not staleness).
#
# Creds: COUCHDB_ADMIN_USER/PASSWORD from /root/.backup-env.
# Alert path: direct ntfy publish (NTFY_CRON_TOKEN from /root/.backup-env)
# to homelab-alerts via https://ntfy.mati-lab.online (Authelia bypass).

set -uo pipefail

STATE=/mnt/bulk/backups/.scripts/.vault-staleness-state
VAULT_DIR=/mnt/bulk/obsidian-vault
STALE_HOURS=48
NTFY_URL=https://ntfy.mati-lab.online/homelab-alerts

[ -f /root/.backup-env ] && . /root/.backup-env || true

alert() {
  echo "VAULT-STALENESS ALERT: $1" >&2
  if [ -n "${NTFY_CRON_TOKEN:-}" ]; then
    curl -fsS --max-time 10 --retry 3 --retry-delay 45 --retry-all-errors \
      -H "Authorization: Bearer $NTFY_CRON_TOKEN" \
      -H "Title: Obsidian vault sync drift" -H "Priority: high" \
      -d "$1" "$NTFY_URL" >/dev/null || echo "WARN: ntfy publish failed" >&2
  fi
}

for v in COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD; do
  [ -n "${!v:-}" ] || { echo "ERROR: $v missing from /root/.backup-env" >&2; exit 1; }
done

SEQ=$(curl -fsS --max-time 15 -u "$COUCHDB_ADMIN_USER:$COUCHDB_ADMIN_PASSWORD" \
  http://127.0.0.1:30015/obsidian-vault 2>/dev/null \
  | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["update_seq"]).split("-")[0])' 2>/dev/null || true)
if [ -z "$SEQ" ]; then
  alert "CouchDB obsidian-vault unreachable from the staleness check (LiveSync store down?)"
  exit 1
fi

PREV_SEQ=$(cat "$STATE" 2>/dev/null || echo "")
printf '%s' "$SEQ" > "$STATE"

NEWEST=$(find "$VAULT_DIR" -type f -not -path '*/.*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
NOW=$(date +%s)
AGE_H=$(( (NOW - ${NEWEST:-0}) / 3600 ))

if [ -z "$PREV_SEQ" ]; then
  echo "first run: seq=$SEQ recorded, newest file ${AGE_H}h old — baseline only"
  exit 0
fi

if [ "$SEQ" != "$PREV_SEQ" ] && [ "$AGE_H" -gt "$STALE_HOURS" ]; then
  alert "CouchDB seq advanced ($PREV_SEQ -> $SEQ) but newest Syncthing file is ${AGE_H}h old — Mac->NAS bridge looks broken; rag-watcher is indexing stale content"
  exit 1
fi

echo "ok: seq $PREV_SEQ -> $SEQ, newest vault file ${AGE_H}h old"
