#!/usr/bin/bash

# Create the remote project directory structure
ssh gooral@192.168.1.252 "sudo mkdir -p /opt/compose/caddy /opt/compose/pihole/etc-pihole /opt/compose/pihole/etc-dnsmasq.d /opt/compose/uptime-kuma/data"

# Ensure Caddy data and config directories exist for certificate persistence
ssh gooral@192.168.1.252 "sudo mkdir -p /opt/compose/caddy/data /opt/compose/caddy/config /opt/compose/uptime-kuma/data"

# Set proper ownership and permissions for the compose directory
ssh gooral@192.168.1.252 "sudo chown -R gooral:gooral /opt/compose"

# Copy docker-compose file
scp docker-compose.yml gooral@192.168.1.252:/opt/compose/

# Copy environment file
scp .env gooral@192.168.1.252:/opt/compose/

# Clear only Caddyfile and Dockerfile, preserve data and config directories
ssh gooral@192.168.1.252 "sudo rm -f /opt/compose/caddy/Caddyfile /opt/compose/caddy/Dockerfile"
scp caddy/Dockerfile gooral@192.168.1.252:/opt/compose/caddy/
scp caddy/Caddyfile gooral@192.168.1.252:/opt/compose/caddy/

# Only clear existing dnsmasq.d files while preserving pihole config
ssh gooral@192.168.1.252 "sudo rm -rf /opt/compose/pihole/etc-dnsmasq.d/*"
scp -r pihole/etc-pihole/* gooral@192.168.1.252:/opt/compose/pihole/etc-pihole/ 2>/dev/null || true
scp -r pihole/etc-dnsmasq.d/* gooral@192.168.1.252:/opt/compose/pihole/etc-dnsmasq.d/ 2>/dev/null || true

# Verify files are in place and set proper permissions
ssh gooral@192.168.1.252 "ls -la /opt/compose/ && sudo chmod -R 644 /opt/compose/.env"

# --- Pi-hole update and safe restart ---
# Stop and remove only Pi-hole container
ssh gooral@192.168.1.252 "cd /opt/compose && sudo docker compose stop pihole || true"
ssh gooral@192.168.1.252 "sudo docker rm -f pihole 2>/dev/null || true"
# Start only Pi-hole
ssh gooral@192.168.1.252 "cd /opt/compose && sudo -E docker compose --env-file .env up -d pihole"

# --- Update and restart other services ---
# Stop and remove Caddy and Uptime Kuma containers
ssh gooral@192.168.1.252 "cd /opt/compose && sudo docker compose stop caddy uptime-kuma || true"
ssh gooral@192.168.1.252 "sudo docker rm -f caddy uptime-kuma 2>/dev/null || true"
# Start Caddy and Uptime Kuma
ssh gooral@192.168.1.252 "cd /opt/compose && sudo -E docker compose --env-file .env up -d caddy uptime-kuma"

echo "Script completed!"
