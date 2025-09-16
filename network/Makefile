# Network Services Makefile
# Provides convenient shortcuts for common operations

.PHONY: help deploy update restart status logs stop start clean health

# Default target
help:
	@echo "Network Services Management"
	@echo "=========================="
	@echo ""
	@echo "Available targets:"
	@echo "  deploy    - Deploy all services"
	@echo "  update    - Update all services"
	@echo "  restart   - Restart all services"
	@echo "  status    - Show status of all services"
	@echo "  logs      - Show logs of all services"
	@echo "  stop      - Stop all services"
	@echo "  start     - Start all services"
	@echo "  clean     - Clean up old files"
	@echo ""
	@echo "Service-specific targets:"
	@echo "  deploy-caddy      - Deploy only Caddy"
	@echo "  deploy-pihole     - Deploy only Pi-hole"
	@echo "  deploy-uptime     - Deploy only Uptime Kuma"
	@echo "  update-caddy      - Update only Caddy"
	@echo "  update-pihole     - Update only Pi-hole"
	@echo "  update-uptime     - Update only Uptime Kuma"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-caddy"
	@echo "  make update"
	@echo "  make status"

# All services operations
deploy:
	@echo "Deploying all services..."
	@cd scripts && ./manage-all.sh deploy

update:
	@echo "Updating all services..."
	@cd scripts && ./manage-all.sh update

restart:
	@echo "Restarting all services..."
	@cd scripts && ./manage-all.sh restart

status:
	@echo "Checking status of all services..."
	@cd scripts && ./manage-all.sh status

logs:
	@echo "Showing logs of all services..."
	@cd scripts && ./manage-all.sh logs

stop:
	@echo "Stopping all services..."
	@cd scripts && ./manage-all.sh stop

start:
	@echo "Starting all services..."
	@cd scripts && ./manage-all.sh start

# Individual service operations
deploy-caddy:
	@echo "Deploying Caddy..."
	@cd scripts && ./manage-caddy.sh deploy

deploy-pihole:
	@echo "Deploying Pi-hole..."
	@cd scripts && ./manage-pihole.sh deploy

deploy-uptime:
	@echo "Deploying Uptime Kuma..."
	@cd scripts && ./manage-uptime-kuma.sh deploy

deploy-dashy:
	@echo "Deploying Dashy..."
	@cd scripts && ./manage-dashy.sh deploy

deploy-prometheus:
	@echo "Deploying Prometheus..."
	@cd scripts && ./manage-prometheus.sh deploy

deploy-grafana:
	@echo "Deploying Grafana..."
	@cd scripts && ./manage-grafana.sh deploy

update-caddy:
	@echo "Updating Caddy..."
	@cd scripts && ./manage-caddy.sh update

update-pihole:
	@echo "Updating Pi-hole..."
	@cd scripts && ./manage-pihole.sh update

update-uptime:
	@echo "Updating Uptime Kuma..."
	@cd scripts && ./manage-uptime-kuma.sh update

update-dashy:
	@echo "Updating Dashy..."
	@cd scripts && ./manage-dashy.sh update

update-prometheus:
	@echo "Updating Prometheus..."
	@cd scripts && ./manage-prometheus.sh update

update-grafana:
	@echo "Updating Grafana..."
	@cd scripts && ./manage-grafana.sh update

restart-caddy:
	@echo "Restarting Caddy..."
	@cd scripts && ./manage-caddy.sh restart

restart-pihole:
	@echo "Restarting Pi-hole..."
	@cd scripts && ./manage-pihole.sh restart

restart-uptime:
	@echo "Restarting Uptime Kuma..."
	@cd scripts && ./manage-uptime-kuma.sh restart

restart-dashy:
	@echo "Restarting Dashy..."
	@cd scripts && ./manage-dashy.sh restart

restart-prometheus:
	@echo "Restarting Prometheus..."
	@cd scripts && ./manage-prometheus.sh restart

restart-grafana:
	@echo "Restarting Grafana..."
	@cd scripts && ./manage-grafana.sh restart

status-caddy:
	@echo "Checking Caddy status..."
	@cd scripts && ./manage-caddy.sh status

status-pihole:
	@echo "Checking Pi-hole status..."
	@cd scripts && ./manage-pihole.sh status

status-uptime:
	@echo "Checking Uptime Kuma status..."
	@cd scripts && ./manage-uptime-kuma.sh status

status-dashy:
	@echo "Checking Dashy status..."
	@cd scripts && ./manage-dashy.sh status

status-prometheus:
	@echo "Checking Prometheus status..."
	@cd scripts && ./manage-prometheus.sh status

status-grafana:
	@echo "Checking Grafana status..."
	@cd scripts && ./manage-grafana.sh status

logs-caddy:
	@echo "Showing Caddy logs..."
	@cd scripts && ./manage-caddy.sh logs

logs-pihole:
	@echo "Showing Pi-hole logs..."
	@cd scripts && ./manage-pihole.sh logs

logs-uptime:
	@echo "Showing Uptime Kuma logs..."
	@cd scripts && ./manage-uptime-kuma.sh logs

logs-dashy:
	@echo "Showing Dashy logs..."
	@cd scripts && ./manage-dashy.sh logs

logs-prometheus:
	@echo "Showing Prometheus logs..."
	@cd scripts && ./manage-prometheus.sh logs

logs-grafana:
	@echo "Showing Grafana logs..."
	@cd scripts && ./manage-grafana.sh logs

clean:
	@echo "Cleaning up old files..."
	@rm -f docker-compose.yml.backup
	@rm -f deploy.sh update-caddy.sh
	@echo "Cleanup completed!"

# Setup and installation
setup:
	@echo "Setting up network services..."
	@chmod +x scripts/*.sh
	@echo "Setup completed!"

# Environment setup
env:
	@if [ ! -f .env ]; then \
		echo "Creating .env from template..."; \
		cp env.template .env; \
		echo "Please edit .env with your actual values"; \
	else \
		echo ".env file already exists"; \
	fi 
