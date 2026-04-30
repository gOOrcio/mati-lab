# LiteLLM (NAS)

TrueNAS Scale Apps, **Custom App** (not in catalog). Installed 2026-04-24
via `midclt`. Paired with Hermes (`nas/hermes/`) — they live on the same
host so Hermes hits LiteLLM over loopback with no network glue.

## Endpoints

- **Direct (LAN):** `http://192.168.1.65:4000`
  - `GET /health/liveliness` — no auth
  - `GET /metrics` — Prometheus format (for `network/prometheus/prometheus.yml`)
  - `POST /v1/chat/completions`, `/v1/embeddings` — OpenAI-compatible, needs `Authorization: Bearer <LITELLM_MASTER_KEY>`
- **Admin UI behind Authelia 2FA:** `https://litellm.mati-lab.online` → Caddy on Pi → `192.168.1.65:4000`

## Config on disk

Config + secrets sit outside of the TrueNAS Apps system so the app is
pure "run this compose", and snapshots of `fast/databases/litellm` give
you point-in-time rollback of the routing rules without touching the
container image.

| Path (NAS) | Content | Source of truth |
|---|---|---|
| `/mnt/fast/databases/litellm/config.yml` | Model aliases, routing, budgets | Copy of `nas/litellm/config.yml` in this repo — edit in repo, scp to NAS, restart app |
| `/mnt/fast/databases/litellm/.env` | `LITELLM_MASTER_KEY`, `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, `POSTGRES_PASSWORD`, `DATABASE_URL`, `GENERIC_CLIENT_ID`/`GENERIC_CLIENT_SECRET`/`GENERIC_*_ENDPOINT`/`GENERIC_SCOPE`/`PROXY_BASE_URL` (Phase 7 SSO) | Only on NAS. Never committed; password-manager-backed |
| `/mnt/fast/databases/litellm-pgdata/` | Postgres-16 data directory for the virtual-keys sidecar (added Phase 7). Owned `apps:apps` (568:568). | Block-level — snapshotted hourly+daily via task 12/13 on `fast/databases`. Phase 8 will add `pg_dump` for transactional consistency. |

To apply a config.yml change: `scp nas/litellm/config.yml truenas_admin@192.168.1.65:/mnt/fast/databases/litellm/config.yml && ssh truenas_admin@192.168.1.65 'midclt call app.redeploy litellm'`.

## Admin UI SSO (Phase 7)

The "Login with SSO" button on `litellm.mati-lab.online/ui` is wired
through Authelia OIDC. Flow: user → Caddy `forward_auth` (Authelia 2FA
gate, already in place) → LiteLLM UI → click "Login with SSO" →
Authelia `/api/oidc/authorization` (recognizes existing session) →
bounces back to `https://litellm.mati-lab.online/sso/callback` → LiteLLM
exchanges code for token → admin UI session as the Authelia identity.

**Configured env vars** (in `.env` on NAS):

| Var | Value |
|---|---|
| `GENERIC_CLIENT_ID` | `litellm` |
| `GENERIC_CLIENT_SECRET` | plaintext; Authelia stores Argon2id hash |
| `GENERIC_AUTHORIZATION_ENDPOINT` | `https://authelia.mati-lab.online/api/oidc/authorization` |
| `GENERIC_TOKEN_ENDPOINT` | `https://authelia.mati-lab.online/api/oidc/token` |
| `GENERIC_USERINFO_ENDPOINT` | `https://authelia.mati-lab.online/api/oidc/userinfo` |
| `GENERIC_SCOPE` | `openid email profile groups` |
| `PROXY_BASE_URL` | `https://litellm.mati-lab.online` |
| `PROXY_ADMIN_ID` | `gooral` — the SSO-claim value (Authelia `preferred_username`) that is auto-promoted to `proxy_admin` on first login. Without this, the SSO-created user lands as `internal_user_viewer` and the UI shows "No keys found" because they can't see the system-wide virtual keys created by the master key. |

