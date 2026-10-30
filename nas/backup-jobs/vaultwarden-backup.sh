#!/usr/bin/env bash
# Nightly backup of Vaultwarden: Postgres dump + the /data dir.
#
# Postgres is an ixVolume (not snapshotted as a host path), so the dump is
# the database backup. /data holds rsa_key.pem (signs login tokens) and
# attachments/sends; it's also covered by the fast/databases/vaultwarden
# snapshot tasks, but a copy next to the dump keeps a restore self-contained.
# Database: vaultwarden / user: vaultwarden (catalogue consts).
#
# Output: /mnt/bulk/backups/vaultwarden/vaultwarden-{db,data}-<ISO>.*.gpg
# Encryption + retention + heartbeat: same shape as litellm-pgdump.sh.

set -euo pipefail

DEST=/mnt/bulk/backups/vaultwarden
DATA=/mnt/fast/databases/vaultwarden/data
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=14

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_VAULTWARDEN_DUMP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
DB_OUT="$DEST/vaultwarden-db-$DATE.sql.gz.gpg"
DATA_OUT="$DEST/vaultwarden-data-$DATE.tar.gz.gpg"

PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^ix-vaultwarden-postgres-' | head -1)
if [ -z "$PG_CONTAINER" ]; then
  echo "ERROR: ix-vaultwarden-postgres-* container not running" >&2
  exit 1
fi

docker exec "$PG_CONTAINER" pg_dump -U vaultwarden -d vaultwarden --no-owner --clean --if-exists \
  | gzip -9 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$DB_OUT"

tar -C "$DATA" --exclude=./icon_cache --exclude=./tmp -czf - . \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$DATA_OUT"

for f in "$DB_OUT" "$DATA_OUT"; do
  if [ ! -s "$f" ]; then
    echo "ERROR: output is empty: $f" >&2
    exit 1
  fi
done

find "$DEST" -name 'vaultwarden-*.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 --retry 3 --retry-delay 45 --retry-all-errors "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) vaultwarden backup ok: $DB_OUT ($(du -h "$DB_OUT" | cut -f1)), $DATA_OUT ($(du -h "$DATA_OUT" | cut -f1))"
