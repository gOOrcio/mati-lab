#!/usr/bin/env bash
# Declare which models each LiteLLM virtual key may use, and reconcile the
# live keys against that declaration.
#
#   bash nas/litellm/update-key-models.sh           # dry run: show drift only
#   bash nas/litellm/update-key-models.sh --apply   # update keys that drift
#
# The live keys hold EXPLICIT model lists (access groups never reached them,
# see notes.md "Virtual keys"), so a model added to config.yml is invisible
# to a client until it is listed here and applied — otherwise the client gets
# `401 key not allowed to access model`.
#
# The master key is pulled into shell memory via SSH + read -rs and never
# lands on disk locally or in output. /key/update replaces a key's `models`
# list, so re-running is idempotent. Keys not listed below are left alone.

set -euo pipefail

LITELLM=http://192.168.1.65:4000
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

AGENTS='"agent-default","agent-smart","coding","embeddings"'
CLAUDE='"claude-opus-5-5","claude-opus-5","claude-opus-4-8","claude-sonnet-5","claude-haiku-4-5"'

# alias -> JSON array of allowed models (the source of truth)
DESIRED=$(cat <<JSON
{
  "hermes":          [$AGENTS],
  "dev-pc-tools-v2": [$AGENTS],
  "claude-code":     [$CLAUDE, $AGENTS],
  "rag-watcher":     ["embeddings"]
}
JSON
)

read -rs LITELLM_MASTER_KEY < <(ssh truenas_admin@192.168.1.65 \
  'grep ^LITELLM_MASTER_KEY /mnt/fast/databases/litellm/.env | cut -d= -f2-')
if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  echo "ERROR: failed to read LITELLM_MASTER_KEY from NAS .env" >&2
  exit 1
fi
export LITELLM LITELLM_MASTER_KEY APPLY DESIRED

python3 - <<'PY'
import json, os, sys, urllib.request

base, key = os.environ["LITELLM"], os.environ["LITELLM_MASTER_KEY"]
apply = os.environ["APPLY"] == "1"
desired = json.loads(os.environ["DESIRED"])
hdr = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}

def call(path, body=None):
    req = urllib.request.Request(base + path, headers=hdr,
                                 data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

live = {k["key_alias"]: k for k in
        call("/key/list?return_full_object=true&size=100")["keys"]
        if isinstance(k, dict) and k.get("key_alias")}

# Every model named here must exist on the proxy, or the key update is a trap.
known = {m["model_name"] for m in call("/model/info")["data"]}
missing = sorted({m for ms in desired.values() for m in ms} - known)
if missing:
    sys.exit(f"ERROR: not defined in LiteLLM: {missing}")

drift = 0
for alias, want in desired.items():
    k = live.get(alias)
    if k is None:
        print(f"{alias:16} MISSING (no such key — issue it first, see notes.md)")
        drift += 1
        continue
    have = k.get("models") or []
    add, drop = sorted(set(want) - set(have)), sorted(set(have) - set(want))
    if not add and not drop:
        print(f"{alias:16} ok")
        continue
    drift += 1
    print(f"{alias:16} +{add} -{drop}")
    if apply:
        got = call("/key/update", {"key": k["token"], "models": want})
        print(f"{'':16} applied -> {got.get('models')}")

if drift and not apply:
    print("\n(dry run — re-run with --apply to update the keys above)")
PY

unset LITELLM_MASTER_KEY
