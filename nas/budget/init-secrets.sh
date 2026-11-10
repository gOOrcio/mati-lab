#!/usr/bin/env bash
# Generate the budget app's secrets ON THE NAS, as truenas_admin. Idempotent:
# an existing file is never overwritten. Values are never printed; copy them
# into Vaultwarden afterwards (labels in nas/budget/notes.md).
#
#   scp nas/budget/init-secrets.sh truenas_admin@192.168.1.65:/tmp/ \
#     && ssh truenas_admin@192.168.1.65 'bash /tmp/init-secrets.sh; rm /tmp/init-secrets.sh'
set -euo pipefail
D=/mnt/fast/databases/budget/secrets
LITELLM_ENV=/mnt/fast/databases/litellm/.env
umask 077
mkdir -p "$D"
chmod 700 "$D"
gen() { openssl rand -hex 24; }

if [ ! -s "$D/actual.env" ]; then
  printf 'ACTUAL_PASSWORD=%s\n' "$(gen)" >"$D/actual.env"
  echo "created actual.env"
fi

if [ ! -s "$D/db.env" ]; then
  p=$(gen)
  printf 'POSTGRES_PASSWORD=%s\nDATABASE_URL=postgres://budget:%s@budget-db:5432/budget\nGRAFANA_RO_PASSWORD=%s\n' \
    "$p" "$p" "$(gen)" >"$D/db.env"
  echo "created db.env"
fi

if [ ! -s "$D/llm.env" ]; then
  mk=$(sed -n 's/^LITELLM_MASTER_KEY=//p' "$LITELLM_ENV" | tr -d '"')
  [ -n "$mk" ] || {
    echo "no LITELLM_MASTER_KEY in $LITELLM_ENV" >&2
    exit 1
  }
  resp=$(curl -sS -X POST http://127.0.0.1:4000/key/generate \
    -H "Authorization: Bearer $mk" -H 'Content-Type: application/json' \
    --data-raw '{"key_alias":"budget","models":["budget-classifier"],"max_budget":1,"budget_duration":"30d"}')
  key=$(printf '%s' "$resp" | jq -r '.key // empty')
  if [ -z "$key" ]; then
    echo "LiteLLM key/generate failed: $(printf '%s' "$resp" | jq -c '.error.message // .detail // "unknown"' 2>/dev/null)" >&2
    exit 1
  fi
  printf 'OPENAI_API_KEY=%s\n' "$key" >"$D/llm.env"
  echo "created llm.env (LiteLLM key alias: budget)"
fi

ls -l "$D" | awk 'NR>1 {print $1, $3, $NF}'
