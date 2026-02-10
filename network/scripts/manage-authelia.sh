#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="authelia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# save = push (config is on host)
save() { log "Pushing authelia config to GitHub"; push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
