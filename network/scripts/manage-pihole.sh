#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f "../.pihole-remote.env" ]]; then
  . "../.pihole-remote.env"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SERVICE_NAME="pihole"
SERVICE_PATH="../pihole"
REMOTE_PATH="${SERVER_PATH}/${SERVICE_NAME}"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }

ensure_network() {
  # only needed because caddy uses an external network named pihole-net
  ssh "${SSH_OPTS[@]}" "$REMOTE" "docker network inspect pihole-net >/dev/null 2>&1 || docker network create pihole-net"
}

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
  [[ -f "${SERVICE_PATH}/.env" ]] && scp "${SSH_OPTS[@]}" "${SERVICE_PATH}/.env" "$REMOTE:/opt/mati-lab/network/pihole/"
}

compose() {
  # pass raw args to docker compose (working in network/pihole directory)
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd /opt/mati-lab/network/pihole && sudo -E docker compose ${*}"
}

deploy()  { log "deploy";  ensure_network; sync_files; compose up -d --pull always; }
update()  { log "update";  sync_files;       compose down; compose up -d --pull always; }
restart() { log "restart"; compose restart; }
start()   { log "start";   compose up -d; }
stop()    { log "stop";    compose stop; }
status()  { compose ps; }
logs()    { compose logs --tail 100 -f; }
check()   { ssh "${SSH_OPTS[@]}" "$REMOTE" "nslookup google.com 127.0.0.1 >/dev/null && echo OK || echo FAIL"; }

case "${1:-help}" in
  deploy|update|restart|start|stop|status|logs|check) "$1" ;;
  *) echo "usage: $0 {deploy|update|restart|start|stop|status|logs|check}"; exit 1 ;;
esac
