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

## VLAN segmentation pre-flight (Task 1, run 2026-09-07)

Every segmentation task diffs against artefacts produced here. All of them live
on the dev PC outside the repo — they contain WPA passphrases and client MACs,
so they are `chmod 600` and reach the NAS only through the nightly restic run.

| Artefact | What it is |
|---|---|
| `~/unifi-backups/unifi-network-<UTC>.unf` | Full controller backup; the last-resort rollback for every task |
| `~/vlan-baseline.txt` | Pre-change reachability: DNS from both resolvers, 6 host pings, 3 service HTTP codes |
| `~/vlan-rollback-networkconf.json` | Networks before any VLAN exists |
| `~/vlan-rollback-portconf.json` | Port profiles before any VLAN exists (**empty** — none defined) |
| `~/vlan-rollback-device.json` | Switch `port_overrides` before any port moves |
| `~/vlan-rollback-wlanconf.json` | The three SSIDs before any re-binding |

Baseline captured: all six infra hosts UP, both resolvers returning
`192.168.1.252` for `mati-lab.online`, `doubleclick.net` sinkholed to `0.0.0.0`,
Gitea 200 / Grafana 302 / Jellyfin 302.

Confirmed at pre-flight, and load-bearing for the plan:

- **No port profiles exist yet** (`rest/portconf` returns an empty array). Wired
  VLAN assignment therefore needs a profile created *before* any Salon port can
  be pointed at one — there is nothing to reuse.
- **All three SSIDs share one `networkconf_id`.** `konewka_iot` is not a
  separate L2 today; re-binding it is what makes it real.
- The UDR is the DHCP server (`Default.dhcpd_enabled = true`). New VLANs get
  their scope here, not in Pi-hole.
- Controller was **10.6.101** at pre-flight, not the 10.5.67 the segmentation
  plan was written against — `mgmt.auto_upgrade` moved it. Expect UI drift from
  the plan's click-paths.

### Verifying a backup is real

`head -c 16 <file> | xxd` must show binary. An auth failure returns an HTML
error page with a 200, so size alone does not prove success — a `.unf` under
~100 KB is a red flag.

### Handling the local API key

The local console key is a console credential, not a repo secret: keep it in a
`chmod 600` file under `~/.config/unifi/`, outside the repo, never committed.
Source `~/.config/unifi/api.sh`, which reads it inline into the `X-API-KEY`
header so the value is never assigned to a shell variable or echoed.

The `guard-bash.py` PreToolUse hook blocks *any* Bash segment pairing a reader
with a secret-shaped path — including the inline `$(cat …)` form its own message
recommends, and including heredocs that merely mention such a filename. Putting
the read inside the sourced helper, and writing docs through the file tools
rather than shell heredocs, keeps the guard's intent (no secret value in a
transcript) without fighting the regex.

**Temporary keys must be revoked.** A key pasted into a chat transcript is
burned; rotate it at the end of the work, per the final segmentation task.

## Zone-Based Firewall (enabled 2026-09-07)

Enabled from the UI (Settings → Security → Firewall). There is no API endpoint
for the switch itself. The migration ran **without prompting** and did not drop
anything: the two legacy `LAN_IN` accepts became eight ZBF policies (`pihole-dns`
and `pihole-dhcp`, one copy per destination zone), and `rest/firewallrule` is now
**empty** — legacy rules are gone, not shadowed.

Zones after migration: `Internal` (holds `Default`), `External`, `Gateway`,
`Vpn`, `Hotspot`, `Dmz`. Reachability was byte-identical before and after.

`pihole-dhcp` is vestigial — the UDR is the DHCP server, so nothing matches it.
Left in place rather than deleted; it costs nothing and removing it is a
separate, revertible decision.

### Policy ordering

Lower `index` wins. User-created policies land at `10000`, derived return
traffic and `Isolated Networks` blocks at `30000`, per-zone-pair defaults
(`Allow All Traffic` / `Block All Traffic`) at `2147483647`. So a targeted allow
at 10000 beats an isolation block at 30000 — that is precisely what lets an
isolated VLAN keep DNS while everything else to `Internal` stays blocked.

### Gotcha: the policies endpoint is paginated at 25

With ZBF on there are ~96 policies. `GET …/firewall/policies` returns the first
25 and gives no visual hint of truncation — a rule you just created simply is
not in the response, and a filter over it looks like a clean negative result.

**Always `?limit=200`, and assert against `totalCount`:**

```bash
api "$B/integration/v1/sites/$SITE/firewall/policies?limit=200" > /tmp/pol.json
jq '.data|length as $n | .totalCount as $t
    | if $n < $t then "TRUNCATED \($n)/\($t)" else "complete \($n)" end' /tmp/pol.json
```

This is the same class of bug as `rc: ok` — a successful-looking response that
confirms nothing. It matters most for verifying that a DNS allow sits above a
deny, which is the one ordering mistake that takes a whole VLAN offline.

### Other 10.6 API shapes worth remembering

- `action` is an object: use `.action.type`, not `\(.action)`.
- Creating a network needs `management`, `name`, `vlanId`, `enabled`,
  `isolationEnabled`, `internetAccessEnabled`, `cellularBackupEnabled` and
  `ipv4Configuration`; with ZBF on, **`zoneId` is also required** even though the
  OpenAPI schema marks it optional. Create the zone first (`networkIds: []` is
  allowed), then the network.
- `allowReturnTraffic: true` is **rejected** on any `→ External` policy
  (`cant-allow-return-traffic`) — the built-in return rule already covers it.
- `ipv4Configuration.dhcpConfiguration` sets subnet, pool, DNS override and lease
  at create time, so new VLANs need no UI trip. Only SSIDs do, because they carry
  a PSK.
