#!/usr/bin/env bash
# Idempotent installer for the dev-PC restic backup job.
#
# Run once on a fresh Ubuntu install, or re-run any time to fill in a
# missing piece. Each step is conditional. The script never destroys
# existing config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/restic"
PASSWORD_FILE="$CONFIG_DIR/repo-password"
KUMA_URL_FILE="$CONFIG_DIR/kuma-push-url"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
NAS_HOST="192.168.1.65"
NAS_USER="truenas_admin"
RESTIC_REPO="sftp:${NAS_USER}@${NAS_HOST}:/mnt/bulk/backups/dev-pc-restic"

step() { echo; echo "==> $*"; }
ok() { echo "    ok: $*"; }
warn() { echo "    WARN: $*" >&2; }

# --- 1. restic ---
step "Check restic"
if command -v restic >/dev/null 2>&1; then
  ok "restic $(restic version | awk '{print $2}') already installed"
else
  echo "    restic not installed. Install with:"
  echo "      sudo apt update && sudo apt install -y restic"
  echo "    Re-run this script after installation."
  exit 1
fi

# --- 2. SSH reachability ---
step "Check SSH reachability to NAS"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${NAS_USER}@${NAS_HOST}" 'true' 2>/dev/null; then
  ok "ssh ${NAS_USER}@${NAS_HOST} works"
else
  echo "    ERROR: cannot ssh ${NAS_USER}@${NAS_HOST} non-interactively." >&2
  echo "    Verify your SSH key is installed and the host is in known_hosts." >&2
  exit 1
fi

# --- 3. Config directory ---
step "Set up $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
ok "$CONFIG_DIR (mode 700)"

# --- 4. Repo password ---
step "Repo password"
if [ -s "$PASSWORD_FILE" ]; then
  ok "$PASSWORD_FILE already exists"
else
  echo "    Generating a fresh 32-byte random password."
  umask 077
  openssl rand -base64 48 | tr -d '\n' > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
  echo
  echo "    >>> SAVE THIS TO PASSWORD MANAGER NOW (label: homelab/dev-pc/restic-repo-password) <<<"
  echo
  cat "$PASSWORD_FILE"
  echo
  echo
  read -rp "    Press ENTER once you've saved the password to PM..."
fi

# --- 5. Initialise restic repo ---
step "Restic repo init"
export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
if restic snapshots >/dev/null 2>&1; then
  ok "repo already initialised at $RESTIC_REPO"
else
  echo "    Repo not yet initialised. Creating remote dir + restic init."
  # /mnt/bulk/backups is root-owned. SFTP runs as truenas_admin, so the
  # restic repo dir needs to be created + owned by that user. Use sudo
  # on the NAS side; will prompt for the truenas_admin sudo password.
  ssh -t "${NAS_USER}@${NAS_HOST}" \
    "sudo install -d -o ${NAS_USER} -g ${NAS_USER} -m 0700 /mnt/bulk/backups/dev-pc-restic"
  restic init
  ok "init complete"
fi

# --- 6. Kuma push URL ---
step "Kuma push URL"
if [ -s "$KUMA_URL_FILE" ]; then
  ok "$KUMA_URL_FILE already staged"
else
  echo "    Mint a new push monitor in Kuma UI (Type=Push, name=backup-dev-pc-restic,"
  echo "    interval=86400s, retry=43200s, max retries=2). Copy the BARE push URL"
  echo "    (strip everything from \`?status=\` onward — see"
  echo "    \`feedback_kuma_push_url_query_string\` for why)."
  read -rp "    Paste push URL (or empty to skip — heartbeat then disabled): " URL
  if [ -n "$URL" ]; then
    umask 077
    printf '%s' "$URL" > "$KUMA_URL_FILE"
    chmod 600 "$KUMA_URL_FILE"
    ok "staged"
    echo "    Also save URL to PM under: homelab/uptime-kuma/push-dev-pc-restic"
  else
    warn "skipped — no heartbeat alerting until staged"
  fi
fi

# --- 7. systemd user units ---
step "systemd user units"
mkdir -p "$SYSTEMD_USER_DIR"
install -m 0644 "$SCRIPT_DIR/dev-pc-backup.service" "$SYSTEMD_USER_DIR/dev-pc-backup.service"
install -m 0644 "$SCRIPT_DIR/dev-pc-backup.timer"   "$SYSTEMD_USER_DIR/dev-pc-backup.timer"
systemctl --user daemon-reload
systemctl --user enable --now dev-pc-backup.timer
ok "timer enabled + started"
systemctl --user list-timers dev-pc-backup.timer --no-pager | head -5

# --- 8. Linger ---
step "Lingering"
if loginctl show-user "$USER" -p Linger | grep -q 'Linger=yes'; then
  ok "linger already enabled"
else
  echo "    Linger is OFF — user timers won't fire when you're logged out."
  echo "    Enabling now requires sudo:"
  echo "      sudo loginctl enable-linger \"$USER\""
  read -rp "    Run sudo loginctl enable-linger now? [y/N] " ans
  if [ "${ans,,}" = "y" ]; then
    sudo loginctl enable-linger "$USER"
    ok "linger enabled"
  else
    warn "skipped — backup will only run while you're logged in"
  fi
fi

# --- 9. First-run smoke ---
step "First-run smoke test"
echo "    Running a backup right now to verify everything wires up."
"$SCRIPT_DIR/restic-backup.sh"

echo
echo "Done. The timer fires daily at 02:30. Tail logs with:"
echo "  journalctl --user -u dev-pc-backup.service -f"