Authelia client config: `network/authelia/configuration.yml` under
`identity_providers.oidc.clients` as `litellm`, redirect URI
`https://litellm.mati-lab.online/sso/callback`. Hashed secret on Pi at
`network/authelia/data/oidc_litellm_client_secret.txt`.

**Caddy `forward_auth` stays in place** — it's the outer gate that
prevents anyone without Authelia 2FA from even loading the LiteLLM UI.
SSO is the inner identity hand-off so LiteLLM knows *who* you are once
Caddy lets you through.

To rotate the SSO secret, see the row in `nas/secrets-inventory.md`.

## Architecture (Phase 7+)

Two containers, one Custom App:
- `litellm` — the gateway proxy. Reads `config.yml` (mounted RO) and `.env`. Listens on host port 4000.
- `litellm-postgres` (added Phase 7) — `postgres:16-alpine` sidecar. Stores virtual-key hashes, per-key budgets, spend metrics. Runs as `568:568`. Reachable inside the app's docker network at hostname `litellm-postgres:5432`. **Required for `/key/*` endpoints** — without it, `/key/generate` returns `DB not connected. See https://docs.litellm.ai/docs/proxy/virtual_keys`.

The litellm container has `depends_on: litellm-postgres` with `condition: service_healthy`, so Postgres' `pg_isready` healthcheck must pass before litellm starts.

## Virtual keys (Phase 7)

LiteLLM admin operations use the **master key** (`LITELLM_MASTER_KEY` in `.env`). Per-consumer access uses **virtual keys** issued via `/key/generate`. Each virtual key has its own model allowlist, budget, and spend tracking.

| Alias | Consumer | Models | Budget | Where the key lives |
|---|---|---|---|---|
| `rag-watcher` | rag-watcher Custom App | `embeddings` | $1 / 30d | `/mnt/fast/databases/rag-watcher/.env` |
| `openclaw` | OpenClaw Custom App | `agent-default`, `agent-smart`, `coding`, `embeddings` | $20 / 30d | OpenClaw in-app config (LLM provider wizard) |
| `dev-pc-tools` | Local CLI tooling on dev box (Claude Code MCP `vault-rag`, OpenCode, ad-hoc curl) | `agent-default`, `agent-smart`, `coding`, `embeddings` | $30 / 30d | Dev-box `~/.claude/mcp.json` env block + shell env |

PM labels follow `homelab/litellm/<alias>`.

### Issue (initial or new consumer)

Use the committed helper script — it pulls the master key into a shell-only env var and never bakes it into a committed file:

```bash
bash nas/litellm/issue-keys.sh
```

The script defines an `issue` function and calls it 3× (rag-watcher, openclaw, dev-pc-tools). Edit the bottom of the script if you ever need to issue a 4th alias.

### Rotate / regenerate a key

```bash
read -rs LITELLM_MASTER_KEY < <(ssh truenas_admin@192.168.1.65 'grep ^LITELLM_MASTER_KEY /mnt/fast/databases/litellm/.env | cut -d= -f2-')
ALIAS=rag-watcher    # or openclaw / dev-pc-tools
curl -sS -X POST "http://192.168.1.65:4000/key/regenerate/key_alias/$ALIAS" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" -d '{}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('new key:', d.get('key','?'))"
unset LITELLM_MASTER_KEY
```

Save new value in PM, then update the consumer:
- **rag-watcher:** `bash nas/litellm/swap-consumer-key.sh rag-watcher` (prompts silently for the new key, edits `.env` over SSH, redeploys)
- **openclaw:** in-container shell (`Apps → openclaw → Shell`), use OpenClaw's config wizard to set the new key. Verify with a Telegram message.
- **dev-pc-tools:** `claude mcp remove vault-rag && claude mcp add vault-rag … -e LITELLM_API_KEY="$NEWKEY" …` — see `compute/rag/mcp/server.py` header comment for the full registration command.

