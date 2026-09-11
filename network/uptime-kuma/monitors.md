# Uptime Kuma monitors

Kuma's source of truth is its own SQLite DB. This file is a human inventory.

URL: `https://uptime-kuma.mati-lab.online`

**Reconciled against the live DB 2026-09-11 (second pass).** 51 monitors in 7
groups; all 50 active ones UP at 08:26.

**First pass 2026-09-11.** The previous version had
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

## Live inventory (51 monitors in 7 groups)

### apps (18)

| Name | Type | Target | Match / notes |
|---|---|---|---|
| authelia | HTTP | `https://authelia.mati-lab.online` | |
| caddy | HTTP | `http://caddy:2019/config/` | Admin API, returns 200. **Do not probe `http://caddy:80`** — see the Caddy note below. ⚠ carries a stray `keyword=Ollama is running` copy-pasted from `ollama-gpu` (inert on HTTP type) |
| gitea | Keyword | `https://gitea.mati-lab.online/api/v1/version` | `version` — LAN `:30009` is SSH, HTTP only via Caddy |
| grafana | Keyword | `http://grafana:3000/api/health` | `ok` |
| hermes | Keyword | `http://192.168.1.65:30264/health` | `"status":"ok"` — body is `{"status": "ok", "platform": "hermes-agent", ...}`. **Do not probe `:30262`** (OIDC, answers 302). Added 2026-09-11 |
| homebridge-http | HTTP | `https://homebridge.mati-lab.online/health` | ignores TLS errors; ping twin in **servers** |
| litellm | Keyword | `http://192.168.1.65:4000/health/liveliness` | `alive` — body is `"I'm alive!"`. Fixed 2026-09-11 (was HTTP-only with a stray `qBittorrent` keyword) |
| loki | Keyword | `http://loki:3100/ready` | `ready` |
| ntfy | HTTP | `https://ntfy.mati-lab.online` | |
| ollama-gpu | Keyword | `http://192.168.1.48:11434/` | `Ollama is running` — verified exact body. Added 2026-09-11 |
| obsidian-couchdb | HTTP | `http://192.168.1.65:30015/` | `accepted_statuscodes: ["401"]` — CouchDB 401s unauthenticated; 401 = alive. **Correct as configured** |
| pihole | HTTP | `https://pihole.mati-lab.online/api/info/version` | |
| prometheus-external | HTTP | `https://prometheus.mati-lab.online/-/healthy` | via Caddy |
| prometheus-internal | Keyword | `http://prometheus:9090/-/healthy` | `Healthy` — direct |
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

### media (7)

| Name | Type | Target | Match / notes |
|---|---|---|---|
| ` jellyfin` | Keyword | `https://jellyfin.mati-lab.online/health` | `Healthy` — verified exact body. Fixed 2026-09-11. ⚠ still has a leading space in the name |
| ` qbittorrent` | Keyword | `http://192.168.1.65:30024/` | `qBittorrent`. ⚠ leading space. **Direct to NAS, not via Caddy** — Authelia 2FA 302s the probe. Kuma sits in qBit's LAN whitelist |
| bazarr | Keyword | `http://192.168.1.65:30028/login` | `Bazarr` |
| jellyseerr | Keyword | `http://192.168.1.65:30029/v1/status` | `version`. **Don't set Body Encoding to JSON** — Express strict-mode rejects GETs with `Content-Type: application/json` |
| prowlarr | Keyword | `http://192.168.1.65:30025/login` | `Prowlarr` |
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
| homebridge-ping | Ping | `192.168.1.155` (HTTP twin in **apps**) |
| nas | Ping | `192.168.1.65` |
| network | Ping | `192.168.1.252` |

### vpn (4)

| Name | Type | Target | Catches |
|---|---|---|---|
| qbit-connectable | Keyword, 300s | `http://192.168.1.65:30024/api/v2/transfer/info` | `"connection_status":"connected"` — **the only working dead-tunnel detector**. Would have caught the 2026-09-10 NAT-PMP failure |
| vpn-ip-not-home | Keyword, 300s, **INVERT** | `http://192.168.1.65:8000/v1/publicip/ip` | keyword = `<home WAN IP>`, inverted → UP when the body does *not* contain it. Catches **killswitch leak only**, not a dead tunnel (a killswitched tunnel returns an empty IP, which also lacks the home IP) |
| gluetun-vpn-tunnel | Keyword, 60s, **INVERT** | `http://192.168.1.65:8000/v1/publicip/ip` | keyword `"public_ip":""` inverted → UP when the tunnel is alive. **Fixed 2026-09-11** — see below |
| vpn-port-mismatch | Push, 1800s | — | NAT-PMP loss / port drift, from `qbit-port-probe.sh` (NAS cron 19, `*/30`). See [`nas/vpn-stack/notes.md`](../../nas/vpn-stack/notes.md) |

