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
  
  log "Committing and pushing current changes to GitHub from host..."
  # Commit and push current state from host
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt/mati-lab && 
    git add . && 
    git diff --cached --quiet || git commit -m 'Update Grafana config from host: $(date)' && 
    git push origin main"
  
  log_success "Configuration exported and pushed to GitHub!"
  log "Run 'git pull' to see the changes locally"
}

case "${1:-help}" in
  export) export_and_push_config ;;
  *) echo "usage: $0 export"; exit 1 ;;
esac