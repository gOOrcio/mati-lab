#!/bin/bash
# Dev-PC wrapper: ship app-config.json + apply.sh to the NAS and run apply.sh as root
# through a one-shot disabled cron job (truenas_admin has no passwordless sudo).
# Usage: nas/vaultwarden/deploy.sh create|update
set -euo pipefail
MODE="${1:?usage: deploy.sh create|update}"
NAS=truenas_admin@192.168.1.65
DIR="$(cd "$(dirname "$0")" && pwd)"
# Stage in a 700 dir under truenas_admin's home, not world-writable /tmp: root runs
# what lands here.
STAGE=/home/truenas_admin/.deploy/vaultwarden
ssh "$NAS" "install -d -m 700 /home/truenas_admin/.deploy $STAGE"
scp -q "$DIR/app-config.json" "$NAS:$STAGE/app.json"
scp -q "$DIR/apply.sh" "$NAS:$STAGE/apply.sh"
ssh "$NAS" "MODE=$MODE STAGE=$STAGE"' bash -s' <<'REMOTE'
set -euo pipefail
ID=$(midclt call cronjob.create "{\"user\":\"root\",\"command\":\"bash $STAGE/apply.sh $MODE\",\"enabled\":false,\"schedule\":{\"minute\":\"0\",\"hour\":\"0\",\"dom\":\"1\",\"month\":\"1\",\"dow\":\"*\"}}" | jq .id)
midclt call -j cronjob.run "$ID" >/dev/null 2>&1 || true
midclt call cronjob.delete "$ID" >/dev/null
tail -n 25 "$STAGE/apply.out"
REMOTE
