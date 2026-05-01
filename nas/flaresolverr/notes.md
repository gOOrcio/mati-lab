# FlareSolverr (NAS)

TrueNAS Scale Custom App. Image `ghcr.io/flaresolverr/flaresolverr:latest`.
Installed 2026-05-01 to bypass Cloudflare anti-bot challenges on
torrent-tracker indexers (TPB, Nyaa.si, etc.) that started getting
"Unable to connect to indexer" errors in Prowlarr.

## What it does

Spawns a headless Chromium per request, navigates to the target URL,
solves any Cloudflare challenge presented, and returns the resulting
cookies + body to the calling app. Prowlarr (configured as an Indexer
Proxy) routes per-tagged-indexer searches through it.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30030`
- **No Caddy vhost** — only Prowlarr (NAS-internal, container-to-host
  via LAN bridge) needs to reach it. Pure JSON API, no human UI to
  protect.
- **No Authelia** — N/A.

## App details

- Image: `ghcr.io/flaresolverr/flaresolverr:latest` (v3.4.x at install)
- Internal port: 8191 → NodePort 30030
- Stateless — no config bind mount needed; only an ix-volume for the
  container's `/config` (Chromium profile, cleared on restart)
- Resource limits: TrueNAS Custom App default (1 CPU / 512 MB at
  install — bump to 1 CPU / 1 GB if Chromium gets OOM-killed during
  high concurrency)

## Key env vars

```yaml
TZ: Europe/Warsaw
LOG_LEVEL: info
LOG_HTML: false          # set to true only when debugging a specific solve
CAPTCHA_SOLVER: none     # we don't pay for 2captcha/anti-captcha
```

## Wiring (Prowlarr)

- Settings → Indexers → **+ Add Indexer Proxy** → **FlareSolverr**
  - Name: `FlareSolverr`
  - Host: `http://192.168.1.65:30030`
  - Request Timeout: `60` s
  - Tags: `flaresolverr` (auto-created at install)
- Settings → Indexers → click each Cloudflare-protected indexer →
  **Tags → flaresolverr** → Save. Prowlarr routes only those indexers
  through FlareSolverr; non-tagged indexers go direct.

At install both `The Pirate Bay` and `Nyaa.si` were tagged.

## How to add a new tagged indexer

1. Add the indexer normally (Prowlarr → Indexers → + → search).
2. Edit it → set Tag = `flaresolverr` → Save.
3. Test the indexer (gear icon → Test) → should pass even if it failed
   without the proxy.

## Storage

None on the bind side. Container-internal `/config` ix-volume holds
the headless Chromium user profile, which is regenerated on each
container restart. Don't bother backing it up.

## Reverse proxy

None.

## Backups

Stateless app — nothing to back up. The Prowlarr proxy registration
+ tag assignment ARE backed up (they're in Prowlarr's SQLite DB,
included in the weekly `arr-config-backup.sh` API-issued ZIP).

## Monitoring

- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30030/`, keyword
  `FlareSolverr is ready` (the root endpoint returns
  `{"msg":"FlareSolverr is ready!","version":"...","userAgent":"..."}`).
- Promtail: `{container=~"ix-flaresolverr-flaresolverr-.*"}`. Useful
  when debugging why a specific solve failed (set `LOG_HTML=true`
  temporarily).

## Admin tips

- **Resource ceiling**: a single solve uses ~200 MB of RAM during the
  Chromium spawn. With the catalog default 512 MB cap, two
  simultaneous solves can OOM-kill. If this becomes a problem, edit
  the Custom App to bump memory to 1 GB.
- **Image updates**: `latest` tracks the FlareSolverr release branch.
  Pull periodically:
  `ssh truenas_admin@nas 'midclt call -j app.pull_images flaresolverr '"'"'{"redeploy": true}'"'"''`.
- **Ban behaviour**: if Cloudflare permanently bans the FlareSolverr
  IP for an indexer, FlareSolverr can't help — only a residential VPN
  in front of it would. Check Prowlarr indexer error: if it says "1020
  Access denied" or similar after FlareSolverr engages, it's a
  CF-IP-block, not a challenge.
- **Session leak**: FlareSolverr sometimes leaks sessions if a solve
  hangs. Restart the container occasionally if memory usage creeps up
  over weeks.

## Restore

After NAS rebuild:

1. `app.create flaresolverr` from `nas/flaresolverr/app-config.json`.
2. Prowlarr's restored DB (from `arr-config-backup` weekly ZIP) already
   contains the indexer-proxy entry + tag assignments — no Prowlarr-
   side action needed.
3. Smoke-test by hitting `http://192.168.1.65:30030/` (expect
   `FlareSolverr is ready!` JSON).

## Why no Caddy / Authelia

- LAN-only API consumers (Prowlarr container → 192.168.1.65:30030).
  No human ever opens FlareSolverr in a browser.
- Exposing it externally is a bad idea — anyone with the URL can use
  your Chromium fleet to bypass Cloudflare for arbitrary URLs (abuse
  vector). Keep it internal.
