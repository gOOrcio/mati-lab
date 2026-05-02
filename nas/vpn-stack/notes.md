# vpn-stack (NAS)

TrueNAS Custom App with **four** services sharing one network namespace:
**Gluetun** (ProtonVPN WireGuard tunnel + killswitch) acts as the gateway
for **qBittorrent**, **Prowlarr**, and **FlareSolverr**. Installed
2026-05-01 to bypass UniFi's content-filter MITM (which was returning
`203.0.113.250` with a self-signed cert for blocked torrent indexer
domains) and to shield torrent traffic from ISP visibility.

FlareSolverr was originally a separate Custom App but **had to be
absorbed into vpn-stack** because Cardigann's 2-stage flow
(FlareSolverr-solves-challenge → Prowlarr-refetches-with-cookies)
requires both stages to use the **same egress IP**. With FlareSolverr
on the host's LAN IP and Prowlarr behind ProtonVPN's Swiss exit,
Cloudflare's session cookies issued to one IP got rejected when
presented from the other. Sharing Gluetun's namespace means both
stages exit through the same Swiss VPN IP → cookies stay coherent →
Cloudflare-protected indexers (EZTV, etc.) work cleanly.

Closes followup [`2.r.2`](../../docs/followups.md).

## Endpoints

| Service | LAN URL | Caddy URL | Auth |
|---|---|---|---|
| qBittorrent | `http://192.168.1.65:30024` | `https://qbit.mati-lab.online` | LAN bypass + Authelia 2FA externally |
| Prowlarr | `http://192.168.1.65:30025` | `https://prowlarr.mati-lab.online` | External (Authelia 2FA) + LAN-disabled |
| Gluetun control API | `http://192.168.1.65:8000` | (none — internal monitoring only) | none |

The published ports are on the **gluetun** container; qBit and Prowlarr
share its network namespace via `network_mode: service:gluetun`.

## Architecture

```
Internet
   ↑
   │ WireGuard tunnel (ProtonVPN, Switzerland)
   │
gluetun container (NET_ADMIN, /dev/net/tun)
   │  Killswitch ON.
   │  Bypasses VPN for: 192.168.1.0/24 (LAN), 172.16.0.0/12 (Docker bridges)
   │  All other egress goes through the VPN tunnel.
   │  DNS: cloudflare DoT (built-in to Gluetun) — bypasses UniFi resolver.
   │
   ├── qbittorrent (network_mode: service:gluetun)
   │     /config  → /mnt/fast/databases/qbittorrent-config (bind)
   │     /downloads → /mnt/bulk/data/torrents (bind, unchanged from pre-VPN)
   │
   └── prowlarr (network_mode: service:gluetun)
         /config  → /mnt/fast/databases/prowlarr/config (bind)
         DOTNET_SYSTEM_NET_DISABLEIPV6=true
```

### Why `FIREWALL_OUTBOUND_SUBNETS` matters

- `192.168.1.0/24` — Sonarr/Radarr API calls Prowlarr at `192.168.1.65:30025`. **Prowlarr's outbound replies need to go LAN-direct, not through the VPN.** Without this subnet allowed, Prowlarr's "Sync App Indexers" + Sonarr/Radarr → Prowlarr searches break silently.
- `172.16.0.0/12` — TrueNAS's docker bridges (e.g. `172.16.14.0/24` for sonarr, `172.16.15.0/24` for radarr). Same reason as above for cross-bridge traffic.

Public-internet traffic (torrent peers, Prowlarr → 1337x.to/Nyaa.si/etc.) goes through the VPN.

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Gluetun env (WireGuard private key) | Bind file | `/mnt/fast/databases/vpn-stack/.env` (root:root 0600) → `/run/secrets/...` (env_file) |
| qBittorrent config | Bind | `/mnt/fast/databases/qbittorrent-config` → `/config` |
| qBittorrent downloads | Bind | `/mnt/bulk/data/torrents` → `/downloads` |
| Prowlarr config | Bind | `/mnt/fast/databases/prowlarr/config` → `/config` |

Note: qBit's config path **changed** during this migration. Pre-vpn-stack
it was a TrueNAS-managed `ixVolume` at
`/mnt/.ix-apps/app_mounts/qbittorrent/config/`. The migration script
copies content out to `/mnt/fast/databases/qbittorrent-config/` (bind
mount, survives Custom App deletes). See `nas/qbittorrent/notes.md` for
the migration trace.

## Credentials

