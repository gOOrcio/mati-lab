#!/usr/bin/bash

# Migration Script: Convert from single docker-compose to separate services
# This script helps migrate from the old setup to the new separate services structure

set -e

# Load environment variables
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
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

echo "🚀 Migration Script: Converting to Separate Services Structure"
echo "================================================================"
echo ""

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    log_error "This script must be run from the network directory containing the old docker-compose.yml"
    exit 1
fi

# Backup old configuration
log_info "Creating backup of old configuration..."
cp docker-compose.yml docker-compose.yml.backup
log_success "Backup created: docker-compose.yml.backup"

# Stop old services
log_info "Stopping old services..."
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && sudo docker compose down" || {
    log_warning "Failed to stop old services, they may not be running"
}

# Create new directory structure
log_info "Creating new directory structure on server..."
ssh ${SERVER_USER}@${SERVER_HOST} "sudo mkdir -p ${SERVER_PATH}/caddy/data ${SERVER_PATH}/caddy/config"
ssh ${SERVER_USER}@${SERVER_HOST} "sudo mkdir -p ${SERVER_PATH}/pihole/etc-pihole ${SERVER_PATH}/pihole/etc-dnsmasq.d"
ssh ${SERVER_USER}@${SERVER_HOST} "sudo mkdir -p ${SERVER_PATH}/uptime-kuma/data"

# Set ownership
ssh ${SERVER_USER}@${SERVER_HOST} "sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_PATH}"

# Copy new service files
log_info "Copying new service configurations..."

# Copy Caddy
scp caddy/docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/caddy/
scp caddy/Dockerfile ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/caddy/
scp caddy/Caddyfile ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/caddy/

# Copy Pi-hole
scp pihole/docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/pihole/
scp -r pihole/etc-pihole/* ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/pihole/etc-pihole/ 2>/dev/null || true
scp -r pihole/etc-dnsmasq.d/* ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/pihole/etc-dnsmasq.d/ 2>/dev/null || true

# Copy Uptime Kuma
scp uptime-kuma/docker-compose.yml ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/uptime-kuma/

# Copy environment file
if [ -f ".env" ]; then
    scp .env ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/caddy/
    scp .env ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/pihole/
    scp .env ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/uptime-kuma/
fi

# Deploy services
log_info "Deploying new services..."

# Deploy Caddy first (as it's the reverse proxy)
log_info "Deploying Caddy..."
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/caddy && sudo -E docker compose --env-file .env up -d --build"

# Deploy Pi-hole
log_info "Deploying Pi-hole..."
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/pihole && sudo -E docker compose --env-file .env up -d"

# Deploy Uptime Kuma
log_info "Deploying Uptime Kuma..."
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/uptime-kuma && sudo -E docker compose --env-file .env up -d"

# Verify deployment
log_info "Verifying deployment..."
echo ""
echo "=== Service Status ==="
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/caddy && sudo docker compose ps"
echo ""
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/pihole && sudo docker compose ps"
echo ""
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH}/uptime-kuma && sudo docker compose ps"

# Cleanup old files
log_info "Cleaning up old files..."
ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && sudo rm -f docker-compose.yml"

log_success "Migration completed successfully!"
echo ""
echo "🎉 Your services are now running in separate docker-compose configurations!"
echo ""
echo "📋 Next steps:"
echo "   1. Test your services:"
echo "      - https://pihole.mati-lab.online"
echo "      - https://proxmox.mati-lab.online"
echo "      - https://homebridge.mati-lab.online"
echo "      - https://uptime-kuma.mati-lab.online"
echo ""
echo "   2. Use the new management scripts:"
echo "      - ./scripts/manage-caddy.sh [action]"
echo "      - ./scripts/manage-pihole.sh [action]"
echo "      - ./scripts/manage-uptime-kuma.sh [action]"
echo "      - ./scripts/manage-all.sh [service] [action]"
echo ""
echo "   3. Remove the old deploy.sh and update-caddy.sh scripts when ready"
echo ""
echo "⚠️  Note: Your old docker-compose.yml has been backed up as docker-compose.yml.backup" 