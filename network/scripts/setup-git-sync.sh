#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f "../.env" ]; then
  export "$(cat ../.env | grep -v '^#' | xargs)"
else
  SERVER_HOST="${SERVER_HOST:-192.168.1.252}"
  SERVER_USER="${SERVER_USER:-gooral}"
  SERVER_PATH="${SERVER_PATH:-/opt/compose}"
fi

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
REMOTE="${SERVER_USER}@${SERVER_HOST}"

log(){ printf "\033[0;34m[INFO]\033[0m %s\n" "$*"; }
log_success(){ printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"; }

setup_git_sync() {
  log "Setting up git sync on host..."
  
  # Initialize git repo on host (in network directory)
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$SERVER_PATH' && git init"
  
  # Configure git user (if not already configured)
  ssh "${SSH_OPTS[@]}" "$REMOTE" "git config --global user.email 'gooral@mati-lab.online' || true"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "git config --global user.name 'mati-lab' || true"
  
  # Rename branch to main (modern convention)
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$SERVER_PATH' && git branch -m master main"
  
  # Add GitHub remote
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$SERVER_PATH' && git remote add origin git@github.com:gOOrcio/mati-lab.git"
  
  # Copy .gitignore files to host
  log "Copying .gitignore files to host..."
  scp "${SSH_OPTS[@]}" "../.gitignore" "$REMOTE:$SERVER_PATH/"
  
  # Copy service .gitignore files (create directories if they don't exist)
  for service in caddy pihole uptime-kuma grafana prometheus dashy network-pi-metrics; do
    if [[ -f "../$service/.gitignore" ]]; then
      ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$SERVER_PATH/$service'"
      scp "${SSH_OPTS[@]}" "../$service/.gitignore" "$REMOTE:$SERVER_PATH/$service/"
    fi
  done
  
  # Initial commit
  ssh "${SSH_OPTS[@]}" "$REMOTE" "cd '$SERVER_PATH' && git add . && git commit -m 'Initial config sync setup'"
  
  log_success "Git sync setup complete!"
  log "To sync config changes: make sync-config-grafana"
  log "Changes will be pushed directly to GitHub"
}

case "${1:-help}" in
  setup) setup_git_sync ;;
  *) echo "usage: $0 setup"; exit 1 ;;
esac