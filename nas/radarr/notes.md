# Radarr (NAS)

TrueNAS Scale Custom App. Installed 2026-05-01 alongside Sonarr / Prowlarr /
Bazarr to close followups row 2.r.1. LinuxServer.io image
(`lscr.io/linuxserver/radarr:latest`).

Sibling app to Sonarr — see [`../sonarr/notes.md`](../sonarr/notes.md) for
the shared design rationale (single `/data` mount, hardlink imports, auth
posture). This file documents only the Radarr-specific bits.

## Endpoints

- **Direct:** `http://192.168.1.65:30027`
- **Through Caddy + Authelia 2FA:** `https://radarr.mati-lab.online`
- **Internal port:** 7878

## Storage

Same shape as Sonarr:

| Role | Type | Path |
|---|---|---|
| Config | Bind | `/mnt/fast/databases/radarr/config` → `/config` |
| Data | Bind | `/mnt/bulk/data` → `/data` |

## Auth

`External` + `DisabledForLocalAddresses`, set via `PUT /api/v3/config/host`
at deploy.

## Wiring (configured at deploy via API)

- Download client: qBittorrent (host `192.168.1.65:30024`, category
  `movies`, no creds — same as Sonarr).
- Remote Path Mapping: `/downloads/` → `/data/torrents/`.
- `copyUsingHardlinks=true`, `importExtraFiles=true`,
  `extraFileExtensions=srt,sub,ssa,ass,nfo`.
- Root folder: `/data/media/movies` (single).
- Indexers: synced from Prowlarr (full sync, movie categories
  `2000–2090`).
- Connect → Jellyfin: **NOT YET WIRED** — Jellyfin was `STOPPED` at
  deploy time. See sonarr/notes.md "Wiring" for the post-Jellyfin-start
  steps.

## Credentials

| Item | Where | PM label |
|---|---|---|
| API key | `/mnt/fast/databases/radarr/config/config.xml` `<ApiKey>` | `homelab/radarr/api-key` |
| Admin login | n/a (External auth) | n/a |

Rotation procedure: same as Sonarr, plus update Prowlarr `Apps → Radarr`
and Bazarr `radarr.apikey`.

## Reverse proxy

`@radarr` block in `network/caddy/Caddyfile`, identical shape to Sonarr.

## Backups

Folded into `arr-config-backup.sh` — see
[`sonarr/notes.md`](../sonarr/notes.md#backups).

## Monitoring

- Promtail: `{container=~"ix-radarr-radarr-.*"}`.
- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30027/login`, keyword
  `Radarr`.
