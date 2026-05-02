#!/bin/bash
# Periodic NAT-PMP forwarded-port consistency probe.
#
# Runs on the NAS host via root cron (every 30 min). Compares
# gluetun's currently-granted forwarded port against qBittorrent's
# active listen_port and pushes Uptime Kuma. Catches the silent failure
# modes that the gluetun up-command can't:
#   - up-command exited 0 after max retries (qBit unreachable at run time)
#   - up-command never fired since last reboot (NAT-PMP never granted)
#   - qBit was reconfigured manually and listen_port drifted
#
# Both reads happen inside gluetun's network namespace via docker exec,
# so qBit's "bypass auth on localhost" rule applies (no creds needed).
#
# Env required (loaded from /root/.backup-env, same pattern as other
# Kuma push jobs on the NAS):
#   KUMA_URL_VPN_PORT_MISMATCH = full https://uptime-kuma.../api/push/<token>

set -eu

# Sourced env (same convention as backup-jobs/*.sh).
if [ -f /root/.backup-env ]; then
  # shellcheck disable=SC1091
  . /root/.backup-env
fi

KUMA_URL="${KUMA_URL_VPN_PORT_MISMATCH:-}"
if [ -z "$KUMA_URL" ]; then
  echo "[qbit-port-probe] KUMA_URL_VPN_PORT_MISMATCH unset; aborting" >&2
  exit 1
fi

GLUETUN="ix-vpn-stack-gluetun-1"

push_kuma() {
  local status="$1" msg="$2"
  # Kuma push API: ?status=up|down&msg=...&ping=
  curl -fsS -o /dev/null --max-time 10 -G \
    --data-urlencode "status=${status}" \
    --data-urlencode "msg=${msg}" \
    "$KUMA_URL" || echo "[qbit-port-probe] kuma push failed" >&2
}

# 1. Read gluetun's forwarded port.
GLUETUN_PORT=$(docker exec "$GLUETUN" cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$GLUETUN_PORT" ] || [ "$GLUETUN_PORT" = "0" ]; then
  push_kuma down "gluetun forwarded_port empty (NAT-PMP not granted)"
  echo "[qbit-port-probe] DOWN: gluetun forwarded_port empty" >&2
  exit 0
fi

# 2. Read qBit's live listen_port via its own API (localhost-bypass).
QBIT_JSON=$(docker exec "$GLUETUN" wget -qO- --timeout=10 http://localhost:30024/api/v2/app/preferences 2>/dev/null || true)
if [ -z "$QBIT_JSON" ]; then
  push_kuma down "qbit preferences unreadable (qBit down or auth-walled)"
  echo "[qbit-port-probe] DOWN: qbit preferences unreadable" >&2
  exit 0
fi

QBIT_PORT=$(printf '%s' "$QBIT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("listen_port",""))' 2>/dev/null || true)
if [ -z "$QBIT_PORT" ]; then
  push_kuma down "qbit listen_port missing from API response"
  echo "[qbit-port-probe] DOWN: qbit listen_port missing" >&2
  exit 0
fi

# 3. Compare.
if [ "$GLUETUN_PORT" != "$QBIT_PORT" ]; then
  push_kuma down "port drift gluetun=${GLUETUN_PORT} qbit=${QBIT_PORT}"
  echo "[qbit-port-probe] DOWN: drift gluetun=${GLUETUN_PORT} qbit=${QBIT_PORT}" >&2
  exit 0
fi

push_kuma up "ok gluetun=qbit=${GLUETUN_PORT}"
echo "[qbit-port-probe] OK gluetun=qbit=${GLUETUN_PORT}"
