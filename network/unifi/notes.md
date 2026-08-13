# UniFi (UDR) — operational notes

The UniFi Dream Router is the LAN gateway, controller, and (partially) an AP.
It is a **product console**: prefer the UI for changes, but the local
Integration + legacy APIs are available and are what the audit below used.

## Topology

```
Netia ONT/router (double NAT — UDR WAN = 192.168.100.15, external 78.10.194.116)
└── UDR (Dream Router) 192.168.1.1 — gateway, controller, Protect, AP
     └── Szafa (USW Lite 8 PoE) 192.168.1.242
          ├── U6+ Gabinet 192.168.1.188      (AP)
          ├── Gabinet (USW Flex Mini) 192.168.1.105
          └── Salon (USW Lite 8 PoE) 192.168.1.171
               └── U6+ Salon 192.168.1.169   (AP)
```

Both U6+ are **wired**, not wireless-meshed. There is no mesh backhaul to tune —
AP-to-AP handoff is a *roaming* concern (802.11r/v), not a mesh one.

G5 Flex camera (192.168.1.243) is a Protect device on the same flat LAN.

## API access

Two different keys, two different scopes — they are not interchangeable:

| Key | Where created | Scope |
|---|---|---|
| Site Manager (cloud) | `unifi.ui.com` account | **Read-only** inventory + ISP metrics, via `https://api.ui.com/v1/*` with `X-API-KEY` |
| Local console | UI → Settings → Control Plane → Integrations | Read **and write** local config, via `https://192.168.1.1/proxy/network/...` |

A cloud key returns `401` against the local console and vice versa.

Local endpoints worth knowing:

- `/proxy/network/integration/v1/sites/<siteId>/...` — modern API. Supports
  networks, wifi broadcasts, firewall zones/policies, ACL rules, DNS policies.
  Schema at `/proxy/network/api-docs/integration.json`.
- `/proxy/network/api/s/default/rest/{wlanconf,networkconf,device,firewallrule,setting}`
  — legacy API. **Radio/channel config is only writable here**; the v1
  integration API has no radio endpoint.
- `/proxy/network/api/s/default/stat/{device,sta,health}` — live stats.
  `radio_table_stats[].tx_retries_pct` is the per-radio retry figure.

### Gotcha: the controller silently drops unknown/gated fields

A `PUT` can return `{"meta":{"rc":"ok"}}` and change **nothing**. Seen twice:

- `radio_table[].is_enabled` — not a supported way to disable a UDR radio.
- `minrate_ng_data_rate_kbps` — ignored until
  `minrate_setting_preference` is also set to `"manual"` (it defaults to
  `"auto"`, which overrides any explicit rate).

**Always re-read the object after a write.** `rc: ok` is not confirmation.

### Gotcha: configured ≠ operating

`radio_table` is the *configured* channel; `radio_table_stats` is what the radio
is *actually on*. They drift — a DFS radar event moves a radio without changing
config. After a radio write, force a provision and re-read:

```bash
curl -sk -X POST -H "X-API-KEY: $KEY" -H 'Content-Type: application/json' \
  -d '{"cmd":"force-provision","mac":"<device-mac>"}' \
  https://192.168.1.1/proxy/network/api/s/default/cmd/devmgr
```

## Backups

Config backup (all settings, no stats), written to `~/unifi-backups/` on the dev
PC, which is included in the nightly restic run to the NAS
(`compute/dev_pc/backup/restic-includes.txt`):

```bash
# 1. ask the controller to build one
curl -sk -X POST -H "X-API-KEY: $KEY" -H 'Content-Type: application/json' \
  -d '{"cmd":"backup","days":"0"}' \
  https://192.168.1.1/proxy/network/api/s/default/cmd/backup
# -> {"data":[{"url":"/dl/backup/<version>.unf"}]}

# 2. download it
curl -sk -H "X-API-KEY: $KEY" \
  https://192.168.1.1/proxy/network/dl/backup/<version>.unf \
  -o ~/unifi-backups/unifi-network-$(date -u +%Y%m%dT%H%M%SZ).unf
```

The `.unf` is AES-encrypted and **contains WPA passphrases** — never commit it,
and keep it only in the restic repo (which is itself encrypted). Verify a
download is real with `head -c 16 <file> | xxd`; an auth failure yields HTML.

The controller also self-backs-up monthly (`super_mgmt.autobackup_cron_expr`,
`30 0 1 * *`, Europe/Warsaw).

## Radio plan (set 2026-08-13)

