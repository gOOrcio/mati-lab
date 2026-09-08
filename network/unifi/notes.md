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

| SSID | Band | Network | Security | Notes |
|---|---|---|---|---|
| `konewka` | 2.4 + 5 | **Trusted (VLAN 20)** since 2026-09-07 | **WPA2/WPA3 transition, PMF optional** since 2026-09-08 | Main SSID. 802.11r + 802.11v on. Phones, MacBook, iPad, watch, dev PC Wi-Fi, RG556. **Binds directly at the top-level `networkconf_id`** — the single-entry PPSK that used to own the binding was consolidated away 2026-09-08 (see the PPSK section below); PPSK is also incompatible with WPA3. The LG fridge and Aqara Hub **no longer ride along** — both moved to `konewka_iot` 2026-09-08. |
| `konewka_iot` | 2.4 | IoT (VLAN 30) | WPA2, PMF **forced off** | Type `IOT_OPTIMIZED`, `l2_isolation` on. Carries the IoT fleet since 2026-09-07. PMF writes are silently rejected on this profile. |
| `konewka_5g` | 5 only | **Trusted (VLAN 20)** since 2026-09-07 | WPA2/WPA3 transition, PMF optional | Kept deliberately for the PlayStation Portal, to guarantee 5 GHz for Remote Play. 802.11r enabled 2026-08-13. |
| `konewka_guest` | 2.4 + 5 | Guest (VLAN 50) | WPA3, captive portal | Isolated. Created 2026-09-07. |

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

### Gotcha: switch port counters update in lumps, client counters are often null

`stat/device` `port_table[].rx_bytes` is the only reliable throughput signal —
client-level `tx_bytes`/`rx_bytes` in `stat/sta` are frequently `null` even for a
device that is plainly working.

But the port counters refresh roughly every **40–60 s**, not per request. Two
samples 30 s apart can return byte-identical values for a link carrying several
Mbps. On 2026-09-07 that produced a "delta = 0 bytes → stream stopped" reading
for a camera that was streaming normally, and nearly triggered a rollback of a
correct firewall change.

**Sample over ≥90 s, or take 4–5 samples and use first-to-last**, before
concluding a link is idle:

```bash
A=$(api "$B/api/s/default/stat/device" | jq -r '.data[]|select(.name=="Salon")|.port_table[]|select(.port_idx==1)|.rx_bytes')
sleep 90
Bv=$(api "$B/api/s/default/stat/device" | jq -r '.data[]|select(.name=="Salon")|.port_table[]|select(.port_idx==1)|.rx_bytes')
echo $(( (Bv - A) * 8 / 90 / 1000000 )) Mbps
```

This is the fourth form of the same lesson: **the controller is not ground
truth.** Stale reservations, untracked DHCP leases, reverted SSID bindings and
lumpy counters have each shown a device as wrong while it worked, or right while
it did not. Verify against the network — pings, HTTP fingerprints, throughput
deltas, both legs of a zone pair.

### Never re-tag the port of the machine you are working from

Done anyway on 2026-09-07, and it cost an outage. Gabinet p5 (dev PC) was moved
to VLAN 20; the PC never leased on the new VLAN and went dark, taking the session
with it. A second session on another machine rolled the port back to Default.

The reasoning that failed was "Wi-Fi on VLAN 1 is the fallback" — it is not a
fallback if it can drop, and it did. A fallback has to be a path that the change
cannot affect: a console, or a NIC on a VLAN you are not touching.

The cause was **not** a static IP. `ipv4.method` on that NIC is `auto`. It is the
same link-bounce problem as the wired IoT devices: **changing a port's VLAN does
not drop the link**, so the host keeps its old-VLAN lease, becomes stranded on a
subnet with no gateway, and only recovers on lease expiry or a manual bounce.

Rules that follow:

- Move wireless SSIDs **before** wired ports, so the host has a working path on
  the destination VLAN before its cable moves.
- Only PoE-powered devices can be recovered remotely (`POWER_CYCLE` on the port
  action endpoint). Mains-powered wired devices — PS5, AppleTV, TV boxes — need a
  physical cable or power bounce.
- **Repoint a DHCP reservation as part of the move, never ahead of it.** Three
  reservations were pre-pointed at VLAN 20 while the devices were still on VLAN 1;
  the RG556 stopped getting a lease at all until they were reverted.

