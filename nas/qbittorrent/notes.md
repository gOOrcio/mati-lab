# qBittorrent (NAS)

> **Now part of the `vpn-stack` Custom App** (since 2026-05-01) —
> qBit shares the gluetun container's network namespace so peer +
> tracker traffic egresses through ProtonVPN. Originally installed as
> a TrueNAS Apps catalog `community`-train app; **migrated to a Custom
> App** under `vpn-stack` to allow `network_mode: service:gluetun`,
> with `/config` migrated from `ixVolume` to bind-mount
> `/mnt/fast/databases/qbittorrent-config/`. **For deploy / restore /
> VPN-related operations, see
> [`../vpn-stack/notes.md`](../vpn-stack/notes.md).** This file
> remains as the historical install trace + qBit-specific operational
> notes (privacy toggles, password reset, etc.).

Originally TrueNAS Scale Apps catalog, `community` train. Installed
2026-04-24, migrated to vpn-stack Custom App 2026-05-01.

## Endpoints

- **Direct (LAN, auth bypassed):** `http://192.168.1.65:30024`
- **Through Caddy + Authelia 2FA:** `https://qbit.mati-lab.online`
- **No external exposure** (not in Cloudflared tunnel; stays LAN-only)
- **BT listening port:** dynamic, set by Gluetun's NAT-PMP up-command (since 2026-05-02 — see `../vpn-stack/notes.md` "VPN port forwarding (NAT-PMP)"). Pre-2026-05-02 it was `51413/tcp+udp` static and not router-forwarded (download-only peering)

## App details

- Image: `ghcr.io/home-operations/qbittorrent:5.1.4` (app version `5.1.4_1.4.4`)
- Container UID/GID: `568:568` (the TrueNAS `apps` user)
- Resource limits: 1 CPU / 512 MB (catalog default — fine)

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Config (settings DB, resume data, GeoDB) | Bind mount (post-vpn-stack migration) | `/mnt/fast/databases/qbittorrent-config` → `/config` |
| Downloads | Host path on SATA mirror | `/mnt/bulk/data/torrents` → `/downloads` |

The pre-vpn-stack catalog app used a managed `ixVolume` at
`/mnt/.ix-apps/app_mounts/qbittorrent/config`. During the 2026-05-01
migration the contents were copied to the new bind path (preserves
state across Custom App lifecycle).

Subdir layout under `/mnt/bulk/data/torrents` (the in-container path is
still `/downloads/...`, just the host source moved):

```
complete/     default save path
incomplete/   temp_path, with `.!qB` extension on in-progress files
```

### Why `/downloads` doesn't match the host path anymore

The host bind source moved from `/mnt/bulk/downloads` →
`/mnt/bulk/data/torrents` during the *arr-stack migration on 2026-05-01,
to put `torrents/` and the Sonarr/Radarr media libraries on the **same**
ZFS dataset (`bulk/data`). Hardlinks can't cross datasets, so all four
`*arr` apps mount `/data → /mnt/bulk/data` and Sonarr/Radarr translate
qBit's `/downloads/foo` paths to `/data/torrents/foo` via Remote Path
Mapping. qBit's container view is unchanged from before — torrents
didn't need re-checking.

### Heads-up: the TrueNAS app form swaps the storage labels

At install, the "Config" and "Downloads" fields in the TrueNAS UI produced
the opposite mapping from what they imply. The correct mapping above was
applied via `midclt call app.update qbittorrent` after install. If you ever
reinstall, double-check the live mounts with:

```bash
ssh truenas_admin@192.168.1.65 \
  'midclt call app.query '"'"'[["name","=","qbittorrent"]]'"'"' \
   | python3 -c "import json,sys;v=json.load(sys.stdin)[0][\"active_workloads\"][\"container_details\"][0][\"volume_mounts\"];print(json.dumps(v,indent=2))"'
```

`/downloads` must resolve to `/mnt/bulk/data/torrents`, not to the
ix_volume and not to the legacy `/mnt/bulk/downloads` (destroyed
post-migration).

## Credentials + access model

- WebUI admin: `admin` / stored in password manager (PBKDF2-hashed in `qBittorrent.conf`)
- **LAN subnet whitelist bypasses qBit's own auth** for `192.168.1.0/24` only
  (`bypass_auth_subnet_whitelist_enabled=true`, `bypass_local_auth=false`)
- Two auth layers in practice:
  - **Through Caddy (`qbit.mati-lab.online`):** Authelia 2FA gate, then Caddy proxies from the Pi's LAN IP → qBit auto-auths via subnet whitelist
  - **Direct (`:30024` from LAN):** subnet whitelist bypasses auth; from anywhere else, admin password is required

## Privacy / safety toggles applied

Set via `POST /api/v2/app/setPreferences`:

| Preference | Value |
|---|---|
| `anonymous_mode` | `true` — strips client identity from peer handshakes |
| `encryption` | `1` (Require) — no unencrypted peer connections |
| `upnp` | `false` |
| `random_port` | `false` |
| `listen_port` | dynamic — set by gluetun NAT-PMP (was `51413` pre-2026-05-02) |
| `preallocate_all` | `true` (avoid fragmentation on SATA mirror) |
| `incomplete_files_ext` | `true` (`.!qB` suffix while downloading) |

