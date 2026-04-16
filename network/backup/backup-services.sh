#!/usr/bin/env bash
# Backs up Pi 5 network service data to NAS via NFS mount.
# Designed to run nightly via systemd timer.
# Config: backup-services.conf (same directory)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/backup-services.conf"
NETWORK_DIR="/opt/mati-lab/network"
NAS_MOUNT="/mnt/nas/backups"
BACKUP_ROOT="$NAS_MOUNT/network-pi"
KEEP_DAYS=30
DATE="$(date +%F)"
LOG_TAG="backup-services"

log()   { echo "[$(date -Is)] $*"; logger -t "$LOG_TAG" "$*" 2>/dev/null || true; }
die()   { log "ERROR: $*"; exit 1; }

# --- Preflight ---
[[ -f "$CONF" ]] || die "Config not found: $CONF"
mountpoint -q "$NAS_MOUNT" || die "NAS not mounted at $NAS_MOUNT"

log "=== Backup started ==="

ERRORS=0

while IFS=: read -r service type source; do
  # Skip comments and blank lines
  [[ "$service" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$service" ]] && continue

  # Trim whitespace
  service="$(echo "$service" | xargs)"
  type="$(echo "$type" | xargs)"
  source="$(echo "$source" | xargs)"

  dest="$BACKUP_ROOT/$service/$DATE"
  mkdir -p "$dest"

  case "$type" in
    bind)
      src="$NETWORK_DIR/$source"
      if [[ -e "$src" ]]; then
        log "[$service] rsync bind: $src -> $dest/"
        rsync -a --delete "$src" "$dest/" || { log "WARN: rsync failed for $service:$source"; ERRORS=$((ERRORS+1)); }
      else
        log "WARN: [$service] bind path not found: $src (skipping)"
      fi
      ;;

    volume)
      vol_path="$(docker volume inspect --format '{{ .Mountpoint }}' "$source" 2>/dev/null || true)"
      if [[ -n "$vol_path" && -d "$vol_path" ]]; then
        log "[$service] rsync volume: $vol_path -> $dest/"
        rsync -a --delete "$vol_path/" "$dest/volume-$(basename "$source")/" || { log "WARN: rsync failed for $service:$source"; ERRORS=$((ERRORS+1)); }
      else
        log "WARN: [$service] volume not found: $source (skipping)"
      fi
      ;;

    export)
      log "[$service] running export: $source"
      if [[ -x "$source" ]]; then
        "$source" || { log "WARN: export script failed for $service"; ERRORS=$((ERRORS+1)); }
      else
        log "WARN: [$service] export script not found or not executable: $source"
      fi
      ;;

    *)
      log "WARN: unknown backup type '$type' for $service"
      ;;
  esac
done < "$CONF"

# --- Grafana dashboard JSON export to git-tracked dir ---
# The export script (run above) already saves to provisioning/dashboards/.
# Copy those to the NAS grafana backup dir for belt-and-suspenders.
GRAFANA_EXPORT_SRC="$NETWORK_DIR/grafana/provisioning/dashboards"
GRAFANA_EXPORT_DEST="$BACKUP_ROOT/grafana/$DATE/dashboards-json"
if ls "$GRAFANA_EXPORT_SRC"/*.json &>/dev/null; then
  mkdir -p "$GRAFANA_EXPORT_DEST"
  cp "$GRAFANA_EXPORT_SRC"/*.json "$GRAFANA_EXPORT_DEST/"
  log "[grafana] Dashboard JSONs copied to $GRAFANA_EXPORT_DEST"
fi

# --- Rotate old backups (per service) ---
log "Rotating backups older than $KEEP_DAYS days..."
find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} + 2>/dev/null || true

if [[ "$ERRORS" -gt 0 ]]; then
  log "=== Backup completed with $ERRORS warning(s) ==="
  exit 1
else
  log "=== Backup completed successfully ==="
fi
