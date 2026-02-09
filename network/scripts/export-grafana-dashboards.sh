#!/usr/bin/env bash
# Exports Grafana dashboards to provisioning/dashboards/*.json
# Run on the server via: ./manage-grafana.sh save
# Requires: docker, jq, curlimages/curl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAFANA_DIR="$(cd "$SCRIPT_DIR/../grafana" && pwd)"
DASHBOARDS_DIR="$GRAFANA_DIR/provisioning/dashboards"
GRAFANA_URL="http://grafana:3000"

# Get admin password from .env or container
GRAFANA_PASS=""
if [[ -f "$GRAFANA_DIR/.env" ]]; then
  GRAFANA_PASS=$(grep -E '^GF_(SECURITY_)?ADMIN_PASSWORD=' "$GRAFANA_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
fi
[[ -z "$GRAFANA_PASS" ]] && GRAFANA_PASS=$(docker exec grafana printenv GF_SECURITY_ADMIN_PASSWORD 2>/dev/null || docker exec grafana printenv GF_ADMIN_PASSWORD 2>/dev/null || true)

if [[ -z "$GRAFANA_PASS" ]]; then
  echo "ERROR: Could not get Grafana admin password. Set GF_SECURITY_ADMIN_PASSWORD in grafana/.env"
  exit 1
fi

fetch() {
  docker run --rm --network pihole-net curlimages/curl:latest -sS -u "admin:$GRAFANA_PASS" -H "Accept: application/json" "$GRAFANA_URL$1"
}

LIST=$(fetch "/api/search?type=dash-db")
[[ -z "$LIST" ]] && echo "No dashboards or Grafana unavailable" && exit 0

UIDS=($(echo "$LIST" | jq -r '.[].uid'))
[[ ${#UIDS[@]} -eq 0 ]] && echo "No dashboards to export" && exit 0

find "$DASHBOARDS_DIR" -maxdepth 1 -name '*.json' -delete

for uid in "${UIDS[@]}"; do
  [[ -z "$uid" ]] && continue
  DATA=$(fetch "/api/dashboards/uid/$uid")
  [[ -z "$DATA" ]] && continue
  DASH=$(echo "$DATA" | jq '.dashboard | .id = null')
  SLUG=$(echo "$DATA" | jq -r '.meta.slug // .dashboard.title | gsub(" "; "-") | ascii_downcase')
  echo "$DASH" > "$DASHBOARDS_DIR/${SLUG}.json"
  echo "Exported: ${SLUG}.json"
done

echo "Exported ${#UIDS[@]} dashboard(s)"
