#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

# Available services
SERVICES=(pihole caddy uptime-kuma)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }
log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }
log_warning(){ printf "\033[1;33m[WARNING]\033[0m %s\n" "$*"; }
log_error(){ printf "\033[0;31m[ERROR]\033[0m %s\n" "$*"; }

# Execute action on a specific service
execute_service_action() {
  local service=$1
  local action=$2

  # Check if service is in the SERVICES array
  local service_found=0
  for s in "${SERVICES[@]}"; do
    if [[ "$s" == "$service" ]]; then
      service_found=1
      break
    fi
  done

  if [[ $service_found -eq 0 ]]; then
    log_error "Unknown service: ${service}"
    return 1
  fi

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
    log "Processing ${service}..."
    execute_service_action "${service}" "${action}" || {
      log_warning "Failed to ${action} ${service}, continuing with other services..."
    }
  done

  log_success "Completed ${action} on all services!"
}

# Show status of all services
show_all_status() {
  log "Showing status of all services..."

  for service in "${SERVICES[@]}"; do
    echo ""
    log "=== ${service} ==="
    execute_service_action "${service}" "status" || {
      log_warning "Failed to get status for ${service}"
    }
  done
}

# Show logs of all services
show_all_logs() {
  log "Showing logs of all services..."

  for service in "${SERVICES[@]}"; do
    echo ""
    log "=== ${service} ==="
    execute_service_action "${service}" "logs" || {
      log_warning "Failed to get logs for ${service}"
    }
  done
}

# Setup SSH options
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

# Deploy all services
deploy_all() {
  log "Deploying all services..."

  # Create base directory structure
  ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo mkdir -p ${SERVER_PATH}"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_PATH}"

  # Deploy each service
  for service in "${SERVICES[@]}"; do
    log "Deploying ${service}..."
    execute_service_action "${service}" "deploy" || {
      log_warning "Failed to deploy ${service}, continuing with other services..."
    }
  done

  log_success "All services deployed!"
}

# Update all services
update_all() {
  log "Updating all services..."

  for service in "${SERVICES[@]}"; do
    log "Updating ${service}..."
    execute_service_action "${service}" "update" || {
      log_warning "Failed to update ${service}, continuing with other services..."
    }
  done

  log_success "All services updated!"
}

# Display usage information
show_usage() {
  echo "usage: $0 [service] [action] or $0 [action] for all services"
  echo ""
  echo "services: ${SERVICES[*]}"
  echo ""
  echo "actions:"
  echo "  deploy  - Deploy the service(s) for the first time"
  echo "  update  - Update and restart the service(s)"
  echo "  restart - Restart the service(s)"
  echo "  status  - Show service(s) status"
  echo "  logs    - Show service(s) logs"
  echo "  stop    - Stop the service(s)"
  echo "  start   - Start the service(s)"
  echo ""
  echo "examples:"
  echo "  $0 caddy deploy     - Deploy only Caddy"
  echo "  $0 deploy           - Deploy all services"
  echo "  $0 status           - Show status of all services"
  echo "  $0 pihole restart   - Restart only Pi-hole"
  exit 1
}

# Main logic
[[ $# -eq 0 ]] && show_usage

# Check if first argument is a service name
service_found=0
for s in "${SERVICES[@]}"; do
  if [[ "$s" == "$1" ]]; then
    service_found=1
    break
  fi
done

if [[ $service_found -eq 1 ]]; then
  # First argument is a service name
  SERVICE=$1
  ACTION=$2

  if [[ -z "${ACTION}" ]]; then
    log_error "Action required when specifying a service"
    echo "usage: $0 ${SERVICE} {deploy|update|restart|status|logs|stop|start}"
    exit 1
  fi

  execute_service_action "${SERVICE}" "${ACTION}"
else
  # First argument is an action for all services
  ACTION=$1

  case "${ACTION}" in
    deploy)  deploy_all ;;
    update)  update_all ;;
    restart) execute_all_services "restart" ;;
    status)  show_all_status ;;
    logs)    show_all_logs ;;
    stop)    execute_all_services "stop" ;;
    start)   execute_all_services "start" ;;
    *)       show_usage ;;
  esac
fi
