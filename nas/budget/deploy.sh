#!/usr/bin/env bash
# Create or update the `budget` TrueNAS Custom App from compose.yml + budget.conf.
# Usage: nas/budget/deploy.sh create|update|render
# No secrets pass through here: compose.yml references env_files on the NAS.
set -euo pipefail
MODE="${1:?usage: deploy.sh create|update|render}"
NAS=truenas_admin@192.168.1.65
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/budget.conf"
[ "$WORKER_TAG" != "__SET_ME__" ] || {
  echo "set WORKER_TAG in budget.conf" >&2
  exit 1
}

rendered=$(
  python3 - "$DIR/compose.yml" "$WORKER_TAG" "$SYNC_ID" "$FEATURES" "$MODE" <<'PY'
import json, sys
path, tag, sync_id, features, mode = sys.argv[1:6]
text = open(path).read()
text = text.replace("__WORKER_TAG__", tag).replace("__FEATURES__", features)
if sync_id:
    text = text.replace("__SYNC_ID__", sync_id)
else:
    # Before bootstrap there is no budget yet: the worker resolves it by name,
    # and actual-ai can't start without an id, so leave it out entirely.
    import re
    text = text.replace('      ACTUAL_SYNC_ID: "__SYNC_ID__"\n', "")
    text = re.sub(r"\n  actual-ai:\n(?:    .*\n|\n)*", "\n", text)
json.loads(features)  # FEATURES must be a JSON array
if mode == "render":
    print(text)
elif mode == "create":
    print(json.dumps({"app_name": "budget", "custom_app": True, "custom_compose_config_string": text}))
else:
    print(json.dumps({"custom_compose_config_string": text}))
PY
)

if [ "$MODE" = render ]; then
  printf '%s\n' "$rendered"
  exit 0
fi

tmp=$(ssh "$NAS" 'mktemp')
printf '%s' "$rendered" | ssh "$NAS" "cat > $tmp"
if [ "$MODE" = create ]; then
  ssh "$NAS" "midclt call -j app.create \"\$(cat $tmp)\" | jq -r '.name + \" \" + .state'; rm -f $tmp"
else
  ssh "$NAS" "midclt call -j app.update budget \"\$(cat $tmp)\" | jq -r '.name + \" \" + .state'; rm -f $tmp"
fi
