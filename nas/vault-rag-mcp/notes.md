# vault-rag-mcp (NAS Custom App)

Streamable-HTTP MCP server fronting the Phase 6 Qdrant `obsidian-vault`
collection. The same `compute/rag/mcp/server.py` script that Claude Code
+ OpenCode call over stdio runs here over HTTP, so Hermes Agent (and any
other LAN MCP client) can reach the vault search tool without bundling
Python or `uv` in their own container.

Deployed as `app-config.json` per `feedback_truenas_custom_app_via_midclt`.

## Endpoints

- **MCP**: `http://192.168.1.65:30019/mcp` (host port 30019 → container 8080).
- **No Caddy vhost.** LAN-only. If we ever expose this beyond the LAN, add
  bearer-token middleware (followup `docs/followups.md` row 6.x.4) before
  putting Caddy in front.

## Config

- Image: `gitea.mati-lab.online/gooral/vault-rag-mcp:v2` (multi-arch
  amd64 + arm64, built from `compute/rag/mcp/Dockerfile` and pushed via
  dev-box `docker buildx`).
- env_file: `/mnt/fast/databases/vault-rag-mcp/.env` (mode 0600, owner
  568:568) — contains `LITELLM_API_KEY=<hermes virtual key>`. Reuses the
  same key as Hermes since it's already authorized for the `embeddings`
  alias and a shared rotation surface is fine.
- Static env in compose:
  - `QDRANT_URL=http://192.168.1.65:30017`
  - `QDRANT_COLLECTION=obsidian-vault`
  - `LITELLM_BASE_URL=http://192.168.1.65:4000`
  - `LITELLM_EMBED_MODEL=embeddings`
  - `MCP_TRANSPORT=streamable-http`
  - `MCP_HTTP_HOST=0.0.0.0`
  - `MCP_HTTP_PORT=8080`

## Update / restart / remove

| Action | Command |
|---|---|
| Image bump | Edit tag in `nas/vault-rag-mcp/app-config.json`, build + `docker buildx ... --push`, then `midclt call -j app.update vault-rag-mcp ...` (replaces compose; see `feedback_truenas_app_update_replaces`) |
| Force-pull `:latest` | `midclt call -j app.pull_images vault-rag-mcp '{"redeploy":true}'` |
| Restart | `midclt call -j app.redeploy vault-rag-mcp` |
| Logs (Loki) | `{container=~"ix-vault-rag-mcp-.*"}` |

## Lessons / gotchas

1. **Build FastMCP with host/port from env at construction time.** The
   default `FastMCP("name")` uses `host="127.0.0.1"`, which makes FastMCP
   auto-enable DNS-rebinding protection with a localhost-only allowlist
   (`["127.0.0.1:*", "localhost:*", "[::1]:*"]`). Setting
   `mcp.settings.host = "0.0.0.0"` AFTER construction doesn't undo that —
   subsequent LAN requests get 421 "Invalid Host header". Fixed in
   `compute/rag/mcp/server.py` by reading env BEFORE constructing FastMCP.
2. **Qdrant client/server version mismatch warning is benign** — image
   pulls `qdrant-client>=1.13` which lands on 1.17.x; the Phase 6 Qdrant
   server is 1.13.0. Minor delta; the `search` API we use is stable.
3. **Same image works for stdio AND streamable-http.** Switching transport
   is just `MCP_TRANSPORT=stdio` vs `streamable-http` env. Claude Code
   continues to invoke the script directly with `uv run` for stdio; this
   container is the streamable-http variant for in-LAN clients.
