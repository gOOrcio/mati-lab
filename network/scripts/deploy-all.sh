#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }
log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }
log_warning(){ printf "\033[1;33m[WARNING]\033[0m %s\n" "$*"; }
log_error(){ printf "\033[0;31m[ERROR]\033[0m %s\n" "$*"; }

deploy_all() {
  log "Deploying both Pi-hole and Caddy services..."

  # First deploy Pi-hole to create the network
  log "Deploying Pi-hole first..."
  ./manage-pihole.sh deploy

  # Wait a moment for Pi-hole to fully start
  log "Waiting for Pi-hole to fully start..."
  sleep 10

  # Then deploy Caddy
  log "Deploying Caddy..."
  ./manage-caddy.sh deploy

  log_success "Both services deployed successfully!"
  log "Testing connection to https://pihole.mati-lab.online/admin/login"

  # Test the connection
  if curl -s -k "https://pihole.mati-lab.online/admin/login" > /dev/null 2>&1; then
    log_success "Connection to Pi-hole admin interface successful!"
  else
    log_warning "Connection test failed. Please check logs and try again."
  fi
}

restart_all() {
  log "Restarting both Pi-hole and Caddy services..."

  ./manage-pihole.sh restart
  sleep 5
  ./manage-caddy.sh restart

  log_success "Both services restarted successfully!"
}

update_all() {
  log "Updating both Pi-hole and Caddy services..."

  ./manage-pihole.sh update
  sleep 5
  ./manage-caddy.sh update

  log_success "Both services updated successfully!"
}

case "${1:-help}" in
  deploy)  deploy_all ;;
  restart) restart_all ;;
  update)  update_all ;;
  *) echo "usage: $0 {deploy|restart|update}"; exit 1 ;;
esac
