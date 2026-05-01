# Prowlarr (NAS)

TrueNAS Scale Custom App. Installed 2026-05-01 to centralise indexer config
for Sonarr + Radarr. LinuxServer.io image (`lscr.io/linuxserver/prowlarr:latest`).

## Endpoints

- **Direct:** `http://192.168.1.65:30025`
- **Through Caddy + Authelia 2FA:** `https://prowlarr.mati-lab.online`
- **Internal port:** 9696

## Storage

| Role | Type | Path |
|---|---|---|
| Config | Bind | `/mnt/fast/databases/prowlarr/config` → `/config` |

No `/data` mount — Prowlarr only ever talks to Sonarr/Radarr/qBit over
HTTP, doesn't read from disk.

## Auth

`External` + `DisabledForLocalAddresses`, set via `PUT /api/v1/config/host`
at deploy.

## Wiring (configured at deploy via API)

Two **Applications** registered:

| Name | Sync Level | Sonarr/Radarr URL | Categories |
|---|---|---|---|
| Sonarr | Full Sync | `http://192.168.1.65:30026` | TV `5000-5080` + anime `5070` |
| Radarr | Full Sync | `http://192.168.1.65:30027` | Movies `2000-2090` |

Both reference Prowlarr at `http://192.168.1.65:30025` (the NAS LAN IP, NOT
`http://prowlarr:9696` — the apps live in separate Docker bridges and can't
resolve each other's container names).

## Indexers

**Empty at deploy time.** Add them via UI:

- Prowlarr UI → **Indexers → + Add Indexer** — pick public ones (1337x,
  Nyaa for anime, etc.) and/or paste private-tracker session cookies /
  API keys.
- Test each one before saving.
- Once an indexer is added/saved, Prowlarr auto-pushes it into Sonarr +
  Radarr (full sync).

For private trackers: `homelab/prowlarr/indexer-<name>` PM rows, one per
tracker. Some private trackers reject qBit's `anonymous_mode=true` (set
in `nas/qbittorrent/notes.md`); flip it off **per-tracker** if you hit
that, not globally.

## Credentials

| Item | Where | PM label |
|---|---|---|
| API key | `/mnt/fast/databases/prowlarr/config/config.xml` `<ApiKey>` | `homelab/prowlarr/api-key` |
| Admin login | n/a (External auth) | n/a |

Rotation: regenerate via Settings → General → Security → API Key, copy
into PM. (No external app references Prowlarr's key today, so rotation
is local — but if you ever wire a custom MCP / scraper, point it at the
PM entry.)

## Reverse proxy

`@prowlarr` block in `network/caddy/Caddyfile`, identical shape to qBit /
Sonarr / Radarr.

## Backups

Folded into `arr-config-backup.sh` (config dir tar.gz.gpg, weekly).
See [`../sonarr/notes.md`](../sonarr/notes.md#backups) for the procedure.

## Monitoring

- Promtail: `{container=~"ix-prowlarr-prowlarr-.*"}`.
- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30025/login`, keyword
  `Prowlarr`.
