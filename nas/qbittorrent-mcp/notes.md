# qbittorrent-mcp (NAS Custom App)

Streamable-HTTP MCP server fronting the qBittorrent Web API. Same shape as
`vault-rag-mcp`. Hermes calls clean tool names (`qbit_add_magnet`,
`qbit_list`, `qbit_pause`, …) instead of crafting raw HTTP/curl.

Deployed via `app-config.json` per `feedback_truenas_custom_app_via_midclt`.

## Endpoints

- **MCP**: `http://192.168.1.65:30020/mcp` (host port 30020 → container 8080)
- **No Caddy vhost.** LAN-only by design. Bearer-token middleware on the MCP
  server is the auth gate.

## Two auth boundaries

```
Hermes  ──[Bearer qbm-…]──>  qbit-mcp  ──[no auth, subnet bypass]──>  qBit
```

1. **Hermes → qbit-mcp**: ASGI bearer middleware enforces
   `Authorization: Bearer ${QBITTORRENT_MCP_TOKEN}`. 401 if missing or wrong.
   Token in `homelab/qbittorrent-mcp/bearer-token` (PM); copy in
   `/mnt/fast/databases/qbittorrent-mcp/.env` (`MCP_BEARER_TOKEN=`); copy in
   `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml` (literal Bearer value
   in `mcp_servers.qbittorrent.headers.Authorization` — `${VAR}`
   interpolation in headers doesn't fire in current Hermes; use the literal
   value).
2. **qbit-mcp → qBit**: qBit's "Bypass authentication for clients in
   whitelisted IP subnets" is configured for `192.168.1.0/24`,
   `172.16.0.0/12`, `10.0.0.0/8`. Containerized clients fall under
   `172.16.0.0/12`; LAN clients under `192.168.1.0/24`. No cookie dance.

The bearer protects the MCP surface; subnet bypass on qBit is the actual
LAN trust boundary. If LAN trust drops (more devices, IoT, guests on the
same VLAN), tighten qBit's bypass to `172.16.0.0/12` only — qbit-mcp keeps
working (it's on a docker bridge), LAN-direct callers need creds. See
`docs/followups.md` row 7.x.6 for that trigger.

## Config

- Image: `gitea.mati-lab.online/gooral/qbittorrent-mcp:v1` (multi-arch,
  built via `docker buildx` from `compute/qbittorrent_mcp/Dockerfile`).
- env_file: `/mnt/fast/databases/qbittorrent-mcp/.env` (mode 0600, owner
  568:568) — `MCP_BEARER_TOKEN=...`.
- Static env in compose:
  - `QBIT_BASE_URL=http://192.168.1.65:30024`
  - `MCP_TRANSPORT=streamable-http`
  - `MCP_HTTP_HOST=0.0.0.0`
  - `MCP_HTTP_PORT=8080`

## Tools exposed

| Tool | Purpose |
|---|---|
| `qbit_add_magnet(magnet, category?, save_path?, paused?)` | Queue a magnet or `.torrent` URL |
| `qbit_list(filter?, category?, sort?, limit?)` | List torrents (filter: downloading/completed/paused/etc.) |
| `qbit_get(hash)` | Detail for one torrent |
| `qbit_pause(hashes)` | Pause one or more (`hash1\|hash2\|…` or `all`) |
| `qbit_resume(hashes)` | Resume |
| `qbit_delete(hashes, delete_files?)` | Delete; `delete_files=False` keeps the data on disk |
| `qbit_categories()` | List configured categories with their save paths |

## Update / restart / remove

| Action | Command |
|---|---|
| Image bump | Edit tag in `nas/qbittorrent-mcp/app-config.json`, build + push, then `midclt call -j app.update qbittorrent-mcp ...` (replaces compose; see `feedback_truenas_app_update_replaces`) |
| Force-pull `:latest` | `midclt call -j app.pull_images qbittorrent-mcp '{"redeploy":true}'` |
| Restart | `midclt call -j app.redeploy qbittorrent-mcp` |
| Logs (Loki) | `{container=~"ix-qbittorrent-mcp-.*"}` |
| Bearer token rotation | Generate new `qbm-...`, update `/mnt/fast/databases/qbittorrent-mcp/.env` AND `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml`, then `midclt app.update qbittorrent-mcp && app.redeploy hermes` |

## Lessons / gotchas (deploy + iterate notes from session)

1. **Both auth surfaces matter.** Bearer on MCP-side is necessary; subnet
   bypass on qBit-side covers the docker bridge IPs (otherwise qBit returns
   403 to qbit-mcp). qBit's "Bypass authentication for clients in whitelisted
   IP subnets" must include `172.16.0.0/12` for containerized callers.
2. **`${VAR}` substitution in Hermes config doesn't fire inside `headers`
   blocks** — only in URL fields (and even there with caveats). Hardcode the
   literal Bearer value in the canonical config.yaml on NAS; keep `${VAR}`
   as documentation in the committed `.example`.
3. **The MCP didn't avoid a cookie dance** — qBit's subnet bypass already
   handled that. The MCP server's value is a typed tool surface for the
   agent and architectural consistency with vault-rag-mcp; not an auth
   simplification.
