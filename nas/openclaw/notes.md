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

## Phase 7 incident (2026-04-30) — currently STOPPED

State: app stopped on NAS pending cutover decision. The Phase 7 attempt to migrate from the LiteLLM master key to the per-consumer `openclaw` virtual key (issued via `/key/generate`, stored under `homelab/litellm/openclaw` in PM) wedged the gateway. Sequence:

1. `openclaw models auth paste-token --provider custom-192-168-1-65-4000 --profile-id custom-192-168-1-65-4000:manual` — succeeded; wrote new openclaw.json + .bak.
2. `openclaw secrets reload` — failed with `gateway closed (1008): pairing required: device is asking for more scopes than currently approved`.
3. `app.redeploy openclaw` — gateway logs reach `[gateway] starting...` and stop. Container stays in Docker `starting` state for 6+ minutes; `[plugins]` and `[telegram]` lines that appeared on a normal restart never appear.
4. Rollback to `openclaw.json.bak` (paste-token's pre-paste backup) — same hang.
5. Rollback to `openclaw.json.last-good` (OpenClaw-managed, 13:08 timestamp) — same hang.

The hang isn't openclaw.json content alone — restoring known-good content didn't unstuck it. Suspects to investigate when revisiting:

- Stale lock or pending-state file under `/home/node/.openclaw/devices/`, `/home/node/.openclaw/identity/`, or `/home/node/.openclaw/credentials/` from the truncated `secrets reload` (the scope-upgrade approval was never granted).
- The `[gateway] starting...` line is logged just before the WebSocket listener binds; if a port collision or pairing-state-DB lock blocks it, no further log line appears.
- Possibly a transient OpenClaw issue with the `paste-token` → in-memory swap path that the on-disk rollback alone doesn't reverse.

Followup row tracking this: `docs/followups.md` 7.x.1. Three options when revisiting:

- **(a) Investigate the hang.** Drop into the volume from outside the container, look for lock files / pending-approval entries, clear them, restart. Cheapest if the hang is a small bit of state.
- **(b) Fresh install** with the virtual key wired from the start via `openclaw onboard --non-interactive --secret-input-mode ref --custom-api-key "$OPENCLAW_VKEY" --custom-provider-id custom-192-168-1-65-4000 ...` per the wizard-cli-automation docs. Keep the Telegram bot token (it's a BotFather artifact, not an OpenClaw artifact — survives the reinstall). Rebuild pairings + skill state from scratch.
- **(c) Reconsider OpenClaw vs Hermes.** OpenClaw was already chosen as the *successor* to a Hermes attempt that fought TrueNAS's Custom App sandbox (see lessons below). If OpenClaw is producing more trouble than value, reverting to Hermes is on the table. Memory note `project_llm_stack` says "Hermes tried and abandoned, don't revive" — so this is the explicit unrevival case if (a) and (b) both fail.

The LiteLLM `openclaw` virtual key remains valid (issued + budget assigned, no traffic). It can stay quiescent; rotation isn't urgent.

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

## RAG integration (Phase 6)

**Decision:** Connect OpenClaw to the homelab Qdrant via MCP, not via a
custom skill. OpenClaw is already an MCP client; reusing the same
`vault_search` server that Claude Code consumes keeps "what tool the
agent has access to" identical across surfaces and avoids forking
implementations.

**Why not the openclaw-rag-skill community project:** it would mean
maintaining a second embedding pipeline parallel to the one
`rag-watcher` and `mcp/server.py` already implement, and the skill
cannot be reused by Claude Code or OpenCode. The MCP path is the
single-source-of-truth choice.

**Why not stdio transport** (the way Claude Code consumes our server):
OpenClaw runs inside a TrueNAS container with no `uv` and no access to
the dev box's filesystem where `compute/rag/mcp/server.py` lives. Stdio
means baking the script + uv into OpenClaw's container — fragile.

**Architecture:** run a second instance of `compute/rag/mcp/server.py`
as a **streamable-http** server in its own TrueNAS Custom App
(`vault-rag-mcp`) on host port `30019`. OpenClaw connects via
`http://192.168.1.65:30019/mcp` over the LAN.

**Status: NOT YET DEPLOYED.** Phase 6 closeout deferred this — the
Claude Code / OpenCode integration via stdio is sufficient for daily
use; OpenClaw RAG ships in Phase 6.x once we have appetite to add
another small Custom App. The MCP server already supports streamable-http
via `MCP_TRANSPORT=streamable-http` (see top of `compute/rag/mcp/server.py`),
so deployment is just packaging.

**Runbook for when we deploy it:**

1. **Add a Dockerfile under `compute/rag/mcp/`** — same Python 3.12 slim
   base as the watcher, copy `server.py`, `pip install mcp httpx
   qdrant-client`, default `CMD` runs the script.
2. **Push image to Gitea** at `gitea.mati-lab.online/gooral/vault-rag-mcp:latest`.
3. **Stage env file at** `/mnt/fast/databases/vault-rag-mcp/.env`:
   ```
   LITELLM_API_KEY=<from password manager>
   ```
4. **Create the Custom App** with this compose (host port 30019 maps to 8080 inside):
   ```yaml
   services:
     vault-rag-mcp:
       image: gitea.mati-lab.online/gooral/vault-rag-mcp:latest
       restart: unless-stopped
       env_file: ["/mnt/fast/databases/vault-rag-mcp/.env"]
       environment:
         QDRANT_URL: http://192.168.1.65:30017
         QDRANT_COLLECTION: obsidian-vault
         LITELLM_BASE_URL: http://192.168.1.65:4000
         LITELLM_EMBED_MODEL: embeddings
         MCP_TRANSPORT: streamable-http
         MCP_HTTP_PORT: "8080"
       ports:
         - {mode: host, protocol: tcp, published: 30019, target: 8080}
   ```
5. **Register with OpenClaw** — from a shell *inside* the OpenClaw
   container (TrueNAS UI → Apps → openclaw → Shell):
   ```
   openclaw mcp set vault-rag '{"url":"http://192.168.1.65:30019/mcp","transport":"streamable-http"}'
   openclaw mcp list
   ```
6. **Verify** by asking OpenClaw a vault question
   ("what's in my homelab notes about LiteLLM"). Expect a
   citation-bearing answer pulled from `nas/litellm/notes.md`.

**Open question deferred to deploy time:** auth on the HTTP MCP. v1
relies on LAN-only port + `mode: host` binding (no Caddy exposure).
If/when we want this reachable from outside the LAN, add a bearer-token
check via FastMCP middleware and rotate the token alongside the
LiteLLM key.
