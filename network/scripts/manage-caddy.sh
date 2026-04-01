#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="caddy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# Override deploy and update to use --build for custom Dockerfile
deploy()   { log "Deploying $SERVICE_NAME";  sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd up -d --build; }
rebuild()  { log "Rebuilding $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd down; compose_cmd up -d --build; }
update()   { log "Updating $SERVICE_NAME";   sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd down; compose_cmd up -d; }

save() { push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|rebuild|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|rebuild|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac