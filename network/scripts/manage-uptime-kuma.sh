#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="uptime-kuma"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs}"; exit 1 ;;
esac