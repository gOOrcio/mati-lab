#!/usr/bin/env bash
set -Eeuo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Available services
SERVICES=(pihole authelia caddy uptime-kuma homarr homer prometheus grafana ntfy diun)

log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }
log_warning(){ printf "\033[1;33m[WARNING]\033[0m %s\n" "$*"; }

# Execute action on a specific service
execute_service_action() {
  local service=$1
  local action=$2
  local script_path="${SCRIPT_DIR}/manage-${service}.sh"
  
  if [[ ! -f "${script_path}" ]]; then
    log_error "Script not found: ${script_path}"
    return 1
  fi

  log "Executing ${action} on ${service}..."
  "${script_path}" "${action}"
}

# Execute action on all services
execute_all_services() {
  local action=$1
  log "Executing ${action} on all services..."

  for service in "${SERVICES[@]}"; do
    execute_service_action "${service}" "${action}" || {
      log_warning "Failed to ${action} ${service}, continuing..."
    }
  done
  log_success "Completed ${action} on all services!"
}

# Show status/logs of all services
show_all() {
  local action=$1
  log "Showing ${action} of all services..."

  for service in "${SERVICES[@]}"; do
    echo ""
    log "=== ${service} ==="
    execute_service_action "${service}" "${action}" || {
      log_warning "Failed to get ${action} for ${service}"
    }
  done
}

# Setup host directory structure
setup_host() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo mkdir -p /opt && sudo chown -R ${SERVER_USER}:${SERVER_USER} /opt"
}

# Display usage
show_usage() {
  echo "usage: $0 [service] [action] or $0 [action] for all services"
  echo ""
  echo "services: ${SERVICES[*]}"
  echo ""
  echo "actions: deploy|update|restart|status|logs|stop|start|push|save"
  echo ""
  echo "examples:"
  echo "  $0 caddy deploy     - Deploy only Caddy"
  echo "  $0 deploy           - Deploy all services"
  echo "  $0 status           - Show status of all services"
  exit 1
}

# Main logic
[[ $# -eq 0 ]] && show_usage

# Check if first argument is a service name
if [[ " ${SERVICES[*]} " =~ " $1 " ]]; then
  # Service-specific action
  SERVICE=$1
  ACTION=$2
  [[ -z "${ACTION}" ]] && { log_error "Action required when specifying a service"; show_usage; }
  execute_service_action "${SERVICE}" "${ACTION}"
else
  # Action for all services
  ACTION=$1
  case "${ACTION}" in
    deploy)  setup_host; execute_all_services "deploy" ;;
    update)  execute_all_services "update" ;;
    restart) execute_all_services "restart" ;;
    status)  show_all "status" ;;
    logs)    show_all "logs" ;;
    stop)    execute_all_services "stop" ;;
    start)   execute_all_services "start" ;;
    push)    execute_all_services "push" ;;
    save)    execute_all_services "save" ;;
    *)       show_usage ;;
  esac
fi
