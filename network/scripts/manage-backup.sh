#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="backup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

run_backup() {
  log "Running backup of all services to NAS"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "/opt/mati-lab/network/backup/backup-services.sh"
}

timer_status() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "systemctl status backup-services.timer --no-pager 2>/dev/null || echo 'Timer not installed'"
  echo ""
  ssh "${SSH_OPTS[@]}" "$REMOTE" "journalctl -u backup-services.service --no-pager -n 20 2>/dev/null || echo 'No backup logs yet'"
}

check_mount() {
  ssh "${SSH_OPTS[@]}" "$REMOTE" "mountpoint -q /mnt/nas/backups && echo 'NAS mount: OK' || echo 'NAS mount: NOT MOUNTED'"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "systemctl is-active backup-services.timer 2>/dev/null && echo 'Timer: active' || echo 'Timer: inactive'"
}

case "${1:-help}" in
  run)    run_backup ;;
  status) timer_status ;;
  check)  check_mount ;;
  *)      echo "usage: $0 {run|status|check}"; exit 1 ;;
esac
