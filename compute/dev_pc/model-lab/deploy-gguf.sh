#!/usr/bin/env bash
# Ship a GGUF from the dev-PC model lab to an Ollama host and register it.
#
#   deploy-gguf.sh <path/to/model.gguf> <model-name> [--local] [--system "prompt"]
#
#   default target: ollama-gpu@192.168.1.48 (the serving VM, 8 GB — mind size!)
#   --local:        the dev-PC Ollama (16 GB, for testing before shipping)
#
# After a successful create, the GGUF is inside Ollama's blob store; the
# staged /tmp copy is removed. To expose the model through LiteLLM, add an
# alias in /mnt/fast/databases/litellm/config.yaml on the NAS + redeploy —
# the script prints the exact snippet.

set -euo pipefail

GGUF="${1:?usage: deploy-gguf.sh <model.gguf> <name> [--local] [--system \"...\"]}"
NAME="${2:?model name required (e.g. mati-fim:v1)}"
shift 2
TARGET="ollama-gpu@192.168.1.48"
SYSTEM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) TARGET="" ;;
    --system) SYSTEM="$2"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

[ -f "$GGUF" ] || { echo "ERROR: $GGUF not found" >&2; exit 1; }
SIZE=$(du -h "$GGUF" | cut -f1)
BASE=$(basename "$GGUF")

MODELFILE="FROM /tmp/$BASE"
[ -n "$SYSTEM" ] && MODELFILE="$MODELFILE
SYSTEM \"\"\"$SYSTEM\"\"\""

if [ -z "$TARGET" ]; then
  echo "== deploying $BASE ($SIZE) to local Ollama as '$NAME' =="
  cp "$GGUF" "/tmp/$BASE"
  printf '%s\n' "$MODELFILE" > "/tmp/$BASE.Modelfile"
  ollama create "$NAME" -f "/tmp/$BASE.Modelfile"
  rm -f "/tmp/$BASE" "/tmp/$BASE.Modelfile"
  ollama list | grep -F "$NAME"
else
  echo "== deploying $BASE ($SIZE) to $TARGET as '$NAME' =="
  scp "$GGUF" "$TARGET:/tmp/$BASE"
  ssh "$TARGET" "printf '%s\n' '$MODELFILE' > /tmp/$BASE.Modelfile && ollama create '$NAME' -f /tmp/$BASE.Modelfile && rm -f /tmp/$BASE /tmp/$BASE.Modelfile && ollama list | grep -F '$NAME'"
fi

cat <<EOF

== next: expose through LiteLLM (optional) ==
Add to model_list in /mnt/fast/databases/litellm/config.yaml on the NAS:

  - model_name: ${NAME%%:*}
    litellm_params:
      model: ollama/$NAME
      api_base: http://192.168.1.48:11434

then: ssh truenas_admin@192.168.1.65 'midclt call app.redeploy litellm'
Smoke test via the gateway with any virtual key:
  curl -s http://192.168.1.65:4000/v1/chat/completions -H "Authorization: Bearer \$KEY" \\
    -d '{"model":"${NAME%%:*}","messages":[{"role":"user","content":"hi"}]}'
EOF
