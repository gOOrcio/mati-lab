#!/usr/bin/env bash
# Weekly backup of the Pi 4 Homebridge OS instance.
#
# Pi 4 runs the official Homebridge OS image — no Docker, no SSH-driven
# rsync. The Homebridge UI exposes a documented backup endpoint that
# produces an application-consistent tar.gz (config.json, auth.json,
# accessories/, persist/, plugins package.json). Restore via the UI:
# Settings → Backup → Restore Backup → upload the unencrypted tar.gz.
#
# Pattern matches arr-config-backup.sh: API-issued archive → gpg AES256
# → bulk/backups/homebridge/ → retention → Kuma push.
#
# Auth: Homebridge UI tokens are short-lived JWTs. We POST username +
# password from /root/.backup-env, get a bearer token, use it for the
# single backup-download request, throw it away.
#
# Output: /mnt/bulk/backups/homebridge/homebridge-<ISO>.tar.gz.gpg
# Retention: 56 days (8 weekly snapshots).

set -euo pipefail

DEST=/mnt/bulk/backups/homebridge
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=56
HOMEBRIDGE_HOST="${HOMEBRIDGE_HOST:-http://192.168.1.155:8581}"

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_HOMEBRIDGE:-}"

for v in HOMEBRIDGE_USERNAME HOMEBRIDGE_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: $v missing from /root/.backup-env" >&2
    exit 1
  fi
done

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/homebridge-$DATE.tar.gz.gpg"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- 1. Login → JWT ---
TOKEN=$(curl -fsS -X POST "$HOMEBRIDGE_HOST/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"username":"%s","password":"%s","otp":""}' \
        "$HOMEBRIDGE_USERNAME" "$HOMEBRIDGE_PASSWORD")" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

if [ -z "$TOKEN" ]; then
  echo "ERROR: Homebridge login produced empty token" >&2
  exit 1
fi

# --- 2. Fetch backup tar.gz ---
curl -fsS "$HOMEBRIDGE_HOST/api/backup/download" \
  -H "Authorization: Bearer $TOKEN" \
  --output "$WORK/homebridge.tar.gz"

if [ ! -s "$WORK/homebridge.tar.gz" ]; then
  echo "ERROR: Homebridge backup endpoint returned empty file" >&2
  exit 1
fi

# Sanity: tar should list at least config.json.
if ! tar -tzf "$WORK/homebridge.tar.gz" >/dev/null 2>&1; then
  echo "ERROR: Homebridge tar.gz failed integrity check" >&2
  exit 1
fi

# --- 3. Encrypt to dest ---
gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase-file "$PASSF" --output "$OUT" "$WORK/homebridge.tar.gz"

if [ ! -s "$OUT" ]; then
  echo "ERROR: encrypted output is empty: $OUT" >&2
  exit 1
fi

# --- 4. Retention ---
find "$DEST" -name 'homebridge-*.tar.gz.gpg' -mtime +$RETAIN_DAYS -delete

# --- 5. Kuma heartbeat ---
[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) homebridge backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
