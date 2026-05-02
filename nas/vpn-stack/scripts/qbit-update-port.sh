#!/bin/sh
# Gluetun VPN_PORT_FORWARDING_UP_COMMAND target.
#
# Gluetun calls this whenever ProtonVPN's NAT-PMP renews/changes the
# forwarded port. Argument $1 is the port (gluetun substitutes
# {{PORTS}} → e.g. "54321").
#
# Runs INSIDE the gluetun container, which shares its network namespace
# with qbittorrent — so localhost:30024 reaches qBit's WebUI.
#
# Prerequisite (one-off): qBit must allow auth bypass on localhost.
#   qBit UI → Tools → Options → Web UI →
#     [x] Bypass authentication for clients on localhost
#   (Or set `WebUI\LocalHostAuth=false` in qBittorrent.conf and restart.)
#
# Without that, this script's POST returns 401 and the listen_port stays
# stale. The script logs but does not fail the gluetun process.

set -eu

PORT="${1:-}"
if [ -z "$PORT" ] || [ "$PORT" = "0" ]; then
  echo "[qbit-update-port] no port passed; skipping" >&2
  exit 0
fi

QBIT_URL="http://localhost:30024"
PAYLOAD="json={\"listen_port\":${PORT},\"random_port\":false,\"upnp\":false}"

echo "[qbit-update-port] setting qBit listen_port=${PORT}" >&2

# busybox wget's --tries only retries on HTTP errors, not connection-level
# failures (rc=4 = ECONNREFUSED / connect timeout). On first deploy qBit may
# need ~30s past gluetun's "service_healthy" to bind its WebUI, so wrap the
# whole call in our own retry loop.
attempt=1
max_attempts=20
while [ "$attempt" -le "$max_attempts" ]; do
  if wget -q --tries=1 --timeout=10 \
          --post-data "$PAYLOAD" \
          -O - "${QBIT_URL}/api/v2/app/setPreferences" >/dev/null; then
    echo "[qbit-update-port] OK (attempt ${attempt})" >&2
    exit 0
  fi
  rc=$?
  echo "[qbit-update-port] attempt ${attempt}/${max_attempts} rc=${rc}, retrying in 5s" >&2
  sleep 5
  attempt=$((attempt + 1))
done
echo "[qbit-update-port] FAILED after ${max_attempts} attempts — check qBit localhost-auth bypass" >&2
exit 0
