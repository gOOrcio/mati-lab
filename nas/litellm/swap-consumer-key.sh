#!/usr/bin/env bash
# Phase 7 Tasks 7-8 — swap an existing consumer's LITELLM_API_KEY in its
# .env on the NAS for the freshly-issued virtual key.
#
# Usage: bash swap-consumer-key.sh <consumer>
#   consumer = `rag-watcher` (LITELLM_API_KEY in /mnt/fast/databases/rag-watcher/.env)
#
# OpenClaw is NOT an .env-driven consumer; rotate that one through the
# in-app `openclaw config` wizard, not this script.
#
# Prompts for the key once (silent) — value goes through stdin to the
# remote shell, never on a command line, never echoed back.

set -euo pipefail

CONSUMER="${1:-}"
case "$CONSUMER" in
  rag-watcher)  ENVF=/mnt/fast/databases/rag-watcher/.env; APP=rag-watcher ;;
  *) echo "usage: $0 <rag-watcher>" >&2; exit 1 ;;
esac

echo "Paste the $CONSUMER virtual-key value (sk-...) and press Enter."
echo "Input is hidden."
read -rs NEWKEY
echo

if [[ ! "$NEWKEY" =~ ^sk- ]]; then
  echo "ERROR: that doesn't look like a LiteLLM key (should start with sk-)" >&2
  unset NEWKEY
  exit 1
fi

# Upload via stdin so the value never appears in ps / shell history /
# argv on either side.
echo "$NEWKEY" | ssh truenas_admin@192.168.1.65 "
  set -e
  NEWKEY=\$(cat)
  ENVF=$ENVF
  if [[ ! -f \"\$ENVF\" ]]; then
    echo \"ERROR: \$ENVF not found on NAS\" >&2
    exit 1
  fi
  # Drop any existing LITELLM_API_KEY line, append the new one
  sed -i '/^LITELLM_API_KEY=/d' \"\$ENVF\"
  echo \"LITELLM_API_KEY=\$NEWKEY\" >> \"\$ENVF\"
  chmod 600 \"\$ENVF\"
  echo \"Updated \$ENVF — keys present:\"
  grep -oE '^[A-Z_]+=' \"\$ENVF\"
"

unset NEWKEY

echo
echo "Force-pulling new image (no-op since image unchanged) and redeploying..."
ssh truenas_admin@192.168.1.65 "midclt call -j app.pull_images $APP '{\"redeploy\": true}'" 2>&1 | tail -3

echo
echo "Done. Tail logs to verify the watcher came up cleanly:"
echo "  curl -sS -G 'http://192.168.1.252:3100/loki/api/v1/query_range' \\"
echo "    --data-urlencode 'query={container=~\"ix-${APP}-${APP}-.*\",host=\"nas\"}' \\"
echo "    --data-urlencode \"start=\$(date -d '2 min ago' +%s)000000000\" \\"
echo "    --data-urlencode \"end=\$(date +%s)000000000\" \\"
echo "    --data-urlencode 'limit=20' --data-urlencode 'direction=backward'"
