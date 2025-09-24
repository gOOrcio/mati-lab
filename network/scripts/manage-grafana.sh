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
  log "sync files"
  ssh "${SSH_OPTS[@]}" "$REMOTE" \
    "sudo mkdir -p '$REMOTE_PATH'/config '$REMOTE_PATH'/provisioning/datasources &&
     sudo chown -R '$SERVER_USER:$SERVER_USER' '$REMOTE_PATH'"
  scp "${SSH_OPTS[@]}" "${SERVICE_PATH}/docker-compose.yml" "$REMOTE:$REMOTE_PATH/"
  scp "${SSH_OPTS[@]}" "${SERVICE_PATH}/provisioning/datasources/prometheus.yml" "$REMOTE:$REMOTE_PATH/provisioning/datasources/"
  [[ -f "${SERVICE_PATH}/.env" ]] && scp "${SSH_OPTS[@]}" "${SERVICE_PATH}/.env" "$REMOTE:$REMOTE_PATH/"
}

compose() {
  # pass raw args to docker compose
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$REMOTE_PATH' && sudo -E docker compose --env-file .env ${*}"
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
