# Off-Pi heartbeat

External witness for the network Pi (`192.168.1.252`). Everything that normally
watches the Pi — Prometheus, Loki, Uptime-Kuma, the Pi's own ntfy — runs **on**
the Pi, so when it dies the monitoring dies with it. The 2026-06-06 NVMe-death
outage went unnoticed until a human spotted the LAN had no DNS. This closes that
blind spot.

## How it works

- Runs on the **NAS** (always-on, independent of the Pi) as a root cron, every
  2 min: `/mnt/bulk/backups/.scripts/pi-heartbeat.sh`.
- Checks the Pi two ways: ICMP ping **and** a TCP connect to `:53` (Pi-hole) —
  the latter confirms a *useful* Pi, not just one that ARP-replies.
- Alerts after **2 consecutive misses** (~4 min) and again on recovery.
- Delivery is **ntfy.sh (public)**, on purpose: the Pi's self-hosted ntfy is
  down exactly when this fires. DNS for `ntfy.sh` is resolved via a hardcoded
  public resolver (`1.0.0.1`) so the alert doesn't depend on Pi-hole either.

## Topic / secret

The ntfy topic lives in `/root/.backup-env` as `NTFY_HEARTBEAT_TOPIC=` on the
NAS — **not committed** (it's a read/write capability for that topic). To find
it: `sudo grep NTFY_HEARTBEAT_TOPIC /root/.backup-env`. Subscribe to it in the
ntfy phone app (server `ntfy.sh`).

## Install / re-install

```bash
scp nas/pi-heartbeat/pi-heartbeat.sh nas/pi-heartbeat/install-heartbeat.sh truenas_admin@192.168.1.65:/tmp/
ssh truenas_admin@192.168.1.65 'sudo bash /tmp/install-heartbeat.sh'   # prints the topic
```

## Notes / trade-offs

- **Planned Pi reboots will alert** (e.g. the NVMe swap) — the recovery ping
  confirms it came back. No maintenance-window suppression by design (keep it
  dumb and reliable).
- Privacy: a "Pi down" line on a public ntfy topic. Topic is a 20-hex-char
  random string. Swap to Telegram (Hermes bot) or NAS email if that matters —
  only `notify()` in the script changes.
- The NAS lists the Pi (`192.168.1.252`) as primary DNS with `1.1.1.3` as
  fallback, so NAS name resolution survives a Pi outage (with a short timeout).
  The script's explicit `@1.0.0.1` resolve avoids even that delay.
