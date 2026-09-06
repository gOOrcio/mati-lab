#!/usr/bin/env bash
# Weekly credential drift check (NAS, root cron, Sun 06:10 UTC).
#
# The 2026-09-06 sweep found four silent credential failures (Homebridge
# backup creds stale 11 weeks, Alertmanager→ntfy dead 3 months, CouchDB
# cred embedded in a cron, repo/live script drift). This check
# authenticates as every NAS-resident credential consumer and alerts on
# any failure — a stale copy now surfaces within a week instead of months.
# Design: docs/secrets-management-proposal.md, option C.
#
# Read-only / side-effect-free by construction:
# - Kuma push URLs are deliberately NOT tested: any GET on a push URL
#   registers a heartbeat, which would mask a genuinely dead backup job.
# - ntfy token is validated via /v1/account (no message published).
# - The alert publish itself exercises the ntfy publish path on failure.
#
# Secrets are read from /root/.backup-env and the per-app .env files;
# nothing is ever echoed — only per-consumer OK/FAIL lines.

set -uo pipefail

NTFY_URL=https://ntfy.mati-lab.online
[ -f /root/.backup-env ] && . /root/.backup-env || true

FAIL=()
ok()   { echo "OK   $1"; }
fail() { echo "FAIL $1"; FAIL+=("$1"); }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@" 2>/dev/null || echo 000; }

# Pull one KEY=value out of an env file without sourcing the whole file.
envval() { grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }

# --- ntfy nas-crons token (no publish) ---
C=$(http_code -H "Authorization: Bearer ${NTFY_CRON_TOKEN:-missing}" "$NTFY_URL/v1/account")
[ "$C" = "200" ] && ok "ntfy nas-crons token" || fail "ntfy nas-crons token (HTTP $C)"

# --- CouchDB admin (obsidian dump cron) ---
C=$(http_code -u "${COUCHDB_ADMIN_USER:-x}:${COUCHDB_ADMIN_PASSWORD:-x}" http://127.0.0.1:30015/_up)
[ "$C" = "200" ] && ok "couchdb admin" || fail "couchdb admin (HTTP $C)"

# --- Homebridge UI creds (homebridge-backup cron) ---
C=$(http_code -X POST http://192.168.1.155:8581/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"username":"%s","password":"%s","otp":""}' "${HOMEBRIDGE_USERNAME:-x}" "${HOMEBRIDGE_PASSWORD:-x}")")
[ "$C" = "201" ] || [ "$C" = "200" ] && ok "homebridge login" || fail "homebridge login (HTTP $C)"

# --- *arr API keys (arr-config-backup + recyclarr) ---
for spec in "sonarr:30026:v3:${SONARR_API_KEY:-}" "radarr:30027:v3:${RADARR_API_KEY:-}" \
            "prowlarr:30025:v1:${PROWLARR_API_KEY:-}"; do
  IFS=: read -r app port apiv key <<<"$spec"
  C=$(http_code -H "X-Api-Key: $key" "http://127.0.0.1:$port/api/$apiv/system/status")
  [ "$C" = "200" ] && ok "$app api key" || fail "$app api key (HTTP $C)"
done
C=$(http_code -H "X-Api-Key: ${BAZARR_API_KEY:-x}" "http://127.0.0.1:30028/api/system/status")
[ "$C" = "200" ] && ok "bazarr api key" || fail "bazarr api key (HTTP $C)"

# --- LiteLLM virtual keys (consumer .env files) ---
for spec in "rag-watcher:/mnt/fast/databases/rag-watcher/.env:LITELLM_API_KEY" \
            "vault-rag-mcp:/mnt/fast/databases/vault-rag-mcp/.env:LITELLM_API_KEY" \
            "hermes:/mnt/fast/databases/hermes/.env:OPENAI_API_KEY"; do
  IFS=: read -r name file var <<<"$spec"
  KEY=$(envval "$file" "$var")
  if [ -z "$KEY" ]; then fail "litellm key $name ($var missing from $file)"; continue; fi
  C=$(http_code -H "Authorization: Bearer $KEY" http://127.0.0.1:4000/v1/models)
  [ "$C" = "200" ] && ok "litellm key $name" || fail "litellm key $name (HTTP $C)"
done

# --- MCP bearer tokens (401 without, non-401 with) ---
check_mcp() {
  local name=$1 port=$2 file=$3
  local tok; tok=$(envval "$file" MCP_BEARER_TOKEN)
  [ -n "$tok" ] || { fail "mcp bearer $name (token missing from $file)"; return; }
  local anon auth
  anon=$(http_code "http://127.0.0.1:$port/mcp")
  auth=$(http_code -H "Authorization: Bearer $tok" "http://127.0.0.1:$port/mcp")
  if [ "$anon" = "401" ] && [ "$auth" != "401" ]; then
    ok "mcp bearer $name"
  else
    fail "mcp bearer $name (anon=$anon auth=$auth — expect 401/non-401)"
  fi
}
check_mcp vault-rag-mcp 30019 /mnt/fast/databases/vault-rag-mcp/.env
QBIT_MCP_PORT=$(docker port ix-qbittorrent-mcp-qbittorrent-mcp-1 2>/dev/null | grep -oE '0\.0\.0\.0:[0-9]+' | head -1 | cut -d: -f2)
[ -n "$QBIT_MCP_PORT" ] && check_mcp qbittorrent-mcp "$QBIT_MCP_PORT" /mnt/fast/databases/qbittorrent-mcp/.env \
  || fail "mcp bearer qbittorrent-mcp (container port not found)"

# --- dump passphrase file ---
P=/mnt/bulk/backups/.secrets/dump-passphrase
if [ -s "$P" ] && [ "$(stat -c %a "$P")" = "600" ]; then ok "dump-passphrase file"; else fail "dump-passphrase file (missing/empty/bad mode)"; fi

# --- verdict ---
echo "---"
if [ ${#FAIL[@]} -gt 0 ]; then
  MSG="secrets drift: ${#FAIL[@]} consumer(s) failing: $(printf '%s; ' "${FAIL[@]}")"
  echo "$MSG" >&2
  curl -fsS --max-time 10 --retry 3 --retry-delay 45 --retry-all-errors \
    -H "Authorization: Bearer ${NTFY_CRON_TOKEN:-}" \
    -H "Title: Secrets drift check: ${#FAIL[@]} failing" -H "Priority: high" \
    -d "$MSG" "$NTFY_URL/homelab-alerts" >/dev/null || echo "WARN: ntfy publish failed" >&2
  exit 1
fi
echo "$(date -u +%FT%TZ) secrets drift check: all consumers OK"
