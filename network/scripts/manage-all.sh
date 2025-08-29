#!/usr/bin/bash

# Master Service Management Script
# Usage: ./manage-all.sh [service] [action] or ./manage-all.sh [action] for all services

set -e

# Load environment variables
if [ -f "../.env" ]; then
    export $(cat ../.env | grep -v '^#' | xargs)
else
    echo "Warning: .env file not found. Using default values."
    export SERVER_HOST=${SERVER_HOST:-192.168.1.252}
    export SERVER_USER=${SERVER_USER:-gooral}
    export SERVER_PATH=${SERVER_PATH:-/opt/compose}
fi

# Available services
SERVICES=("caddy" "pihole" "uptime-kuma")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to execute action on a specific service
execute_service_action() {
    local service=$1
    local action=$2
    
    if [[ ! " ${SERVICES[@]} " =~ " ${service} " ]]; then
        log_error "Unknown service: ${service}"
        return 1
    fi
    
    local script_path="${SCRIPT_DIR}/manage-${service}.sh"
    if [[ ! -f "${script_path}" ]]; then
        log_error "Script not found: ${script_path}"
        return 1
    fi
    
    log_info "Executing ${action} on ${service}..."
    "${script_path}" "${action}"
}

# Function to execute action on all services
execute_all_services() {
    local action=$1
    
    log_info "Executing ${action} on all services..."
    
    for service in "${SERVICES[@]}"; do
        log_info "Processing ${service}..."
        execute_service_action "${service}" "${action}" || {
            log_warning "Failed to ${action} ${service}, continuing with other services..."
        }
    done
    
    log_success "Completed ${action} on all services!"
}

# Function to show status of all services
show_all_status() {
    log_info "Showing status of all services..."
    
    for service in "${SERVICES[@]}"; do
        echo ""
        log_info "=== ${service} ==="
        execute_service_action "${service}" "status" || {
            log_warning "Failed to get status for ${service}"
        }
    done
}

# Function to show logs of all services
show_all_logs() {
    log_info "Showing logs of all services..."
    
    for service in "${SERVICES[@]}"; do
        echo ""
        log_info "=== ${service} ==="
        execute_service_action "${service}" "logs" || {
            log_warning "Failed to get logs for ${service}"
        }
    done
}

# Function to deploy all services
deploy_all() {
    log_info "Deploying all services..."
    
    # Create base directory structure
    ssh ${SERVER_USER}@${SERVER_HOST} "sudo mkdir -p ${SERVER_PATH}"
    ssh ${SERVER_USER}@${SERVER_HOST} "sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_PATH}"
    
    # Deploy each service
    for service in "${SERVICES[@]}"; do
        log_info "Deploying ${service}..."
        execute_service_action "${service}" "deploy" || {
            log_warning "Failed to deploy ${service}, continuing with other services..."
        }
    done
    
    log_success "All services deployed!"
}

# Function to update all services
update_all() {
    log_info "Updating all services..."
    
    for service in "${SERVICES[@]}"; do
        log_info "Updating ${service}..."
        execute_service_action "${service}" "update" || {
            log_warning "Failed to update ${service}, continuing with other services..."
        }
    done
    
    log_success "All services updated!"
}

# Main script logic
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [service] [action] or $0 [action] for all services"
    echo ""
    echo "Services: ${SERVICES[*]}"
    echo ""
    echo "Actions:"
    echo "  deploy  - Deploy the service(s) for the first time"
    echo "  update  - Update and restart the service(s)"
    echo "  restart - Restart the service(s)"
    echo "  status  - Show service(s) status"
    echo "  logs    - Show service(s) logs"
    echo "  stop    - Stop the service(s)"
    echo "  start   - Start the service(s)"
    echo ""
    echo "Examples:"
    echo "  $0 caddy deploy     - Deploy only Caddy"
    echo "  $0 deploy           - Deploy all services"
    echo "  $0 status           - Show status of all services"
    echo "  $0 pihole restart   - Restart only Pi-hole"
    exit 1
fi

# Check if first argument is a service name
if [[ " ${SERVICES[@]} " =~ " $1 " ]]; then
    # First argument is a service name
    SERVICE=$1
    ACTION=$2
    
    if [[ -z "${ACTION}" ]]; then
        log_error "Action required when specifying a service"
        echo "Usage: $0 ${SERVICE} [deploy|update|restart|status|logs|stop|start]"
        exit 1
    fi
    
    execute_service_action "${SERVICE}" "${ACTION}"
else
    # First argument is an action for all services
    ACTION=$1
    
    case "${ACTION}" in
        deploy)
            deploy_all
            ;;
        update)
            update_all
            ;;
        restart)
            execute_all_services "restart"
            ;;
        status)
            show_all_status
            ;;
        logs)
            show_all_logs
            ;;
        stop)
            execute_all_services "stop"
            ;;
        start)
            execute_all_services "start"
            ;;
        help|*)
            echo "Usage: $0 [service] [action] or $0 [action] for all services"
            echo ""
            echo "Services: ${SERVICES[*]}"
            echo ""
            echo "Actions:"
            echo "  deploy  - Deploy the service(s) for the first time"
            echo "  update  - Update and restart the service(s)"
            echo "  restart - Restart the service(s)"
            echo "  status  - Show service(s) status"
            echo "  logs    - Show service(s) logs"
            echo "  stop    - Stop the service(s)"
            echo "  start   - Start the service(s)"
            echo "  help    - Show this help message"
            exit 1
            ;;
    esac
fi 