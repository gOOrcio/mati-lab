# OpenClaw (NAS)

TrueNAS Scale Apps, **official catalog app** (`stable` train). Installed
2026-04-24. Pairs with LiteLLM on the same NAS — OpenClaw's LLM backend
is the `http://192.168.1.65:4000/v1` gateway.

OpenClaw replaces the originally-attempted Hermes Agent install. Hermes's
entrypoint (start-as-root → chown /opt/data → drop to unprivileged user)
fights TrueNAS's Custom App sandbox in ways we couldn't reliably work
around. OpenClaw ships a native TrueNAS catalog app built for TrueNAS's
conventions (UID 568 apps user, ixVolume-managed config, etc.), so it
just works.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:30262`
  - `/` — web dashboard (OpenClaw Control)
  - `/health` — liveness (Uptime Kuma scrapes this)
  - `/__openclaw__/canvas/` — canvas host page
- **Through Caddy + Authelia 2FA:** `https://openclaw.mati-lab.online`
- **Gateway WebSocket** (used by dashboard internally): same port, `ws://192.168.1.65:30262` / `wss://openclaw.mati-lab.online`

**Port 30262 is BOTH the dashboard HTTP and the gateway WS.** OpenClaw's
own docs and CLI default to `ws://127.0.0.1:18789` (pre-TrueNAS
convention), which is not where the supervised process actually listens.
See "CLI gotcha" below.

## Auth (three separate secrets — don't confuse them)

| Secret | Role | Where it lives |
|---|---|---|
| **Authelia 2FA** | External gate at Caddy vhost | Authelia's users DB |
| **Gateway Token** (shared bearer) | Authorizes clients to the OpenClaw gateway API | TrueNAS app form → stored in your password manager |
| **Dashboard session token** (from `openclaw dashboard` CLI) | Pre-approved tokenized URL, bypasses per-browser pairing | Ephemeral, regenerate with `openclaw dashboard` |
| **LiteLLM master key** | OpenClaw uses this as the API key it sends to LiteLLM | `/mnt/fast/databases/litellm/.env` on NAS |

Also: **per-device pairing.** Every new browser/device that connects to
the gateway queues a pairing request that must be approved explicitly.
That's a security feature, not a bug. See "Pairing workflow" below.

## App config (TrueNAS catalog form values — for install reference)

