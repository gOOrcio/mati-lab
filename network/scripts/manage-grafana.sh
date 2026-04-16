#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="grafana"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# Grafana-specific functions
ensure_network() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "docker network inspect pihole-net >/dev/null 2>&1 || docker network create pihole-net"
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

  local grafana_pass
  grafana_pass=$(grep -E '^GF_(SECURITY_)?ADMIN_PASSWORD=' "../grafana/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  [[ -z "$grafana_pass" ]] && { log_error "Could not read Grafana admin password from .env"; exit 1; }

  # Wrap the dashboard JSON in the API envelope
  local payload
  payload=$(jq -n --argjson dash "$(jq '.id = null' "$json_file")" '{dashboard: $dash, overwrite: true}')

  local response
  response=$(ssh "${SSH_OPTS[@]}" "$REMOTE" "curl -sS -X POST \
    -H 'Content-Type: application/json' \
    -u 'admin:${grafana_pass}' \
    -d '${payload}' \
    http://grafana:3000/api/dashboards/db")

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