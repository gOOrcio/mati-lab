# Jellyseerr (NAS)

TrueNAS Scale Custom App. Image `fallenbagel/jellyseerr:latest` (v2.7.x at
install). Installed 2026-05-01 as Phase 1 of the *arr-extras follow-on.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30029` (returns 307 → /setup until
  configured, then to /requests)
- **Through Caddy:** `https://requests.mati-lab.online`
- **No external exposure** (LAN + Tailscale/WireGuard only — family-from-
  outside use VPN).
- **No Authelia gate** — Jellyseerr delegates auth to Jellyfin (uses the
  Jellyfin user DB). Once Jellyfin OIDC is in place, the chain is
  Authelia → Jellyfin login → Jellyseerr session.

## App details

- Image: `fallenbagel/jellyseerr:latest`
- Container UID/GID: `568:568` (set explicitly; the default image runs root)
- Internal port: 5055 → NodePort 30029
- Resource limits: TrueNAS Custom App default (1 CPU / 512 MB)

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Config (SQLite + JSON settings + per-user request history) | Bind | `/mnt/fast/databases/jellyseerr/config` → `/app/config` |

## Wiring (configured at first-run wizard)

- Auth: **Jellyfin** (admin: `gooral`, populated from Jellyfin user DB)
- Libraries exposed: Movies, Shows, Anime
- Sonarr: `192.168.1.65:30026`, profile `WEB-1080p`, root `/data/media/tv`,
  anime profile `WEB-1080p`, anime root `/data/media/anime` (single Sonarr
  config with both regular + anime sub-configs)
- Radarr: `192.168.1.65:30027`, profile **`HD Bluray + WEB`** (the
  Recyclarr-managed one; NOT Radarr's built-in `HD-1080p`), root
  `/data/media/movies`

The Sonarr/Radarr profile names are created by Recyclarr — if Recyclarr
hasn't synced yet, the profiles won't exist and the wizard's dropdown will
only show Radarr's built-in defaults. Run Recyclarr first.

## Permissions model

- `gooral` = Jellyseerr admin (auto-promoted because first Jellyfin user
  is admin in Jellyseerr).
- All permissions enabled including **Auto-Approve** so requests skip the
  manual gate.
- Family members imported on first Jellyfin login (post Jellyfin OIDC
  rollout). Default new-user permissions: Request + Auto-Approve. Tighten
  per-user from Settings → Users when invitee count grows.

## Known footgun: tag-requests vs. Radarr v6

**Disable "Tag Requests with Username"** in the Radarr server config
(Settings → Services → Radarr → edit → Advanced).

Why: Jellyseerr's default behaviour creates a tag like `1 - gooral`
(id-space-dash-space-username) per requester in Radarr/Sonarr. **Radarr v6+
enforces `^[a-z0-9-]+$`** for tag labels and rejects spaces with HTTP 400.
The result is a silent failure where Jellyseerr accepts the request
(status: "Requested"), fires `MEDIA_AUTO_APPROVED` notification, then
errors trying to create the tag in Radarr — request never reaches Radarr's
movie list.

Symptom in `/mnt/fast/databases/jellyseerr/config/logs/jellyseerr.log`:

```
[error][Media Request]: Something went wrong sending request to Radarr
{"errorMessage":"[Radarr] Failed to create tag: Request failed with status code 400"}
```

Sonarr v4 still accepts the spaces-style tag, so the bug is currently
Radarr-only. If a future Sonarr update tightens the same regex, disable
its tag-requests too.

## Reverse proxy

`network/caddy/Caddyfile` `@jellyseerr` block. **No `forward_auth`** —
Jellyseerr handles its own login.

## Backups

`/mnt/fast/databases/jellyseerr/config` is bundled into the weekly
`arr-config-backup.sh` archive (alongside the four *arr API-issued ZIPs).
Same retention (8 weeks), same encryption, same Kuma monitor.

Restore: `app.stop jellyseerr` → decrypt + untar the `jellyseerr-config.tar.gz`
inside the bundle over `/mnt/fast/databases/jellyseerr/config` → `app.start jellyseerr`
→ verify `/api/v1/status` returns 200.

## Monitoring

- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30029/status`, keyword
  `version`. (`/status` 307-redirects to `/login` HTML, which contains
  "version" in its page metadata — close enough as a liveness check. The
  more semantic `/api/v1/status` endpoint also works and returns
  `{"version":"2.7.3",...}` JSON — either is fine. **Body Encoding in
  Kuma must be left at default; selecting JSON sets `Content-Type:
  application/json` on a GET, which Jellyseerr's Express strict-mode
  rejects.**)
- Promtail: `{container=~"ix-jellyseerr-jellyseerr-.*"}`.

## Admin tips

- API key (for headless ops): Settings → General → API Key → regenerate.
  Save under PM `homelab/jellyseerr/api-key` if anything ever needs
  programmatic access.
- Library sync from Jellyfin: triggered automatically on schedule;
  manually via Settings → Jellyfin → "Sync Libraries".
- New family member needs a Jellyfin user first (manual create in Jellyfin
  UI, or auto-provisioned via Authelia OIDC once that's in place). They
  then log into Jellyseerr with their Jellyfin creds.
- After changing Radarr/Sonarr API keys: Settings → Services → click the
  server → paste new key → Test → Save. Otherwise Jellyseerr request
  pushes silently fail with auth errors in the log.
