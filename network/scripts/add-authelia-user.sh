#!/usr/bin/env bash
# Add a user to Authelia's file-based users_database.yml.
#
# Usage:
#   ./add-authelia-user.sh           # creates a regular user (group: users)
#   ./add-authelia-user.sh --admin   # creates an admin user (group: admins)
#
# Steps:
#   1. Prompts for username, display name (optional), email, password (silent).
#   2. Generates argon2id hash via the running Authelia container on the Pi
#      (password sent via stdin so it never appears in any process's argv).
#   3. Appends YAML entry to the LOCAL ../authelia/data/users_database.yml
#      (the gitignored source of truth that ./manage-authelia.sh syncs).
#   4. scp's the updated file to the Pi. Authelia 4.38+ watches the file
#      and hot-reloads — no container restart needed.
#   5. Reminds you to save the password to PM.

set -Eeuo pipefail

SERVICE_NAME="authelia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=network/scripts/common.sh
source "$SCRIPT_DIR/common.sh"

LOCAL_DB="$SCRIPT_DIR/../$SERVICE_NAME/data/users_database.yml"
REMOTE_DB="/opt/mati-lab/network/$SERVICE_NAME/data/users_database.yml"

ADMIN=0
[[ "${1:-}" == "--admin" ]] && ADMIN=1
GROUP="users"
[[ $ADMIN == 1 ]] && GROUP="admins"

[[ -f "$LOCAL_DB" ]] || { log_error "$LOCAL_DB not found — bootstrap from users_database.yml.example first"; exit 1; }

# --- prompts ---------------------------------------------------------------
read -r -p "Username (lowercase, [a-z0-9_-]+): " USERNAME
[[ "$USERNAME" =~ ^[a-z0-9_-]+$ ]] || { log_error "Invalid username"; exit 1; }

# Already in the file? Refuse to overwrite. Match the YAML key shape:
#   users:
#     <username>:
if grep -qE "^[[:space:]]+${USERNAME}:[[:space:]]*\$" "$LOCAL_DB"; then
  log_error "User '$USERNAME' already exists in $LOCAL_DB"
  exit 1
fi

read -r -p "Display name (default: $USERNAME): " DISPLAY
[[ -z "$DISPLAY" ]] && DISPLAY="$USERNAME"

read -r -p "Email: " EMAIL
[[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || { log_error "Invalid email"; exit 1; }

while :; do
  read -rs -p "Password (min 8 chars): " PW1; echo
  [[ ${#PW1} -ge 8 ]] || { echo "  too short — retry" >&2; continue; }
  read -rs -p "Confirm password:        " PW2; echo
  [[ "$PW1" == "$PW2" ]] || { echo "  mismatch — retry" >&2; continue; }
  break
done

# --- hash via running Authelia container -----------------------------------
log "Generating argon2id hash via Authelia container on $REMOTE..."
# Password fed over stdin → docker exec -i → shell reads PW → authelia reads
# from --password "$PW". Password never lands in argv on the Pi's process list.
HASH=$(printf '%s' "$PW1" | ssh "${SSH_OPTS[@]}" "$REMOTE" \
  'docker exec -i authelia sh -c '"'"'IFS= read -r PW && authelia crypto hash generate argon2 --password "$PW"'"'"'' \
  | awk '/^Digest:/ { sub(/^Digest: /, ""); print }')

unset PW1 PW2

[[ -n "$HASH" ]] || { log_error "hash generation failed (Authelia container running?)"; exit 1; }

# --- append YAML entry to local file ---------------------------------------
log "Appending entry to $LOCAL_DB..."
BACKUP="${LOCAL_DB}.bak.$(date +%Y%m%dT%H%M%S)"
cp -a "$LOCAL_DB" "$BACKUP"

cat >>"$LOCAL_DB" <<EOF

  ${USERNAME}:
    displayname: "${DISPLAY}"
    password: "${HASH}"
    email: ${EMAIL}
    groups:
      - ${GROUP}
EOF

# YAML sanity check (Authelia would refuse to reload otherwise — better to
# catch it before pushing to the Pi)
if ! python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$LOCAL_DB"; then
  log_error "users_database.yml became invalid YAML; restoring backup"
  cp -a "$BACKUP" "$LOCAL_DB"
  exit 1
fi

# --- push only the users_database.yml to Pi --------------------------------
log "Copying updated users_database.yml to $REMOTE..."
scp "${SSH_OPTS[@]}" "$LOCAL_DB" "$REMOTE:/tmp/users_database.yml" >/dev/null
ssh -t "$REMOTE" "sudo install -m 0644 -o root -g root /tmp/users_database.yml $REMOTE_DB && rm /tmp/users_database.yml"

# Authelia 4.38+ watches users_database.yml and hot-reloads on change. No
# container restart required.
log_success "User '$USERNAME' added (group: $GROUP, hash: argon2id)."
echo
echo "Next steps:"
echo "  • Save the cleartext password to PM: homelab/authelia/user-${USERNAME}"
echo "  • Authelia hot-reloads automatically; the user can log in within ~10s."
echo "    If login still rejects after a minute, force a reload:"
echo "      ssh ${REMOTE} 'cd /opt/mati-lab/network && docker compose restart authelia'"
echo "  • Local backup of pre-add file: ${BACKUP}"
