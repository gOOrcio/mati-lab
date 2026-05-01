#!/usr/bin/env bash
# Weekly tar.gz of the four *arr config dirs, encrypted with the shared
# backup passphrase. Same shape as litellm-pgdump.sh / hermes-backup.sh.
#
# State backed up: prowlarr.db, sonarr.db, radarr.db, bazarr.db (SQLite)
# plus config.xml/yml files. Restore = stop app, untar over config dir,
# start app.
#
# Output: /mnt/bulk/backups/arr/arr-<ISO>.tar.gz.gpg

set -euo pipefail

DEST=/mnt/bulk/backups/arr
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=56  # 8 weeks

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_ARR_CONFIG:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/arr-$DATE.tar.gz.gpg"

tar -C /mnt/fast/databases \
    --exclude='*/Logs/*' \
    --exclude='*/logs/*' \
    --exclude='*/MediaCover/*' \
    --exclude='*/cache/*' \
    --exclude='*/log/*' \
    -czf - prowlarr/config sonarr/config radarr/config bazarr/config \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: arr config archive is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'arr-*.tar.gz.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) arr config backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
