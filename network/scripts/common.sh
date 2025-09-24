#!/usr/bin/env bash
set -Eeuo pipefail

# Common service management functions
# Usage: source this file in service-specific scripts

# Load environment variables
if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"
GITHUB_REPO="git@github.com:gOOrcio/mati-lab.git"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }
log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }
log_error(){ printf "\033[0;31m[ERROR]\033[0m %s\n" "$*"; }

# Common functions
sync_from_github() {
  log "Syncing from GitHub"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt && 
    if [ -d 'mati-lab' ]; then 
      cd mati-lab && git pull origin main; 
    else 
      git clone $GITHUB_REPO && cd mati-lab && git checkout main; 
    fi"
}

copy_env_file() {
  local service_path="$1"
  [[ -f "${service_path}/.env" ]] && scp "${SSH_OPTS[@]}" "${service_path}/.env" "$REMOTE:/opt/mati-lab/network/$SERVICE_NAME/"
}

compose_cmd() {
  local service_dir="/opt/mati-lab/network/$SERVICE_NAME"
  local env_flag=""
  [[ -f "../$SERVICE_NAME/.env" ]] && env_flag="--env-file .env"
  
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd $service_dir && sudo -E docker compose $env_flag ${*}"
}

# Standard service operations
deploy()  { log "Deploying $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd up -d --build; }
update()  { log "Updating $SERVICE_NAME"; sync_from_github; copy_env_file "../$SERVICE_NAME"; compose_cmd down; compose_cmd up -d --build; }
restart() { log "Restarting $SERVICE_NAME"; compose_cmd restart; }
start()   { log "Starting $SERVICE_NAME"; compose_cmd up -d; }
stop()    { log "Stopping $SERVICE_NAME"; compose_cmd stop; }
status()  { compose_cmd ps; }
logs()    { compose_cmd logs --tail 50 -f; }