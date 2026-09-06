#!/usr/bin/env bash
# Alerting-pipeline dead-man check (Pi, root via systemd timer, every 6h).
#
# Born from the 2026-06→09 incident: Alertmanager→ntfy got 403 on every
# notify for ~3 months and nothing noticed, because the only thing that
# could have alerted about alerting was alerting. This script is the
# independent observer:
#
#   1. Watchdog alert (always firing, rules/deadman.yml) must be present in
#      Alertmanager's active-alerts API → proves Prometheus rule eval AND
#      Prometheus→Alertmanager delivery.
#   2. alertmanager_notifications_failed_total must not be increasing
#      (via Prometheus query API) → proves the ntfy egress isn't erroring.
#   3. ntfy /v1/health must be healthy.
#
# On ANY failure it publishes directly to ntfy homelab-alerts using the
# alertmanager token file (independent of the Alertmanager process, but
# NOT of ntfy itself — if ntfy is down, the journal + failed unit state is
# the only trace. True independence needs an external ping service; see
# docs/sweep-2026-09-06.md action items).
#
# Optional heartbeat: if /opt/mati-lab/network/deadman/.env defines
# KUMA_URL_DEADMAN (push monitor minted in the Kuma UI), every healthy run
# pushes it, so a dead timer ALSO surfaces (in Kuma, whose own reds notify
# via its separate ntfy token — a genuinely second credential path).

set -uo pipefail

TOKEN_FILE=/opt/mati-lab/network/alertmanager/ntfy-token
NTFY_URL=http://localhost:8093/homelab-alerts
ENV_FILE=/opt/mati-lab/network/deadman/.env
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

FAILURES=()

# 1. Watchdog present in Alertmanager
AM_ALERTS=$(docker exec alertmanager wget -qO- 'http://localhost:9093/api/v2/alerts?active=true' 2>/dev/null || true)
if ! grep -q '"Watchdog"' <<<"$AM_ALERTS"; then
  FAILURES+=("Watchdog alert missing from Alertmanager (Prometheus->AM chain broken)")
fi

# 2. Notification failures counter flat (prometheus publishes no host port —
# query it inside its own container, same as the Alertmanager check above)
NOTIFY_FAILS=$(docker exec prometheus wget -qO- \
  'http://localhost:9090/api/v1/query?query=sum(increase(alertmanager_notifications_failed_total%5B2h%5D))' 2>/dev/null \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print(float(d[0]["value"][1]) if d else 0)' 2>/dev/null || echo "query-error")
if [ "$NOTIFY_FAILS" = "query-error" ]; then
  FAILURES+=("Prometheus query API unreachable")
elif python3 -c "import sys; sys.exit(0 if float('$NOTIFY_FAILS') > 0.5 else 1)"; then
  FAILURES+=("Alertmanager notify failures in last 2h: $NOTIFY_FAILS")
fi

# 3. ntfy health
NTFY_OK=$(curl -fsS --max-time 10 http://localhost:8093/v1/health 2>/dev/null | grep -c '"healthy":true' || true)
if [ "$NTFY_OK" != "1" ]; then
  FAILURES+=("ntfy /v1/health not healthy")
fi

if [ ${#FAILURES[@]} -gt 0 ]; then
  MSG=$(printf '%s; ' "${FAILURES[@]}")
  echo "DEADMAN FAIL: $MSG" >&2
  curl -fsS --max-time 10 --retry 3 --retry-delay 30 --retry-all-errors \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: ALERTING PIPELINE BROKEN (dead-man check)" \
    -H "Priority: urgent" \
    -d "$MSG" "$NTFY_URL" >/dev/null \
    || echo "DEADMAN: ntfy publish ALSO failed — alerting fully dark" >&2
  exit 1
fi

echo "deadman ok: watchdog present, notify-fails=$NOTIFY_FAILS, ntfy healthy"
if [ -n "${KUMA_URL_DEADMAN:-}" ]; then
  curl -fsS --max-time 10 --retry 3 --retry-delay 30 --retry-all-errors \
    "$KUMA_URL_DEADMAN?status=up&msg=ok" >/dev/null || echo "WARN: Kuma deadman push failed" >&2
fi