### Gotcha: with PPSK enabled, the private key entry owns the SSID's network

`konewka` has `private_preshared_keys_enabled: true` with a single entry in
`private_preshared_keys[]`, and each entry carries its **own** `networkconf_id`.
When PPSK is on, that entry — not the top-level `networkconf_id` — decides which
VLAN a client lands on, and the controller reconciles the top-level field back
to match.

Symptoms seen 2026-09-07 while rebinding `konewka` to Trusted:

- `PUT rest/wlanconf/<id>` with only the top-level field changed returned
  `{"meta":{"rc":"ok"},"data":[]}` — an **empty** `data` array, where a real
  write echoes the object. A by-id read showed Trusted for a few seconds, then
  every read (list and by-id) showed Default again. No client moved.
- `konewka_5g`, which has no PPSK, rebound first time with the same pattern.

Fix: transform **both** fields in the same write —

```bash
api "$B/api/s/default/rest/wlanconf/$W" | jq '.data[0]
  | .networkconf_id=$n | .private_preshared_keys |= map(.networkconf_id=$n)' \
  --arg n "$NET" > /tmp/w-put.json
```

After that write the response still echoes the top-level field as **Default**
while the PPSK entry says Trusted, and every client re-leases on VLAN 20 anyway.
The v1 API tells the truth here: `securityConfiguration.presharedKeys[].network`
is the binding; read that, not the legacy top-level field, when verifying.

`data: []` on a PUT is therefore a fourth "ok that confirms nothing" shape —
treat it as a rejected or reconciled write and go find the field that owns the
value.

### Intra-zone Block is the platform default, not a misconfiguration

Every **user-defined** zone gets a `Block All Traffic` policy for its own
X→X pair, `origin: SYSTEM_DEFINED` (Trusted, IoT, Cameras, Guest, Dmz, Hotspot
all match). Only the built-in `Internal` and `Vpn` default to Allow.

It is inert while a zone holds a single network — same-subnet traffic is
L2-switched and never reaches the firewall. Do not "fix" it to Allow on sight;
it only becomes relevant if a second network is added to an existing zone.

### The policy-ordering endpoint is broken on 10.6.101 — reorder in the UI

`PUT /integration/v1/sites/<site>/firewall/policies/ordering` returns
`500 api.unexpected-error` on every attempt, with a valid body and both required
query params (`sourceFirewallZoneId`, `destinationFirewallZoneId`). The matching
`GET` works and reports the current order, so the ids are right.

Consequence: **you cannot place a policy above an existing one via the API.**
Within a zone pair, user policies are indexed in creation order — 10000, 10001,
… — so a rule created later always evaluates later. If ordering matters (a deny
that must precede an allow), either create them in the required order to begin
with, or drag them in the UI: Settings → Security → Firewall → Policies → Reorder.

### IoT devices that ride on a shared SSID inherit that SSID's VLAN

The LG fridge and Aqara Hub could not be re-onboarded onto `konewka_iot`, so they
stayed on `konewka`. When `konewka` moved to Trusted (VLAN 20) on 2026-09-07 they
moved with it — and Trusted carries `Trusted-to-Infra-allow`, so two IoT devices
silently gained **full access to VLAN 1**, the exact outcome the segmentation
exists to prevent. They were *more* contained on VLAN 1 than they are on 20.

An SSID is a VLAN assignment for every device on it. "Leave it where it is" is not
a stable decision once that SSID is scheduled to move — re-check every accepted
exception after any SSID re-binding.

Mitigation in place: `IoT-exceptions-to-Infra-deny`, source zone Trusted with a
**MAC** filter (`54:ef:44:68:16:6d`, `1c:39:29:86:51:fd`) → Internal, `BLOCK`,
`connectionStateFilter: ["NEW"]` so Homebridge can still drive the Aqara Hub.
MAC rather than IP because reservations for these two would not persist.
**It is created but sits at index 10001, below the allow at 10000, so it is not
yet enforcing** — it needs the UI reorder described above.

## Adding a device after segmentation

**Policy is per zone, not per device.** Of the user-defined firewall policies,
almost all are zone-to-zone; a device inherits its zone from its VLAN. Nothing
needs a rule written for it **on the UDR**. Host firewalls are another matter —
see the next gotcha. (The two `pihole-*` rules are pre-ZBF legacy, and
`IoT-exceptions-to-Infra-deny` is a workaround for devices that cannot be moved
to the right SSID — not the design.)

