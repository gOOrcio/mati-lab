#!/usr/bin/env bash
# Validate the Pi stack's configs with the same tool versions that run them.
# Used by .gitea/workflows/config-checks.yml (pre-merge) and `make check`.
#
# Files are streamed into the tool containers with tar over stdin instead of
# bind mounts: in CI the job talks to the runner's Docker over its socket, so
# the checkout isn't visible to sibling containers. No secrets are needed —
# missing env files get empty stand-ins, Caddy gets a correctly-shaped fake
# Cloudflare token (its DNS module checks the format, not validity).
set -Eeuo pipefail

# Work on a throwaway copy of network/ (1–2 MB): the env-file stand-ins
# below must never land in a real checkout, where deploy scripts would copy
# an empty .env over the Pi's real one. Uncommitted edits are still checked.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # network/
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -a "$SRC" "$WORK/network"
cd "$WORK/network"
FAILED=()

# Image of a service, read from its compose file, so a Renovate bump is
# validated by the new version.
image_of() { awk -v pat="$2" '$1 == "image:" && $2 ~ pat {print $2; exit}' "$1/docker-compose.yml"; }

step() { printf '\n== %s\n' "$1"; }
fail() { FAILED+=("$1"); echo "FAIL: $1"; }

step "docker compose config (every stack)"
for f in */docker-compose.yml; do
  d=$(dirname "$f")
  # Gitignored env files don't exist in a clean checkout: create empty
  # stand-ins for any the compose file references, then validate.
  for _ in 1 2 3 4; do
    if out=$(cd "$d" && docker compose -f docker-compose.yml config -q 2>&1); then
      echo "ok   $d"; continue 2
    fi
    missing=$(printf '%s\n' "$out" | sed -nE 's/.*env file (.*) not found.*/\1/p' | head -1)
    [ -n "$missing" ] || break
    mkdir -p "$(dirname "$missing")" && : > "$missing"
  done
  printf '%s\n' "$out" | grep -v 'variable is not set' | head -5
  fail "compose: $d"
done

step "prometheus: config + rules"
img=$(image_of prometheus 'prom/prometheus')
tar -cf - prometheus | docker run --rm -i --entrypoint sh "$img" -c '
  set -e; mkdir -p /tmp/w && tar -xf - -C /tmp/w && cd /tmp/w/prometheus
  promtool check config --syntax-only prometheus.yml
  promtool check rules rules/*.yml' || fail "prometheus ($img)"

step "alertmanager: config"
img=$(image_of alertmanager 'prom/alertmanager')
tar -cf - alertmanager | docker run --rm -i --entrypoint sh "$img" -c '
  set -e; mkdir -p /tmp/w && tar -xf - -C /tmp/w
  amtool check-config /tmp/w/alertmanager/alertmanager.yml' || fail "alertmanager ($img)"

step "caddy: build image from network/caddy/Dockerfile + validate Caddyfile"
# Native build for the runner's arch — same Dockerfile and modules as the
# arm64 image the Pi runs, which is what `caddy validate` needs to load.
if docker build -q -t mati-lab/caddy-ci:check caddy >/dev/null; then
  tar -cf - caddy/Caddyfile | docker run --rm -i --entrypoint sh \
      -e CF_API_TOKEN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa mati-lab/caddy-ci:check -c '
    set -e; mkdir -p /tmp/w && tar -xf - -C /tmp/w
    caddy validate --config /tmp/w/caddy/Caddyfile --adapter caddyfile 2>&1 | tail -1' \
    | tee /dev/stderr | grep -qx 'Valid configuration' || fail "caddy validate"
else
  fail "caddy image build"
fi

echo
if [ ${#FAILED[@]} -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi
echo "all config checks passed"