| Item | Where | PM label |
|---|---|---|
| ProtonVPN account | proton.me login | `homelab/protonvpn/account` |
| WireGuard config (full `.conf`) | regenerated in Proton UI per device | `homelab/protonvpn/wireguard-config-vpn-stack-nas` |
| WireGuard private key | NAS `/mnt/fast/databases/vpn-stack/.env` `WIREGUARD_PRIVATE_KEY=` (root:root 0600) | `homelab/protonvpn/wireguard-private-key` |

## Rotation procedure (WireGuard private key)

1. ProtonVPN web UI → VPN → WireGuard configuration → delete the old
   `vpn-stack-nas` config and Create a new one (same name, same options).
2. Copy the new `PrivateKey` value.
3. Update PM rows.
4. Stage on NAS (root sudo):
   ```bash
   ssh -t truenas_admin@192.168.1.65 'sudo install -m 0600 -o root -g root /dev/stdin /mnt/fast/databases/vpn-stack/.env <<<"WIREGUARD_PRIVATE_KEY=$NEW_KEY"'
   ```
5. Redeploy Gluetun:
   ```bash
   ssh truenas_admin@192.168.1.65 'midclt call -j app.redeploy vpn-stack'
   ```
6. Verify within ~30 s:
   ```bash
   curl -fsS http://192.168.1.65:8000/v1/publicip/ip
   ```
   Expected: `public_ip` is a Swiss IP (NOT your home IP). Containers
   inside the namespace see VPN egress only.

## Verification post-deploy

```bash
# 1. Public IP from inside the tunnel
curl -fsS http://192.168.1.65:8000/v1/publicip/ip | python3 -m json.tool
#    Expect: "public_ip": "<some Swiss IP>", "country": "Switzerland"

# 2. qBittorrent reachable on host port (gluetun-published)
curl -fsS -o /dev/null -w 'qbit=%{http_code}\n' http://192.168.1.65:30024/api/v2/app/version
#    Expect: 200

# 3. Prowlarr reachable on host port (gluetun-published)
curl -fsS -o /dev/null -w 'prowlarr=%{http_code}\n' http://192.168.1.65:30025/login
#    Expect: 200

# 4. Prowlarr can reach Sonarr (LAN traffic SHOULD bypass VPN per
#    FIREWALL_OUTBOUND_SUBNETS):
#    Prowlarr UI → Settings → Apps → Sonarr → Test → green
#    Or hit Prowlarr's /api/v1/applications/test endpoint with the existing
#    Sonarr application config.

# 5. Indexer test through VPN (should now succeed where it failed today):
#    Prowlarr UI → Indexers → Nyaa.si → click gear → Test → green
```

If step 1 returns your home IP, the tunnel didn't establish — check
Gluetun's container logs (`midclt call container.logs gluetun ...` or via
TrueNAS UI) for WireGuard handshake errors. Most common cause:
WIREGUARD_PRIVATE_KEY mismatch or stale Proton-side config.

## Killswitch behavior

Gluetun blocks all egress except via the VPN tunnel. If the WireGuard
peer fails:

- qBittorrent: connections drop, torrents stall but stay listed (will
  resume on tunnel re-establishment).
- Prowlarr: indexer searches return errors. Sonarr/Radarr → Prowlarr
  calls keep working (LAN, bypassed) but get empty search results.
- LAN access to qBit/Prowlarr UIs keeps working (host port mapping is
  unaffected by tunnel state).

Acceptable: failures are loud, no silent data leakage, recovery is
automatic on tunnel restore.

## Monitoring