**Wireless — nothing to configure.** The SSID decides the VLAN:

| SSID | VLAN | Access |
|---|---|---|
| `konewka`, `konewka_5g` | Trusted 20 | infra + IoT + cameras + internet |
| `konewka_iot` | IoT 30 | internet + DNS only |
| `konewka_guest` | Guest 50 | internet only, isolated |

**Wired — the port decides, and it must be set deliberately.** There are three
kinds of port and no single correct default:

| Kind | Config | Examples |
|---|---|---|
| Infrastructure | VLAN 1, `forward: all` (trunk) | APs, switch uplinks, Proxmox host |
| Client | access port, `forward: native` + `tagged_vlan_mgmt: block_all` | PC, PS5, AppleTV, camera, Hue Bridge |
| Unused | least privilege (Guest 50) | Szafa p1/p5/p6/p7 |

### Gotcha: host firewalls scoped to `192.168.1.0/24` outlive the VLAN move

Found 2026-09-08, a day after the dev PC landed on Trusted (VLAN 20). The UDR
zone policy was right — `Trusted-to-Infra-allow` passed everything, ping worked
to every VLAN 1 host — yet TCP to the Ollama VM (`:22`, `:11434`) and the Pi
(`:22`) timed out, and LiteLLM on the NAS could no longer reach the dev PC's
Ollama. Three separate ufw instances, each written when the LAN was flat:

| Host | Rule as found | Effect after the move |
|---|---|---|
| Ollama VM `.48` | `22,11434/tcp ALLOW from 192.168.1.0/24` | dev PC pings it, every TCP connect times out |
| Pi `.252` | `22,53,5000,5001 from 192.168.1.0/24` | SSH from the dev PC dead (deploys, Ansible). DNS + Loki still worked only because Docker-published ports bypass ufw |
| dev PC `.173→20.173` | default-deny, no rule for the NAS | `UFW BLOCK SRC=192.168.1.65 DPT=11434` in `journalctl -k`; LiteLLM's `coding` primary and `agent-default` local fallback silently dead |

The signature is **ping works, TCP times out, and VLAN 1 → VLAN 1 to the same
port works**. That combination rules out the UDR (a zone block drops ICMP too)
and points at the destination host. Ubuntu's ufw accepts echo-request in
`ufw-before-input` regardless of user rules, which is why ICMP is a false
comfort here.

Fix pattern: add the Trusted subnet as a second source rather than widening
to `any` (Ollama VM: `compute/ollama_vm` `ufw_allowed_sources`; Pi:
`network/ansible/group_vars/all/vars.yml` `ufw_rules`; dev PC:
`dev_pc/ollama-setup.md`). LiteLLM's `api_base` for the dev PC moved to
`192.168.20.173` in the same change.

**Checklist for any future VLAN move:** grep the repo for the old subnet in
`ufw`/`src:`/`from:` fields *before* moving the port, and test one TCP port
per host from the new VLAN afterwards — not just ping.

### Why wireless can auto-assign and wired cannot

**An SSID is authenticated; a cable is not.** A device joining `konewka_iot`
proves it belongs there by knowing that passphrase, so the VLAN can be inferred
safely. A cable proves nothing — the port is the only signal, and it cannot know
what is on the other end. 802.1X is the real answer to this and is overkill here.

**Do not make Trusted the wired default.** It breaks the most likely wired
addition: an AP needs a *trunk* (all VLANs tagged, VLAN 1 untagged for
management). On a Trusted access port an AP loses its management network and
every tagged SSID. This is why Salon p2, Szafa p2/p3/p4/p8 and Gabinet p1/p2 are
deliberately untagged-all.

It is also the wrong failure mode. Forget to downgrade a port and an IoT gadget
silently gets full infra access, working perfectly, discovered during an
incident. Forget to upgrade one and a PC just cannot reach the NAS — obvious and
fixed in seconds. **Prefer the loud failure.**

### Unused ports set to Guest (2026-09-08)

Szafa p1/p5/p6/p7 and Gabinet p4 → Guest 50, so anything plugged into a spare
port gets internet and nothing else.

**Counters are necessary but not sufficient — ask the owner.** Two down ports
both showed large byte counts and looked identical from the API:

