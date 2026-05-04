#!/usr/bin/env bash
# Dev PC → NAS restic backup.
#
# Backs up developer state (~/Projects, ~/.claude, dotfiles, ~/.ssh) to a
# restic repo on the NAS over SFTP. Daily via systemd user timer; weekly
# (Sunday) the run also prunes old snapshots.
#
# Repo: sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic
# Password file: ~/.config/restic/repo-password
# Includes: <script-dir>/restic-includes.txt
# Excludes: <script-dir>/restic-excludes.txt
# Heartbeat: ~/.config/restic/kuma-push-url (Kuma push monitor)
#
# Exits non-zero on backup failure; the missed Kuma heartbeat then
# trips ntfy via Kuma's default routing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/restic"
PASSWORD_FILE="$CONFIG_DIR/repo-password"
KUMA_URL_FILE="$CONFIG_DIR/kuma-push-url"
INCLUDES="$SCRIPT_DIR/restic-includes.txt"
EXCLUDES="$SCRIPT_DIR/restic-excludes.txt"

export RESTIC_REPOSITORY="sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic"
export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"

# Preflight
for f in "$PASSWORD_FILE" "$INCLUDES" "$EXCLUDES"; do
  [ -r "$f" ] || { echo "ERROR: missing or unreadable: $f" >&2; exit 1; }
done

if ! command -v restic >/dev/null 2>&1; then
  echo "ERROR: restic not installed (apt install restic)" >&2
  exit 1
fi

# Resolve include paths from the includes file. Skip blank lines and
# `#` comments. Each line is a path relative to $HOME or absolute.
INCLUDE_ARGS=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  if [[ "$line" = /* ]]; then
    path="$line"
  else
    path="$HOME/$line"
  fi
  if [ -e "$path" ]; then
    INCLUDE_ARGS+=("$path")
  else
    echo "WARN: include path missing, skipping: $path" >&2
  fi
done < "$INCLUDES"

if [ ${#INCLUDE_ARGS[@]} -eq 0 ]; then
  echo "ERROR: no resolvable include paths in $INCLUDES" >&2
  exit 1
fi

START=$(date -u +%FT%TZ)
echo "[$START] dev-pc restic backup start"
echo "  paths: ${INCLUDE_ARGS[*]}"

# Backup
restic backup \
  --host="$(hostname)" \
  --tag="dev-pc-systemd" \
  --exclude-file="$EXCLUDES" \
  --exclude-caches \
  --one-file-system=false \
  "${INCLUDE_ARGS[@]}"

# Sunday: prune. Other days: skip — prune is expensive and weekly
# cadence is fine for our retention shape.
if [ "$(date +%u)" = "7" ]; then
  echo "  sunday: forget + prune"
  restic forget \
    --host="$(hostname)" \
    --tag="dev-pc-systemd" \
    --keep-daily=14 --keep-weekly=8 --keep-monthly=6 \
    --prune
fi

END=$(date -u +%FT%TZ)
echo "[$END] dev-pc restic backup ok"

# Heartbeat — only after successful completion of all of the above.
if [ -r "$KUMA_URL_FILE" ]; then
  KUMA_URL=$(<"$KUMA_URL_FILE")
  KUMA_URL=${KUMA_URL//$'\n'/}
  if [ -n "$KUMA_URL" ]; then
    curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || \
      echo "WARN: Kuma push failed (backup itself was OK)" >&2
  fi
fi
