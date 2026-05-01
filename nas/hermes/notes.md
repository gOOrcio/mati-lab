# Hermes Agent (NAS)

TrueNAS Scale Apps, **Custom App**, image `nousresearch/hermes-agent:v2026.4.23`.
Installed 2026-04-30 / 2026-05-01 as the replacement for OpenClaw (which
wedged during the Phase 7 paste-token cutover; see `docs/followups.md`
row 7.x.1 closure note). Pairs with LiteLLM on the same NAS — Hermes's LLM
backend is the `http://192.168.1.65:4000/v1` gateway.

Hermes Agent is the originally-attempted Phase 3 candidate. It was abandoned
in favor of OpenClaw on 2026-04-24 because the upstream Docker entrypoint at
that point fought TrueNAS's userns/cap-drop sandbox (root → chown → drop-priv
fight). By 2026-04-30 the entrypoint had been refactored to use `gosu` with
explicit `HERMES_UID` / `HERMES_GID` env vars, which works with TrueNAS's
Custom App model cleanly: pre-chown the bind-mount as 568:568, set
`HERMES_UID=568 HERMES_GID=568`, container starts as root for the privilege
drop, the entrypoint chowns nothing (data already correctly owned), exec's
gosu hermes, agent runs as 568.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30262` — dashboard sidecar
  (`hermes dashboard --port 9119 --insecure`). Hermes embeds a per-session
  token in the HTML, so even direct LAN access requires going through the
  intended browser flow.
- **Through Caddy + Authelia 2FA:** `https://hermes.mati-lab.online` →
  `192.168.1.65:30262`. Default `two_factor` policy applies (no per-host
  rule needed in Authelia).
- **Telegram:** `@HermesMatiBot` — gateway service polls Telegram outbound,
  no exposed port. BotFather token reused from the OpenClaw install (it's a
  BotFather artifact, survives any Hermes/OpenClaw rebuild).
- **No `/health` endpoint by default.** Kuma monitor is HTTP-Keyword on `/`
  matching `Hermes Agent - Dashboard`.

## App layout

Two services in one Custom App, sharing the `/opt/data` volume:

| Service | Command | Why |
|---|---|---|
| `hermes` | `hermes gateway` | Outbound Telegram poller + cron scheduler. Runs the actual agent. |
| `hermes-dashboard` | `hermes dashboard --port 9119 --host 0.0.0.0 --no-open --insecure` | Web UI for config / API keys / sessions. Read+write to the same /opt/data state. |

Both services run as **`user: 0:0`** in the compose with `cap_add:
[CHOWN, FOWNER, SETUID, SETGID, DAC_OVERRIDE]`. The image's entrypoint
(`/opt/hermes/docker/entrypoint.sh`) detects `id -u == 0`, applies
`HERMES_UID`/`HERMES_GID` via `usermod`/`groupmod`, fixes ownership on
`/opt/data` if needed, then `exec gosu hermes "$0" "$@"` to drop privs.

## Auth (three secrets — keep them straight)

| Secret | Role | Where it lives |
|---|---|---|
| **Authelia 2FA** | External gate at the Caddy vhost | Authelia's `users_database.yml` |
| **`OPENAI_API_KEY` (= LiteLLM virtual key `hermes`)** | Hermes → LiteLLM auth (used because `provider: custom` reads OpenAI-compatible env vars) | `/mnt/fast/databases/hermes/.env`; PM `homelab/litellm/hermes` |
| **`TELEGRAM_BOT_TOKEN`** | `@HermesMatiBot` BotFather token | `/mnt/fast/databases/hermes/.env`; PM `homelab/openclaw/telegram-bot` (PM label inherited from OpenClaw install — could be retitled to `homelab/hermes/telegram-bot` next rotation) |

Plus per-session dashboard tokens (Hermes-managed, ephemeral) and
`TELEGRAM_ALLOWED_USERS` allowlist (numeric Telegram user IDs).

## File layout

| Path | Owner | Purpose | EXDEV-safe? |
|---|---|---|---|
| `/mnt/.ix-apps/app_mounts/hermes/data/` | `568:568 0755` | Container `/opt/data` — sessions, memory, config.yaml, skills, logs. | yes (single ZFS dataset = `fast/ix-apps`) |
| `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml` | `568:568 0640` | Hermes's primary config. **Edited in-band** by `hermes config set`, `/sethome`, dashboard. | atomic `rename()` works (same fs as parent) |
| `/mnt/fast/databases/hermes/.env` | `568:568 0600` | env_file: read by both compose services. Static, no in-band edits. | no in-band writes — EXDEV doesn't apply |

**Why config.yaml is in the data dir, not in `/mnt/fast/databases/hermes/`
(where LiteLLM-style services keep their config):** Hermes uses atomic
`rename()` for safe in-band saves, and `rename()` fails with `EXDEV` across
ZFS datasets. The data dir lives on `fast/ix-apps`, the LiteLLM-style
"databases" path lives on `fast/databases`. Different datasets → different
filesystems from the kernel's perspective → `EXDEV`. Putting config.yaml on
the same dataset as the data dir fixes it. `.env` doesn't have this problem
because Hermes never writes to it.

## Deploy / update / remove

