#!/usr/bin/env bash
# Nightly backup of the household budget (Actual Budget server data).
#
# /mnt/fast/databases/budget/actual-data holds server-files/account.sqlite
# (password hash, sessions, file list, Enable Banking config) and
# user-files/ (the budget blobs). It's SQLite under a live server, so the tar
# reads from a temporary ZFS snapshot: crash-consistent, no app downtime.
# pgdata is NOT backed up: it's a mirror the worker rebuilds every 30 min.
# secrets/ is NOT backed up: the values live in Vaultwarden.
#
# Output: /mnt/bulk/backups/budget/budget-data-<ISO>.tar.gz.gpg
# Encryption + retention + heartbeat: same shape as vaultwarden-backup.sh.

set -euo pipefail

DS=fast/databases/budget
DEST=/mnt/bulk/backups/budget
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=30

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_BUDGET_BACKUP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
SNAP="backup-$DATE"
OUT="$DEST/budget-data-$DATE.tar.gz.gpg"

zfs snapshot "$DS@$SNAP"
trap 'zfs destroy "$DS@$SNAP" 2>/dev/null || true' EXIT

MNT=$(zfs get -H -o value mountpoint "$DS")
tar -C "$MNT/.zfs/snapshot/$SNAP/actual-data" -czf - . |
  gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: output is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'budget-data-*.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 --retry 3 --retry-delay 45 --retry-all-errors "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) budget backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
