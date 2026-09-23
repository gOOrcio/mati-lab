#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck disable=SC2034 # used by common.sh after source
SERVICE_NAME="mapa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

# Install/refresh the sync timer and run one pull so /opt/wysowa exists
# before nginx bind-mounts it.
install_sync() {
  log "Installing mapa-sync timer"
  # shellcheck disable=SC2029 # intentional client-side expansion of SERVER_USER
  ssh "${SSH_OPTS[@]}" "$REMOTE" "
    set -euo pipefail
    sudo install -d -o $SERVER_USER -g $SERVER_USER /opt/wysowa
    sudo ln -sf /opt/mati-lab/network/mapa/mapa-sync.service /etc/systemd/system/mapa-sync.service
    sudo ln -sf /opt/mati-lab/network/mapa/mapa-sync.timer /etc/systemd/system/mapa-sync.timer
    sudo systemctl daemon-reload
    sudo systemctl start mapa-sync.service
    sudo systemctl enable --now mapa-sync.timer
  "
}

# Pull the map now instead of waiting for the timer.
sync() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo systemctl start mapa-sync.service && journalctl -u mapa-sync.service -n 5 --no-pager -o cat"
}

deploy() { log "Deploying $SERVICE_NAME"; sync_from_gitea; copy_env_file "../$SERVICE_NAME"; install_sync; compose_cmd up -d --pull always --force-recreate; }
save() { push; }

case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push|save|sync) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push|save|sync}"; exit 1 ;;
esac