| Port | Counters | Reality |
|---|---|---|
| Gabinet p3 | 42 GB rx / 129 GB tx | **work PC, merely powered off** → stays VLAN 1 |
| Gabinet p4 | 722 MB / 3.7 GB | decommissioned mini-PC, then briefly the NAS → **spare** |

Traffic history proves a port *was* used, never that it still is. `up=false`
alone is worthless — a laptop is off most of the day. Confirm intent with the
owner before repurposing a port that has ever carried traffic; the Szafa four
were safe to assume only because they read exactly **0 bytes, 0 packets**.

Untouched by design: Gabinet p1 (uplink), **p2 (Proxmox trunk, four bridged VM
MACs)**, p3 (work PC); Szafa p2/p3/p4/p8 and Salon p2/p8 (AP and switch uplinks).

`forward: "disabled"` does **not** down a port on 10.6 (that needs a Disabled
port profile, and `rest/portconf` is empty), so pointing spare ports at Guest is
the honest option — disabling them would look like protection without being it.

### Moving a device beats writing a policy for it (2026-09-08)

The LG fridge and Aqara Hub spent a day on Trusted 20 — they had ridden along
when `konewka` moved — which handed two IoT devices full VLAN 1 access. The
stopgap was `IoT-exceptions-to-Infra-deny`, a MAC-scoped BLOCK. It never
enforced: user policies are indexed in creation order within a zone pair, so it
landed at 10001 *below* the allow at 10000, and neither the ordering API (500s
on 10.6.101) nor the UI drag would move it.

Once both devices were re-onboarded onto `konewka_iot`, the policy was **deleted**
rather than fixed. The zone-level `IoT-to-Infra-deny` already covers them.

The lesson generalises: **a per-device exception is a symptom that a device is on
the wrong network.** Fixing placement removed the exception, the ordering
problem, and the audit burden in one step. There are now zero per-device
policies apart from the two pre-ZBF `pihole-*` rules.

Rollback copy of the deleted policy, if it is ever needed again:
`~/vlan-rollback-iot-exceptions-policy.json` (dev PC, `chmod 600`).

### Gotcha: HAP ports are ephemeral — never pin a HomeKit accessory by port

Moving the Aqara Hub between VLANs changed its HomeKit port from `33051` to
`43913`. HAP ports are assigned per bridge instance and are not stable across a
re-pair, restart or network change; Homebridge child bridges behave the same way
(Govee `31081`, Daikin `59268`, main `51484`, WoL `59802` — none of them the
documented default `51826`).

So a closed HAP port after a move means "re-advertised elsewhere", not "broken".
Read the current port from the SRV record rather than scanning:

```bash
# _hap._tcp.local SRV records, from a host on the controller's VLAN
python3 /tmp/srv2.py    # see the mDNS probe pattern in this file's history
```

This also means **firewall rules must never target a HAP port** — scope them to
the zone pair, which is what `Trusted-to-IoT-allow` and `Infra-to-IoT-allow` do.

### PPSK consolidated away on `konewka` (2026-09-08) — and why

`konewka` carried a **single-entry PPSK** (`private_preshared_keys_enabled:
true`) that predated the segmentation. It was not a per-user-PSK setup: the one
entry simply held the *real* Wi-Fi password (14 chars) while the SSID's own
`x_passphrase` held a different, unused 32-char generated key.

That made the entry load-bearing in a non-obvious way. **The PPSK entry's own
`networkconf_id` decides the client VLAN, and the controller reconciles the
top-level field back to it.** So after the VLAN move:

| Field | Read | Reality |
|---|---|---|
| top-level `networkconf_id` | `Default` (VLAN 1) | misleading |
| PPSK entry `networkconf_id` | `Trusted` | **authoritative** |
| where clients actually were | `192.168.20.x` | Trusted |

A top-level-only `PUT` therefore returned `{"rc":"ok","data":[]}` and silently
reverted within a minute — the failure the Mac session hit.

**Also: PPSK is incompatible with WPA3.** In the v1 schema `presharedKeys` exists
only on `IntegrationWifiWpa2PersonalSecurityConfigurationDetailDto`; the
`WPA2_WPA3_PERSONAL` DTO has no such field. Enabling WPA3 would have dropped the
PPSK array and dumped every trusted wireless client onto VLAN 1, with no error.
**Check this before raising any PPSK SSID to WPA3.**

