#!/usr/bin/env bash
# Copy the grafana_ro password from the NAS secrets into network/grafana/.env
# (as BUDGET_PG_RO_PASSWORD) on this dev PC, the source `make deploy-grafana`
# copies to the Pi. Never prints the value. Re-run after rotating it.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ENVF="$REPO/network/grafana/.env"
[ -f "$ENVF" ] || {
  echo "missing $ENVF" >&2
  exit 1
}

val=$(ssh truenas_admin@192.168.1.65 \
  "sed -n 's/^GRAFANA_RO_PASSWORD=//p' /mnt/fast/databases/budget/secrets/db.env")
[ -n "$val" ] || {
  echo "GRAFANA_RO_PASSWORD not found on the NAS" >&2
  exit 1
}
[[ "$val" =~ ^[0-9a-f]+$ ]] || {
  echo "unexpected value format" >&2
  exit 1
}

tmp=$(mktemp)
grep -v '^BUDGET_PG_RO_PASSWORD=' "$ENVF" >"$tmp" || true
printf 'BUDGET_PG_RO_PASSWORD=%s\n' "$val" >>"$tmp"
cat "$tmp" >"$ENVF"
rm -f "$tmp"
unset val
echo "BUDGET_PG_RO_PASSWORD set in network/grafana/.env ($(grep -c '^BUDGET_PG_RO_PASSWORD=' "$ENVF") line)"
