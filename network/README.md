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
├── migrate-to-separate-services.sh
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
./manage-caddy.sh [deploy|update|restart|status|logs|stop|start]

# Pi-hole
./manage-pihole.sh [deploy|update|restart|status|logs|stop|start]

# Uptime Kuma
./manage-uptime-kuma.sh [deploy|update|restart|status|logs|stop|start]
```

### Bulk Operations

Manage all services at once:

```bash
./manage-all.sh [deploy|update|restart|status|logs|stop|start]
```

### Service-Specific Operations

```bash
./manage-all.sh caddy restart    # Restart only Caddy
./manage-all.sh pihole update    # Update only Pi-hole
./manage-all.sh status           # Show status of all services
```

## 🔄 Migration from Old Setup

If you're migrating from the old single `docker-compose.yml` setup:

1. **Backup your current setup**
2. **Run the migration script**:
    ```bash
    chmod +x migrate-to-separate-services.sh
    ./migrate-to-separate-services.sh
    ```

The migration script will:

-   Backup your old configuration
-   Stop old services
-   Deploy new separate services
-   Preserve all data
-   Clean up old files

## 🚀 CI/CD Integration

### GitHub Actions

The `.github/workflows/deploy-service.yml` workflow provides:

-   Automatic deployment on code changes
-   Manual deployment with service/action selection
-   SSH key-based authentication
-   Environment variable injection

**Required Secrets:**

-   `SSH_PRIVATE_KEY` - SSH private key for server access
-   `SERVER_HOST` - Target server IP
-   `SERVER_USER` - SSH username
-   `SERVER_PATH` - Remote compose directory
-   `ENV_FILE_CONTENT` - Content of your .env file

### Jenkins

The `Jenkinsfile` provides:

-   Parameterized builds for service/action selection
-   Credential-based authentication
-   Pipeline stages for deployment and verification

**Required Credentials:**

-   `SERVER_HOST` - String credential
-   `SERVER_USER` - String credential
-   `SERVER_PATH` - String credential
-   `SSH_PRIVATE_KEY` - SSH private key credential

### Gitea Actions

The GitHub Actions workflow can be adapted for Gitea Actions by:

-   Changing the workflow trigger syntax
-   Adjusting secret names if needed
-   Using Gitea's runner syntax

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
