#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="caddy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Override deploy to use --build for custom Dockerfile
deploy()  { log "Deploying $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd up -d --build; }
update()  { log "Updating $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd down; compose_cmd up -d --build; }

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push}"; exit 1 ;;
esac