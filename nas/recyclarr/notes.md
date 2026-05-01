# Recyclarr (NAS)

Cron-driven `docker run` (no long-lived container). Image
`ghcr.io/recyclarr/recyclarr:latest`. Installed 2026-05-01 as Phase 1 of the
*arr-extras follow-on.

## What it does

Pulls TRaSH-Guides curated quality profiles + custom formats and pushes them
into Sonarr (TV + Anime via the same `WEB-1080p` profile) and Radarr
(`HD Bluray + WEB`). Without it, *arr default profiles accept anything that
matches resolution; with it, Sonarr/Radarr score releases by group, codec,
audio, HDR, etc., and pick the best of N candidates per search.

## Where state lives

| Path | Purpose |
|---|---|
| `nas/recyclarr/config.yml` (in repo) | Source of truth — committed |
| `/mnt/fast/databases/recyclarr/config.yml` (NAS) | Live config; copy of repo file, scp'd at deploy |
| `/mnt/fast/databases/recyclarr/{configs,includes,logs,resources,state}` | Recyclarr's own state — auto-managed |
| `/mnt/bulk/backups/.scripts/recyclarr-sync.sh` (NAS, root) | Cron-invoked wrapper |
| `/var/log/recyclarr-sync.log` (NAS, root) | Cron output |
| `/root/.backup-env` (NAS, root) | `SONARR_API_KEY`, `RADARR_API_KEY`, `KUMA_URL_RECYCLARR_SYNC` |

## Cadence

Sun 04:30 UTC, registered as TrueNAS cronjob (id 18 at install). Heartbeats
Kuma push monitor `recyclarr-sync` (interval 604800 s, retry 259200 s).

## v8 template gotchas (caught the first time so writing them down)

Recyclarr v8's `template:` include keyword is **generator-only** —
`recyclarr config create --template <id>` produces a starter file, but
`include: { template: ... }` at runtime expects entries from the v8 branch's
`includes.json`, which is intentionally empty. Hence `nas/recyclarr/config.yml`
**inlines** the template content instead of `include:`-ing it.

If you ever want to refresh against a newer TRaSH preset, fetch:

- Sonarr: <https://github.com/recyclarr/config-templates/blob/v8/sonarr/templates/web-1080p.yml>
- Radarr: <https://github.com/recyclarr/config-templates/blob/v8/radarr/templates/hd-bluray-web.yml>

…and merge changes into our `config.yml`.

Other v8 changes worth knowing:

- `replace_existing_custom_formats` is removed (silently ignored if present).
- Instance labels (the second-level keys under `sonarr:` / `radarr:`) must
  be **unique across services** — that's why we use `sonarr-main` and
  `radarr-main` (not just `main`).
- `custom_format_groups` replaced the old `custom_formats` block.
- Listing default-or-required CFs in a group's `select:` produces "redundant"
  warnings — only list optional add-ons.

## Container quirks

The script runs Recyclarr as `--user 568:568` so it can read the
`apps:apps`-owned `config.yml`. Recyclarr expects `$HOME` and
`$XDG_CONFIG_HOME` set so it has a writable path for cloning the
config-templates repo and writing state. Both are pinned to `/config` in
the wrapper script.

## What the sync changes

`delete_old_custom_formats: true` for Sonarr and Radarr — Recyclarr removes
any custom format it managed previously but is no longer listed in
`config.yml`. Useful when trimming. **Be aware** that any CF added by hand in
the UI will be removed if Recyclarr doesn't know about it. None today.

## Verifying / previewing changes

Preview without applying:

```bash
ssh -t truenas_admin@192.168.1.65 'sudo docker run --rm \
  --user 568:568 \
  -v /mnt/fast/databases/recyclarr:/config \
  -e HOME=/config -e XDG_CONFIG_HOME=/config \
  -e SONARR_API_KEY=$(sudo grep ^SONARR_API_KEY= /root/.backup-env | cut -d= -f2) \
  -e RADARR_API_KEY=$(sudo grep ^RADARR_API_KEY= /root/.backup-env | cut -d= -f2) \
  ghcr.io/recyclarr/recyclarr:latest \
  sync --config /config/config.yml --preview'
```

Force a sync now (skip cron wait):

```bash
ssh -t truenas_admin@192.168.1.65 'sudo /mnt/bulk/backups/.scripts/recyclarr-sync.sh'
```

## Restore

Recyclarr is stateless — there's nothing to restore. After NAS rebuild:

1. Recreate `/mnt/fast/databases/recyclarr/`, scp the committed `config.yml`,
   chown 568:568.
2. Re-stage `recyclarr-sync.sh` under `/mnt/bulk/backups/.scripts/` (sudo).
3. Re-stage `SONARR_API_KEY` / `RADARR_API_KEY` / `KUMA_URL_RECYCLARR_SYNC`
   in `/root/.backup-env`.
4. Re-register cron via `midclt cronjob.create`.
5. Run once manually; verify profiles + CFs appear in Sonarr/Radarr UIs
   (currently `WEB-1080p` and `HD Bluray + WEB`).

## Monitoring

- Kuma push monitor `recyclarr-sync` — heartbeat on every successful run.
- Logs: `/var/log/recyclarr-sync.log` (root-readable) plus per-run debug
  at `/mnt/fast/databases/recyclarr/logs/cli/`.
- Promtail does not scrape one-shot containers, so log capture is via the
  on-disk file only.

## Admin tips

- API key rotation: regenerate in Sonarr/Radarr UI, update `/root/.backup-env`,
  no Recyclarr-side change needed.
- Disable temporarily: `midclt call cronjob.update <id> '{"enabled":false}'`.
- After every successful sync, re-assign series to the freshly-created profile
  in Sonarr (e.g. `WEB-1080p`); old default profiles like "HD - 720p/1080p"
  remain on the system as fallbacks.
- Series type matters for anime grabs: in Sonarr UI, anime series should be
  marked `seriesType=anime` so absolute episode numbering is used (already
  done for FMA at install).
