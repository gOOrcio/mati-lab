#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="caddy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

CADDY_IMAGE="gitea.mati-lab.online/gooral/caddy-cloudflare:latest"
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
  ensure_network
  sync_from_gitea
  copy_env_file "../$SERVICE_NAME"
  # See common.sh::deploy for why --force-recreate is needed.
  compose_cmd up -d --force-recreate
}

ensure_network() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "docker network inspect pihole-net >/dev/null 2>&1 || docker network create --opt com.docker.network.bridge.enable_ip_masquerade=true pihole-net"
}

rebuild() {
  log "Rebuilding $SERVICE_NAME"
  build_and_push
  sync_from_gitea
  copy_env_file "../$SERVICE_NAME"
  compose_cmd up -d --pull always
}

reload_caddy() {
  log "Reloading Caddy config"
  compose_cmd exec caddy caddy reload --config /etc/caddy/Caddyfile
  log_success "Caddy config reloaded"
}

update() {
  log "Updating $SERVICE_NAME (pull only, no rebuild)"
  sync_from_gitea
  copy_env_file "../$SERVICE_NAME"
  compose_cmd up -d --pull always --force-recreate
}

save() { push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|rebuild|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|rebuild|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