### `gluetun-vpn-tunnel` — FIXED 2026-09-11

Formerly named `public_ip` and filed under **media**, which is part of why it
was hard to find. Now renamed and in the **vpn** group.

It used to be **green with a dead tunnel**: keyword `public_ip` also matches
the dead-tunnel body `{"public_ip":""}`.

Now: keyword `"public_ip":""` with **Invert Keyword ON** — UP when the body
does *not* contain the empty-IP signature. A healthy check reads
`200 - OK, keyword not found`, which is the correct result for an inverted
keyword.

Do **not** reach for the JSON Query type: on 2.1.0 there are open bugs where
JSONata evaluates differently than jsonata.org. And do not use a naive `.`
keyword — the endpoint returns **9 fields**, so `.` matches
`datapacket.com` or the `location` value and reproduces the same false-green.

### Caddy: why `http://caddy:80` cannot be monitored directly

Verified 2026-09-11 from inside the Kuma container:

| Test | Result |
|---|---|
| `curl http://caddy:80` (no redirect follow) | clean **308** to `https://caddy/` |
| `curl -L` (what Kuma does by default) | **`tlsv1 alert internal error`** |
| `curl -L -k` (ignore TLS) | **still fails** |
| `curl http://caddy:2019/config/` | **200** |

Caddy 308-redirects port 80 to HTTPS. Kuma follows redirects, then does a TLS
handshake with SNI `caddy` — for which Caddy holds no certificate, so it
aborts the handshake server-side.

**Ticking "Ignore TLS/SSL error" does not help**, because the failure is a
server-side abort, not client-side cert validation. That is the first thing
anyone tries, and it wastes time.

Two working options:
- **`http://caddy:2019/config/`** (admin API, 200) — what is configured now
- `http://caddy:80` with **Max. Redirects = 0** and accepted codes
  `200-299,300-399`, so the 308 itself is the answer

Either only proves the Caddy process is alive. **Caddy's TLS path is already
monitored transitively** — `gitea`, `authelia`, `ntfy`, `proxmox`,
`prometheus-external` and `uptime-kuma` all probe `https://*.mati-lab.online`
and therefore traverse Caddy's TLS termination.

## Known issues (as of 2026-09-11 second pass)

All 50 active monitors are UP. Remaining items are tidies, not outages.

1. **4 names still carry a leading space**: ` jellyfin`, ` qbittorrent`,
   ` backup-dev-pc-restic`, ` backup-hermes-dump`, ` backup-nas-zfs-health`.
   They sort oddly and exact-name lookups miss them.
2. **`caddy` carries a stray `keyword=Ollama is running`** copy-pasted from
   `ollama-gpu`. Inert on HTTP type, but a landmine if the type ever changes.
   Same class of error as the old `qBittorrent` keyword on `litellm`.
3. **`obsidian-couchdb` has an inert `keyword=ok`** on an HTTP-type monitor.
   Harmless; the `["401"]` accepted-code is what actually makes it correct.
4. **`mati-gamer` is disabled and has no notification.** Fine while off;
   re-attach the notification if it is ever re-enabled.
5. **`hermes` keyword has no space** (`"status":"ok"`) while the observed body
   is `{"status": "ok", ...}`. It matches and is green — flagged only because
   if the serialisation ever changes, this is where it would break.

## Genuinely missing (verified 2026-09-11)

| Name | Why not yet |
|---|---|
| rag-watcher | **Push** monitor — needs a cron in the container to push first. Creating the monitor alone just yields a red light |
| promtail-nas | Same: needs an emitter before the monitor is meaningful |

**Deliberately not added:**

- **`homarr`** — verified **not deployed**: no container (not even stopped),
  nothing listening on 7575, and `network/homarr/` holds only `appdata/` and a
  `.env` with no compose file. The old gap list asked for a monitor on a
  service that does not exist.
- **`cloudflared`** — the suggested probe was
  `https://gitea.mati-lab.online/api/v1/version`, byte-for-byte what the
  `gitea` monitor already does. It adds no information and doubles the alert
  noise.

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