qBit egresses through ProtonVPN (Switzerland) via the gluetun sidecar
in vpn-stack — see `../vpn-stack/notes.md`.

## Reverse proxy

`network/caddy/Caddyfile` — the `@qbittorrent` block routes through
`forward_auth http://authelia:9091` before reverse-proxying to
`http://192.168.1.65:30024`. Authelia default policy is `two_factor`, applied
via the `*.mati-lab.online` wildcard in `network/authelia/configuration.yml`.

## Admin tips

- Smoke-test passed 2026-04-24: downloaded `debian-13.4.0-amd64-netinst.iso`,
  SHA-256 matched Debian's official `SHA256SUMS` after moving from
  `incomplete/` to `complete/`.
- Uptime Kuma should monitor **direct** (`http://192.168.1.65:30024/api/v2/app/version`)
  — going via Caddy hits Authelia and returns a 302 to the login page.
- Resetting the WebUI password:
  1. Via WebUI: **Tools → Options → Web UI → Authentication**.
  2. Via API (from any LAN host, no auth needed):
     ```bash
     curl -X POST http://192.168.1.65:30024/api/v2/app/setPreferences \
       --data-urlencode 'json={"web_ui_username":"admin","web_ui_password":"<new>"}'
     ```
  3. Via config file: stop the app, edit
     `/mnt/.ix-apps/app_mounts/qbittorrent/config/qBittorrent/qBittorrent.conf`,
     remove the `WebUI\Password_PBKDF2` line, start the app — the default
     `adminadmin` login works until you set a new one.

## `missingFiles` mass outbreak — Jellyfin rewriting `.nfo` through Sonarr hardlinks (2026-09-10)

**Symptom.** 25 torrents stuck in `missingFiles` with `progress=0`, all
`category=tv`, clustered in two batches (5× Ironheart added 2026-05-01,
20× Adventure Time S01 added 2026-06-11). Looked like deleted media.

**It was not missing media.** Every `.mkv` was present, correct size, correct
ownership. The qBittorrent log named the real fault:

```
fast resume rejected. check_resume(/downloads/complete/…/<episode>.nfo):
mismatching file size
```

Every failure was on the **`.nfo`**, never the video.

**Root cause — a hardlink shared between two apps that both write it:**

1. Sonarr imports with hardlinks and had **Import Extra Files** on, so it
   hardlinked the `.mkv` *and the `.nfo`* into `/mnt/bulk/data/media/tv/…`.
2. Jellyfin has "save metadata into media folders" on and **rewrites that
   `.nfo` in place** on library refresh.
3. Same inode ⇒ the seeding torrent's file changes size underneath libtorrent
   ⇒ `check_resume` rejects at startup ⇒ `missingFiles`.

Proof: inode `1106` was shared between the torrent's `.nfo` and
`…/Adventure Time - S01E08 - Business Time WEBDL-1080p.nfo`; content was
Jellyfin's `<episodedetails>`/`<lockdata>` XML (not the scene NFO); `.nfo`
mtime Aug 10 23:03 vs the `.mkv`'s untouched Jun 11 18:51.

**The 25 were only the visible part.** Comparing every file of all 238
torrents against disk: **140 size mismatches, all `.nfo`, zero `.mkv`** —
25 already broken, **115 still seeding that would have dropped out on the
next restart**. libtorrent only re-validates at restore, so the damage
stays latent until qBittorrent restarts.

**Repair applied.** Break the hardlink on the download side (`cp -p` to a
temp + `mv` back ⇒ new inode; the library keeps its own copy), then force
recheck so each torrent re-pulls the correct `.nfo` bytes. 118 + 17 links
broken, 0 failures, 0 hardlinked `.nfo` left, **326 video hardlinks
preserved** (those are intentional and must never be broken — breaking them
would double disk usage).

**Prevention.** Sonarr/Radarr → Settings → Media Management → **Import Extra
Files** off (or drop `nfo` from the list). The scene `.nfo` has no value in
the library, and it is the only thing that was shared between the two trees.
Jellyfin metadata saving can stay on once nothing is hardlinked.

**Watch for:** the same class of bug with any file both a *arr imports and a
media server rewrites — artwork (`folder.jpg`, `-thumb.jpg`) and Bazarr
subtitles are the obvious candidates. Checked 2026-09-10: only `.nfo` was
ever hardlinked, no artwork or subtitles.

```bash
# audit: anything non-video hardlinked into the seeding tree is a landmine
find /mnt/bulk/data/torrents -type f -links +1 \
  ! -iname '*.mkv' ! -iname '*.mp4' -printf '%n\t%p\n'
```

**Gotcha: `/tmp` is `noexec` on TrueNAS.** A root cron pointed at
`/tmp/script.sh` runs and silently does nothing — no error, no output. Use
`/bin/sh /tmp/script.sh`, which reads the file instead of exec'ing it.
