#!/usr/bin/env bash
# Nightly transactional dump of Paperless-ngx's Postgres (followups PL.1).
#
# Paperless (catalogue app) Postgres lives on an ixVolume, NOT in the bulk/paperless
# snapshots, so this dump IS the database backup (users, owners, tags, workflows,
# mail rules, Gmail refresh tokens). Documents themselves: snapshots 25/26.
# Database: paperless / user: paperless, both inside the container — no host-side
# credentials needed (pg_dump runs as that user via `docker exec`).
#
# Output: /mnt/bulk/backups/paperless-pgdump/paperless-<ISO>.sql.gz.gpg
# Encryption: gpg --symmetric --cipher-algo AES256, passphrase from
#             /mnt/bulk/backups/.secrets/dump-passphrase
# Retention: 14 days
# On success: ping Kuma push URL (from /root/.backup-env if present)

set -euo pipefail

DEST=/mnt/bulk/backups/paperless-pgdump
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=14

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_PAPERLESS_DUMP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/paperless-$DATE.sql.gz.gpg"

PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^ix-paperless-ngx-postgres-' | head -1)
if [ -z "$PG_CONTAINER" ]; then
  echo "ERROR: ix-paperless-ngx-postgres-* container not running" >&2
  exit 1
fi

docker exec "$PG_CONTAINER" pg_dump -U paperless -d paperless --no-owner --clean --if-exists \
  | gzip -9 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: dump output is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'paperless-*.sql.gz.gpg' -mtime +$RETAIN_DAYS -delete

# Push monitor heartbeat
[ -n "$KUMA_URL" ] && curl -fsS -m 10 --retry 3 --retry-delay 45 --retry-all-errors "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) paperless dump ok: $OUT ($(du -h "$OUT" | cut -f1))"
