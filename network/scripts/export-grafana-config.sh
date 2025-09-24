#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }
log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }

export_grafana_config() {
  log "Exporting Grafana configuration from host..."
  
  # Create provisioning directories
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$SERVER_PATH/grafana/provisioning/datasources' '$SERVER_PATH/grafana/provisioning/dashboards'"
  
  # Export datasources (requires API key or admin access)
  log "Exporting datasources..."
  ssh "${SSH_OPTS[@]}" "$REMOTE" "curl -s -H 'Content-Type: application/json' http://localhost:3000/api/datasources" > /tmp/datasources.json
  
  # Convert to provisioning format
  log "Converting to provisioning format..."
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cat > '$SERVER_PATH/grafana/provisioning/datasources/exported.yml' << 'EOF'
apiVersion: 1

datasources:
EOF"
  
  # Add each datasource
  ssh "${SSH_OPTS[@]}" "$REMOTE" "curl -s http://localhost:3000/api/datasources | jq -r '.[] | \"  - name: \" + .name + \"\\n    type: \" + .type + \"\\n    url: \" + .url + \"\\n    access: \" + .access + \"\\n    isDefault: \" + (.isDefault | tostring) + \"\\n    editable: true\\n\"' >> '$SERVER_PATH/grafana/provisioning/datasources/exported.yml'"
  
  log_success "Configuration exported!"
  log "Run 'make sync-config-grafana' to commit changes"
}

case "${1:-help}" in
  export) export_grafana_config ;;
  *) echo "usage: $0 export"; exit 1 ;;
esac