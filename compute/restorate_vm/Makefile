.PHONY: provision configure deploy install-deps \
        db-backup db-restore db-clean db-shell db-logs db-psql-exec

# ── SSH / container config ────────────────────────────────────────────────────
SSH_KEY  := ~/.ssh/id_ed25519
SSH_HOST := debian@192.168.1.203
SSH      := ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no $(SSH_HOST)
SSH_TTY  := ssh -t -i $(SSH_KEY) -o StrictHostKeyChecking=no $(SSH_HOST)

DB_CONTAINER := restorate-db
DB_NAME      := restorate
DB_USER      := restorate
APP_DIR      := /opt/restorate

BACKUP_DIR := ./backups

# ── Provisioning ──────────────────────────────────────────────────────────────

install-deps:
	ansible-galaxy collection install -r requirements.yml

provision: install-deps
	ansible-playbook playbooks/site.yml

configure:
	ansible-playbook playbooks/configure_vm.yml

deploy:
	ansible-playbook playbooks/deploy_app.yml

# ── Database operations ───────────────────────────────────────────────────────
# All targets connect to the remote VM over SSH and run commands inside the
# restorate-db Docker container.

## db-backup: Dump the database to ./backups/restorate_<timestamp>.dump (custom format).
##            Backups are portable across Postgres minor versions via pg_restore.
db-backup:
	@mkdir -p $(BACKUP_DIR)
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	 OUTFILE=$(BACKUP_DIR)/restorate_$$TIMESTAMP.dump; \
	 echo "Backing up to $$OUTFILE ..."; \
	 $(SSH) "docker exec $(DB_CONTAINER) pg_dump -U $(DB_USER) -Fc $(DB_NAME)" > $$OUTFILE; \
	 echo "Done — $$(du -sh $$OUTFILE | cut -f1)"

## db-restore FILE=<path>: Restore a dump created by db-backup.
##   Example: make db-restore FILE=backups/restorate_20260402_120000.dump
##   WARNING: This runs with --clean so existing data is dropped before restore.
db-restore:
	@test -n "$(FILE)" || { echo "Usage: make db-restore FILE=<path/to/dump>"; exit 1; }
	@test -f "$(FILE)" || { echo "File not found: $(FILE)"; exit 1; }
	@echo "Restoring $(FILE) into $(DB_NAME) on $(SSH_HOST) ..."
	$(SSH) "docker exec -i $(DB_CONTAINER) pg_restore -U $(DB_USER) -d $(DB_NAME) --clean --if-exists --no-owner" < $(FILE)
	@echo "Done. Restarting API to re-run migrations ..."
	$(SSH) "cd $(APP_DIR) && docker compose restart api"

## db-clean: Drop and recreate the public schema — wipes all application tables.
##           The API auto-migrates the schema on next startup.
##           Use this for a fresh-state deploy without recreating the Postgres container.
db-clean:
	@echo "WARNING: This will wipe all data in $(DB_NAME). Press Ctrl-C within 5 seconds to abort."
	@sleep 5
	$(SSH) "docker exec $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) \
	        -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO $(DB_USER);'"
	@echo "Schema wiped. Restarting API to re-run auto-migration ..."
	$(SSH) "cd $(APP_DIR) && docker compose restart api"

## db-shell: Open an interactive psql session on the remote database.
db-shell:
	$(SSH_TTY) "docker exec -it $(DB_CONTAINER) psql -U $(DB_USER) $(DB_NAME)"

## db-logs: Tail PostgreSQL container logs.
db-logs:
	$(SSH_TTY) "docker logs -f --tail=100 $(DB_CONTAINER)"

## db-psql-exec SQL="<query>": Run a one-shot SQL statement (no TTY needed, good for scripts).
##   Example: make db-psql-exec SQL="SELECT count(*) FROM users"
db-psql-exec:
	@test -n "$(SQL)" || { echo "Usage: make db-psql-exec SQL=\"<query>\""; exit 1; }
	$(SSH) "docker exec $(DB_CONTAINER) psql -U $(DB_USER) -d $(DB_NAME) -c '$(SQL)'"
