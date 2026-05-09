# nas-docker-proxy

Read-only Docker API surface, exposed on `192.168.1.65:2375`. The Pi's Homepage
container reads it to enumerate NAS Docker containers for label-driven
auto-discovery. **Read-only** — all write paths denied at the proxy.

## Lockdown profile

- All write env vars explicitly `0` (`POST`, `EXEC`, `VOLUMES`, `BUILD`,
  `COMMIT`, `IMAGES_DELETE`, `SWARM`, `SECRETS`, `SERVICES`, `TASKS`,
  `PLUGINS`, `NODES`, `SESSION`, `DISTRIBUTION`, `SYSTEM`, `AUTH`, `CONFIGS`).
- Allowed reads: `CONTAINERS`, `IMAGES`, `INFO`, `NETWORKS`, `VERSION` only.
- Container is `read_only: true` with tmpfs at `/run` (only the haproxy runtime
  socket needs to be writable).
- `docker.sock` mounted `:ro`.
- Bound to `192.168.1.65` (NAS LAN IP), not `0.0.0.0` — single-interface exposure.
- Source-IP allowlisted to `192.168.1.252/32` (the Pi). See "Source IP
  allowlist" below for the enforcement mechanism actually used (recorded after
  initial deploy).
- `user: "0:999"` — UID 0 inside the container is needed for the privileged-port
  bind, GID 999 = NAS docker group. **Verify GID before deploy** with
  `ssh root@192.168.1.65 'getent group docker'` and adjust if different.

## Source IP allowlist

Initial deploy will try, in order:

1. **TrueNAS Scale 25.x app-level source-IP restriction** if the chart UI
   exposes a "Container Configuration → Allowed IPs" / "Source IP" field.
2. **Host-level nftables rule on the NAS** if (1) is not first-class:

   ```bash
   ssh root@192.168.1.65 "nft 'add rule inet filter input tcp dport 2375 ip saddr != 192.168.1.252 drop'"
   # persist:
   ssh root@192.168.1.65 "nft list ruleset > /etc/nftables.conf"
   ```

Verification (run AFTER allowlist applied):

```bash
# from dev PC (NOT the Pi) — should fail/timeout:
curl --max-time 3 -s http://192.168.1.65:2375/version || echo "BLOCKED — good"

# from the Pi — should return JSON:
ssh gooral@192.168.1.252 "curl -s http://192.168.1.65:2375/version | jq -r '.Version'"
```

## Backup

Stateless — nothing to back up. Re-creating the app from `app-config.json` is
the recovery path.

## Health monitor

Uptime-Kuma HTTP monitor: `http://192.168.1.65:2375/_ping` — expects 200 with
body `OK`. Probe runs from the Pi (Kuma is on the Pi); since the proxy is
Pi-IP-pinned, Kuma succeeds and other LAN hosts get blocked.

## Deploy / update

Per `feedback_truenas_app_update_replaces` and
`feedback_truenas_custom_app_via_midclt`:

```bash
# Initial create (scp this file's app-config.json to NAS first):
scp app-config.json root@192.168.1.65:/tmp/docker-socket-proxy.json
ssh root@192.168.1.65 "midclt call -j app.create '$(cat /tmp/docker-socket-proxy.json)'"

# Update (must include ALL required fields — partial updates wipe siblings):
# Re-run the create-style call with the full app-config.json.

# Redeploy without image bump:
ssh root@192.168.1.65 "midclt call app.redeploy docker-socket-proxy"

# Redeploy WITH :latest image pull (use this for tecnativa/docker-socket-proxy bumps):
ssh root@192.168.1.65 "midclt call -j app.pull_images docker-socket-proxy '{\"redeploy\": true}'"
```

## Threat model accepted

Read-only Docker API exposure to the LAN, IP-allowlisted to one host. If the
LAN is hostile, this is a problem; this homelab's threat model assumes it
isn't. The proxy denies all write paths so RCE against NAS containers via
this surface is not possible.

## Deployed

Pending — afternoon deployment pass on 2026-05-06. Record outcome here:

- Date deployed:
- Source-IP enforcement path used (chart UI vs nftables):
- GID adjustment required: yes / no
