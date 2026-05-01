# Network Services Makefile
# Provides convenient shortcuts for common operations

.PHONY: help deploy update restart status logs stop start clean setup env rebuild-caddy backup backup-status backup-check add-authelia-user add-authelia-admin

# Service definitions — ordered for dependency-safe deploys
# pihole (DNS) → registry-mirror (Docker registry) → caddy (TLS reverse proxy) → rest
SERVICES := pihole registry-mirror caddy authelia cloudflared uptime-kuma homarr prometheus grafana ntfy diun loki network-pi-metrics pve-exporter promtail grafana-ntfy-bridge graphite-exporter alertmanager
OPERATIONS := deploy update restart status logs stop start push save
BRANCH ?= main

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
	@echo "  push      - Push all service changes to Gitea"
	@echo "  save      - Save configs (Uptime Kuma, Grafana, homarr) and push to Gitea"
	@echo "  clean     - Clean up old files"
	@echo "  setup     - Setup scripts permissions"
	@echo "  env       - Create .env from template"
	@echo ""
	@echo "  backup             - Run backup of all services to NAS"
	@echo "  backup-status      - Show backup timer status and recent logs"
	@echo "  backup-check       - Check NAS mount and timer status"
	@echo ""
	@echo "Service-specific targets:"
	@echo "  {operation}-{service}  - e.g., deploy-caddy, update-grafana"
	@echo ""
	@echo "Special targets:"
	@echo "  check-pihole         - Check Pi-hole DNS resolution"
	@echo "  rebuild-caddy        - Rebuild Caddy image (use when Dockerfile/plugins change)"
	@echo "  add-authelia-user    - Add a regular user to Authelia (group: users)"
	@echo "  add-authelia-admin   - Add an admin user to Authelia (group: admins)"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-caddy"
	@echo "  make update"
	@echo "  make status"
	@echo "  make deploy-caddy BRANCH=feature/foo"

# All services operations
deploy update restart status logs stop start push save:
	@echo "$(shell echo $@ | tr '[:lower:]' '[:upper:]')ing all services..."
	@cd scripts && BRANCH=$(BRANCH) ./manage-all.sh $@

# Generate service-specific targets dynamically
define service_target_template
$(1)-$(2):
	@echo "$$(shell echo $(1) | tr '[:lower:]' '[:upper:]')ing $$(shell echo $(2) | tr '-' ' ' | sed 's/\b\w/\U&/g')..."
	@cd scripts && BRANCH=$(BRANCH) ./manage-$(2).sh $(1)
endef

$(foreach service,$(SERVICES),$(foreach op,$(OPERATIONS),$(eval $(call service_target_template,$(op),$(service)))))

# Special targets
check-pihole:
	@echo "Checking Pi-hole DNS resolution..."
	@cd scripts && ./manage-pihole.sh check

rebuild-caddy:
	@echo "Rebuilding Caddy..."
	@cd scripts && BRANCH=$(BRANCH) ./manage-caddy.sh rebuild

rebuild-grafana-ntfy-bridge:
	@echo "Rebuilding Grafana-Ntfy-Bridge..."
	@cd scripts && BRANCH=$(BRANCH) ./manage-grafana-ntfy-bridge.sh rebuild

# Authelia user management — interactive prompts
add-authelia-user:
	@cd scripts && ./add-authelia-user.sh

add-authelia-admin:
	@cd scripts && ./add-authelia-user.sh --admin

# Backup targets
backup:
	@echo "Running service backup to NAS..."
	@cd scripts && ./manage-backup.sh run

backup-status:
	@echo "Checking backup status..."
	@cd scripts && ./manage-backup.sh status

backup-check:
	@echo "Checking backup prerequisites..."
	@cd scripts && ./manage-backup.sh check

# Utility targets
clean:
	@echo "Cleaning up old files..."
	@rm -f docker-compose.yml.backup deploy.sh update-caddy.sh
	@echo "Cleanup completed!"

setup:
	@echo "Setting up network services..."
	@chmod +x scripts/*.sh
	@echo "Setup completed!"

env:
	@if [ ! -f .env ]; then \
		echo "Creating .env from template..."; \
		cp env.template .env; \
		echo "Please edit .env with your actual values"; \
	else \
		echo ".env file already exists"; \
	fi
