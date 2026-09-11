# Uptime Kuma monitors

Kuma's source of truth is its own SQLite DB. This file is a human inventory.

URL: `https://uptime-kuma.mati-lab.online`

**Reconciled against the live DB 2026-09-11.** The previous version had
drifted badly in both directions — it listed monitors that did not exist
under those names, marked live monitors as "to add", and omitted 14 that were
running. That is worse than having no inventory: it is what made us believe a
`gluetun-vpn-tunnel` monitor was watching the VPN when nothing of that name
existed.

## Re-running the reconcile

Do this after any batch of UI changes. Read-only; never writes.

```bash
ssh gooral@192.168.1.252 'sudo python3 -c "
import sqlite3,json
con=sqlite3.connect(\"file:/opt/mati-lab/network/uptime-kuma/app/data/kuma.db?mode=ro\",uri=True)
for r in con.execute(\"SELECT name,type,active,keyword,interval FROM monitor ORDER BY name\"): print(r)
"'
```

**Never select `push_token`** — push URLs are secrets (anyone holding one can
mark a monitor green). They live in the password manager under
`homelab/uptime-kuma/push-<name>`.

## Live inventory (48 monitors in 7 groups)

### apps (15)

| Name | Type | Target | Match / notes |
|---|---|---|---|
| authelia | HTTP | `https://authelia.mati-lab.online` | |
| gitea | Keyword | `https://gitea.mati-lab.online/api/v1/version` | `version` — LAN `:30009` is SSH, HTTP only via Caddy |
| grafana | Keyword | `http://grafana:3000/api/health` | `ok` |
| homebridge | HTTP | `https://homebridge.mati-lab.online/health` | also a ping monitor in **servers** |
| litellm | HTTP | `http://192.168.1.65:4000/health/liveliness` | ⚠ stray `keyword=qBittorrent` (inert on HTTP type). Only checks for 200, not `alive` |
| loki | Keyword | `http://loki:3100/ready` | `ready` |
| ntfy | HTTP | `https://ntfy.mati-lab.online` | |
| obsidian-couchdb | HTTP | `http://192.168.1.65:30015/` | `accepted_statuscodes: ["401"]` — CouchDB 401s unauthenticated; 401 = alive. **Correct as configured** |
| pihole | HTTP | `https://pihole.mati-lab.online/api/info/version` | |
| prometheus | HTTP | `https://prometheus.mati-lab.online/-/healthy` | duplicate — see below |
| prometheus | Keyword | `http://prometheus:9090/-/healthy` | `Healthy` — duplicate name |
| proxmox | HTTP | `https://proxmox.mati-lab.online/api2/json/version` | accepts `200-299,400-499` (401s unauthenticated) |
| qdrant | Keyword | `http://192.168.1.65:30017/healthz` | `passed` |
| syncthing | Keyword | `http://192.168.1.65:30016/rest/noauth/health` | `OK` |
| uptime-kuma | HTTP | `https://uptime-kuma.mati-lab.online` | self-check |

### devices (7)

| Name | Type | Target | Notes |
|---|---|---|---|
| AppleTV | Ping | `192.168.20.161` | HomeKit hub — the Matter target in `IoT-to-HomeKit-hub-allow` |
| Hue Bridge | HTTP | `https://192.168.30.221/api/config` | **This is the doc's old `hue-bridge-iot`.** Catches bridge down *and* loss of `Infra-to-IoT-allow` |
| NetiaBox | Ping | `192.168.100.1` | ISP router |
| PS5 | Ping | `192.168.20.248` | |
| UDR | Ping | `192.168.1.1` | gateway |
| camera-g5-flex | Ping | `192.168.40.243` | camera down *and* loss of `Infra-to-Cameras-allow` |
| mati-gamer | Ping | `192.168.20.173` | **DISABLED, and the only monitor with no notification attached** |

### dns (3)

| Name | Type | Query | Via | Notes |
|---|---|---|---|---|
| dns-pihole-primary | DNS | `mati-lab.online` A | `192.168.1.252` | client-facing address |
| dns-pihole2-nas | DNS | `mati-lab.online` A | `192.168.1.65` | secondary — the one that silently covers for the primary |
| pihole-dns | DNS | `google.pl` A | `pihole` | tests the *service* by container name |

### media (8)

