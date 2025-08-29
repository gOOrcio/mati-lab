#!/usr/bin/bash

# Pi-hole Service Management Script
# Usage: ./manage-pihole.sh [deploy|update|restart|status|logs|stop|start]

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

SERVICE_NAME="pihole"
SERVICE_PATH="../pihole"
REMOTE_PATH="${SERVER_PATH}/${SERVICE_NAME}"

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

deploy() {
    log_info "Deploying ${SERVICE_NAME} service..."
    
    # Create remote directory structure
    ssh ${SERVER_USER}@${SERVER_HOST} "sudo mkdir -p ${REMOTE_PATH}/etc-pihole ${REMOTE_PATH}/etc-dnsmasq.d"
    
    # Set ownership
    ssh ${SERVER_USER}@${SERVER_HOST} "sudo chown -R ${SERVER_USER}:${SERVER_USER} ${REMOTE_PATH}"
    
    # Copy files
    scp ${SERVICE_PATH}/docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/
    scp -r ${SERVICE_PATH}/etc-pihole/* ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/etc-pihole/ 2>/dev/null || true
    scp -r ${SERVICE_PATH}/etc-dnsmasq.d/* ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/etc-dnsmasq.d/ 2>/dev/null || true
    
    # Copy environment file if it exists
    if [ -f "../.env" ]; then
        scp ../.env ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/
    fi
    
    # Deploy the service
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo -E docker compose --env-file .env up -d"
    
    log_success "${SERVICE_NAME} deployed successfully!"
}

update() {
    log_info "Updating ${SERVICE_NAME} service..."
    
    # Copy updated files
    scp ${SERVICE_PATH}/docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/
    scp -r ${SERVICE_PATH}/etc-pihole/* ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/etc-pihole/ 2>/dev/null || true
    scp -r ${SERVICE_PATH}/etc-dnsmasq.d/* ${SERVER_USER}@${SERVER_HOST}:${REMOTE_PATH}/etc-dnsmasq.d/ 2>/dev/null || true
    
    # Restart the service
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo docker compose down && sudo -E docker compose --env-file .env up -d"
    
    log_success "${SERVICE_NAME} updated successfully!"
}

restart() {
    log_info "Restarting ${SERVICE_NAME} service..."
    
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo docker compose restart"
    
    log_success "${SERVICE_NAME} restarted successfully!"
}

status() {
    log_info "Checking ${SERVICE_NAME} service status..."
    
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo docker compose ps"
}

logs() {
    log_info "Showing ${SERVICE_NAME} service logs..."
    
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo docker compose logs --tail 50 -f"
}

stop() {
    log_info "Stopping ${SERVICE_NAME} service..."
    
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo docker compose stop"
    
    log_success "${SERVICE_NAME} stopped successfully!"
}

start() {
    log_info "Starting ${SERVICE_NAME} service..."
    
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${REMOTE_PATH} && sudo -E docker compose --env-file .env up -d"
    
    log_success "${SERVICE_NAME} started successfully!"
}

# Main script logic
case "${1:-help}" in
    deploy)
        deploy
        ;;
    update)
        update
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    stop)
        stop
        ;;
    start)
        start
        ;;
    help|*)
        echo "Usage: $0 [deploy|update|restart|status|logs|stop|start]"
        echo ""
        echo "Commands:"
        echo "  deploy  - Deploy the service for the first time"
        echo "  update  - Update and restart the service"
        echo "  restart - Restart the service"
        echo "  status  - Show service status"
        echo "  logs    - Show service logs"
        echo "  stop    - Stop the service"
        echo "  start   - Start the service"
        echo "  help    - Show this help message"
        exit 1
        ;;
esac 