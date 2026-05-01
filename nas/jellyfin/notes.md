# Jellyfin (NAS)

TrueNAS Scale catalog app (`community` train, image `jellyfin/jellyfin:10.11.8`).
Installed in Phase 2; storage layout migrated 2026-05-01 alongside the *arr
stack to share `bulk/data` for hardlink imports.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30013` (HTTP) / `30014` (HTTPS)
- **Through Caddy:** `https://jellyfin.mati-lab.online`
- **No Authelia gate** — Jellyfin manages its own users (per-user library
  access). Mobile/web clients depend on direct login.

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Config | `ixVolume` | `/mnt/.ix-apps/app_mounts/jellyfin/config` → `/config` |
| Cache | `ixVolume` | `/mnt/.ix-apps/app_mounts/jellyfin/cache` → `/cache` |
| Media library | Bind | `/mnt/bulk/data/media` → `/media` |
| Transcodes | `tmpfs`-style volume | docker volume → `/cache/transcodes` |

The in-container path is `/media`. Inside Jellyfin, libraries should be
configured to read from:
- `/media/movies` — Radarr-managed
- `/media/tv` — Sonarr-managed (regular TV)
- `/media/anime` — Sonarr-managed (anime root)

## Bind-mount gotcha (the *arr migration broke this once)

Before 2026-05-01 the bind mount was `/mnt/bulk/media` → `/media`. The *arr
stack migration destroyed `bulk/media` and consolidated content under
`bulk/data/media`. **The Jellyfin app config is NOT auto-migrated** — it
was patched manually via:

```bash
ssh truenas_admin@192.168.1.65 'midclt call app.config jellyfin' > /tmp/j.json
# mutate storage.additional_storage[*].host_path_config.path from
# /mnt/bulk/media to /mnt/bulk/data/media
midclt call -j app.update jellyfin '{"values": {"storage": <full storage block>}}'
```

If a future migration moves the media dataset again, Jellyfin will fail to
start with "Failed 'up' action" until its bind mount is repointed via the
same procedure.

## AMD VAAPI hardware transcoding

Resources block enables `use_all_gpus: true` and the catalog passes
`/dev/kfd` + `/dev/dri` into the container. **`renderD128` is currently
not present** on this NAS (no iGPU render node) — followups row 2.r.5 has
the cross-reference. Hardware transcode is therefore not actually doing
anything; software transcode handles whatever clients can't direct-play.

## Wiring (Sonarr / Radarr → Jellyfin Connect)

When Sonarr or Radarr finishes an import they POST to Jellyfin's
notification webhook to trigger a per-library refresh (instead of a full
periodic scan). To wire this:

1. Jellyfin UI → **Dashboard → API Keys → + Add**, name e.g. `arr-import`.
   Save the key under PM `homelab/jellyfin/api-key-arr`.
2. Run `nas/jellyfin/wire-arr-connect.py <api-key>` from the dev box. The
   script registers identical Emby/Jellyfin notification entries on
   Sonarr + Radarr (host `192.168.1.65:30013`, triggers `On Import` /
   `On Upgrade` / `On Series Delete` / `On Episode File Delete`).

Until this is wired, Jellyfin only sees new imports on its scheduled
library scan (default daily). Manually triggering "Scan Library" in the
UI is the workaround.

## Credentials

| Item | Where | PM label |
|---|---|---|
| Admin login | Jellyfin's own user DB at `/config/data/jellyfin.db` | `homelab/jellyfin/admin` |
| API key for *arr Connect | minted in UI as above | `homelab/jellyfin/api-key-arr` |

## Backups

Jellyfin's state (user accounts, watch progress, library metadata) lives
in `/mnt/.ix-apps/app_mounts/jellyfin/config/data/`. **Not currently
backed up** — same accepted-risk bucket as the media library itself
(followup 8.1). Worth picking up if Jellyfin user data accumulates value
(watch history, custom collections).

## Monitoring

- Uptime Kuma: `jellyfin` HTTP monitor on `https://jellyfin.mati-lab.online/health`
  (returns body `Healthy` 200 when up). Goes through Caddy fine —
  Jellyfin doesn't have Authelia in front.
- Promtail: `{container=~"ix-jellyfin-jellyfin-.*"}`.

## Admin tips

- Hardware transcode revisit (followup 2.r.5): if `/dev/dri/renderD128`
  ever shows up on this hardware, flip Jellyfin to use VAAPI for h264 +
  HEVC; otherwise software transcode is fine for typical 1-2 client load.
- After every dataset migration touching `/media` content: verify Jellyfin
  starts (`midclt call -j app.start jellyfin`) before assuming the
  migration is complete.
- Library scan after a fresh *arr import: usually auto-triggers via
  Connect notification (once wired); else **Dashboard → Scheduled Tasks →
  Scan All Libraries → Run**.
