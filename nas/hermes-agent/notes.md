# Hermes Agent (NAS) — catalogue app

TrueNAS Scale **catalogue app** `hermes-agent` (train `community`, chart
version `1.0.9`, image `nousresearch/hermes-agent:v2026.7.20`). Replaces the
bespoke Custom App formerly at `nas/hermes/`, which was **deleted via the UI
on 2026-07-31** (no longer a rollback target — see `nas/hermes/notes.md`).
Single `gateway run` container; no separate dashboard
sidecar service — the catalogue chart serves the dashboard from the same
container on its own published port.

The `hermes-investor` plugin is **not baked into the image**. It's built as a
standalone bundle (`uv pip install --target`, matching the image's Python ABI)
and injected at runtime via `PYTHONPATH` + a read-only bind mount — see
"Plugin bundle" below. Deploy artifacts and rationale: see "Plan + spec"
at the bottom.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30262` — dashboard, published from
  `network.dashboard_port` in `app-config.json`.
- **Through Caddy + Authelia 2FA:** `https://hermes.mati-lab.online` →
  `192.168.1.65:30262` (unchanged from the bespoke app — same Caddy vhost).
- **Telegram:** `@HermesMatiBot` — same bot, token migrates from the old
  app's `.env` to this app's `TELEGRAM_BOT_TOKEN` env var (PM
  `homelab/openclaw/telegram-bot`, same entry the bespoke app used).

## App layout

One catalogue-managed container (`gateway run`) — the chart's own compose
handles the gateway + dashboard process split internally; we don't author
`custom_compose_config` for this app. Configuration is entirely through the
`values` dict in `app-config.json`, matching the app's `questions.yaml`
schema (verified shape documented inline in `app-config.json`'s sibling task
brief / the migration spec below).

## No `HERMES_UID` / `HERMES_GID`

Do **not** set these anywhere in this app's config. The catalogue image runs
at its **native UID 10000** — all host paths below must be pre-owned
`10000:10000`. Setting `HERMES_UID=568` (the bespoke app's value) triggers a
10+ minute chown storm on redeploy and breaks the `investor-dashboard` app's
writes to the shared `hermes-investor/` subtree (also expects 10000:10000).
This mirrors the rule already in force for `investor-dashboard` — see
`nas/investor-dashboard/notes.md`.

## ⚠️ Upgrade trap: `gateway_key` must be ≥16 chars before `app.upgrade`

Chart **1.0.9** added a validation rule: `hermes_agent.gateway_key` must be at
least 16 characters. `midclt call -j app.upgrade hermes-agent` **stops the
container first, then runs validation** — so if `gateway_key` is shorter, the
upgrade aborts with `[EINVAL] hermes_agent.gateway_key: String should have at
least 16 characters` and leaves the app **STOPPED** (catalogue apps do not
auto-restart from stopped). This is exactly what caused the **2026-07-21 →
2026-07-31 outage** (10 days down, which also failed every nightly
`hermes-backup` cron → the repeating cron alerts).

**Before any `app.upgrade`, ensure `gateway_key` is ≥16 chars.** Rotating it
is a `midclt call -j app.update hermes-agent` on the full `hermes_agent` values
group (remember: `app.update` **replaces** the nested group — include every
sibling field or they zero out). `gateway_key` is a secret; changing it affects
anything authenticating to the Hermes gateway. Resolved 2026-07-31 by rotating
14 → 32 chars, then upgrading cleanly to 1.0.9.

## Storage

| Role | Type | Path (host → container) | Owner | Read-only? |
|---|---|---|---|---|
| App data (`storage.data`) | host_path | `/mnt/fast/databases/hermes/data` → chart-managed data mount | `10000:10000` | no |
| Plugin bundle (`additional_storage[0]`) | host_path | `/mnt/fast/databases/hermes-investor-bundle/investor-sp` → `/opt/investor-sp` | `10000:10000` | **yes** |

The data path is a **new** dataset (`fast/databases/hermes`), separate from
the bespoke app's `/mnt/.ix-apps/app_mounts/hermes/data`. The plugin bundle
lives on its own dataset (`fast/databases/hermes-investor-bundle`) so it
survives independently of app data and can be mounted read-only — the
catalogue app never writes into it. Both must be pre-created and
`filesystem.setperm`'d to `10000:10000` before `app.create` (see
`nas/investor-dashboard/notes.md` for the `zfs.dataset.create` +
`filesystem.setperm` pattern; same steps apply here).

`investor-dashboard`'s shared bind mount (`/opt/data/hermes-investor`) needs
to be repointed at the new `fast/databases/hermes/data/hermes-investor`
subtree as part of this migration — see `nas/investor-dashboard/app-config.json`
and its notes.md (Task A3 of the migration plan).

## Plugin bundle

Built by `hermes-investor/scripts/build_investor_bundle.sh` **inside the
target stock image** (for Python-ABI match — never copy an existing bundle
across image versions) and installed at
`/mnt/fast/databases/hermes-investor-bundle/investor-sp` on the NAS, owned
`10000:10000`. The app mounts it read-only at `/opt/investor-sp` and sets
`PYTHONPATH=/opt/investor-sp` (both in `additional_envs` /
`additional_storage` in `app-config.json`) so `importlib.metadata` discovers
the `hermes_agent.plugins` entry point at startup.

**The build runs LOCALLY on the dev PC**, not on the NAS: `truenas_admin` has
no docker and no passwordless sudo, so the script pulls + builds inside the
target image on the dev box, rsyncs the result to the bundle dataset
(temporarily `950`-owned for the transfer), hands ownership back to `10000`
via `midclt filesystem.setperm`, and `midclt app.redeploy`s. This is why the
NAS-side `docker`-based recipe in older docs does not apply here.

## Backups

The nightly logical backup (`/mnt/bulk/backups/.scripts/hermes-backup.sh`,
TrueNAS cronjob, 04:15 UTC → `hermes backup` inside the container, gpg on the
host) was updated for this migration: `DATA_DIR` →
`/mnt/fast/databases/hermes/data` and the container-name grep →
`^ix-hermes-agent-hermes-agent-` (the catalogue container). The old script
targeted the bespoke `.ix-apps` path + `ix-hermes-hermes-` container and would
have silently backed up the stale/retired data. A `.bak-<ts>` of the original
sits alongside it. Verified by a manual `midclt call cronjob.run <id>` after
the change (produced a fresh `hermes-*.zip.gpg`).

## Env vars (`hermes_agent.additional_envs`)

**The catalogue app has NO `env_file`** — everything the bespoke app's `.env`
provided must be replicated here in `additional_envs`. The plugin's path
config is the easy thing to miss: each path reads its own `HERMES_INVESTOR_*`
var and otherwise falls back to relative `./data/*`, so omitting them makes
the plugin **load but fail to find its data** (health check reports
portfolio/sources/candidates "missing" — this bit us on the 2026-07-17
cutover). The full set:

| Var | Value / source | Purpose |
|---|---|---|
| `HERMES_HOME` | `/opt/data` | Hermes data root |
| `PYTHONPATH` | `/opt/investor-sp` | plugin discovery (see above) |
| `HERMES_DASHBOARD_CHAT_TRUST_ALL_HOSTS` | `1` | dashboard `/chat` tab behind Caddy |
| `HERMES_INVESTOR_DATA_DIR` | `/opt/data/hermes-investor` | plugin data dir |
| `HERMES_INVESTOR_DB_PATH` | `/opt/data/hermes-investor/db.sqlite` | plugin SQLite (~60 MB) |
| `HERMES_INVESTOR_PORTFOLIO_PATH` | `/opt/data/hermes-investor/portfolio.json` | portfolio (also written by investor-dashboard) |
| `HERMES_INVESTOR_SOURCES_PATH` | `/opt/data/hermes-investor/sources.json` | collector sources |
| `HERMES_INVESTOR_CANDIDATES_PATH` | `/opt/data/hermes-investor/candidates.json` | legacy candidate seed |
| `HERMES_INVESTOR_SKILLS_OVERLAY` | `/opt/data/hermes-investor/skills-overlay` | agent-writable skill overlays |
| `HERMES_INVESTOR_DISCOVERY_SNAPSHOT_PATH` | `/opt/data/hermes-investor/candidates.snapshot.json` | discovery pipeline output path |
| `HERMES_INVESTOR_SEC_USER_AGENT` | `hermes-investor mateusz.goral92@gmail.com` | SEC EDGAR fetch identification (required by SEC fair-use policy) |
| `OPENAI_API_KEY` | PM `homelab/litellm/hermes` | LiteLLM virtual key — Hermes reads OpenAI-compatible env vars for `provider: custom` |
| `OPENAI_BASE_URL` | `http://192.168.1.65:4000/v1` | LiteLLM gateway |
| `TELEGRAM_BOT_TOKEN` | PM `homelab/openclaw/telegram-bot` | `@HermesMatiBot` BotFather token (PM label inherited from OpenClaw, same as the bespoke app) |
| `TELEGRAM_ALLOWED_USERS` | PM `homelab/hermes/telegram-allowed-users` | comma-separated numeric Telegram user IDs |

**Do NOT set `TZ`** — it's reserved by the chart (defined by the app
developer); passing it makes `app.create` render-fail with `Environment
variable [TZ] is already defined`. The container runs UTC and the investor
cron schedules are already stored as UTC expressions, so this is functionally
a non-issue.

