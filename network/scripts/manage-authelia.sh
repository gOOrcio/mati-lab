#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="authelia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SERVICE_DIR="../$SERVICE_NAME"
REMOTE_DATA="/opt/mati-lab/network/$SERVICE_NAME/data"

# Copy data/ files (users_database.yml) that are gitignored
copy_data() {
  if [[ -f "${SERVICE_DIR}/data/users_database.yml" ]]; then
    log "Copying users database to server..."
    ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo mkdir -p $REMOTE_DATA && sudo chown -R ${SERVER_USER}:${SERVER_USER} $REMOTE_DATA"
    scp "${SSH_OPTS[@]}" "${SERVICE_DIR}/data/users_database.yml" "$REMOTE:$REMOTE_DATA/"
  else
    log_error "No users database found at ${SERVICE_DIR}/data/users_database.yml"
    log_error "Copy users_database.yml.example to data/users_database.yml and set a real password hash"
    return 1
  fi
}

# Override deploy/update to also push data files
deploy() { log "Deploying $SERVICE_NAME"; sync_from_github; copy_env_file "$SERVICE_DIR"; copy_data; compose_cmd up -d --pull always; }
update() { log "Updating $SERVICE_NAME"; sync_from_github; copy_env_file "$SERVICE_DIR"; copy_data; compose_cmd down; compose_cmd up -d --pull always; }

# save = push (config is on host)
save() { log "Pushing authelia config to GitHub"; push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
