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

## Notification routing

All of the above are wired to the existing ntfy notification channel
(`ntfy.mati-lab.online`), same as the rest of the homelab monitors.
