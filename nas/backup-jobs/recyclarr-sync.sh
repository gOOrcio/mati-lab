#!/usr/bin/env bash
# Weekly Recyclarr sync — pulls TRaSH-Guides curated profiles + custom formats
# into Sonarr/Radarr via API. Same shape as the other backup-jobs scripts
# (cron-driven, sources /root/.backup-env, pushes Kuma heartbeat on success).
#
# Stateless: nothing to back up. Heartbeat-only monitoring.

set -euo pipefail

CONFIG_DIR=/mnt/fast/databases/recyclarr

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_RECYCLARR_SYNC:-}"

if [ -z "${SONARR_API_KEY:-}" ] || [ -z "${RADARR_API_KEY:-}" ]; then
  echo "ERROR: SONARR_API_KEY / RADARR_API_KEY missing from /root/.backup-env" >&2
  exit 1
fi

if [ ! -r "$CONFIG_DIR/config.yml" ]; then
  echo "ERROR: $CONFIG_DIR/config.yml missing or unreadable" >&2
  exit 1
fi

docker run --rm \
  --user 568:568 \
  -v "$CONFIG_DIR":/config \
  -e HOME=/config \
  -e XDG_CONFIG_HOME=/config \
  -e SONARR_API_KEY="$SONARR_API_KEY" \
  -e RADARR_API_KEY="$RADARR_API_KEY" \
  ghcr.io/recyclarr/recyclarr:latest \
  sync --config /config/config.yml

[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) recyclarr sync ok"
