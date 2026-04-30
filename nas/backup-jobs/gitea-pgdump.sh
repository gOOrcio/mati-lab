#!/usr/bin/env bash
# Phase 8 Task 3 — nightly transactional dump of Gitea's Postgres.
#
# Gitea ships with a Postgres sidecar (TrueNAS catalog app default).
# Database: gitea / user: gitea, both inside the container — no host-side
# credentials needed (pg_dump runs as that user via `docker exec`).
#
# Output: /mnt/bulk/backups/gitea-pgdump/gitea-<ISO>.sql.gz.gpg
# Encryption: gpg --symmetric --cipher-algo AES256, passphrase from
#             /mnt/bulk/backups/.secrets/dump-passphrase
# Retention: 14 days
# On success: ping Kuma push URL (from /root/.backup-env if present)

set -euo pipefail

DEST=/mnt/bulk/backups/gitea-pgdump
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=14

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_GITEA_DUMP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/gitea-$DATE.sql.gz.gpg"

PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^ix-gitea-postgres-' | head -1)
if [ -z "$PG_CONTAINER" ]; then
  echo "ERROR: ix-gitea-postgres-* container not running" >&2
  exit 1
fi

docker exec "$PG_CONTAINER" pg_dump -U gitea -d gitea --no-owner --clean --if-exists \
  | gzip -9 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: dump output is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'gitea-*.sql.gz.gpg' -mtime +$RETAIN_DAYS -delete

# Push monitor heartbeat
[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) gitea dump ok: $OUT ($(du -h "$OUT" | cut -f1))"
