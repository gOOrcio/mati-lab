.PHONY: provision configure deploy install-deps \
        db-backup db-restore db-clean db-shell annotate-deploy \
        maintenance-on maintenance-off

# ── SSH config ───────────────────────────────────────────────────────────────
SSH_KEY  ?= ~/.ssh/id_ed25519
SSH_HOST ?= root@192.168.1.203
SSH      := ssh -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new $(SSH_HOST)
SSH_TTY  := ssh -t -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new $(SSH_HOST)

DB_NAME  ?= restorate
DB_USER  ?= restorate
APP_DIR  ?= /opt/restorate

BACKUP_DIR := ./backups

# ── Provisioning ─────────────────────────────────────────────────────────────

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_lxc.yml

GRAFANA_HOST ?= gooral@192.168.1.252
SSH_GRAFANA  := ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new $(GRAFANA_HOST)

deploy:
	ansible-playbook playbooks/deploy_app.yml
	@$(MAKE) annotate-deploy 2>/dev/null || echo "[WARN] Deploy annotation failed (non-fatal)"

annotate-deploy:
	@COMMIT=$$(cd ~/Projects/resto-rate && git log -1 --format='%h' 2>/dev/null || echo "unknown"); \
	$(SSH_GRAFANA) "docker exec grafana curl -sf -X POST http://localhost:3000/api/annotations \
	  -u 'goorcio:gOOral3714!@#' \
	  -H 'Content-Type: application/json' \
	  -d '{\"tags\":[\"deploy\",\"restorate\"],\"text\":\"Restorate deploy: $$COMMIT\"}'" \
	  && echo "[OK] Deploy annotation created" \
	  || echo "[WARN] Could not create annotation"

# ── Database operations ──────────────────────────────────────────────────────
# Commands run directly on the LXC (no Docker container).

db-backup:
	@mkdir -p $(BACKUP_DIR)
	@set -e; \
	 TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	 OUTFILE=$(BACKUP_DIR)/$(DB_NAME)_$$TIMESTAMP.dump; \
	 TMPFILE=$$OUTFILE.tmp; \
	 echo "Backing up to $$OUTFILE ..."; \
	 $(SSH) "sudo -u postgres pg_dump -Fc $(DB_NAME)" > $$TMPFILE && \
	 mv $$TMPFILE $$OUTFILE && \
	 echo "Done — $$(du -sh $$OUTFILE | cut -f1)" || { rm -f $$TMPFILE; exit 1; }

db-restore:
	@test -n "$(FILE)" || { echo "Usage: make db-restore FILE=<path/to/dump>"; exit 1; }
	@test -f "$(FILE)" || { echo "File not found: $(FILE)"; exit 1; }
	@echo "Restoring $(FILE) into $(DB_NAME) ..."
	cat "$(FILE)" | $(SSH) "sudo -u postgres pg_restore -d $(DB_NAME) --clean --if-exists --no-owner --exit-on-error"
	@echo "Done. Restarting API to re-run migrations ..."
	$(SSH) "systemctl restart restorate-api"

db-clean:
	@echo "WARNING: This will wipe all data in $(DB_NAME). Press Ctrl-C within 5 seconds to abort."
	@sleep 5
	$(SSH) "sudo -u postgres psql -d $(DB_NAME) -v ON_ERROR_STOP=1 -X \
	        -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO $(DB_USER);'"
	@echo "Schema wiped. Restarting API ..."
	$(SSH) "systemctl restart restorate-api"

db-shell:
	$(SSH_TTY) "sudo -u postgres psql $(DB_NAME)"

# ── Maintenance worker (Cloudflare) ──────────────────────────────────────────
# Worker source lives at ~/Projects/resto-rate/infra/maintenance/worker/
# Requires (one-time): bun install + bunx wrangler login
#
# The worker auto-serves the maintenance page when the origin is unreachable
# (5xx / tunnel down). `maintenance-on` additionally pins a scheduled window
# until UNTIL, even if the origin is up.
#
## maintenance-on UNTIL="2026-04-23T10:00:00+02:00" [MESSAGE="..."]
##   Enable scheduled maintenance. UNTIL is required (ISO datetime + timezone).
maintenance-on:
	@test -n "$(UNTIL)" || { echo "Usage: make maintenance-on UNTIL=\"2026-04-23T10:00:00+02:00\" [MESSAGE=\"...\"]"; exit 1; }
	cd ~/Projects/resto-rate/infra/maintenance/worker && \
	  bunx wrangler deploy \
	    --var MAINTENANCE_UNTIL:"$(UNTIL)" \
	    --var MAINTENANCE_MESSAGE:"$(MESSAGE)"
	@echo "Maintenance ON until $(UNTIL)"

## maintenance-off: Disable scheduled maintenance; worker reverts to transparent
##   proxy (still auto-serves the maintenance page on origin 5xx / tunnel down).
maintenance-off:
	cd ~/Projects/resto-rate/infra/maintenance/worker && bunx wrangler deploy
	@echo "Maintenance OFF — worker back to transparent-proxy mode"
