#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SERVICE_NAME="grafana"
SERVICE_PATH="../grafana"
REMOTE_PATH="${SERVER_PATH}/${SERVICE_NAME}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }

sync_files() {
  log "sync files from GitHub"
  
  # Clone or pull the entire repository
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt && 
    if [ -d 'mati-lab' ]; then 
      cd mati-lab && git pull origin main; 
    else 
      git clone git@github.com:gOOrcio/mati-lab.git && 
      cd mati-lab && git checkout main; 
    fi"
  
  # Copy environment file if it exists locally
  [[ -f "${SERVICE_PATH}/.env" ]] && scp "${SSH_OPTS[@]}" "${SERVICE_PATH}/.env" "$REMOTE:/opt/mati-lab/network/grafana/"
}

compose() {
  # pass raw args to docker compose (working in network/grafana directory)
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt/mati-lab/network/grafana && sudo -E docker compose --env-file .env ${*}"
}

deploy()  { log "deploy";  sync_files; compose up -d; }
update()  { log "update";  sync_files; compose down; compose up -d; }
restart() { log "restart"; compose restart; }
start()   { log "start";   compose up -d; }
stop()    { log "stop";    compose stop; }
status()  { compose ps; }
logs()    { compose logs --tail 50 -f; }

case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs}"; exit 1 ;;
esac
