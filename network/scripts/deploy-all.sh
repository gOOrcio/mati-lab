#!/usr/bin/bash

# Deploy both Pi-hole and Caddy together
# Usage: ./deploy-all.sh [deploy|restart|update]

set -e

# Load environment variables
if [ -f "../.env" ]; then
    export "$(cat ../.env | grep -v '^#' | xargs)"
else
    echo "Warning: .env file not found. Using default values."
    export SERVER_HOST=${SERVER_HOST:-192.168.1.252}
    export SERVER_USER=${SERVER_USER:-gooral}
    export SERVER_PATH=${SERVER_PATH:-/opt/compose}
fi

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

deploy_all() {
    log_info "Deploying both Pi-hole and Caddy services..."
    
    # First deploy Pi-hole to create the network
    log_info "Deploying Pi-hole first..."
    ./manage-pihole.sh deploy
    
    # Wait a moment for Pi-hole to fully start
    log_info "Waiting for Pi-hole to fully start..."
    sleep 10
    
    # Then deploy Caddy
    log_info "Deploying Caddy..."
    ./manage-caddy.sh deploy
    
    log_success "Both services deployed successfully!"
    log_info "Testing connection to https://pihole.mati-lab.online/admin/login"
    
    # Test the connection
    if curl -s -k "https://pihole.mati-lab.online/admin/login" > /dev/null 2>&1; then
        log_success "Connection to Pi-hole admin interface successful!"
    else
        log_warning "Connection test failed. Please check logs and try again."
    fi
}

restart_all() {
    log_info "Restarting both Pi-hole and Caddy services..."
    
    ./manage-pihole.sh restart
    sleep 5
    ./manage-caddy.sh restart
    
    log_success "Both services restarted successfully!"
}

update_all() {
    log_info "Updating both Pi-hole and Caddy services..."
    
    ./manage-pihole.sh update
    sleep 5
    ./manage-caddy.sh update
    
    log_success "Both services updated successfully!"
}

# Main script logic
case "${1:-help}" in
    deploy)
        deploy_all
        ;;
    restart)
        restart_all
        ;;
    update)
        update_all
        ;;
    help|*)
        echo "Usage: $0 [deploy|restart|update]"
        echo ""
        echo "Commands:"
        echo "  deploy  - Deploy both services for the first time"
        echo "  restart - Restart both services"
        echo "  update  - Update and restart both services"
        echo "  help    - Show this help message"
        exit 1
        ;;
esac 
