#!/usr/bin/env bash
# Phase 8 Task 7 — stage Kuma push-monitor URLs for the backup crons.
#
# Run once on the dev box. Each URL gets read silently and piped to
# /root/.backup-env (root:root 600) on the NAS via the same chmod-write-revert
# dance we used for the passphrase. URLs never appear in argv / shell history.
#
# After this lands: each cron sources /root/.backup-env on every run,
# pings its Kuma URL on success. Kuma alerts (via ntfy) on absence.
# A long-stuck cron = a missed heartbeat = a phone push.

set -euo pipefail

NAS_PATH=/mnt/bulk/backups/.secrets/backup-env

prompt_url() {
  local name=$1
  echo -n "Push URL for $name: " >&2
  local url
  read -rs url
  echo >&2
  if [[ ! "$url" =~ ^https://uptime-kuma\.mati-lab\.online/api/push/ ]]; then
    echo "ERROR: $name URL doesn't look right (expected https://uptime-kuma.../api/push/...)" >&2
    return 1
  fi
  echo "$url"
}

echo "Paste each Kuma push URL when prompted. Input is hidden."
echo "Save each one in PM as homelab/uptime-kuma/push-<name> first."
echo

URL_GITEA=$(prompt_url "backup-gitea-pgdump")
URL_LITELLM=$(prompt_url "backup-litellm-pgdump")
URL_ZFS=$(prompt_url "nas-zfs-health")

# Build the env file content locally, pipe via stdin to NAS.
ENV_CONTENT="KUMA_URL_GITEA_DUMP=$URL_GITEA
KUMA_URL_LITELLM_DUMP=$URL_LITELLM
KUMA_URL_ZFS_HEALTH=$URL_ZFS"

# Relax dir, write file as truenas_admin, chown back, restore dir.
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.setperm "{\"path\":\"/mnt/bulk/backups/.secrets\",\"mode\":\"777\"}" 2>&1 | tail -1' >/dev/null

echo "$ENV_CONTENT" | ssh truenas_admin@192.168.1.65 "cat > $NAS_PATH && chmod 600 $NAS_PATH && wc -l $NAS_PATH"

ssh truenas_admin@192.168.1.65 "
  midclt call -j filesystem.chown '{\"path\":\"$NAS_PATH\",\"uid\":0,\"gid\":0}' 2>&1 | tail -1
  midclt call -j filesystem.setperm '{\"path\":\"$NAS_PATH\",\"mode\":\"600\"}' 2>&1 | tail -1
  midclt call -j filesystem.setperm '{\"path\":\"/mnt/bulk/backups/.secrets\",\"mode\":\"700\"}' 2>&1 | tail -1
" >/dev/null

unset URL_GITEA URL_LITELLM URL_ZFS ENV_CONTENT

# The crons currently look at /root/.backup-env via `[ -f /root/.backup-env ] && . /root/.backup-env`.
# We can't write to /root from truenas_admin, so the env file lives under .secrets/. Patch the
# scripts in place so they source from the right path.
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.setperm "{\"path\":\"/mnt/bulk/backups/.scripts\",\"mode\":\"777\"}" 2>&1 | tail -1' >/dev/null
for s in gitea-pgdump litellm-pgdump zfs-health-cron; do
  ssh truenas_admin@192.168.1.65 "
    midclt call -j filesystem.setperm '{\"path\":\"/mnt/bulk/backups/.scripts/$s.sh\",\"mode\":\"666\"}' 2>&1 | tail -1
  " >/dev/null
  ssh truenas_admin@192.168.1.65 "sed -i 's|/root/.backup-env|/mnt/bulk/backups/.secrets/backup-env|g' /mnt/bulk/backups/.scripts/$s.sh"
  ssh truenas_admin@192.168.1.65 "
    midclt call -j filesystem.setperm '{\"path\":\"/mnt/bulk/backups/.scripts/$s.sh\",\"mode\":\"755\"}' 2>&1 | tail -1
  " >/dev/null
done
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.setperm "{\"path\":\"/mnt/bulk/backups/.scripts\",\"mode\":\"755\"}" 2>&1 | tail -1' >/dev/null

# Verify with a one-shot run of one cron — should now ping Kuma.
echo
echo "URLs staged. Trigger gitea cron once to confirm Kuma turns green."
echo "Run: ssh truenas_admin@192.168.1.65 'midclt call -j cronjob.run 6'"
echo "Then check Kuma UI — backup-gitea-pgdump should be green within ~30s."