Regulatory reality for EU/Poland: **only ch 36–48 is non-DFS** on 5 GHz.
Anything 52–144 is DFS and will be vacated on a radar detection, which shows up
as an unexplained Wi-Fi drop.

| AP | 2.4 GHz | 5 GHz |
|---|---|---|
| U6+ Gabinet | ch **1** @ 20 MHz | ch **36** @ 40 MHz |
| UDR (wardrobe, entry/bathroom fill) | ch **6** @ 20 MHz | ch **36** @ 20 MHz |
| U6+ Salon | ch **11** @ 20 MHz | ch **44** @ 40 MHz |

Rules encoded here:

- **Never 40 MHz on 2.4 GHz.** The band has only three non-overlapping 20 MHz
  channels (1/6/11); a 40 MHz channel consumes two of them. The previous config
  had UDR ch1@40 and Gabinet ch6@40 overlapping directly.
- **Never 160 MHz here.** A 160 MHz channel anchored at 36 or 44 spans 36–64,
  which (a) covers the whole non-DFS block so no second AP can be clean, and
  (b) drags in DFS 52–64. Gabinet was previously 160 MHz and Salon was
  *configured* on DFS ch132 but had been bumped down onto ch36, landing on top
  of Gabinet.
- The UDR keeps both radios on deliberately: it is in a wardrobe by the entry
  and covers a bathroom dead spot that neither U6+ reaches. Its 5 GHz overlaps
  Gabinet's lower half, which is an accepted trade — it is low-traffic and
  RF-attenuated inside the wardrobe.

## WLANs

| SSID | Band | Security | Notes |
|---|---|---|---|
| `konewka` | 2.4 + 5 | WPA2, PMF optional | Main SSID. 802.11r + 802.11v on. Carries almost everything, IoT included. |
| `konewka_iot` | 2.4 | WPA2, PMF **forced off** | Type `IOT_OPTIMIZED`. Nearly unused (1 client). PMF writes are silently rejected on this profile. |
| `konewka_5g` | 5 only | WPA2/WPA3 transition, PMF optional | Kept deliberately for the PlayStation Portal, to guarantee 5 GHz for Remote Play. 802.11r enabled 2026-08-13. |

All three have `minrate_setting_preference: manual` with a **6 Mbps floor** on
both bands. Previously 1 Mbps, which let beacons and management frames go out at
802.11b rates — a large, invisible airtime tax on every 2.4 GHz frame.

AP groups: `All APs` (default, includes UDR) carries `konewka` + `konewka_iot`.
`U6P-only` (created 2026-08-13) carries `konewka_5g`, keeping the redundant
5 GHz SSID off the UDR.

## Stability

`mgmt.auto_upgrade = true`, `auto_upgrade_hour = 3` — the UDR applies firmware
unattended at 03:00 and reboots, dropping every switch port at once. This is the
documented trigger for the Pi 5 `macb` NIC wedge (10.5 h outage 2026-06-19) —
see the postmortem in `network/ansible/notes.md`.

**Left enabled by explicit decision (2026-08-13):** `make netheal` on the Pi has
prevented recurrence, so the blast radius is bounded. Revisit if a wedge happens
again.

Other notes:

- **Double NAT.** UDR WAN is `192.168.100.15` behind the Netia router. Relevant
  to any port-forward or inbound VPN work.
- **UDR memory pressure.** 87.4% memory / load 1.55 on 2 GB RAM running Network
  + Protect + the G5 Flex camera. Matches the `status: controller` reboot reason
  seen in the postmortem alongside `status: firmware`.
- WAN itself is healthy: 24 h of ISP metrics showed 3.09 ms avg latency, 0%
  packet loss, 0 downtime, 282↓/365↑ Mbps flat.

## Security posture

- **Flat L2.** One corporate network (`Default`, 192.168.1.0/24). Camera, IoT,
  and every homelab server share a broadcast domain. Segmentation design lives
  in `docs/superpowers/specs/2026-08-13-network-segmentation-design.md` (local).
- **Zone-Based Firewall is not configured** — the gateway is still on legacy
  rules (only two, both `accept` for Pi-hole DNS/DHCP). ZBF is a prerequisite
  for the segmentation design.
- IPS is **on** in `ips` mode with 23,073 ET signatures across 13 categories.
- SSL inspection off; DoH `auto`.
- `konewka_iot` has `l2_isolation = false` and points at the same network as
  everything else — it is an IoT SSID in name only.
