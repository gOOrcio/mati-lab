# Network Services Management

This directory contains the network services for the mati-lab infrastructure, now organized as separate, independently manageable services.

## 🏗️ Architecture

Each service now has its own:

-   `docker-compose.yml` file
-   Configuration directory
-   Data persistence volumes
-   Management scripts

### Services

1. **Caddy** - Reverse proxy with automatic HTTPS
2. **Pi-hole** - DNS ad-blocker and DHCP server
3. **Uptime Kuma** - Uptime monitoring

## 📁 Directory Structure

```
network/
├── caddy/
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── Caddyfile
│   ├── data/          # Persistent certificates
│   └── config/        # Persistent configuration
├── pihole/
│   ├── docker-compose.yml
│   ├── etc-pihole/    # Pi-hole configuration
│   └── etc-dnsmasq.d/ # DNS configuration
├── uptime-kuma/
│   ├── docker-compose.yml
│   └── data/          # Persistent monitoring data
├── scripts/
│   ├── manage-caddy.sh
│   ├── manage-pihole.sh
│   ├── manage-uptime-kuma.sh
│   └── manage-all.sh
├── .env               # Environment variables
├── env.template       # Environment template
└── README.md
```

## 🚀 Quick Start

### 1. Environment Setup

Copy the environment template and fill in your values:

```bash
cp env.template .env
# Edit .env with your actual values
```

Required environment variables:

-   `CF_API_TOKEN` - Cloudflare API token for DNS challenges
-   `PIHOLE_ADMIN_PASS` - Pi-hole admin password
-   `SERVER_HOST` - Target server IP
-   `SERVER_USER` - SSH username
-   `SERVER_PATH` - Remote compose directory

### 2. Deploy All Services

```bash
cd scripts
chmod +x *.sh
./manage-all.sh deploy
```

### 3. Deploy Individual Service

```bash
./manage-caddy.sh deploy
./manage-pihole.sh deploy
./manage-uptime-kuma.sh deploy
```

## 🛠️ Management Commands

### Individual Service Management

Each service can be managed independently:

```bash
# Caddy
./manage-caddy.sh [deploy|update|restart|status|logs|stop|start|push|save]

# Pi-hole
./manage-pihole.sh [deploy|update|restart|status|logs|stop|start|push|save]

# Uptime Kuma
./manage-uptime-kuma.sh [deploy|update|restart|status|logs|stop|start|push|save]

# Grafana
./manage-grafana.sh [deploy|update|restart|status|logs|stop|start|push|save]

# Dashy
./manage-dashy.sh [deploy|update|restart|status|logs|stop|start|push|save]
```

### Saving Configs to Git

After configuring monitors (Uptime Kuma), dashboards (Grafana), or layout (Dashy) via the web UI, save them to git:

```bash
./manage-uptime-kuma.sh save   # Monitors in app/data/
./manage-grafana.sh save       # Exports dashboards via API to provisioning/dashboards/
./manage-dashy.sh save         # conf.yml is bind-mounted (edits via web UI)

# Save all
./manage-all.sh save
```

- **Uptime Kuma**: `app/data/` (SQLite) is committed
- **Grafana**: Dashboards exported to `provisioning/dashboards/*.json` (requires `jq`, `GF_SECURITY_ADMIN_PASSWORD` in grafana/.env)
- **Dashy**: `config/conf.yml` is bind-mounted

### Bulk Operations

Manage all services at once:

```bash
./manage-all.sh [deploy|update|restart|status|logs|stop|start|push|save]
```

### Service-Specific Operations

```bash
./manage-all.sh caddy restart    # Restart only Caddy
./manage-all.sh pihole update    # Update only Pi-hole
./manage-all.sh status           # Show status of all services
```

## 📊 Service Status

Check service status:

```bash
# Individual service
./manage-caddy.sh status

# All services
./manage-all.sh status
```

## 📋 Logs

View service logs:

```bash
# Individual service
./manage-caddy.sh logs

# All services (shows logs for each service)
./manage-all.sh logs
```

## 🔧 Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure scripts are executable (`chmod +x *.sh`)
2. **SSH Connection Failed**: Verify SSH keys and server connectivity
3. **Environment Variables Missing**: Check `.env` file exists and contains required values
4. **Service Won't Start**: Check logs with `./manage-[service].sh logs`

### Debug Mode

Add `set -x` to any script to enable debug output:

```bash
#!/usr/bin/bash
set -x  # Add this line for debug output
```

## 🔒 Security Considerations

-   SSH keys should be stored securely in CI/CD systems
-   Environment files contain sensitive data - never commit `.env` files
-   Use least-privilege SSH users for deployment
-   Regularly rotate API tokens and passwords

## 📈 Scaling and Adding Services

To add a new service:

1. Create service directory with `docker-compose.yml`
2. Create management script in `scripts/`
3. Add service to `SERVICES` array in `manage-all.sh`
4. Update CI/CD configurations if needed

## 🤝 Contributing

When modifying services:

1. Test changes locally first
2. Use the management scripts for deployment
3. Update documentation
4. Consider backward compatibility for data persistence

## 📞 Support

For issues or questions:

1. Check service logs first
2. Verify environment configuration
3. Test SSH connectivity
4. Review this documentation
