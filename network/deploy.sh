#!/usr/bin/bash

# Create the remote project directory structure
ssh gooral@192.168.1.252 "sudo mkdir -p /opt/compose/caddy /opt/compose/pihole/etc-pihole /opt/compose/pihole/etc-dnsmasq.d"

# Set proper ownership and permissions for the compose directory
ssh gooral@192.168.1.252 "sudo chown -R gooral:gooral /opt/compose"

# Copy docker-compose file
scp docker-compose.yml gooral@192.168.1.252:/opt/compose/

# Copy environment files
scp .env.caddy .env.pihole gooral@192.168.1.252:/opt/compose/

# Create a combined .env file that Docker Compose will automatically recognize
ssh gooral@192.168.1.252 "cat /opt/compose/.env.caddy /opt/compose/.env.pihole > /opt/compose/.env"

# Clear existing Caddy config files before copying new ones
ssh gooral@192.168.1.252 "sudo rm -rf /opt/compose/caddy/*"
scp -r caddy/Dockerfile gooral@192.168.1.252:/opt/compose/caddy/
scp -r caddy/Caddyfile gooral@192.168.1.252:/opt/compose/caddy/

# Only clear existing dnsmasq.d files while preserving pihole config
ssh gooral@192.168.1.252 "sudo rm -rf /opt/compose/pihole/etc-dnsmasq.d/*"
scp -r pihole/etc-pihole/* gooral@192.168.1.252:/opt/compose/pihole/etc-pihole/ 2>/dev/null || true
scp -r pihole/etc-dnsmasq.d/* gooral@192.168.1.252:/opt/compose/pihole/etc-dnsmasq.d/ 2>/dev/null || true

# Verify files are in place and set proper permissions
ssh gooral@192.168.1.252 "ls -la /opt/compose/ && sudo chmod -R 644 /opt/compose/.env*"

# Stop and remove existing containers that might cause conflicts
ssh gooral@192.168.1.252 "cd /opt/compose && sudo docker compose down || true"
ssh gooral@192.168.1.252 "sudo docker rm -f caddy pihole 2>/dev/null || true"

# Deploy the stack with sudo and explicitly specify env file
ssh gooral@192.168.1.252 "cd /opt/compose && sudo -E docker compose --env-file .env up -d"

echo "Deployment completed!"