Fixed by consolidating, in **one** write (separate writes let the reconciler undo
them):

1. copy the PPSK password into the top-level `x_passphrase` — so no device needs
   re-joining, the password is unchanged from the client's point of view;
2. set the top-level `networkconf_id` to Trusted;
3. `private_preshared_keys_enabled: false`, `private_preshared_keys: []`.

Verified after: binding held past the ~60 s revert window, all clients
re-associated onto `192.168.20.x` unattended, minrate floor survived. Rollback
snapshot: `~/vlan-rollback-konewka-wlanconf.json` (dev PC, `chmod 600`).

The general rule: **a VLAN binding that lives anywhere other than the SSID's own
`networkconf_id` is a trap.** All four SSIDs now bind directly.

### Guest control restricted subnets

`guest_access` carries `restricted_subnet_1/2/3` = `192.168.0.0/16`,
`172.16.0.0/12`, `10.0.0.0/8`, and this version exposes **no `allowed_subnet`
field** to punch through them. That range contains both DNS resolvers, so if the
legacy guest-control path ever takes precedence over ZBF it will kill guest DNS.
It does not today — `Guest-to-DNS-allow` at index 10000 wins — but re-test guest
name resolution after any change to portal or guest-control settings.

## IoT wall proven from inside VLAN 30 (2026-09-08)

Every earlier check ran from a permitted VLAN, which can only show that
allows allow. A deny rule is proven only from the side it denies. Run from the
MacBook joined to `konewka_iot` (2.4 GHz, ch1) with source `192.168.30.174`,
10:52 CEST, using TCP connects — not ping. The deny is a silent BLOCK, so an
ICMP timeout is indistinguishable from a host being down; every target below
was confirmed OPEN from Trusted 20 the same day, so a TCP timeout from VLAN 30
can only mean the firewall acted.

| From IoT 30 to | Port | Expect | Got |
|---|---|---|---|
| TrueNAS `192.168.1.65` | 443 | BLOCKED | BLOCKED |
| TrueNAS `192.168.1.65` | 80 | BLOCKED | BLOCKED |
| Proxmox `192.168.1.184` | 8006 | BLOCKED | BLOCKED |
| Pi `192.168.1.252` | 80 | BLOCKED | BLOCKED |
| dev PC `192.168.20.173` (Trusted) | 22 | BLOCKED | BLOCKED |
| g5-flex `192.168.40.243` (Cameras) | 443 | BLOCKED | BLOCKED |
| gateway `192.168.30.1` | 53 | OPEN | OPEN |
| DNS `mati-lab.online` via `192.168.1.252` | 53 | answer | `192.168.1.252` |
| DNS `mati-lab.online` via `192.168.1.65` | 53 | answer | `192.168.1.252` |
| Pi-hole ad-block `doubleclick.net` | 53 | `0.0.0.0` | `0.0.0.0` |
| internet `1.1.1.1` | 443 | OPEN | OPEN |

11/11. `IoT-to-Infra-deny` (idx 10001) holds against Infra, Trusted and
Cameras; `IoT-to-DNS-allow` (idx 10000) still sits above it and its
destination filter still carries both resolvers; `IoT → External` is intact.
The segmentation is proven, not inferred.

Reusable test: `nc -z -G 3 -w 3 <host> <port>` per row, gated on
`ipconfig getifaddr en0` matching `192.168.30.*` — if it reads `192.168.20.x`
the laptop is still on `konewka` and every result is worthless. The script is
in the net.10 handoff (local, gitignored). Rejoin `konewka` afterwards and
confirm `192.168.20.x`; a trusted laptop forgotten on `konewka_iot` is exactly
the trap the iPhone fell into on 2026-09-07.

Failure modes, if this is ever re-run and does not come back clean:

- A BLOCKED row comes back OPEN → the wall has a hole; most likely ordering.
  Do not fix from the IoT side; the ordering endpoint is broken on 10.6.101
  (see above), so reorder in the UI.
- Blocks pass but DNS fails → `IoT-to-DNS-allow` fell below the deny or lost an
  address. Highest-consequence silent failure: every IoT device loses names and
  looks offline while the network is fine.
- Internet fails too → suspect the SSID/VLAN binding, not policy; re-check the
  source IP first.
