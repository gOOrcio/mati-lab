#!/bin/bash
# Dev-PC wrapper: ship app-config.json + apply.sh to the NAS and run apply.sh as root
# through a one-shot disabled cron job (truenas_admin has no passwordless sudo).
# Usage: nas/paperless/deploy.sh create|update
set -euo pipefail
MODE="${1:?usage: deploy.sh create|update}"
NAS=truenas_admin@192.168.1.65
DIR="$(cd "$(dirname "$0")" && pwd)"
scp -q "$DIR/app-config.json" "$NAS:/tmp/paperless-app.json"
scp -q "$DIR/apply.sh" "$NAS:/tmp/paperless-apply.sh"
ssh "$NAS" "MODE=$MODE"' bash -s' <<'REMOTE'
set -euo pipefail
ID=$(midclt call cronjob.create "{\"user\":\"root\",\"command\":\"bash /tmp/paperless-apply.sh $MODE\",\"enabled\":false,\"schedule\":{\"minute\":\"0\",\"hour\":\"0\",\"dom\":\"1\",\"month\":\"1\",\"dow\":\"*\"}}" | jq .id)
midclt call -j cronjob.run "$ID" >/dev/null 2>&1 || true
midclt call cronjob.delete "$ID" >/dev/null
tail -n 25 /tmp/paperless-apply.out
REMOTE
