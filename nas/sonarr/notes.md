# Sonarr (NAS)

TrueNAS Scale Custom App. Installed 2026-05-01 alongside Radarr / Prowlarr /
Bazarr to close followups row 2.r.1. LinuxServer.io image
(`lscr.io/linuxserver/sonarr:latest`).

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30026`
- **Through Caddy + Authelia 2FA:** `https://sonarr.mati-lab.online`
- **No external exposure** (not in Cloudflared tunnel; LAN + Tailscale only).

## App details

- Image: `lscr.io/linuxserver/sonarr:latest` (v4.x at install)
- Internal port: 8989; container UID/GID: `568:568` via `PUID`/`PGID`
- Resource limits: TrueNAS Custom App default (1 CPU / 512 MB)
- App-config payload: [`app-config.json`](app-config.json) — used by
  `midclt call -j app.create "$(cat app-config.json)"`

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Config (SQLite DB, settings) | Bind | `/mnt/fast/databases/sonarr/config` → `/config` |
| Data (single mount, media + torrents) | Bind | `/mnt/bulk/data` → `/data` |

The single `/data` mount is **load-bearing for hardlinks**. Do NOT split it
into separate `/tv`, `/movies`, `/downloads` mounts — that re-introduces the
cross-filesystem boundary and silently degrades imports to copy mode.

## Auth

- `AuthenticationMethod = External`,
  `AuthenticationRequired = DisabledForLocalAddresses` (set via
  `PUT /api/v3/config/host` at deploy time).
- Inbound traffic from Caddy on the Pi LAN is treated as local → Authelia is
  the only effective gate via the public hostname.
- LAN-direct hits to `:30026` bypass auth (same posture as qBittorrent).

## Wiring (configured at deploy via API)

- **Download client:** qBittorrent at `192.168.1.65:30024`, category `tv`,
  no username/password — qBit's subnet whitelist (`192.168.1.0/24`)
  accepts the docker-bridged source IP. Leave as-is; if followup 7.x.6
  ever tightens that, swap in qBit admin creds from
  `homelab/qbittorrent/admin`.
- **Remote Path Mapping:** host `192.168.1.65`, remote `/downloads/`,
  local `/data/torrents/`.
- **Media management:** `copyUsingHardlinks=true`, `importExtraFiles=true`,
  `extraFileExtensions=srt,sub,ssa,ass,nfo`.
- **Root folders:** `/data/media/tv`, `/data/media/anime`.
- **Indexers:** synced automatically from Prowlarr (full sync, all TV
  categories incl. anime `5070`).
- **Connect → Jellyfin:** **NOT YET WIRED** — Jellyfin was `STOPPED` at
  deploy time. To wire later: start Jellyfin, mint an API key in its
  Dashboard → API Keys, then in Sonarr UI Settings → Connect → +
  Emby/Jellyfin, host `192.168.1.65` port from `midclt app.query
  "[[\"name\",\"=\",\"jellyfin\"]]"`, paste API key, triggers `On Import` +
  `On Upgrade` + `On Series Delete` + `On Episode File Delete`.

## Credentials

| Item | Where | PM label |
|---|---|---|
| API key | `/mnt/fast/databases/sonarr/config/config.xml` `<ApiKey>` element | `homelab/sonarr/api-key` |
| Admin login | not set up — auth posture is "external" via Authelia | n/a |

API key is auto-generated on first boot. **Copy it into the password
manager once** (and re-copy after every rotation), since:

- Prowlarr's "Apps → Sonarr" entry references it
- Bazarr's `sonarr.apikey` config field references it
- A future Jellyfin-Connect notification doesn't, but anything else that
  reads from Sonarr will.

To rotate: regenerate via Sonarr UI **Settings → General → Security**, then
update `homelab/sonarr/api-key` and the Prowlarr + Bazarr entries above.

## Reverse proxy

`network/caddy/Caddyfile` — `@sonarr` block:

```caddy
forward_auth http://authelia:9091 { … }
reverse_proxy http://192.168.1.65:30026
```

After editing the Caddyfile: `make deploy-caddy BRANCH=<branch>`, then on
the Pi `docker compose up -d --force-recreate caddy` — per
`feedback_caddy_bind_mount_recreate`.

## Backups

Config dir is captured weekly by
`nas/backup-jobs/arr-config-backup.sh` → `/mnt/bulk/backups/arr/arr-<ISO>.tar.gz.gpg`.
8-week retention. Encrypted with the shared backup passphrase
(`/mnt/bulk/backups/.secrets/dump-passphrase`, PM label
`homelab/backups/dump-passphrase`).

Restore = `midclt call -j app.stop sonarr`, decrypt + untar over
`/mnt/fast/databases/sonarr/config`, `app.start sonarr`, verify API
responds at `:30026`.

## Monitoring

- **Promtail (NAS)** auto-scrapes; query Loki with
  `{container=~"ix-sonarr-sonarr-.*"}`.
- **Uptime Kuma** monitor `sonarr` (HTTP-Keyword on
  `http://192.168.1.65:30026/login`, keyword `Sonarr`) — to be added by
  user via Kuma UI.
- **Alertmanager** — existing "container exit" rules cover this app
  without new config.

## Admin tips

- API key changes: regenerate in UI, then update Prowlarr `Apps → Sonarr`
  and Bazarr `sonarr.apikey`. Both will silently stop syncing if the key
  is stale.
- If imports start copying instead of hardlinking: Activity → History
  shows the import row with `Hardlink` vs `Copy`. Most common cause is
  someone splitting the `/data` mount — check `volume_mounts` via
  `midclt call app.query`.
- Adding a new root folder: ensure it lives under `/data/media/` (single
  mount); root folders elsewhere will copy-import.