### Inspect spend per key

```bash
read -rs LITELLM_MASTER_KEY < <(ssh truenas_admin@192.168.1.65 'grep ^LITELLM_MASTER_KEY /mnt/fast/databases/litellm/.env | cut -d= -f2-')
curl -sS "http://192.168.1.65:4000/spend/keys" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | python3 -m json.tool
unset LITELLM_MASTER_KEY
```

Or use the LiteLLM dashboard at `litellm.mati-lab.online/ui` (Authelia 2FA in front).

## Install trace (reproducibility)

The TrueNAS Custom App was created via `midclt` with this payload. If you
have to rebuild from scratch (fresh NAS, whatever), re-run exactly this:

```bash
# 1. Stage config files on NAS (from the repo side)
scp nas/litellm/config.yml truenas_admin@192.168.1.65:/mnt/fast/databases/litellm/config.yml

# 2. Create the .env with master + provider keys (never committed; from password manager)
ssh truenas_admin@192.168.1.65 'cat > /mnt/fast/databases/litellm/.env <<EOF
LITELLM_MASTER_KEY=<from password manager>
DEEPSEEK_API_KEY=<platform.deepseek.com>
ANTHROPIC_API_KEY=<platform.anthropic.com>
EOF
chmod 600 /mnt/fast/databases/litellm/.env'

# 3. Install the Custom App. Call may time out on the client end but the
#    job completes in TrueNAS; verify with `midclt call app.query`.
ssh truenas_admin@192.168.1.65 "midclt call app.custom.create '$(python3 <<'PY'
import json
compose = '''services:
  litellm:
    image: litellm/litellm:v1.83.7-stable
    restart: unless-stopped
    command: [\"--config\", \"/etc/litellm/config.yml\", \"--port\", \"4000\"]
    env_file:
      - /mnt/fast/databases/litellm/.env
    volumes:
      - type: bind
        source: /mnt/fast/databases/litellm/config.yml
        target: /etc/litellm/config.yml
        read_only: true
    ports:
      - target: 4000
        published: 4000
        protocol: tcp
        mode: host
'''
print(json.dumps({'app_name': 'litellm', 'custom_compose_config_string': compose}))
PY
)'"

# 4. Verify
curl -sS http://192.168.1.65:4000/health/liveliness   # expect: {"status":"healthy"}
```

## Update / restart

| Action | Command |
|---|---|
| Apply config.yml change (live-reload) | `scp nas/litellm/config.yml truenas_admin@192.168.1.65:/mnt/fast/databases/litellm/config.yml && ssh truenas_admin@192.168.1.65 'midclt call app.redeploy litellm'` |
| Rotate provider or master key | Edit `/mnt/fast/databases/litellm/.env` on NAS (never the repo), then `midclt call app.redeploy litellm` |
| Bump image tag | Edit the compose string above (or via TrueNAS UI: Apps → litellm → Edit), re-run `app.custom.create` or `midclt call app.redeploy litellm` after editing the stored compose |
| View logs | TrueNAS UI → Apps → litellm → Logs, or `ssh ... 'cid=$(midclt call app.container_ids litellm \| python3 -c "import json,sys;print(list(json.load(sys.stdin).keys())[0])"); docker logs $cid --tail 100'` |
| Stop / start | `midclt call app.stop litellm` / `midclt call app.start litellm` |
| Remove | `midclt call app.delete litellm '{"remove_images":true}'` then delete `/mnt/fast/databases/litellm/` |

## Backup note (Phase 8 scope)

`/mnt/fast/databases/litellm/` is the entire stateful surface. Covered by
any snapshot task on `fast/databases` or `fast/databases/litellm`. The
`.env` also lives here — if you restore from a snapshot on a fresh NAS,
the provider keys come with. See `nas/snapshots.md`.
