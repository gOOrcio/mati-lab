# Bazarr (NAS)

TrueNAS Scale Custom App. Installed 2026-05-01 to fetch subtitles for the
Sonarr + Radarr libraries. LinuxServer.io image
(`lscr.io/linuxserver/bazarr:latest`).

## Endpoints

- **Direct:** `http://192.168.1.65:30028`
- **Through Caddy + Authelia 2FA:** `https://bazarr.mati-lab.online`
- **Internal port:** 6767

## Storage

| Role | Type | Path |
|---|---|---|
| Config (SQLite + YAML) | Bind | `/mnt/fast/databases/bazarr/config` → `/config` |
| Data (read-only access to media library) | Bind | `/mnt/bulk/data` → `/data` |

Bazarr writes `.srt` (and similar) files alongside each video file under
`/data/media/...`. Sonarr/Radarr's "import extra files" config picks them
up if a torrent comes in with embedded subs; Bazarr fills the gap when
the release lacks them.

## Auth

Bazarr's auth model is **NOT** the External-pattern used by Sonarr / Radarr
/ Prowlarr. At deploy time `auth.type=null` (no UI auth required).
Authelia 2FA via Caddy is the effective gate; LAN-direct access at
`:30028` has no auth. Same posture in practice as the other three.

If you ever want a belt-and-suspenders local password, set it via
**Settings → General → Security** (UI only — no API path) and save the
admin login under `homelab/bazarr/admin`.

## Wiring (configured at deploy via direct config.yaml patch)

Bazarr's `/api/system/settings` POST endpoint silently no-ops on partial
JSON payloads despite returning HTTP 204; **do NOT trust the API to wire
Sonarr/Radarr connections.** The deploy-time wiring was done by directly
editing `/mnt/fast/databases/bazarr/config/config/config.yaml`:

```yaml
general:
  use_sonarr: true
  use_radarr: true
sonarr:
  ip: 192.168.1.65
  port: 30026
  ssl: false
  base_url: /
  apikey: '<sonarr api key>'
radarr:
  ip: 192.168.1.65
  port: 30027
  ssl: false
  base_url: /
  apikey: '<radarr api key>'
```

After patching, restart Bazarr (`midclt call -j app.stop bazarr` then
`app.start bazarr`).

**Subtitle languages NOT YET CONFIGURED.** Sub-language profiles are
required for Bazarr to actually fetch anything. Set via UI:

1. **Settings → Languages → Languages Filter** → add the languages you
   want (English at minimum; Polish if you want).
2. **Settings → Languages → Language Profiles → + Add a new profile**
   → name `default`, add language(s), save.
3. **Settings → Series → Default profile** → `default`. Same for
   **Settings → Movies → Default profile**.
4. **Settings → Providers** → enable at least one (OpenSubtitles.com is
   the standard pick; needs a free account, paste creds in UI).

After all four steps, Bazarr will start scanning + fetching for new
imports automatically.

## Credentials

| Item | Where | PM label |
|---|---|---|
| API key | `/mnt/fast/databases/bazarr/config/config/config.yaml` `auth.apikey` | `homelab/bazarr/api-key` |
| Subtitle provider creds | filled in via Settings → Providers | `homelab/bazarr/provider-<name>` once added |

## Reverse proxy

`@bazarr` block in `network/caddy/Caddyfile`, identical shape to the
others.

## Backups

Folded into `arr-config-backup.sh` (config dir tar.gz.gpg, weekly).
See [`../sonarr/notes.md`](../sonarr/notes.md#backups).

## Monitoring

- Promtail: `{container=~"ix-bazarr-bazarr-.*"}`.
- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30028/`, keyword
  `Bazarr`.

## Admin tips

- Settings POST silently no-ops a lot. After ANY UI settings change,
  verify by reading back `/api/system/settings` (with `X-Api-Key` header)
  and grep'ing the relevant block.
- Bazarr re-reads `config.yaml` only on startup. After a manual file
  patch, you MUST restart the app (`app.stop bazarr` + `app.start
  bazarr`); there's no SIGHUP equivalent.
