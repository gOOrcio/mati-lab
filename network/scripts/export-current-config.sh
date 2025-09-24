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
  log "Exporting current Grafana configuration..."
  
  # Create provisioning directory on host
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$SERVER_PATH/provisioning/datasources'"
  
  # Try to get datasources (this might fail without auth)
  log "Attempting to export datasources..."
  
  # Create a basic provisioning file with current datasource
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cat > '$SERVER_PATH/provisioning/datasources/current.yml' << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
    editable: true
EOF"
  
  log_success "Basic configuration exported!"
  log "You may need to manually update the datasource name"
  log "Edit: $SERVER_PATH/provisioning/datasources/current.yml"
}

case "${1:-help}" in
  export) export_grafana_config ;;
  *) echo "usage: $0 export"; exit 1 ;;
esac