#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="grafana-ntfy-bridge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

IMAGE="registry.mati-lab.online/grafana-ntfy-bridge:latest"
BRIDGE_REPO="$HOME/Projects/grafana-ntfy-bridge"

build_and_push() {
  log "Building grafana-ntfy-bridge image locally for linux/arm64"
  docker buildx build \
    --platform linux/arm64 \
    --tag "$IMAGE" \
    --push \
    "$BRIDGE_REPO"
  log_success "Image pushed to $IMAGE"
}

deploy() {
  log "Deploying $SERVICE_NAME"
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd up -d
}

rebuild() {
  log "Rebuilding $SERVICE_NAME"
  build_and_push
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd up -d --pull always
}

update() {
  log "Updating $SERVICE_NAME (pull only, no rebuild)"
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd up -d --pull always
}

save() { push; }

case "${1:-help}" in
  deploy|rebuild|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|rebuild|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
