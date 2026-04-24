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
| `/mnt/fast/databases/litellm/.env` | `LITELLM_MASTER_KEY`, `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` | Only on NAS. Never committed; password-manager-backed |

To apply a config.yml change: `scp nas/litellm/config.yml truenas_admin@192.168.1.65:/mnt/fast/databases/litellm/config.yml && ssh truenas_admin@192.168.1.65 'midclt call app.redeploy litellm'`.

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
