#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="pihole"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Pi-hole-specific functions
ensure_network() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "docker network inspect pihole-net >/dev/null 2>&1 || docker network create pihole-net"
}

check() { 
  ssh "${SSH_OPTS[@]}" "$REMOTE" "nslookup google.com 127.0.0.1 >/dev/null && echo OK || echo FAIL"
}

# Override deploy to include network setup
deploy()  { log "Deploying $SERVICE_NAME"; ensure_network; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd up -d --pull always; }
update()  { log "Updating $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd down; compose_cmd up -d --pull always; }

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|check) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|check}"; exit 1 ;;
esac