| Name | Type | Target | Match / notes |
|---|---|---|---|
| ` jellyfin` | HTTP | `https://jellyfin.mati-lab.online/health` | ⚠ leading space in name; stray `keyword=qBittorrent` (inert). Should keyword-check `Healthy` |
| ` qbittorrent` | Keyword | `http://192.168.1.65:30024/` | `qBittorrent`. ⚠ leading space. **Direct to NAS, not via Caddy** — Authelia 2FA 302s the probe. Kuma sits in qBit's LAN whitelist |
| bazarr | Keyword | `http://192.168.1.65:30028/login` | `Bazarr` |
| jellyseerr | Keyword | `http://192.168.1.65:30029/v1/status` | `version`. **Don't set Body Encoding to JSON** — Express strict-mode rejects GETs with `Content-Type: application/json` |
| prowlarr | Keyword | `http://192.168.1.65:30025/login` | `Prowlarr` |
| public_ip | Keyword | `http://192.168.1.65:8000/v1/publicip/ip` | ⚠ **BROKEN + misfiled** — see VPN section |
| radarr | Keyword | `http://192.168.1.65:30027/login` | `Radarr` |
| sonarr | Keyword | `http://192.168.1.65:30026/login` | `Sonarr` |

All *arr monitors use the **direct LAN NodePort** — Caddy fronts return 302 to
Authelia, useless for probing.

### push-monitors (8)

Push URLs are secrets; they live in PM under `homelab/uptime-kuma/push-<name>`
and in `/root/.backup-env` on the NAS as `KUMA_URL_*`.

| Name | Interval | Notes |
|---|---|---|
| ` backup-dev-pc-restic` | 86400 | ⚠ leading space. URL in dev-PC `~/.config/restic/kuma-push-url` |
| ` backup-hermes-dump` | 90000 | ⚠ leading space |
| ` backup-nas-zfs-health` | 90000 | ⚠ leading space |
| backup-arr-config-backup | 604800 | `KUMA_URL_ARR_CONFIG` |
| backup-gitea-pgdump | 90000 | |
| backup-homebridge-dump | 604800 | `KUMA_URL_HOMEBRIDGE` |
| backup-litellm-pgdump | 90000 | |
| backup-recyclarr-sync | 604800 | `KUMA_URL_RECYCLARR_SYNC` |

### servers (4)

| Name | Type | Target |
|---|---|---|
| compute | Ping | `192.168.1.184` |
| homebridge | Ping | `192.168.1.155` (duplicate name — HTTP monitor in **apps**) |
| nas | Ping | `192.168.1.65` |
| network | Ping | `192.168.1.252` |

### vpn (3)

| Name | Type | Target | Catches |
|---|---|---|---|
| qbit-connectable | Keyword, 300s | `http://192.168.1.65:30024/api/v2/transfer/info` | `"connection_status":"connected"` — **the only working dead-tunnel detector**. Would have caught the 2026-09-10 NAT-PMP failure |
| vpn-ip-not-home | Keyword, 300s, **INVERT** | `http://192.168.1.65:8000/v1/publicip/ip` | keyword = `<home WAN IP>`, inverted → UP when the body does *not* contain it. Catches **killswitch leak only**, not a dead tunnel (a killswitched tunnel returns an empty IP, which also lacks the home IP) |
| vpn-port-mismatch | Push, 1800s | — | NAT-PMP loss / port drift, from `qbit-port-probe.sh` (NAS cron 19, `*/30`). See [`nas/vpn-stack/notes.md`](../../nas/vpn-stack/notes.md) |

**`public_ip` is the monitor this file used to call `gluetun-vpn-tunnel`.** It
is filed under **media**, not vpn, which is part of why it was hard to find.

⚠ **It is broken.** Keyword `public_ip` also matches the dead-tunnel body
`{"public_ip":""}`, so it stays **green with no tunnel** (proven 2026-09-08,
still unfixed 2026-09-11).

**Fix:** keyword `"public_ip":""` with **Invert Keyword ON** — UP when the
body does *not* contain the empty-IP signature. Invert is already proven to
work in this install (`vpn-ip-not-home` uses it). Then move it into the
**vpn** group.

Do *not* reach for the JSON Query monitor type here: on 2.1.0 there are open
bugs where JSONata evaluates differently than jsonata.org and monitors go red
after upgrade. Also note the endpoint returns **9 fields**, not just
`public_ip` — so a naive keyword like `.` would match `datapacket.com` or the
`location` value and reproduce the same false-green.

## Known issues found in the 2026-09-11 reconcile

