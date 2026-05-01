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
- **BT listening port:** `51413/tcp+udp` — **not** port-forwarded on the router, so effectively download-only peering

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
| `listen_port` | `51413` |
| `preallocate_all` | `true` (avoid fragmentation on SATA mirror) |
| `incomplete_files_ext` | `true` (`.!qB` suffix while downloading) |

No VPN. If that changes, the Gluetun sidecar pattern is documented at
<https://www.raveen.ca/posts/2025-05-29-qbit-gluetun/>.

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
