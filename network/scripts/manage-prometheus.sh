#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SERVICE_NAME="prometheus"
SERVICE_PATH="../prometheus"
REMOTE_PATH="${SERVER_PATH}/${SERVICE_NAME}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }

sync_config() {
  log "sync config from host to git"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$REMOTE_PATH' && git add . && git diff --cached --quiet || git commit -m 'Update config: $(date)' && git push origin main"
}

compose() {
  # pass raw args to docker compose
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$REMOTE_PATH' && sudo -E docker compose ${*}"
}

deploy()  { log "deploy";  sync_files; compose up -d --build; }
update()  { log "update";  sync_files; compose down; compose up -d --build; }
restart() { log "restart"; compose restart; }
start()   { log "start";   compose up -d; }
stop()    { log "stop";    compose stop; }
status()  { compose ps; }
logs()    { compose logs --tail 50 -f; }

case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|sync_config) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|sync_config}"; exit 1 ;;
esac
