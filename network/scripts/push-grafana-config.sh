#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="grafana"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

push_config() {
  log "Pushing $SERVICE_NAME configuration to GitHub"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt/mati-lab && 
    git pull origin main &&
    git add . && 
    git diff --cached --quiet || git commit -m 'Update $SERVICE_NAME config: $(date)' && 
    git push origin main"
  log_success "Configuration pushed to GitHub!"
  log "Run 'git pull' to see changes locally"
}

case "${1:-help}" in
  push) push_config ;;
  *) echo "usage: $0 push"; exit 1 ;;
esac