#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="caddy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

CADDY_IMAGE="192.168.1.252:5000/caddy-cloudflare:latest"
CADDY_DOCKERFILE="../caddy/Dockerfile"

# Build the custom caddy image locally (fast x86/arm64) and push to the LAN registry.
# The Pi then pulls the pre-built image instead of compiling Go on the SD card.
build_and_push() {
  log "Building caddy-cloudflare image locally for linux/arm64"
  docker buildx build \
    --platform linux/arm64 \
    --tag "$CADDY_IMAGE" \
    --push \
    -f "$CADDY_DOCKERFILE" \
    "$(dirname "$CADDY_DOCKERFILE")"
  log_success "Image pushed to $CADDY_IMAGE"
}

deploy() {
  log "Deploying $SERVICE_NAME"
  build_and_push
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd pull
  compose_cmd up -d
}

rebuild() {
  log "Rebuilding $SERVICE_NAME"
  build_and_push
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd down
  compose_cmd pull
  compose_cmd up -d
}

update() {
  log "Updating $SERVICE_NAME (pull only, no rebuild)"
  sync_from_github
  copy_env_file "../$SERVICE_NAME"
  compose_cmd down
  compose_cmd pull
  compose_cmd up -d
}

save() { push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|rebuild|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|rebuild|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
