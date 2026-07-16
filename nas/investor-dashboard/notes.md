# Investor Dashboard (NAS)

TrueNAS Scale Custom App. Image
`gitea.mati-lab.online/gooral/investor-dashboard:dev` built and published by
the `hermes-investor` repository's `.gitea/workflows/build-dashboard.yml`
workflow (push to `main` touching `dashboard/**`, or `workflow_dispatch`).

FastAPI + SvelteKit portfolio UI: edit positions, view P/L and cost basis,
read Hermes analysis widgets (scores, drift, alerts). Writes `portfolio.json`
for the Hermes investor plugin; keeps its own `dashboard.sqlite` for prices
and UI state.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30032`
- **Through Caddy:** `https://invest.mati-lab.online` (Authelia 2FA)
- **No external exposure** (LAN + Tailscale/WireGuard only).

The app holds portfolio positions and cost-basis data. Authelia 2FA gates the
public hostname; LAN-direct skips the gate — don't expose `:30032` outside the
homelab.

## App details

- Image: `gitea.mati-lab.online/gooral/investor-dashboard:dev`
  - Built by `hermes-investor/.gitea/workflows/build-dashboard.yml` on push
    to `main` (paths: `dashboard/**`, `src/hermes_investor/**`,
    `pyproject.toml`, workflow file) or manual dispatch.
  - Main branch → `:dev`; git tags `v*` → `:vX.Y` + `:latest`.
  - Architecture: linux/amd64 only.
- Container UID/GID: **`10000:10000`** — matches the stock Hermes Agent
  image's native user and the ownership of `/opt/data/hermes-investor/` inside
  the Hermes data volume. The dashboard bind-mounts that path read/write for
  `portfolio.json` and read-only for `db.sqlite`; running as 568 would fail
  on writes. Do **not** set `HERMES_UID=568` on Hermes if you expect this
  mount to stay writable without a chown pass.
- Internal port: 8000 → host port 30032.
- Resource limits: TrueNAS Custom App default (1 CPU / 512 MB) — sufficient;
  idle near zero, peaks under a few hundred MB during price refresh.

## Storage

| Role | Type | Path (host → container) |
|---|---|---|
| Dashboard DB (`dashboard.sqlite`) | Bind | `/mnt/fast/databases/investor-dashboard/data` → `/data` |
| Hermes investor data (shared) | Bind | `/mnt/.ix-apps/app_mounts/hermes/data/hermes-investor` → `/opt/data/hermes-investor` |

The shared mount provides read-only access to `db.sqlite` (analysis widgets)
and read/write access to `portfolio.json` (atomic writes for the plugin).
The dashboard DB holds cached prices and UI-only state — separate from Hermes.

Pre-create the dashboard dataset before launching the app:

```bash
midclt call zfs.dataset.create '{
  "name": "fast/databases/investor-dashboard",
  "type": "FILESYSTEM"
}'
# data dir
mkdir -p /mnt/fast/databases/investor-dashboard/data
midclt call filesystem.setperm '{
  "path": "/mnt/fast/databases/investor-dashboard/data",
  "uid": 10000, "gid": 10000, "mode": "0755",
  "options": {"recursive": true, "stripacl": true}
}'
```

(Or via the TrueNAS UI — Datasets → fast/databases → Add Dataset
`investor-dashboard`, then ACL editor → Owner 10000, Group 10000.)

The Hermes investor path already exists once Hermes is deployed; no extra
dataset needed for the shared bind.

## Wiring / first boot

Deploy the Custom App **after** the `:dev` image exists in the registry
(Task 7). Caddy vhost lives in `network/caddy/Caddyfile` (Task 6).

First boot with an empty `dashboard.sqlite` does **not** wipe a populated
`portfolio.json` — the backend guards against overwriting existing Hermes
portfolio data. Open the UI, enter or import positions; writes land in
`portfolio.json` for `@HermesMatiBot` to read on the next monthly run.

## Reverse proxy

`network/caddy/Caddyfile` `@invest` block. **`forward_auth` to Authelia**
on everything except `/api/health` (Uptime Kuma probes that path without
auth so the 302 login redirect does not fake up-status).

## Backups

`/mnt/fast/databases/investor-dashboard/data/dashboard.sqlite` is small
(cached prices + UI state). Safe to add to `backup-jobs/` in a later cycle;
loss on container restart is recoverable via a price refresh.

`portfolio.json` is already covered by the Hermes backup
(`nas/backup-jobs/hermes-backup.sh`) since it lives under the Hermes data
tree. That file is the canonical portfolio source for the investor plugin.

## Secrets

None in-app. Edge auth is Authelia 2FA at the Caddy vhost only; the container
has no API keys or env_file secrets.

