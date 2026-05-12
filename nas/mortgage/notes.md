# Mortgage (NAS)

TrueNAS Scale Custom App. Image
`gitea.mati-lab.online/gooral/mortgage-calc:latest` built and published by
the `mortgage-calc` repository's gitea release workflow.

Small FastAPI + HTMX web app: upload your latest mBank harmonogram CSV,
get the next snowball-prepayment recommendation or a what-if projection,
plus an estimated prorated-interest charge for the prepayment day.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30030`
- **Through Caddy:** `https://mortgage.mati-lab.online` (Authelia 2FA)
- **No external exposure** (LAN + Tailscale/WireGuard only).

The app holds PII (loan principal, original installment, prepayment
history derived from the uploaded CSV). Authelia 2FA gates the public
hostname; LAN-direct skips the gate so don't expose `:30030` outside the
homelab.

## App details

- Image: `gitea.mati-lab.online/gooral/mortgage-calc:latest`
  - Built by `mortgage-calc/.gitea/workflows/release.yml` on every push
    to `main` that touches `mortgage/`, `Dockerfile`, `pyproject.toml`,
    or `uv.lock`.
  - Architecture: linux/amd64 only.
- Container UID/GID: `568:568` (matches the TrueNAS apps user; required
  for write access to the bind-mounted `/data` directory).
- Internal port: 8000 → NodePort 30030.
- Resource limits: TrueNAS Custom App default (1 CPU / 512 MB) — generous;
  the app idles near zero, peaks under 200 MB while running a projection.

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| State (current.csv + state.json) | Bind | `/mnt/fast/databases/mortgage/data` → `/data` |

`state.json` carries the anchor (Decimal as string) + last-upload metadata.
`current.csv` is the byte-for-byte CP1250 export from mBank. Both written
atomically via tempfile + rename so a crash mid-upload preserves the
previous state.

Pre-create the dataset before launching the app:

```bash
midclt call zfs.dataset.create '{
  "name": "fast/databases/mortgage",
  "type": "FILESYSTEM"
}'
midclt call filesystem.setperm '{
  "path": "/mnt/fast/databases/mortgage/data",
  "uid": 568, "gid": 568, "mode": "0755", "options": {"recursive": true, "stripacl": true}
}'
```

(Or via the TrueNAS UI — Datasets → fast/databases → Add Dataset
`mortgage`, then ACL editor → Owner 568, Group 568.)

## Wiring

First-run is just "upload your harmonogram, enter the anchor." There is
no admin panel, no signup flow, no schema migration. If the volume is
empty the form starts blank and asks for both fields.

## Reverse proxy

`network/caddy/Caddyfile` `@mortgage` block. **`forward_auth` to
Authelia** on everything except `/healthz` (which Kuma probes; bypassing
auth keeps the probe cheap and prevents the 302 login redirect from
faking up-status).

## Backups

`/mnt/fast/databases/mortgage/data` is tiny (~50 KB: one CSV + one JSON).
Add to the next `arr-config-backup.sh` cycle or skip — the canonical
source for `current.csv` is mBank itself (re-export anytime), and
`state.json` only persists the anchor (which is a single number the user
already knows). No real loss on container restart.

If you want it bundled anyway, append a `mortgage.tar.gz` entry to
`/mnt/fast/scripts/arr-config-backup.sh`:

```bash
tar czf "$STAGE/mortgage.tar.gz" -C /mnt/fast/databases/mortgage data
```

## Monitoring

- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30030/healthz`,
  keyword `ok`. The endpoint returns `ok` plaintext with 200 — the
  Caddyfile bypasses Authelia for that path so the probe doesn't hit
  the 2FA wall.
- Promtail: `{container=~"ix-mortgage-mortgage-.*"}`.

## Admin tips

- After a new image push, pull via the TrueNAS UI: Apps → mortgage →
  Edit → "Pull image" toggle ON → Update. Or via CLI:
  `app.update mortgage`.
- The anchor is editable in the form on every submit. If you refinance
  in real life, type the new anchor on the next upload; it overwrites
  the persisted value.
- Crash-recovery: the app is stateless w.r.t. RAM. Restart the container,
  the volume preserves `current.csv` + `state.json`.
- If the volume gets corrupt: delete `/mnt/fast/databases/mortgage/data/state.json`
  and `/mnt/fast/databases/mortgage/data/current.csv`. The UI will show
  the empty form and let you upload fresh.
