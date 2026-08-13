# pihole2 (NAS Custom App) — DNS secondary

Second Pi-hole, running on the NAS, serving as the **`dns2` handed out by UDR
DHCP**. Deployed 2026-08-13.

## Why this exists

UDR DHCP used to hand out `dns1 = 192.168.1.252` (Pi-hole) and
`dns2 = 1.1.1.3` (Cloudflare). Clients do **not** treat a secondary resolver as
failover-only — they query whichever answers, often in parallel. That meant:

1. **Pi-hole filtering was silently bypassed** for a share of every client's
   queries.
2. **`*.mati-lab.online` split-horizon resolution was intermittent.** A client
   asking `1.1.1.3` got the *public* answer instead of the internal
   `192.168.1.252`, which is a strong candidate for any "works, then randomly
   doesn't" behaviour with internal services.

Deleting `dns2` outright wasn't right either — the Pi has a documented outage
history (see the `macb` wedge postmortem in `network/ansible/notes.md`), and a
single resolver means Pi down = no DNS for the house. So: a **second local
resolver with full parity**, keeping redundancy without the bypass.

## Config

- App name `pihole2`, `app-config.json` per `feedback_truenas_custom_app_via_midclt`.
- Image `pihole/pihole:2025.11.1` — same tag as the Pi, so behaviour matches.
- Data at `/mnt/fast/databases/pihole2/{etc-pihole,etc-dnsmasq.d}`.
- `.env` (mode 0600) holds `FTLCONF_webserver_api_password`, generated at
  deploy. Also store it in the password manager as `homelab/pihole2/admin`.
- Runs as **root** (not 568) with the same capability set as the Pi's compose —
  Pi-hole needs `NET_ADMIN`/`NET_RAW` and binds port 53 internally.

### Gotcha: port 53 must bind a specific host IP

The NAS **already has port 53 in use** — TrueNAS's apps bridge listens on
`10.142.24.1:53` (and an IPv6 ULA). A bare `53:53` publish binds `0.0.0.0` and
collides with it. The ports block therefore pins the host IP:

```json
{"mode": "host", "protocol": "tcp", "host_ip": "192.168.1.65", "published": 53, "target": 53}
```

`192.168.1.65:53` itself was verified free before deploy.

## Endpoints

- **DNS**: `192.168.1.65:53` (tcp + udp)
- **Admin UI**: `http://192.168.1.65:30053/admin` — LAN only, no Caddy vhost.

## Parity verification

Run this from any LAN host after changes. Both columns must agree:

```bash
for q in mati-lab.online gitea-ssh.mati-lab.online wpad.mati-lab.online doubleclick.net; do
  printf '%-28s NAS=%s PI=%s\n' "$q" \
    "$(dig +short @192.168.1.65 "$q" | tr '\n' ' ')" \
    "$(dig +short @192.168.1.252 "$q" | tr '\n' ' ')"
done
```

Expected: `mati-lab.online` → `192.168.1.252`; `gitea-ssh.mati-lab.online` →
`192.168.1.65`; `wpad.mati-lab.online` → NXDOMAIN; `doubleclick.net` →
`0.0.0.0`. Verified matching at deploy time.

## Drift and sync

The two instances **will** drift if you allowlist a domain or add a local DNS
record in one UI and not the other — which reproduces the exact intermittent
bug class this whole change was meant to kill.

`nebula-sync` handles it, and runs **on the Pi**, not here: the Pi's Pi-hole
publishes only port 53, so its admin API is reachable only inside the
`pihole-net` Docker bridge (and via Caddy behind Authelia). Running the syncer
on the Pi lets it read the primary at `http://pihole:8080` internally and push
to this replica at `http://192.168.1.65:30053` over the LAN — with no new
exposure of the primary's API.

See `network/nebula-sync/`. Hourly at :17, `FULL_SYNC=true`.

**Consequence:** treat the **Pi as the source of truth**. Make config changes
there; this replica gets overwritten on the next sync.

## Update / restart / remove

| Action | Command |
|---|---|
| Restart | `midclt call -j app.redeploy pihole2` |
| Image bump | Edit tag in `nas/pihole2/app-config.json`, then `midclt call -j app.update pihole2 ...` (replaces compose — see `feedback_truenas_app_update_replaces`) |
| Logs (Loki) | `{container=~"ix-pihole2-.*"}` |
| Remove | `midclt call -j app.delete pihole2` — **first** set UDR `dhcpd_dns_2` back, or clients keep pointing at a dead resolver |

Note: `truenas_admin` has **no Docker socket access**, so `docker exec` into
this container fails. Use the Pi-hole HTTP API on `:30053` or `midclt` instead.

## Related

- UDR DHCP config: `network/unifi/notes.md`
- Primary Pi-hole: `network/pihole/`
- Sync service: `network/nebula-sync/`
