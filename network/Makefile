# Network Services Makefile
# Provides convenient shortcuts for common operations

.PHONY: help deploy update restart status logs stop start clean setup env rebuild-caddy

# Service definitions
SERVICES := pihole authelia caddy uptime-kuma homarr prometheus grafana ntfy diun cloudflared loki network-pi-metrics registry-mirror pve-exporter promtail grafana-ntfy-bridge
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
	@echo "  push      - Push all service changes to GitHub"
	@echo "  save      - Save configs (Uptime Kuma, Grafana, homarr) and push to GitHub"
	@echo "  clean     - Clean up old files"
	@echo "  setup     - Setup scripts permissions"
	@echo "  env       - Create .env from template"
	@echo ""
	@echo "Service-specific targets:"
	@echo "  {operation}-{service}  - e.g., deploy-caddy, update-grafana"
	@echo ""
	@echo "Special targets:"
	@echo "  check-pihole         - Check Pi-hole DNS resolution"
	@echo "  rebuild-caddy        - Rebuild Caddy image (use when Dockerfile/plugins change)"
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
