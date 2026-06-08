#!/usr/bin/env bash
# Off-Pi heartbeat — runs on the NAS (always-on, independent of the Pi) and
# alerts when the network Pi (.252) goes silent. Everything that normally
# watches the Pi (Prometheus, Loki, Uptime-Kuma, the Pi's own ntfy) runs ON
# the Pi, so when it dies the monitoring dies with it. This is the external
# witness. Added after the 2026-06-06 NVMe-death outage, which went unnoticed
# until a human noticed the LAN had no DNS.
#
# Delivery uses ntfy.sh (public) on purpose: the Pi's self-hosted ntfy is down
# exactly when this fires. DNS is resolved via a hardcoded public resolver so
# the alert doesn't depend on Pi-hole (also down when this matters).
#
# Cron: every 2 min as root (TrueNAS cronjob). Topic comes from /root/.backup-env
# (NTFY_HEARTBEAT_TOPIC=...), which is NOT committed.
set -uo pipefail

[ -f /root/.backup-env ] && . /root/.backup-env

PI_IP="${PI_HEARTBEAT_IP:-192.168.1.252}"
TOPIC="${NTFY_HEARTBEAT_TOPIC:?set NTFY_HEARTBEAT_TOPIC in /root/.backup-env}"
STATE="/tmp/pi-heartbeat.state"      # consecutive-fail counter (ok to reset on NAS reboot)
FAIL_THRESHOLD="${PI_HEARTBEAT_THRESHOLD:-2}"   # alert after N misses (~2 min apart)
RESOLVER="1.0.0.1"                   # resolve ntfy.sh without Pi-hole

alive() {
  ping -c1 -W3 "$PI_IP" >/dev/null 2>&1 && return 0
  # Secondary signal: is Pi-hole answering on :53? Confirms a *useful* Pi, not
  # just one that ARP-replies.
  timeout 3 bash -c "exec 3<>/dev/tcp/$PI_IP/53" >/dev/null 2>&1 && return 0
  return 1
}

notify() {  # $1=title  $2=priority  $3=tags  $4=message
  local ip
  ip="$(dig +short +time=3 +tries=1 @"$RESOLVER" ntfy.sh A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)"
  [ -z "$ip" ] && ip="$(dig +short ntfy.sh A 2>/dev/null | grep -E '^[0-9.]+$' | head -1)"
  curl -fsS --max-time 10 ${ip:+--resolve "ntfy.sh:443:$ip"} \
    -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
    -d "$4" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1
}

count="$(cat "$STATE" 2>/dev/null || echo 0)"
case "$count" in (*[!0-9]*) count=0 ;; esac

if alive; then
  if [ "$count" -ge "$FAIL_THRESHOLD" ]; then
    notify "✅ network Pi recovered" "default" "white_check_mark" \
      "Pi $PI_IP is answering again ($(date '+%F %T %Z')). LAN DNS/Caddy should be back."
  fi
  echo 0 > "$STATE"
else
  count=$((count + 1))
  echo "$count" > "$STATE"
  if [ "$count" -eq "$FAIL_THRESHOLD" ]; then
    notify "🚨 network Pi DOWN" "urgent" "rotating_light,warning" \
      "No ping or DNS from $PI_IP for $count checks (~$((count * 2)) min). LAN DNS + Caddy + *.mati-lab.online are likely down. $(date '+%F %T %Z')"
  fi
fi
