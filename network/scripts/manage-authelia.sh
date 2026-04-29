#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="authelia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

SERVICE_DIR="../$SERVICE_NAME"
REMOTE_DATA="/opt/mati-lab/network/$SERVICE_NAME/data"

# Copy data/ files (gitignored) to remote server
copy_data() {
  if [[ -f "${SERVICE_DIR}/data/users_database.yml" ]]; then
    log "Copying data files to server..."
    # shellcheck disable=SC2029 # intentional client-side expansion
    ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo mkdir -p $REMOTE_DATA && sudo chown -R ${SERVER_USER}:${SERVER_USER} $REMOTE_DATA"
    scp "${SSH_OPTS[@]}" "${SERVICE_DIR}/data/users_database.yml" "$REMOTE:$REMOTE_DATA/"
  else
    log_error "No users database found at ${SERVICE_DIR}/data/users_database.yml"
    log_error "Copy users_database.yml.example to data/users_database.yml and set a real password hash"
    return 1
  fi

  # Copy OIDC key files if they exist
  for oidc_file in oidc.key oidc_hmac_secret.txt oidc_proxmox_client_secret.txt; do
    if [[ -f "${SERVICE_DIR}/data/${oidc_file}" ]]; then
      log "Copying ${oidc_file} to server..."
      scp "${SSH_OPTS[@]}" "${SERVICE_DIR}/data/${oidc_file}" "$REMOTE:$REMOTE_DATA/"
    fi
  done
}

# Override deploy/update to also push data files
# --force-recreate on deploy: configuration.yml is bind-mounted; see common.sh::deploy.
deploy() { log "Deploying $SERVICE_NAME"; sync_from_gitea; copy_env_file "$SERVICE_DIR"; copy_data; compose_cmd up -d --pull always --force-recreate; }
update() { log "Updating $SERVICE_NAME"; sync_from_gitea; copy_env_file "$SERVICE_DIR"; copy_data; compose_cmd down; compose_cmd up -d --pull always; }

# save = push (config is on host)
save() { log "Pushing authelia config to Gitea"; push; }

# Handle command line arguments
case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|push|save) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|push|save}"; exit 1 ;;
esac