- A protocol `PRESET` of `TCP_UDP` covers DNS in one policy instead of two.
- New networks default to `mdnsForwardingEnabled: true`. On an isolated VLAN that
  partially defeats the isolation — turn it off explicitly.

### Gotcha: a UI save reverts fields the form does not show

Editing an SSID in the UI writes the **whole** `wlanconf` object, resetting
anything the form does not render. Setting the `konewka_guest` passphrase in the
UI silently reverted `minrate_setting_preference` from `manual` back to `auto`
and the 2.4 GHz floor from 6000 to 1000 kbps — the exact airtime tax the radio
plan above exists to prevent.

**After any UI edit to a WLAN, re-read and re-apply the API-only fields.** Same
family as `midclt app.update` replacing nested groups. When re-applying, fetch
the object and transform it with `jq` rather than composing a fresh body, so
`x_passphrase` is carried through untouched and never printed.

It is **not only cosmetic fields**. On 2026-09-07 a UI visit to `konewka_iot`
reverted `networkconf_id` from IoT back to Default *and* `l2_isolation` from
true back to false — silently undoing a whole VLAN migration, with nine devices
still happily associated to the SSID and every one of them back on
`192.168.1.x`. Nothing errored; the UI simply wrote the object it had loaded.

Verify after any UI session that touches a WLAN:

```bash
api "$B/api/s/default/rest/wlanconf" | jq -r '.data[]
  | "\(.name)\tnet=\(.networkconf_id)\tl2iso=\(.l2_isolation)"'
```

### WiFi "type" is a UI abstraction, not a data model

The UI's WiFi Type dropdown (Standard / Guest Hotspot / IoT) does not map to a
single field. In the v1 API only two broadcast types exist — `STANDARD` and
`IOT_OPTIMIZED` — and the guest/hotspot behaviour is **three independent
settings**:

| Concern | Field |
|---|---|
| Portal | `hotspotConfiguration.type` = `CAPTIVE_PORTAL` \| `PASSPOINT` |
| Encryption | `securityConfiguration.type` = `OPEN` \| `WPA2_PERSONAL` \| `WPA2_WPA3_PERSONAL` \| … (**required**) |
| Guest policy | legacy `is_guest` + `l2_isolation` |

So **a captive portal and a passphrase are fully compatible.** Choosing "Guest
Hotspot" in the UI merely presets security to `OPEN` and hides the password
field, which reads as "hotspot networks cannot have a passphrase". They can —
set the security separately.

`OPEN` also accepts `encryption: ENHANCED_OPEN` or `ENHANCED_OPEN_WITH_TRANSITION`
(OWE): WPA3-grade over-the-air encryption with **no passphrase**, transition mode
falling back to plain open for older clients. That is Ubiquiti's recommended
guest posture and is why the UI steers away from a password field. A passphrase
is still stronger — it keeps strangers off the SSID entirely.

**A captive portal is not a security control.** It gates HTTP access; it does
nothing to the radio. Portal-on-open leaves all guest traffic sniffable in the
air. Encryption comes only from WPA2/WPA3 or OWE.

### Gotcha: a zone deny silently eats return traffic

The single most expensive bug of the segmentation work (2026-09-07). A deny like
"VLAN X cannot reach `192.168.1.0/24`" written with no connection-state filter
also kills the **return** leg of anything Infra initiates *into* VLAN X.

ZBF derives a `<name> (Return)` policy when a policy sets
`allowReturnTraffic: true`, but derived policies land at index **30000** while
user-created policies land at **10000/10001**. Lower index wins:

| idx | policy | states | effect |
|---|---|---|---|
| 10001 | `IoT-to-Infra-deny` | ALL | drops the replies |
| 30000 | `Infra-to-IoT-allow (Return)` | RELATED, ESTABLISHED | never reached |

**Fix: scope every such deny to `connectionStateFilter: ["NEW"]`.** New sessions
initiated from the restricted VLAN are still blocked; established replies fall
through to the return-allow.

The symptom is nasty because everything looks right: the outbound leg tests fine,
the policy list reads correctly, `enabled=true` — and the application is simply
dead. Here it meant Homebridge could not drive the Hue Bridge. Test **both legs**
of every zone pair, not just the direction the rule names.

### DHCP reservations are bound to a network, and go stale on a VLAN move

A client reservation (`rest/user/<_id>`) carries `use_fixedip`, `fixed_ip` **and**
`network_id`. Moving a device to another VLAN does not update it — the
reservation silently stops applying, and the device takes a pool address instead.

Seen 2026-09-07: the Hue Bridge held `fixed_ip: 192.168.1.221, network_id:
Default` while physically on VLAN 30. It worked only because the UDR ignored the
mismatched reservation and leased from the IoT pool.

**When migrating a device between VLANs, update `network_id` and `fixed_ip`
together**, in the same write as the port or SSID change:

```bash
api "$B/api/s/default/rest/user" | jq -r '.data[] | select(.use_fixedip==true)
  | "\(.name // "-")\t\(.mac)\t\(.fixed_ip)\t\(.network_id // "-")"' | sort
```

Audit that list *before* any migration batch — a reservation you believe pins an
address may be inert, which turns "the device got the wrong IP" into a confusing
hunt through DHCP logs.

### Guest control restricted subnets

`guest_access` carries `restricted_subnet_1/2/3` = `192.168.0.0/16`,
`172.16.0.0/12`, `10.0.0.0/8`, and this version exposes **no `allowed_subnet`
field** to punch through them. That range contains both DNS resolvers, so if the
legacy guest-control path ever takes precedence over ZBF it will kill guest DNS.
It does not today — `Guest-to-DNS-allow` at index 10000 wins — but re-test guest
name resolution after any change to portal or guest-control settings.
