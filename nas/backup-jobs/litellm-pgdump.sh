#!/usr/bin/env bash
# Phase 8 Task 4 — nightly transactional dump of LiteLLM's Postgres.
#
# LiteLLM has a Postgres sidecar added in Phase 7 (virtual keys backing
# store). Database: litellm / user: litellm.
#
# Output: /mnt/bulk/backups/litellm-pgdump/litellm-<ISO>.sql.gz.gpg
# Encryption + retention + heartbeat: same shape as gitea-pgdump.sh.

set -euo pipefail

DEST=/mnt/bulk/backups/litellm-pgdump
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=14

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_LITELLM_DUMP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/litellm-$DATE.sql.gz.gpg"

PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^ix-litellm-litellm-postgres-' | head -1)
if [ -z "$PG_CONTAINER" ]; then
  echo "ERROR: ix-litellm-litellm-postgres-* container not running" >&2
  exit 1
fi

docker exec "$PG_CONTAINER" pg_dump -U litellm -d litellm --no-owner --clean --if-exists \
  | gzip -9 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: dump output is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'litellm-*.sql.gz.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) litellm dump ok: $OUT ($(du -h "$OUT" | cut -f1))"
