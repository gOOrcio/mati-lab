# Uptime Kuma monitors

Kuma's source of truth is its own SQLite DB. This file is a human inventory —
keep it in rough sync after adding/removing monitors in the UI.

URL: `https://uptime-kuma.mati-lab.online`

## Phase 2 — NAS media stack

| Name | Type | URL | Notes |
|---|---|---|---|
| jellyfin | HTTP | `https://jellyfin.mati-lab.online/health` | Returns body `Healthy` with 200 when alive |
| qbittorrent | HTTP-Keyword | `http://192.168.1.65:30024/` | **Direct to NAS, not through Caddy.** Keyword `qBittorrent`. Through Caddy, Authelia 2FA blocks the probe (302 → login). Kuma is on `pihole-net` which falls in the qBit LAN subnet whitelist, so direct works |

Immich monitor deferred with Task 3.

## Phase 2.r — *arr automation

Each monitor uses the **direct LAN NodePort** (Caddy fronts return 302 →
Authelia, useless for probing).

| ☑ | Name | Type | URL | Match |
|---|---|---|---|---|
| ☑ | prowlarr | HTTP-Keyword | `http://192.168.1.65:30025/login` | `Prowlarr` |
| ☑ | sonarr | HTTP-Keyword | `http://192.168.1.65:30026/login` | `Sonarr` |
| ☑ | radarr | HTTP-Keyword | `http://192.168.1.65:30027/login` | `Radarr` |
| ☑ | bazarr | HTTP-Keyword | `http://192.168.1.65:30028/` | `Bazarr` |
| ☑ | arr-config-backup | Push | minted in Kuma UI; URL in PM (`homelab/uptime-kuma/push-arr-config-backup`) and `/root/.backup-env` (`KUMA_URL_ARR_CONFIG`) | weekly heartbeat (interval 604800s, retry 259200s) |

## Phase 2.r extras Phase 1 — Recyclarr + Jellyseerr

| ☑ | Name | Type | URL | Match |
|---|---|---|---|---|
| ☑ | jellyseerr | HTTP-Keyword | `http://192.168.1.65:30029/status` | `version` (Jellyseerr's `/status` 307s to `/login`; the login HTML contains "version" in metadata. **Don't set Body Encoding to JSON** — Express strict-mode rejects GETs with `Content-Type: application/json`.) |
| ☑ | recyclarr-sync | Push | minted in Kuma UI; URL in PM (`homelab/uptime-kuma/push-recyclarr-sync`) and `/root/.backup-env` (`KUMA_URL_RECYCLARR_SYNC`) | weekly heartbeat (interval 604800s, retry 259200s) |

## vpn-stack — ProtonVPN tunnel

| ☐ | Name | Type | URL | Match |
|---|---|---|---|---|
| ☐ | gluetun-vpn-tunnel | HTTP-Keyword | `http://192.168.1.65:8000/v1/publicip/ip` | `public_ip` — Gluetun's control API exposes the tunnel-side public IP. If the container is up and tunnel is established, this returns 200 with a JSON body containing `public_ip` (a Swiss IP). If tunnel handshake fails or container is down, the endpoint either 503s or returns no body — Kuma flips red. (Bonus: visit the URL manually after a deploy to confirm `public_ip` is NOT your home IP — that would indicate killswitch failure.) |

## Phase 7 coverage gap list (to add)

Walk this top-down via the Kuma UI; tick each row when added. Match the
endpoint pattern in the Phase 2 rows above (direct LAN whenever possible
to bypass the Authelia 302-redirect on Caddy-fronted vhosts).

### Tier 1 — core flow

| ☐ | Name | Type | Endpoint | Match |
|---|---|---|---|---|
| ☐ | authelia | HTTP-Keyword | `http://authelia:9091/api/health` | `OK` |
| ☐ | litellm | HTTP-Keyword | `http://192.168.1.65:4000/health/liveliness` | `alive` (response is `"I'm alive!"`, not `healthy`) |
| ☐ | qdrant | HTTP-Keyword | `http://192.168.1.65:30017/healthz` | `passed` |
| ☐ | gitea | HTTP-Keyword | `https://gitea.mati-lab.online/api/v1/version` | `version` (LAN `:30009` is SSH; HTTP only via Caddy) |
| ☐ | ollama-gpu | HTTP-Keyword | `http://192.168.1.48:11434/` | `Ollama is running` |
| ☐ | caddy | HTTP | `http://caddy:80` | 200/400 acceptable |
| ☐ | cloudflared (transitive) | HTTP-Keyword | `https://gitea.mati-lab.online/api/v1/version` | `version` |

### Tier 2 — observability + persistence

| ☐ | Name | Type | Endpoint | Match |
|---|---|---|---|---|
| ☐ | loki | HTTP-Keyword | `http://loki:3100/ready` | `ready` |
| ☐ | prometheus | HTTP-Keyword | `http://prometheus:9090/-/healthy` | `Healthy` |
| ☐ | grafana | HTTP-Keyword | `http://grafana:3000/api/health` | `ok` |
| ☐ | ntfy | HTTP-Keyword | `http://ntfy:80/v1/health` | `success` |
| ☐ | obsidian-couchdb | HTTP (status code) | `http://192.168.1.65:30015/` | accept status `401` (CouchDB returns 401 on `/` and `/_up` for unauthenticated requests; 401 = "alive but auth required") |
| ☐ | syncthing | HTTP-Keyword | `http://192.168.1.65:30016/rest/noauth/health` | `OK` |

### Tier 3 — useful, not critical

| ☐ | Name | Type | Endpoint | Match |
|---|---|---|---|---|
| ☐ | pi-hole (DNS) | DNS | `mati-lab.online` via `192.168.1.252` | resolves |
| ☐ | hermes | HTTP-Keyword | `http://192.168.1.65:30262/` | `Hermes Agent - Dashboard` (the dashboard sidecar serves a 200 with this title) |
| ☐ | homebridge | HTTP | `http://192.168.1.155:8581/health` | 200 |
| ☐ | homarr | HTTP | `http://homarr:7575/api/health` | 200 |
| ☐ | rag-watcher | Push | (Kuma → new push monitor → cron in container) | within 12h |
| ☐ | promtail-nas | Push | Same pattern | within 5 min |

After ticking each row, also fold the Phase 2 table at the top of this
file into a single combined inventory. Push-monitor URLs land in the
password manager under `homelab/uptime-kuma/push-<name>` (anyone with
the URL can mark the monitor green — treat as a secret).

## Notification routing

All monitors route to the existing ntfy notification channel
(`ntfy.mati-lab.online`), same as the rest of the homelab.
