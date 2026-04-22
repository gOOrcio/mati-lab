#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="grafana"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# Grafana-specific functions
ensure_network() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "docker network inspect pihole-net >/dev/null 2>&1 || docker network create --opt com.docker.network.bridge.enable_ip_masquerade=true pihole-net"
}

# export dashboards from Grafana API to provisioning/dashboards, then push
save() {
  log "Exporting Grafana dashboards and pushing to GitHub"
  sync_from_github
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt/mati-lab/network/scripts && chmod +x export-grafana-dashboards.sh && ./export-grafana-dashboards.sh"
  push
}

# Override deploy to include network setup
deploy()  { log "Deploying $SERVICE_NAME"; ensure_network; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd up -d; }

# Import a dashboard JSON file via the Grafana API
# Usage: ./manage-grafana.sh import path/to/dashboard.json
import_dashboard() {
  local json_file="${2:-}"
  [[ -z "$json_file" ]] && { log_error "Usage: $0 import <dashboard.json>"; exit 1; }
  [[ ! -f "$json_file" ]] && { log_error "File not found: $json_file"; exit 1; }

  local grafana_user grafana_pass
  grafana_user=$(grep -E '^GF_SECURITY_ADMIN_USER=' "../grafana/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  grafana_pass=$(grep -E '^GF_(SECURITY_)?ADMIN_PASSWORD=' "../grafana/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  [[ -z "$grafana_pass" ]] && { log_error "Could not read Grafana admin password from .env"; exit 1; }
  grafana_user="${grafana_user:-admin}"

  # Build API payload as a temp file (handles large dashboards)
  local payload_file
  payload_file=$(mktemp)
  jq '{dashboard: (. | .id = null), overwrite: true}' "$json_file" > "$payload_file"

  # SCP payload to Pi, then import via docker on pihole-net
  local remote_payload
  remote_payload="/tmp/grafana-import-$(basename "$json_file")"
  scp "${SSH_OPTS[@]}" "$payload_file" "$REMOTE:$remote_payload"
  rm -f "$payload_file"

  # shellcheck disable=SC2029  # $remote_payload must expand client-side here
  local response
  response=$(ssh "${SSH_OPTS[@]}" "$REMOTE" "docker run --rm --network pihole-net \
    -v '$remote_payload:/payload.json' \
    curlimages/curl:latest \
    -sS -X POST \
    -H 'Content-Type: application/json' \
    -u '${grafana_user}:${grafana_pass}' \
    -d @/payload.json \
    http://grafana:3000/api/dashboards/db && rm -f '$remote_payload'")

  local status
  status=$(echo "$response" | jq -r '.status // "error"')
  if [[ "$status" == "success" ]]; then
    log_success "Dashboard imported: $(echo "$response" | jq -r '.slug')"
  else
    log_error "Import failed: $response"
    exit 1
  fi
}

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push|save) "$1" ;;
  import) import_dashboard "$@" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push|save|import <file.json>}"; exit 1 ;;
esac