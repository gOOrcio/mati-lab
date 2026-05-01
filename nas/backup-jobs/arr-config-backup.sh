#!/usr/bin/env bash
# Weekly *arr-stack backup. Uses each app's own API to produce
# application-consistent backups (the documented restore path: each *arr's UI
# accepts the resulting ZIP via System → Backup → Restore from File).
#
# Replaces the previous "tar config dir" approach, which risked catching
# SQLite mid-transaction and drifted on cache excludes.
#
# Coverage:
# - Prowlarr / Sonarr / Radarr / Bazarr → API-issued ZIPs (consistent)
# - Jellyseerr → tar of /app/config (no API backup endpoint exists)
#
# Output: /mnt/bulk/backups/arr/arr-<ISO>.tar.gz.gpg containing the 4 ZIPs +
# the Jellyseerr config tar, gpg-symmetric encrypted with the shared
# passphrase. 8-week retention.

set -euo pipefail

DEST=/mnt/bulk/backups/arr
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=56  # 8 weeks

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_ARR_CONFIG:-}"

for v in PROWLARR_API_KEY SONARR_API_KEY RADARR_API_KEY BAZARR_API_KEY; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: $v missing from /root/.backup-env" >&2
    exit 1
  fi
done

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Trigger an *arr v1/v3 backup, wait for completion, copy ZIP to $WORK/<app>.zip.
# Detects the new file by diffing the Backups dir before vs after.
backup_arr() {
  local app=$1 port=$2 key=$3 apiv=$4
  local base="http://192.168.1.65:$port/api/$apiv"
  local backups_dir="/mnt/fast/databases/$app/config/Backups/manual"

  mkdir -p "$backups_dir"   # apps create on first backup; harmless if it exists
  local before
  before=$(ls -1 "$backups_dir" 2>/dev/null | sort) || before=""

  local cmd_id
  cmd_id=$(curl -fsS -X POST "$base/command" \
    -H "X-Api-Key: $key" -H 'Content-Type: application/json' \
    -d '{"name":"Backup"}' | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')

  local i status=""
  for i in $(seq 1 60); do
    status=$(curl -fsS "$base/command/$cmd_id" -H "X-Api-Key: $key" \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')
    [ "$status" = "completed" ] && break
    [ "$status" = "failed" ] && { echo "ERROR: $app backup command failed" >&2; exit 1; }
    sleep 1
  done
  [ "$status" = "completed" ] || { echo "ERROR: $app backup timed out (last status=$status)" >&2; exit 1; }

  local after new
  after=$(ls -1 "$backups_dir" 2>/dev/null | sort) || true
  new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
  if [ -z "$new" ]; then
    echo "ERROR: $app backup completed but no new file appeared in $backups_dir" >&2
    exit 1
  fi
  cp "$backups_dir/$new" "$WORK/$app.zip"
  echo "  $app: $new"
}

# Bazarr's backup API + on-disk path differ slightly from the v1/v3 *arrs.
backup_bazarr() {
  local key="$BAZARR_API_KEY"
  local backups_dir="/mnt/fast/databases/bazarr/config/backup"

  mkdir -p "$backups_dir"
  local before
  before=$(ls -1 "$backups_dir" 2>/dev/null | sort) || before=""

  curl -fsS -X POST "http://192.168.1.65:30028/api/system/backups" \
    -H "X-Api-Key: $key" >/dev/null

  local i after new=""
  for i in $(seq 1 30); do
    after=$(ls -1 "$backups_dir" 2>/dev/null | sort) || true
    new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
    [ -n "$new" ] && break
    sleep 1
  done
  if [ -z "$new" ]; then
    echo "ERROR: bazarr backup produced no new file in $backups_dir" >&2
    exit 1
  fi
  cp "$backups_dir/$new" "$WORK/bazarr.zip"
  echo "  bazarr: $new"
}

echo "=== triggering app-issued backups ==="
backup_arr prowlarr 30025 "$PROWLARR_API_KEY" v1
backup_arr sonarr   30026 "$SONARR_API_KEY"   v3
backup_arr radarr   30027 "$RADARR_API_KEY"   v3
backup_bazarr

# Jellyseerr has no API backup endpoint — tar its config dir.
echo "=== jellyseerr config tar ==="
tar -C /mnt/fast/databases -czf "$WORK/jellyseerr-config.tar.gz" \
    --exclude='jellyseerr/config/logs' \
    --exclude='jellyseerr/config/cache' \
    jellyseerr/config 2>/dev/null || \
    echo "  (jellyseerr/config not yet present — skipped)"

OUT="$DEST/arr-$DATE.tar.gz.gpg"
tar -C "$WORK" -czf - $(ls "$WORK") \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSF" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: archive empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'arr-*.tar.gz.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) arr backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