Plus `hermes_agent.gateway_key` (PM `homelab/hermes/gateway-key`) — the
catalogue chart's own gateway auth key, a schema field distinct from
`additional_envs`. None of the values above are committed anywhere; every
occurrence in `app-config.json` is a `__FROM_PM__<pm-entry>` placeholder
resolved by the operator at `app.create`/`app.update` time.

## Upgrading Hermes

Catalogue apps upgrade by chart `version` bump, not image rebuild:

1. Check the catalogue for a newer `hermes-agent` chart version (`midclt
   call catalog.get_app_details hermes-agent '{"train":"community"}'` or the
   TrueNAS UI Apps page).
2. Bump `version` (and the pinned image tag if the chart lets you override
   it) in `app-config.json`, then `midclt call app.update hermes
   "$(cat app-config.json)"` (payload shape — confirm current `app.update`
   semantics; it may replace the full `values` block, same caveat as the old
   Custom App's `custom_compose_config`) followed by `app.redeploy hermes`.
   Or upgrade via the TrueNAS UI (Apps → hermes → Update).
3. **Only if the new image bumps the Python minor version** (check with
   `docker run --rm --entrypoint /opt/hermes/.venv/bin/python
   nousresearch/hermes-agent:<new-tag> --version`), rebuild the plugin
   bundle: `hermes-investor/scripts/build_investor_bundle.sh` (targets the
   new image so the compiled wheels — pydantic-core, pandas/numpy —
   ABI-match). No image build for us either way; the bundle is a plain
   `PYTHONPATH` install.
4. Verify: container `Up` with 0 restarts, `hermes tools list` shows
   `✓ enabled hermes-investor`, dashboard returns 200 on `:30262`, a
   one-shot `hermes -z "PONG"` authenticates against Telegram.

## Deploy / update / remove

| Action | Command |
|---|---|
| Deploy from app-config.json | `scp nas/hermes-agent/app-config.json truenas_admin@192.168.1.65:/tmp/ha.json && ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/ha.json)" && rm /tmp/ha.json'` |
| Update values | `ssh ... midclt call -j app.update hermes "$(cat app-config.json)"` — verify current `app.update` payload semantics before relying on partial vs full replace |
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call -j app.redeploy hermes'` |
| Stop / Start | `midclt call app.stop hermes` / `midclt call app.start hermes` |
| View logs | Loki: `{container=~"ix-hermes-.*"}` filtered by `host="nas"` |
| Remove (preserve data) | UI → Apps → hermes → Delete → uncheck "remove ixVolumes" |
| Remove fully | UI checkbox / `app.delete hermes '{"remove_ix_volumes":true}'`. **DESTROYS** sessions, memory, paired-device tokens, skills |

## Plan + spec

This app-config is Task A2 of the catalogue migration. Full plan and design
rationale live in the `hermes-investor` repo (not this one):

- Plan: `hermes-investor/docs/superpowers/plans/2026-07-16-decouple-hermes-catalogue-migration.md`
- Design spec: `hermes-investor/docs/superpowers/specs/2026-07-16-decouple-plugin-catalogue-migration-design.md`

Phase A (this task + siblings A1/A3/A4) is repo-prep only, zero production
impact. Phase B (not yet run as of this file's authoring) is the live NAS
cutover — an operator runbook that briefly stops the shared
`@HermesMatiBot` while migrating, with the bespoke `hermes` Custom App kept
as a stop-not-delete rollback until soak passes. See the plan doc for the
full task list and verification gates.
