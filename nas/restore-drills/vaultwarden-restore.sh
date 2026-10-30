#!/usr/bin/env bash
# Vaultwarden restore drill: newest backup pair → scratch Postgres + scratch dir.
#
# Runs as root on the NAS (temp-cron channel; see vaultwarden-restore.md).
# Prints row counts and file names only, never contents. Production is untouched.

set -euo pipefail

SRC=/mnt/bulk/backups/vaultwarden
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
PG_IMAGE=postgres:18.6-trixie
NAME=pg-drill-vaultwarden
SCRATCH=$(mktemp -d /tmp/vw-drill.XXXXXX)
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$SCRATCH"' EXIT

DB=$(ls -t "$SRC"/vaultwarden-db-*.sql.gz.gpg | head -1)
DATA=$(ls -t "$SRC"/vaultwarden-data-*.tar.gz.gpg | head -1)
echo "db dump:   $DB"
echo "data tar:  $DATA"

docker run -d --name "$NAME" -e POSTGRES_DB=vaultwarden -e POSTGRES_USER=vaultwarden \
  -e POSTGRES_PASSWORD=drill-throwaway-pw "$PG_IMAGE" >/dev/null
for _ in $(seq 30); do
  docker exec "$NAME" pg_isready -U vaultwarden -d vaultwarden >/dev/null 2>&1 && break
  sleep 1
done

gpg --batch --quiet --decrypt --passphrase-file "$PASSF" "$DB" | gunzip \
  | docker exec -i "$NAME" psql -q -U vaultwarden -d vaultwarden -v ON_ERROR_STOP=1 >/dev/null

for t in users ciphers folders devices twofactor; do
  printf '%-10s %s\n' "$t" "$(docker exec "$NAME" psql -U vaultwarden -d vaultwarden -tAc "SELECT count(*) FROM $t")"
done

gpg --batch --quiet --decrypt --passphrase-file "$PASSF" "$DATA" | tar -xzf - -C "$SCRATCH"
echo "data files:"
(cd "$SCRATCH" && find . -maxdepth 1 -mindepth 1 -printf '  %f %s bytes\n' | sort)

echo "drill ok"
