#!/usr/bin/bash

echo "🔄 Updating Caddyfile and restarting Caddy service..."

# Copy only the Caddyfile to the server
echo "📁 Copying Caddyfile to server..."
scp caddy/Caddyfile gooral@192.168.1.252:/opt/compose/caddy/

# Verify the file was copied
echo "✅ Verifying file copy..."
ssh gooral@192.168.1.252 "ls -la /opt/compose/caddy/Caddyfile"

# Restart only the Caddy container
echo "🔄 Restarting Caddy container..."
ssh gooral@192.168.1.252 "cd /opt/compose && sudo docker compose restart caddy"

# Wait a moment for the service to start
echo "⏳ Waiting for Caddy to start..."
sleep 5

# Check if Caddy is running
echo "🔍 Checking Caddy status..."
ssh gooral@192.168.1.252 "sudo docker compose ps caddy"

# Show recent logs to verify it started correctly
echo "📋 Recent Caddy logs:"
ssh gooral@192.168.1.252 "sudo docker logs caddy --tail 10"

echo "✅ Caddy update completed!"
echo "🌐 Test your domains:"
echo "   - https://pihole.mati-lab.online"
echo "   - https://proxmox.mati-lab.online"
echo "   - https://homebridge.mati-lab.online"
echo "   - https://restorate.dev.mati-lab.online" 