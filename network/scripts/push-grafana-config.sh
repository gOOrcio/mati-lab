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

export_and_push_config() {
  log "Exporting current Grafana configuration from host..."
  
  # Create provisioning directory on host
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$SERVER_PATH/provisioning/datasources'"
  
  # Export current datasource configuration
  log "Creating provisioning file with current datasource name..."
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cat > '$SERVER_PATH/provisioning/datasources/prometheus.yml' << 'EOF'
apiVersion: 1

datasources:
  - name: prometheus-mati-lab
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
    editable: true
EOF"
  
  log "Copying updated config to local repository..."
  # Copy the updated config to local
  scp "${SSH_OPTS[@]}" "$REMOTE:$SERVER_PATH/provisioning/datasources/prometheus.yml" "../grafana/provisioning/datasources/"
  
  log "Committing and pushing to GitHub..."
  # Commit and push locally
  cd .. && git add grafana/provisioning/datasources/prometheus.yml && git commit -m "Update Grafana datasource name to prometheus-mati-lab" && git push origin main
  
  log_success "Configuration exported and pushed to GitHub!"
  log "Run 'git pull' to see the changes locally"
}

case "${1:-help}" in
  export) export_and_push_config ;;
  *) echo "usage: $0 export"; exit 1 ;;
esac