## Deploy / update / remove

| Action | Command |
|---|---|
| Deploy from app-config.json | `scp nas/investor-dashboard/app-config.json truenas_admin@192.168.1.65:/tmp/id.json && ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/id.json)" && rm /tmp/id.json'` |
| Patch compose layout | `ssh ... midclt call -j app.update investor-dashboard "$(python3 -c '...')"` — `app.update` **replaces** `custom_compose_config`; include the full block (see `feedback_truenas_app_update_replaces`) |
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call -j app.redeploy investor-dashboard'` |
| Stop / Start | `midclt call app.stop investor-dashboard` / `midclt call app.start investor-dashboard` |
| Image bump (`:dev` on main) | `midclt call -j app.pull_images investor-dashboard '{"redeploy":true}'` after CI publishes |
| View logs | Loki: `{container=~"ix-investor-dashboard-.*"}` |
| Remove (preserve data) | UI → Apps → investor-dashboard → Delete → uncheck "remove ixVolumes" |
| Remove fully | UI checkbox / `app.delete investor-dashboard '{"remove_ix_volumes":true}'`. **DESTROYS** dashboard.sqlite only; Hermes data on the shared mount is untouched |

## Monitoring

- Uptime Kuma: HTTP-Keyword on `http://192.168.1.65:30032/api/health`,
  keyword `ok`. Caddy bypasses Authelia for that path.
- Promtail: `{container=~"ix-investor-dashboard-.*"}`.

## Admin tips

- After a new `:dev` image push, pull + redeploy:
  `midclt call -j app.pull_images investor-dashboard '{"redeploy":true}'`.
- Crash-recovery: restart the container; volumes preserve both DBs and
  `portfolio.json`.
- If dashboard state corrupts: delete `dashboard.sqlite` under
  `/mnt/fast/databases/investor-dashboard/data/` and restart — the UI
  rebuilds from `portfolio.json` + a fresh price fetch. Do **not** delete
  `portfolio.json` unless you intend to reset Hermes portfolio state.

## Deployed 2026-07-16

Image `gitea.mati-lab.online/gooral/investor-dashboard:dev`
(`sha256:b3610b816a8a6fa4ea990bd30609fdb3d08e3edc513eea1027bab1def5ab5771`)
built locally from `hermes-investor` `cursor/dashboard-deploy` and pushed to
Gitea registry. Custom App `investor-dashboard` created via `app.create` with
`nas/investor-dashboard/app-config.json`.

Pre-deploy: ZFS dataset `fast/databases/investor-dashboard` created; required
explicit `zfs.dataset.mount` (dataset was `mounted: no` after create). Data dir
`/mnt/fast/databases/investor-dashboard/data` created + `filesystem.setperm`
uid/gid 10000.

| # | Check | Result | Notes |
|---|---|---|---|
| V1 | Container up | **PASS** | `state: RUNNING`, container `running` |
| V2 | LAN health | **PASS** | `hermes_db_readable` + `portfolio_path_writable` true |
| V3 | LAN SPA | **PASS** | `curl :30032/` returns HTML shell |
| V4 | Authelia gate | **FAIL** | `https://invest.mati-lab.online` → 404; `@invest` vhost only on `cursor/investor-dashboard-app`, not `main` |
| V5 | Health bypass | **FAIL** | same — Caddy on Pi synced from `main` (no invest block) |
| V6 | Positions API | **PASS** | POST VWCE → enriched row with P/L fields; test row deleted after verify |
| V7 | portfolio.json sync | **PASS** | `filesystem.stat` on shared mount: 656 B, uid 10000, mtime bumped on create |
| V8 | No wipe | **PASS** | empty portfolio preserved; dashboard DB init did not overwrite Hermes data |
| V9 | Analysis | **PASS** | `GET /api/analysis/standard` → `available: true` |
| V10 | Refresh prices | **PASS** | `POST /api/prices/refresh` → 200 (warning: no live quote for VWCE during test) |

**Remaining human steps**

1. Push + merge `mati-lab` branch `cursor/investor-dashboard-app` (Caddy `@invest`
   block), then `make deploy-caddy` from `main`.
2. Re-run V4/V5 in browser + `curl https://invest.mati-lab.online/api/health`.
3. Optional: Uptime Kuma monitor on `https://invest.mati-lab.online/api/health`
   (keyword `ok`).

### Follow-up 2026-07-16 (Caddy live)

- Deployed Caddy from `cursor/investor-dashboard-app` via `make deploy-caddy BRANCH=cursor/investor-dashboard-app`.
- **V4 PASS:** `https://invest.mati-lab.online/` → 302 Authelia.
- **V5 PASS:** `https://invest.mati-lab.online/api/health` → 200 JSON without login.