| Action | Command |
|---|---|
| Deploy from app-config.json | `scp nas/hermes/app-config.json truenas_admin@192.168.1.65:/tmp/h.json && ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/h.json)" && rm /tmp/h.json'` |
| Patch compose layout | `ssh ... midclt call -j app.update hermes "$(python3 -c '...')"` — see commit `1659d26` for an example payload (`app.update` REPLACES `custom_compose_config`, so include the full block, per `feedback_truenas_app_update_replaces`) |
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call -j app.redeploy hermes'` |
| Stop / Start | `midclt call app.stop hermes` / `midclt call app.start hermes` |
| Image upgrade | Edit tag in `nas/hermes/app-config.json`, `app.update`. For `:latest` (don't pin to it!) use `app.pull_images hermes '{"redeploy":true}'`. |
| View logs | Loki: `{container=~"ix-hermes-.*"}` filtered by `host="nas"` (Phase 7 Promtail-on-NAS captures both services) |
| Remove (preserve data) | UI → Apps → hermes → Delete → uncheck "remove ixVolumes" |
| Remove fully | UI checkbox / `app.delete hermes '{"remove_ix_volumes":true}'`. **DESTROYS** sessions, memory, paired-device tokens, skills. |

## Telegram allowlist

`TELEGRAM_ALLOWED_USERS` is a comma-separated list of numeric Telegram
user IDs in `.env`. To add a new user: ask them to message `@userinfobot`
to get their numeric ID, append to the list, then `app.redeploy hermes`.

To restrict group access without DM access, use `TELEGRAM_GROUP_ALLOWED_USERS`
(separate var, sender-scoped to group/forum messages). `*` allows any sender
or chat (don't use unless you mean it).

## LLM wiring

Hermes uses `provider: custom` in `config.yaml`, which reads `OPENAI_API_KEY`
+ `OPENAI_BASE_URL` from `.env`. We point those at LiteLLM:

- `OPENAI_BASE_URL=http://192.168.1.65:4000/v1`
- `OPENAI_API_KEY=<the hermes virtual key>` (from PM)

The default model alias is `agent-default` (LiteLLM routes:
DeepSeek → Sonnet → Ollama fallback). For `/smart`-style escalation,
Hermes can target `agent-smart` (Sonnet only).

## RAG / vault search (Phase 6 integration)

`mcp_servers.vault-rag.url = http://192.168.1.65:30019/mcp` (streamable-http
MCP). Server lives in `vault-rag-mcp` Custom App (Task 6 of the followups
plan). Hermes connects to it on startup; until that Custom App is deployed
you'll see retry warnings in Loki:

```
WARNING tools.mcp_tool: MCP server 'vault-rag' initial connection failed
  (attempt N/3), retrying in Ns: ...
```

This is expected during the staged rollout — gateway works fine without
RAG, just no vault search until Task 6 lands.

## Backup

Logical: nightly `/mnt/bulk/backup-jobs/hermes-backup.sh` at 04:15 UTC →
`bulk/backups/hermes/hermes-<DATE>.tar.gz.gpg` with Kuma push monitor
`backup-hermes-dump`. See Task 7 of the followups plan.

ZFS: data lives on `fast/ix-apps` (TrueNAS-managed — we do NOT
snapshot this dataset). The logical backup is the only durable copy. Q2
restore drill at `nas/restore-drills/q2-hermes.md` walks the recovery
path.

## Forensic record

- **2026-04-30, Task 1:** OpenClaw config snapshotted to
  `/mnt/bulk/backups/openclaw-final-20260430.tar.gz` (368 MB, root-owned).
- **2026-04-30, Task 2:** LiteLLM virtual key alias renamed
  `openclaw` → `hermes` via `/key/update`. Token value unchanged. PM
  entry retitled.
- **2026-04-30, Task 3:** Hermes config template committed at
  `nas/hermes/config.yaml.example`. Real `.env` staged at
  `/mnt/fast/databases/hermes/.env` (568:568, 0600).
- **2026-04-30, Task 4a:** `app.create` succeeded on first try via root +
  gosu drop-priv. Initial run hit invalid `.env` (literal placeholder text
  written by mistake); after user re-staged with real values, Hermes
  connected to Telegram.
- **2026-05-01, Task 4a fix-up:** `/sethome` failed with `EXDEV`. Moved
  `config.yaml` from `/mnt/fast/databases/hermes/` to
  `/mnt/.ix-apps/app_mounts/hermes/data/` (same ZFS dataset as `/opt/data`)
  via `app.update` dropping the separate config bind-mount. Atomic saves
  work after the move.
- **2026-05-01, Task 5:** Added `hermes-dashboard` sidecar service running
  `hermes dashboard --insecure` at host port 30262. Caddy vhost
  `hermes.mati-lab.online` behind Authelia 2FA → `192.168.1.65:30262`.
  OpenClaw deleted (`app.delete openclaw remove_ix_volumes:true`).

## Lessons / gotchas

1. **`config.yaml` MUST live on the same ZFS dataset as `/opt/data`.**
   Hermes uses atomic `rename()` for in-band edits (`/sethome`, dashboard
   "save", `hermes config set`). Cross-dataset = `EXDEV`. Don't put it
   under `/mnt/fast/databases/hermes/` even though that matches the
   LiteLLM-style convention.
2. **Default `command:` is `hermes` (interactive REPL), NOT a service.**
   For long-running gateway, override to `["hermes", "gateway"]`. For the
   dashboard, override to `["hermes", "dashboard", ...]`. They're separate
   processes — run as separate compose services.
3. **`hermes dashboard` defaults to `127.0.0.1:9119`.** Pass
   `--host 0.0.0.0 --insecure` to bind on all interfaces inside the
   container. Don't be alarmed by the warning — Authelia 2FA at the Caddy
   vhost + Hermes's own per-session token are the real gates.
4. **`docker compose env_file` parser is strict.** No quotes around values,
   no spaces around `=`, no inline comments. The "key cannot contain a
   space" error usually means a malformed line (we hit this twice during
   Task 3).
5. **OpenClaw's `:18789` vs `:30262` CLI gotcha doesn't apply** — Hermes
   doesn't have an in-container WebSocket gateway port distinct from the
   dashboard port. Just one number per service, host-published.