- **Uptime Kuma**:
  - Existing `qbittorrent` + `prowlarr` HTTP monitors stay on
    `192.168.1.65:30024/30025` — no changes needed. **Important
    indirect property:** qBit and Prowlarr share Gluetun's network
    namespace (`network_mode: service:gluetun`); if Gluetun's
    container exits, the entire namespace tears down and both
    monitors flip red simultaneously. So the existing monitors
    cover Gluetun-container-down failure mode for free.
  - `gluetun-vpn-tunnel` (deferred — see "Auth on Gluetun's control
    API" below). Would have detected: tunnel handshake failed even
    while container is "up". Skipped for now because Gluetun v3.40+
    requires API-key auth on the control server, and our LAN-only
    Kuma can't easily authenticate. Workaround documented below.
- **Promtail**: auto-scrapes `ix-vpn-stack-{gluetun,qbittorrent,prowlarr}-*`.
  Useful for WireGuard handshake diagnosis.

## Auth on Gluetun's control API (deferred)

Gluetun v3.40+ requires API-key auth on every control-server route
(port 8000). Without auth, `GET /v1/publicip/ip` returns 401, which
means Uptime Kuma can't probe it for tunnel-leak detection.

The fix is committed but not deployed: `nas/vpn-stack/auth.toml`
exposes `GET /v1/publicip/ip` without auth (LAN-only, read-only —
safe). Mutating endpoints stay default-deny. **To activate:**

1. Stage the file via sudo (root-owned bind mount):
   ```bash
   scp nas/vpn-stack/auth.toml truenas_admin@192.168.1.65:/tmp/auth.toml
   ssh -t truenas_admin@192.168.1.65 'sudo install -m 0644 -o root -g root /tmp/auth.toml /mnt/fast/databases/vpn-stack/auth.toml && rm /tmp/auth.toml'
   ```
2. Re-edit `nas/vpn-stack/app-config.json` to add the bind mount on
   gluetun + the env var:
   ```json
   "environment": {
     ...,
     "HTTP_CONTROL_SERVER_AUTH_CONFIG_FILEPATH": "/auth/config.toml"
   },
   "volumes": [
     {"type": "bind", "source": "/mnt/fast/databases/vpn-stack/auth.toml", "target": "/auth/config.toml", "read_only": true}
   ]
   ```
3. `app.update vpn-stack` with the new config.
4. Verify: `curl http://192.168.1.65:8000/v1/publicip/ip` returns 200
   with `{"public_ip":"...","country":"Switzerland",...}`.
5. Add the `gluetun-vpn-tunnel` Kuma monitor:
   HTTP-Keyword on the same URL, keyword `public_ip`.

**Cost of deferring**: less direct tunnel-leak detection. The qBit
"firewalled / not firewalled" status (visible in qBit UI) and the
indirect monitors above are sufficient for normal operation.

## Backups

- Gluetun: stateless, nothing to back up.
- Prowlarr: existing `arr-config-backup.sh` API-issued ZIP works
  unchanged (the script hits Prowlarr's API at the same NodePort 30025).
- qBittorrent: settings + WebUI password are in
  `/mnt/fast/databases/qbittorrent-config/qBittorrent/qBittorrent.conf`;
  resume data in `BT_BACKUP/`. Covered by ZFS daily snapshot on
  `fast/databases` (Phase 7 task 12/13).

## Restore (after NAS rebuild)

1. Generate fresh ProtonVPN WireGuard config (or restore existing one
   from PM).
2. Stage `/mnt/fast/databases/vpn-stack/.env` on the new NAS:
   ```bash
   sudo install -m 0600 -o root -g root /dev/stdin /mnt/fast/databases/vpn-stack/.env <<<"WIREGUARD_PRIVATE_KEY=$KEY"
   ```
3. Restore qBit config (from ZFS snapshot rollback or backup) to
   `/mnt/fast/databases/qbittorrent-config/` (chown 568:568).
4. Restore Prowlarr config (from `arr-config-backup` API ZIP) to
   `/mnt/fast/databases/prowlarr/config/`.
5. `app.create vpn-stack` from `nas/vpn-stack/app-config.json`.
6. Wait for Gluetun's healthcheck to pass.
7. Verify per "Verification post-deploy" above.

## VPN port forwarding (NAT-PMP)

ProtonVPN supports NAT-PMP on its WireGuard servers and gluetun
auto-detects the forwarded port. We wire that port into qBit's
`listen_port` so qBit becomes connectable inside the tunnel — fixing
the "Downloading metadata ∞" stalls on sparse swarms (which happen
because passive peers can't accept inbound connections from us).

Closes followup [`2.r.3`](../../docs/followups.md).

### Architecture

```
gluetun
  │   on tunnel up + every NAT-PMP renewal (~45s):
  │     calls VPN_PORT_FORWARDING_UP_COMMAND
  │     → /scripts/qbit-update-port.sh <port>
  │       → wget POST localhost:30024/api/v2/app/setPreferences
  │         {listen_port: <port>, random_port: false, upnp: false}
  │
  └── qbittorrent (same netns)
        listen_port now matches the gluetun-forwarded port
        → inbound peer connections succeed → not firewalled
```

The script runs inside gluetun's busybox shell. `localhost:30024`
reaches qBit because they share the network namespace.

### One-off prereqs

1. **Regenerate the ProtonVPN WireGuard config with port-forwarding
   enabled.** In Proton's web UI → VPN → WireGuard configuration →
   delete the `vpn-stack-nas` config and create a new one with the
   "NAT-PMP (Port Forwarding)" toggle **ON**. The generated config's
   peer name will end with `+pmp` (e.g.
   `vpn-stack-nas+pmp-...`). Copy the new `PrivateKey`. Without the
   `+pmp` modifier, ProtonVPN rejects NAT-PMP requests at the gateway
   and `VPN_PORT_FORWARDING` will log retry loops with no port granted.

2. **Update PM** rows under `homelab/protonvpn/wireguard-config-vpn-stack-nas`
   and `.../wireguard-private-key`. Stage the new key on the NAS (same
   procedure as the rotation runbook above).

3. **qBit: bypass auth on localhost.** The script POSTs to qBit's API
   without credentials. Enable it once via qBit UI:
   `Tools → Options → Web UI → [x] Bypass authentication for clients on localhost`
   then **Save**. Verifiable in `qBittorrent.conf`:
   `WebUI\LocalHostAuth=false`. Without this, the script's POST returns
   401 and the listen_port stays stale.

4. **Stage the script bind-mount target** on the NAS:
   ```bash
   ssh truenas_admin@192.168.1.65 \
     'sudo install -d -m 0755 -o root -g root /mnt/fast/databases/vpn-stack/scripts'
   scp nas/vpn-stack/scripts/qbit-update-port.sh \
     truenas_admin@192.168.1.65:/tmp/qbit-update-port.sh
   ssh -t truenas_admin@192.168.1.65 \
     'sudo install -m 0755 -o root -g root /tmp/qbit-update-port.sh \
        /mnt/fast/databases/vpn-stack/scripts/qbit-update-port.sh \
      && rm /tmp/qbit-update-port.sh'
   ```

5. **Apply the new app-config.json** (`VPN_PORT_FORWARDING=on` +
   script bind-mount):
   ```bash
   ssh truenas_admin@192.168.1.65 \
     'midclt call -j app.update vpn-stack "$(cat /tmp/app-config-values.json)"'
   ```
   Or simpler: redeploy fully via `app.delete` + `app.create` if
   `app.update` doesn't pick up the new `volumes` entry on gluetun
   (TrueNAS sometimes gates compose-level changes through full
   recreate). State is in bind mounts, so recreate is safe.

### Verification

```bash
# 1. Gluetun got a forwarded port from Proton
ssh truenas_admin@192.168.1.65 \
  'docker exec ix-vpn-stack-gluetun-1 cat /tmp/gluetun/forwarded_port'
#    Expect: a port number (e.g. 54321), not empty

# 2. qBit's listen_port matches
curl -s http://192.168.1.65:30024/api/v2/app/preferences \
  | python3 -c 'import json,sys;p=json.load(sys.stdin);print("listen_port=",p["listen_port"])'
#    Expect: same port as step 1

# 3. qBit reports "Connection status: Connected" (not "Firewalled")
#    Check qBit UI bottom-left corner. If still "Firewalled" 60s after
#    deploy, gluetun container logs will show NAT-PMP retry errors.

# 4. Stalled metadata torrents resume
#    Re-add a fresh magnet → "Downloading metadata" should clear in
#    seconds-to-minutes, not stall indefinitely.
```

### Operational notes

- **Port changes on every NAT-PMP renewal** (Proton renews every ~45s
  internally; the public-facing port itself rotates only when the
  tunnel re-establishes or Proton's gateway cycles). Each change
  re-runs the up-command, idempotently re-setting qBit's listen_port.
- **Don't expose the forwarded port at the docker level.** Inbound
  peer traffic arrives on gluetun's tunnel interface, which gluetun
  iptables-forwards into the shared netns based on destination port —
  no `published` port mapping needed (and adding one would only expose
  the port on the NAS LAN, which we don't want).
- **Killswitch interaction:** if the tunnel drops, qBit can't reach
  peers (correct — that's the point). When the tunnel re-establishes
  and a new port is granted, the up-command fires and qBit picks the
  new port up automatically.
- **Multiple-clients risk:** only qBit listens on the forwarded port.
  Don't add a second peer-listening service to the namespace without
  picking a different scheme (e.g. running its own NAT-PMP client).

## Admin tips

- **Server hop**: change `SERVER_COUNTRIES` env var (or set
  `SERVER_HOSTNAMES` for a specific server) and `app.redeploy
  vpn-stack`. Public IP changes within 30 s.
- **Proton outage**: Gluetun retries; in extreme cases fall back to
  another country by editing env. Proton's status: `status.proton.me`.
- **Don't expose the Gluetun control API (8000) externally** — it
  reveals tunnel state and could leak the public-IP info. LAN-only.
