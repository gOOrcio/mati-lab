#!/usr/bin/env bash
# Point the existing virtual keys at ACCESS GROUPS (and the Ollama wildcards)
# instead of explicit model lists, so a model added to a group — via
# config.yml, the Admin UI, or POST /model/new — is visible to every key
# holding that group with no further key edits.
#
# Same conventions as issue-keys.sh: the master key is pulled into shell
# memory via SSH + read -rs and never lands on disk locally. Idempotent —
# /key/update replaces the `models` list, so re-running is harmless.
#
# Groups are declared in config.yml under model_info.access_groups:
#   agents      : agent-default, agent-smart, coding, embeddings
#   claude-code : claude-opus-4-8, claude-sonnet-5, claude-haiku-4-5
# Wildcard deployments (pve-ollama/*, dev-ollama/*) cannot be in a group on
# the free tier, so keys that should reach them list the pattern itself.
#
# rag-watcher is deliberately left alone: it keeps `embeddings` only.

set -euo pipefail

LITELLM=http://192.168.1.65:4000

read -rs LITELLM_MASTER_KEY < <(ssh truenas_admin@192.168.1.65 \
  'grep ^LITELLM_MASTER_KEY /mnt/fast/databases/litellm/.env | cut -d= -f2-')

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "ERROR: failed to read LITELLM_MASTER_KEY from NAS .env" >&2
  exit 1
fi

# update <alias> <model-or-group>...
update() {
  local alias=$1; shift
  local models_json
  models_json=$(printf '"%s",' "$@" | sed 's/,$//')
  local body
  printf -v body '{"key_alias":"%s","models":[%s]}' "$alias" "$models_json"

  curl -sS -X POST "$LITELLM/key/update" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$body" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
if "models" not in d:
    print("ERROR:", d, file=sys.stderr); sys.exit(1)
print("alias:", d.get("key_alias"), " models:", d.get("models"))'
}

update openclaw      agents
update dev-pc-tools  agents "pve-ollama/*" "dev-ollama/*"
update claude-code   claude-code

# ── Smoke tests (master key; proves routing, not key scoping) ──
echo
echo "== /v1/models as seen through the proxy (wildcards expanded via check_provider_endpoint):"
curl -sS "$LITELLM/v1/models" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | python3 -c 'import sys,json; print(sorted(m["id"] for m in json.load(sys.stdin)["data"]))'

echo
echo "== pve-ollama/qwen3.5:2b via wildcard (expect a short reply):"
curl -sS "$LITELLM/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"model":"pve-ollama/qwen3.5:2b","messages":[{"role":"user","content":"Reply with the single word: pong"}],"max_tokens":20}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("choices",[{}])[0].get("message",{}).get("content") or d)'

echo
echo "== models stored in the DB (empty list until something is added via UI/API):"
curl -sS "$LITELLM/model/info" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | python3 -c '
import sys,json
rows=json.load(sys.stdin)["data"]
db=[m["model_name"] for m in rows if m.get("model_info",{}).get("db_model")]
print(db)'

unset LITELLM_MASTER_KEY