1. **`public_ip` broken** (above) — the only item here that costs real coverage.
2. **5 names have a leading space**: `jellyfin`, `qbittorrent`,
   `backup-dev-pc-restic`, `backup-hermes-dump`, `backup-nas-zfs-health`.
   They sort oddly and exact-name lookups miss them. Trim in the UI.
3. **`litellm` and `jellyfin` carry a stray `keyword=qBittorrent`** copy-pasted
   from the qbittorrent monitor. Inert on HTTP type, so nothing is broken
   today — but both are only checking for a 200, not for the body they should.
4. **Duplicate names**: `prometheus` ×2 and `homebridge` ×2. Both pairs are
   deliberate (HTTP + ping / internal + external), but identical names make
   alerts ambiguous. Rename rather than delete.
5. **`mati-gamer` is disabled and has no notification.** Fine while off;
   re-attach the notification if it is ever re-enabled.

## Genuinely missing (verified absent 2026-09-11)

| Name | Type | Endpoint | Match |
|---|---|---|---|
| hermes | HTTP | `http://192.168.1.65:30264/health` | Gateway API health. **Do not keyword-check `:30262`** — since v2026.9.7 the dashboard requires OIDC and answers 302, never an anonymous 200. A 502 in Sept 2026 went unnoticed for want of this monitor |
| ollama-gpu | Keyword | `http://192.168.1.48:11434/` | `Ollama is running` |
| caddy | HTTP | `http://caddy:80` | 200/400 acceptable |
| cloudflared (transitive) | Keyword | `https://gitea.mati-lab.online/api/v1/version` | `version` |
| homarr | HTTP | `http://homarr:7575/api/health` | 200 |
| rag-watcher | Push | cron in container | within 12h |
| promtail-nas | Push | same pattern | within 5 min |

`hermes` is the one with a known past outage behind it — worth doing first.

## VLAN segmentation coverage (added 2026-09-08)

Kuma runs on the Pi (`192.168.1.252`, VLAN 1 / Internal zone). **Every probe
therefore tests the path *from VLAN 1*.** That matters for what they can and
cannot prove.

| Monitor | Catches |
|---|---|
| `dns-pihole-primary` | Pi-hole down/wedged, at the client-facing address |
| `dns-pihole2-nas` | secondary resolver down — the one that silently covers for the primary |
| `camera-g5-flex` | camera down, **and** `Infra-to-Cameras-allow` being lost |
| `Hue Bridge` | bridge down, **and** `Infra-to-IoT-allow` being lost |

Interval 60 s, retries 2, notify via ntfy. All four verified green 2026-09-08
and still live 2026-09-11 (the last was renamed from `hue-bridge-iot`).

> **`dns-pihole-primary` found a real bug on its first run.** It sat Down while
> `dns-pihole2-nas` passed — the Pi's ufw admitted DNS from `172.18.0.0/16`, but
> every Pi Docker bridge is under `172.17.0.0/16` (Kuma is 172.17.1.20). No
> container on the Pi could query the Pi's own LAN DNS. Invisible before, because
> containers reach Pi-hole by container name on the shared bridge and never touch
> ufw — which is exactly why the older `pihole-dns` monitor stayed green. Fixed in
> `network/ansible/group_vars/all/vars.yml`.
>
> Keep both DNS monitors: `pihole-dns` tests the service, the other two test the
> **client-facing address** every VLAN actually resolves against. Only the latter
> catches a host-firewall or binding fault.

### What these do NOT catch

**None of them test `IoT-to-DNS-allow`.** A probe from VLAN 1 to `192.168.1.252`
exercises Internal→Internal, not IoT→Internal. If the IoT DNS allow slipped below
the deny, every IoT device would lose name resolution and these monitors would
stay green.

That failure can only be proven from inside VLAN 30 — the manual TCP/dig matrix
run from a laptop on `konewka_iot` (see `network/unifi/notes.md`). **Re-run that
matrix after any firewall or SSID change**; Kuma cannot replace it.

**Nor do they catch IoT→Trusted regressions.** The 2026-09-11 Matter failure —
where the Hue bridge could not push motion events to the Apple TV — was invisible
to every monitor here, because `Hue Bridge` probes Infra→IoT, the opposite
direction. The `IoT-to-Trusted-deny` firewall log is what caught it. See
`network/unifi/notes.md`.

## Notification routing

One channel: **`Uptime`** (id 1, active) → `ntfy.mati-lab.online`.

Every active monitor is attached to it. The only monitor without a
notification is `mati-gamer`, which is disabled.
