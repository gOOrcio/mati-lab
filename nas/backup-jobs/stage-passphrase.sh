#!/usr/bin/env bash
# Phase 8 Task 2 — stage the backup encryption passphrase on the NAS.
#
# Run once on the dev box. Generates nothing — you paste the value from
# PM (homelab/backups/dump-passphrase). The value travels via SSH stdin
# (never on argv / shell history / process listing).
#
# Final destination: /mnt/bulk/backups/.secrets/dump-passphrase
# Owner: root:root, mode 600
# Read by every cron under nas/backup-jobs/*.sh

set -euo pipefail

DEST=/mnt/bulk/backups/.secrets/dump-passphrase

echo "Generate a passphrase locally first:"
echo "    openssl rand -base64 48"
echo "Save it in your password manager under 'homelab/backups/dump-passphrase'."
echo "Then paste it here (input is hidden) and press Enter:"
read -rs PASS
echo

if [[ ${#PASS} -lt 32 ]]; then
  echo "ERROR: passphrase too short (got ${#PASS} chars; expected 32+)" >&2
  unset PASS
  exit 1
fi

# Stage via the chmod-write-revert dance — NAS dir is 700 root:root.
# Step 1: relax dir to 777 (so truenas_admin can write into it).
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.setperm "{\"path\":\"/mnt/bulk/backups/.secrets\",\"mode\":\"777\"}" 2>&1 | tail -1' >/dev/null

# Step 2: pipe value through stdin to a temp file under truenas_admin's ownership.
echo -n "$PASS" | ssh truenas_admin@192.168.1.65 "
  cat > $DEST
  chmod 600 $DEST
  ls -la $DEST | head -1
"
unset PASS

# Step 3: chown to root + chmod the dir back to 700.
ssh truenas_admin@192.168.1.65 "
  midclt call -j filesystem.chown '{\"path\":\"$DEST\",\"uid\":0,\"gid\":0}' 2>&1 | tail -1
  midclt call -j filesystem.setperm '{\"path\":\"$DEST\",\"mode\":\"600\"}' 2>&1 | tail -1
  midclt call -j filesystem.setperm '{\"path\":\"/mnt/bulk/backups/.secrets\",\"mode\":\"700\"}' 2>&1 | tail -1
" >/dev/null

# Step 4: verify (size only — never read content)
ssh truenas_admin@192.168.1.65 "midclt call filesystem.stat $DEST" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'staged ok: {d.get(\"size\")} bytes, mode={oct(d.get(\"mode\",0))}, uid={d.get(\"uid\")}/gid={d.get(\"gid\")}')"
echo "passphrase staged at $DEST on NAS"
