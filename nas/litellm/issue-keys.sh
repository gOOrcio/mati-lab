#!/usr/bin/env bash
# Phase 7 Task 6 — issue per-consumer LiteLLM virtual keys.
#
# Run once on the dev box. The master key is pulled into shell-process
# memory via SSH + read -rs and never lands on disk locally; it stays in
# /mnt/fast/databases/litellm/.env on the NAS where it already lives.
#
# Each generated key prints once. SAVE EACH `key:` VALUE INTO THE
# PASSWORD MANAGER IMMEDIATELY under the printed `homelab/litellm/<alias>`
# label — LiteLLM only stores hashes, this is a one-shot view.
#
# Idempotent re-run: if a key alias already exists, LiteLLM returns 400.
# Use /key/regenerate (different curl call) to rotate an existing key.

set -euo pipefail

# Pull master key from NAS .env into shell-only env var. Never echoed.
read -rs LITELLM_MASTER_KEY < <(ssh truenas_admin@192.168.1.65 \
  'grep ^LITELLM_MASTER_KEY /mnt/fast/databases/litellm/.env | cut -d= -f2-')

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "ERROR: failed to read LITELLM_MASTER_KEY from NAS .env" >&2
  exit 1
fi

issue() {
  local alias=$1 budget=$2; shift 2
  local models_json
  models_json=$(printf '"%s",' "$@" | sed 's/,$//')
  local body
  printf -v body \
    '{"key_alias":"%s","models":[%s],"max_budget":%s,"budget_duration":"30d"}' \
    "$alias" "$models_json" "$budget"

  curl -sS -X POST "http://192.168.1.65:4000/key/generate" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$body" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
if "key" not in d:
    print("ERROR:", d, file=sys.stderr); sys.exit(1)
print("alias:", d.get("key_alias"), "  key:", d.get("key", "?"))
print("  -> save in PM as: homelab/litellm/" + str(d.get("key_alias", "?")))'
}

issue rag-watcher  1   embeddings
issue openclaw     20  agent-default agent-smart coding embeddings
issue dev-pc-tools 30  agent-default agent-smart coding embeddings

unset LITELLM_MASTER_KEY
