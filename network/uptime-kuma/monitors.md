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

| ☑ | Name | Type | URL | Match |
|---|---|---|---|---|
| ⚠ | gluetun-vpn-tunnel | HTTP-Keyword | `http://192.168.1.65:8000/v1/publicip/ip` | **BROKEN — keyword `public_ip` also matches the dead-tunnel response `{"public_ip":""}`, so this monitor is green with no tunnel (proven 2026-09-08). Change it to something that cannot match an empty value.** Original: `public_ip` — Gluetun's control API exposes the tunnel-side public IP. Auth on the control API is gated by `auth.toml` (allowlists this one route as `auth = "none"`); all mutating routes stay default-deny. Returns 200 with a JSON body containing `public_ip` (a Swiss IP) when the tunnel is up; 503/empty when handshake fails or container is down. **Bonus**: visit the URL manually after a deploy to confirm `public_ip` is NOT your home IP — that would indicate killswitch failure. |
| ☐ | vpn-port-mismatch | Push | minted in Kuma UI; URL in PM (`homelab/uptime-kuma/push-vpn-port-mismatch`) and `/root/.backup-env` (`KUMA_URL_VPN_PORT_MISMATCH`) | every 30 min from `qbit-port-probe.sh` cron — pushes `down` when gluetun's `forwarded_port` and qBit's `listen_port` disagree, or when either is unreadable. See [`nas/vpn-stack/notes.md`](../../nas/vpn-stack/notes.md) "Port-consistency probe". (Heartbeat 1800s, retry 3600s.) |

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
| ☐ | backup-homebridge-dump | Push | minted in Kuma UI; URL in PM (`homelab/uptime-kuma/push-homebridge-backup`) and `/root/.backup-env` (`KUMA_URL_HOMEBRIDGE`) | weekly heartbeat (interval 604800s, retry 259200s) |
| ☐ | backup-dev-pc-restic | Push | minted in Kuma UI; URL in PM (`homelab/uptime-kuma/push-dev-pc-restic`) and dev-PC `~/.config/restic/kuma-push-url` | daily heartbeat (interval 86400s, retry 43200s, max retries 2) |
| ☐ | homarr | HTTP | `http://homarr:7575/api/health` | 200 |
| ☐ | rag-watcher | Push | (Kuma → new push monitor → cron in container) | within 12h |
| ☐ | promtail-nas | Push | Same pattern | within 5 min |

After ticking each row, also fold the Phase 2 table at the top of this
file into a single combined inventory. Push-monitor URLs land in the
password manager under `homelab/uptime-kuma/push-<name>` (anyone with
the URL can mark the monitor green — treat as a secret).

## VLAN segmentation coverage (added 2026-09-08)

Kuma runs on the Pi (`192.168.1.252`, VLAN 1 / Internal zone). **Every probe
below therefore tests the path *from VLAN 1*.** That matters for what they can
and cannot prove — see the caveat after the table.

| ☑ | Name | Type | Endpoint | Expect | Catches |
|---|---|---|---|---|---|
| ☑ | `dns-pihole-primary` | DNS | `mati-lab.online` via `192.168.1.252`, A record | `192.168.1.252` | Pi-hole down/wedged |
| ☑ | `dns-pihole2-nas` | DNS | `mati-lab.online` via `192.168.1.65`, A record | `192.168.1.252` | secondary resolver down — the one that silently covers for the primary |
| ☑ | `camera-g5-flex` | Ping | `192.168.40.243` | up | camera down, **and** the `Infra-to-Cameras-allow` policy being lost |
| ☑ | `hue-bridge-iot` | HTTP | `https://192.168.30.221/api/config` (ignore TLS) | 200 | Hue Bridge down, **and** the `Infra-to-IoT-allow` policy being lost (Homebridge depends on it) |

Interval 60 s, retries 2, notify via the ntfy channel like everything else.
All four added and verified green 2026-09-08.

> **`dns-pihole-primary` found a real bug on its first run.** It sat Down while
> `dns-pihole2-nas` passed — the Pi's ufw admitted DNS from `172.18.0.0/16`, but
> every Pi Docker bridge is under `172.17.0.0/16` (Kuma is 172.17.1.20). No
> container on the Pi could query the Pi's own LAN DNS. Invisible before, because
> containers reach Pi-hole by container name on the shared bridge and never touch
> ufw — which is exactly why the older `pihole-dns` monitor stayed green. Fixed in
> `network/ansible/group_vars/all/vars.yml`. See `network/unifi/notes.md`.
>
> Keep both DNS monitors: the older `pihole-dns` tests the service, these test the
> **client-facing address** every VLAN actually resolves against. Only the latter
> catches a host-firewall or binding fault.

### What these do NOT catch

**None of them test `IoT-to-DNS-allow`.** A probe from VLAN 1 to `192.168.1.252`
exercises Internal→Internal, not IoT→Internal. If the IoT DNS allow slipped below
the deny, every IoT device would lose name resolution and these monitors would
stay green.

That failure can only be proven from inside VLAN 30 — the manual TCP/dig matrix
run from a laptop on `konewka_iot` (see `network/unifi/notes.md`, "IoT wall
proven from inside VLAN 30"). **Re-run that matrix after any firewall or SSID
change**; it is not something Kuma can replace.

The two VLAN-crossing monitors (`camera-g5-flex`, `hue-bridge-iot`) are the
closest continuous proxy: they fail if the corresponding `Infra-to-*-allow`
policy disappears, which is the most likely way this config regresses.

## Notification routing

All monitors route to the existing ntfy notification channel
(`ntfy.mati-lab.online`), same as the rest of the homelab.