| Field | Value |
|---|---|
| Application Name | `openclaw` |
| Authentication Mode | Shared bearer token |
| Gateway Token | (from password manager) |
| Allowed Origins | `https://openclaw.mati-lab.online` |
| Proxy Trusted Proxies | `192.168.1.252` (Pi — Caddy's source IP) |
| User ID / Group ID | `568` / `568` |
| Port Bind Mode | Publish on host |
| Port Number | `30262` |
| Config Storage | ixVolume (TrueNAS-managed) |
| CPUs / Memory | 2 / 4096 MB |

## LLM wiring (as actually configured)

Done via the interactive wizard in the container shell. If you ever rebuild:

- **Model/auth provider**: Custom Provider (NOT "LiteLLM" — that provider
  driver injected an unwanted `litellm/` prefix and misrouted on first
  attempt)
- **API Base URL**: `http://192.168.1.65:4000/v1` (the `/v1` matters)
- **API Key**: LiteLLM master key (`cat /mnt/fast/databases/litellm/.env` on NAS)
- **Model ID**: `agent-default` — exactly, no prefix
- **Endpoint compatibility**: Unknown (detect automatically) — OpenClaw
  probes and reports "Detected OpenAI-compatible endpoint"
- **Endpoint ID**: auto-generated, e.g. `custom-192-168-1-65-4000`
- **Model alias**: leave blank

## Telegram integration (as actually configured)

- Bot: `@HermesMatiBot` (named "mati-lab hermes" from earlier install
  attempts — name kept for continuity)
- Bot token registered via wizard; stored in OpenClaw config.
- **Allowlist is CRITICAL**. Without it, anyone who finds the bot
  username can burn your DeepSeek/Claude quota. Set via:
  ```sh
  openclaw security audit            # surfaces missing allowlist
  openclaw config set channels.telegram.allowedUsers '[<your_id>]'
  ```
  Get your numeric Telegram user ID from `@userinfobot`.

## Hardening done at install

- `gateway.controlUi.allowInsecureAuth=false` — wizard defaulted to
  `true` for ease of setup; turned off after first successful dashboard
  connection.

## Pairing workflow (every new browser/device)

When a new browser connects (to the dashboard or canvas), the gateway
queues a pairing request. You must approve it once per device; it
persists until you revoke.

```sh
# List pending
openclaw devices list

# Approve (get the requestId from dashboard error banner, log line, or the list above)
openclaw devices approve <requestId>

# Reject (if suspicious)
openclaw devices reject <requestId>

# Revoke a previously-approved device later
openclaw devices revoke <deviceId>
```

Each successful approval rotates the token for that device. The browser
stores it in localStorage; subsequent visits don't re-prompt.

## CLI gotcha — the `:18789` vs `:30262` mismatch

**Symptom:** `openclaw devices list` / `openclaw doctor` fail with
`gateway closed (1006 abnormal closure (no close frame))`. Message says
`Gateway target: ws://127.0.0.1:18789`.

**Why:** OpenClaw CLI hardcodes `ws://127.0.0.1:18789` as its default,
inherited from pre-TrueNAS "run gateway bare on your laptop"
convention. Our TrueNAS custom app actually binds the gateway to
**port 30262** inside the container (matching the external port we
exposed). Nothing listens on 18789 in this deployment.

**Fix:** inside the container shell, point the CLI at the right port.
Either:

```sh
# One-shot, session-scoped
export OPENCLAW_GATEWAY_URL=ws://127.0.0.1:30262

# Persistent (writes to ~/.openclaw/openclaw.json)
openclaw config set gateway.port 30262
```

(Exact config key depends on OpenClaw version — `openclaw config list`
or grep the json to confirm. As of 2026.4.21 it's `gateway.port`.)

Without this, no CLI command that hits the gateway (devices, security
audit, doctor) will work.

## Do-not-run-from-the-shell list

Gateway lifecycle is owned by TrueNAS. Running these in the container
shell creates a second gateway process that fights the supervised one
(bonjour name conflicts, Telegram 409 "terminated by other getUpdates",
state-file corruption):

| Don't run in shell | Use instead |
|---|---|
| `openclaw gateway run` | Already running as container PID 1; restart via `midclt call app.redeploy openclaw` |
| `openclaw gateway stop` / `start` / `restart` | Same — `midclt call app.stop/start/redeploy openclaw` |
| `openclaw onboard` / `openclaw init` (after initial setup) | `openclaw config set <key> <value>` — in-place patch, no gateway restart |

**Safe to run in shell** (read/patch only):

- `openclaw doctor`
- `openclaw config get|list|set|unset`
- `openclaw devices list|approve|reject|revoke`
- `openclaw security audit [--deep] [--fix]`
- `openclaw dashboard` (generates tokenized URL — read-only, safe)

## Update / restart / remove

| Action | Command |
|---|---|
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call app.redeploy openclaw'` |
| Stop / Start | `midclt call app.stop openclaw` / `midclt call app.start openclaw` |
| Change image tag | TrueNAS UI → Apps → openclaw → Edit → Image Selector |
| Remove (keeps data) | TrueNAS UI → Apps → openclaw → Delete (uncheck "remove ixVolumes") |
| Remove fully | Delete + check "remove ixVolumes" — DESTROYS all pairing, sessions, memory |
| View logs | TrueNAS UI → Apps → openclaw → Logs, or `sudo docker logs <cid>` on NAS |

## Backup (Phase 8 scope)

OpenClaw's state sits in the ixVolume bound to `/opt/data`. Snapshot the
enclosing dataset (`fast/ix-apps/app_mounts/openclaw/...`) via a
Phase-8 periodic snapshot task. State DB is SQLite; pair the snapshot
with a nightly `sqlite3 state.db '.backup ...'` dump to
`bulk/backups/openclaw/` for consistency guarantees. Add to
`nas/snapshots.md` when Phase 8 runs.

## Lessons from the install — don't repeat these

1. **Don't use OpenClaw's "LiteLLM" provider driver** for a LiteLLM
   proxy behind an OpenAI-compatible base_url. Use "Custom Provider"
   — OpenClaw's LiteLLM driver wants to route through its own LiteLLM
   library and adds prefixes we don't want.
2. **The `user: 568` convention in the TrueNAS catalog app matters.**
   Trying to use `user: 10000` (Hermes's convention) on a TrueNAS
   Custom App gets tangled in capabilities/userns. Catalog apps exist
   for a reason.
3. **Don't run `openclaw gateway run` in the container shell** if
   TrueNAS is already supervising. Second instance → Telegram 409
   conflicts + mDNS name collisions.
4. **Pairing is per-device.** A fresh incognito tab counts as a new
   device. Embrace it or keep `openclaw devices list` handy.
