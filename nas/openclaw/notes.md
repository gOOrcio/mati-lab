# OpenClaw (NAS)

TrueNAS Scale Apps, **official catalog app** (`stable` train). Installed
2026-04-24 via the TrueNAS UI. Pairs with LiteLLM on the same NAS —
OpenClaw's LLM backend is the `http://192.168.1.65:4000/v1` gateway.

OpenClaw replaces the originally-attempted Hermes Agent install. Hermes's
entrypoint (start-as-root → chown /opt/data → drop to unprivileged user)
fights TrueNAS's Custom App sandbox in ways we couldn't reliably work
around — three crash-loop variants across cap_add / user:10000 /
user:568 / entrypoint-override. OpenClaw has an official catalog app
engineered for TrueNAS's `user: 568` + userns-remap model, so "just works".
If you're ever tempted back to Hermes, re-read `docs/superpowers/plans/`
for the war stories.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30262`
  - `/` — web dashboard (OpenClaw Control)
  - `/health` — liveness
  - `/metrics` — Prometheus format (scraped by `network/prometheus/prometheus.yml`)
  - `/stats` — runtime stats page
- **Through Caddy + Authelia 2FA:** `https://openclaw.mati-lab.online`

## Auth

- **Gateway Token** (shared bearer) — set at install time in the TrueNAS
  app form. Stored in your password manager. Anyone calling OpenClaw's
  gateway API must send this as `Authorization: Bearer <token>`. The
  dashboard handles this transparently once you log in.
- **Authelia 2FA** sits in front at the Caddy vhost — external access
  needs clear that first. LAN-direct access to `192.168.1.65:30262`
  bypasses Authelia; Gateway Token is the only layer there.

## App config (TrueNAS catalog form values)

| Field | Value |
|---|---|
| Application Name | `openclaw` |
| Authentication Mode | Shared bearer token |
| Gateway Token | (password manager) |
| Allowed Origins | `https://openclaw.mati-lab.online` — required for the dashboard when accessed via Caddy, otherwise browser CORS blocks API calls |
| Proxy Trusted Proxies | `192.168.1.252` (the Pi — Caddy's source IP) |
| User ID / Group ID | `568` / `568` (TrueNAS apps user) |
| Port Bind Mode | Publish on host |
| Port Number | `30262` |
| Config Storage | ixVolume (TrueNAS-managed) |
| CPUs / Memory | 2 / 4096 MB |

## LLM backend (post-install onboarding)

OpenClaw has a one-time onboarding wizard via the web dashboard OR via the
`openclaw onboard` CLI. We're using LiteLLM as the LLM provider:

- **Provider type**: OpenAI-compatible / Custom
- **Base URL**: `http://192.168.1.65:4000/v1`
- **API Key**: the LiteLLM master key (not OpenClaw's gateway token —
  these are two separate secrets. Gateway Token auths clients to
  OpenClaw; this API key auths OpenClaw to LiteLLM.)
- **Default model**: `agent-default` (LiteLLM alias → DeepSeek primary)
- **Smart / escalation model**: `agent-smart` (LiteLLM alias → Claude Sonnet 4.6 only)

CLI equivalent:

```sh
# Inside OpenClaw container shell (TrueNAS UI → Apps → openclaw → Shell)
openclaw onboard \
  --auth-choice litellm-api-key \
  --custom-base-url http://192.168.1.65:4000/v1
# (paste LiteLLM master key when prompted)
```

## Messaging platforms (Telegram — Task 5)

Set up in the OpenClaw dashboard → Settings → Messaging, OR via env
vars added on the TrueNAS app form:

```
TELEGRAM_BOT_TOKEN=<from @BotFather>
TELEGRAM_ALLOWED_USERS=<your user id from @userinfobot>
```

Then redeploy the app for env changes to take effect. See
`docs/superpowers/plans/2026-04-24-phase-3-llm-infrastructure.md` Task 5
for the full walkthrough.

## Backup (Phase 8 scope)

OpenClaw stores state in its ixVolume (TrueNAS-managed). Snapshot the
enclosing dataset via a Phase-8 periodic snapshot task. Because the
state includes a SQLite memory DB, pair the snapshot with a nightly
`sqlite3 memory.db '.backup ...'` logical dump to `bulk/backups/openclaw/`
for consistency guarantees. Add to `nas/snapshots.md` when Phase 8 runs.

## Update / restart / remove

| Action | Command |
|---|---|
| Restart | `midclt call app.redeploy openclaw` (or TrueNAS UI → Apps → openclaw → Restart) |
| Stop / Start | `midclt call app.stop openclaw` / `midclt call app.start openclaw` |
| Change image tag | TrueNAS UI → Apps → openclaw → Edit → Image Selector |
| Remove (keeps data) | TrueNAS UI → Apps → openclaw → Delete (uncheck "remove ixVolumes") |
| Remove fully | Delete app + check "remove ixVolumes" — irrecoverable without Phase-8 backup |
| Logs | TrueNAS UI → Apps → openclaw → Logs, or `sudo docker logs <cid>` on NAS |
