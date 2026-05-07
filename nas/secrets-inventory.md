# Secrets inventory

The single source of truth for "where every long-lived secret lives, what depends on it, and how to rotate it." **Values are NEVER in this file** — they live in the password manager under `homelab/<service>/<role>` labels. This doc is the index.

If you rotate a secret, update its row's "Last rotated" date.

## How to use this file

- **Rotation triggered by a leak** → find the row, follow Procedure, then update Last rotated.
- **Rotation triggered by calendar** → annual sweep of every row whose Procedure cost is < 10 minutes.
- **Adding a new service** → add a row before the service ships. If the row would have no dependents, the secret probably doesn't need to exist.
- **Forgotten where something lives** → search this file first. Per-service notes add detail; this is the index.

## Conventions

- **PM label** is the password-manager entry name. The value lives there, never here.
- **Dependents** = what breaks if this secret rotates without coordination.
- **Procedure** = the minimum sequence to change the value end-to-end. Cross-references to per-service notes for nuance.
- **Last rotated** = ISO date. Empty = never rotated since install.

---

## LiteLLM

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Master key** | `/mnt/fast/databases/litellm/.env` (`LITELLM_MASTER_KEY=`) | `homelab/litellm/master` | LiteLLM admin operations only (issuing virtual keys, viewing all spend, editing config). Should be consumed by **no** deployed service after Phase 7 Tasks 6–9. | (1) Generate 64-char random. (2) Edit `.env` on NAS. (3) `midclt call app.redeploy litellm`. (4) Verify via curl. (5) Update PM. | 2026-04-24 (install) |
| **DeepSeek key** | `/mnt/fast/databases/litellm/.env` (`DEEPSEEK_API_KEY=`) | `homelab/litellm/deepseek-provider` | LiteLLM `agent-default` + `coding` aliases (DeepSeek path). Without it: those aliases fall back to Claude / local Ollama. | (1) `platform.deepseek.com` → API Keys → rotate. (2) Edit `.env` on NAS. (3) `app.redeploy litellm`. (4) PM. | 2026-04-24 |
| **Anthropic key** | `/mnt/fast/databases/litellm/.env` (`ANTHROPIC_API_KEY=`) | `homelab/litellm/anthropic-provider` | LiteLLM `agent-smart` + `agent-default` fallback. | (1) `console.anthropic.com` → Keys → rotate. (2) Edit `.env`. (3) `app.redeploy litellm`. (4) PM. | 2026-04-24 |
| **Virtual key — `rag-watcher`** | `/mnt/fast/databases/rag-watcher/.env` (`LITELLM_API_KEY=`) | `homelab/litellm/rag-watcher` | rag-watcher Custom App. | (1) LiteLLM `/key/regenerate/key_alias/rag-watcher`. (2) `bash nas/litellm/swap-consumer-key.sh rag-watcher` (prompts silently). (3) PM. | 2026-04-30 (issued + first use) |
| **Virtual key — `hermes`** | `/mnt/fast/databases/hermes/.env` (`OPENAI_API_KEY=`) on NAS for Hermes; `/mnt/fast/databases/vault-rag-mcp/.env` (`LITELLM_API_KEY=`) for vault-rag-mcp. Hermes uses OPENAI_API_KEY for `provider: custom` (LiteLLM is OpenAI-compatible). | `homelab/litellm/hermes` | Hermes Agent LLM provider auth + vault-rag-mcp embeddings (`embeddings` alias). | (1) LiteLLM `/key/regenerate/key_alias/hermes`. (2) Edit BOTH `.env` files. (3) `midclt call -j app.redeploy hermes && midclt call -j app.redeploy vault-rag-mcp`. (4) PM. | 2026-05-01 (alias renamed openclaw → hermes via `/key/update`; in production for both consumers) |
| **Bearer — `vault-rag-mcp`** | `/mnt/fast/databases/vault-rag-mcp/.env` (`MCP_BEARER_TOKEN=`) on NAS. Hermes-side copy: `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml` literal value in `mcp_servers.vault-rag.headers.Authorization` (NOT env-interpolated; `${VAR}` doesn't fire inside `headers`). | `homelab/vault-rag-mcp/bearer-token` | vault-rag-mcp ASGI bearer middleware. Without matching token: every Hermes request gets 401. | (1) `openssl rand -hex 24` — prefix `vrm-`. (2) Edit `/mnt/fast/databases/vault-rag-mcp/.env`. (3) Edit `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml`. (4) `midclt app.update vault-rag-mcp && app.redeploy hermes`. (5) PM. | 2026-05-01 (issued at install) |
| **Bearer — `qbittorrent-mcp`** | `/mnt/fast/databases/qbittorrent-mcp/.env` (`MCP_BEARER_TOKEN=`) on NAS. Hermes-side copy: `/mnt/.ix-apps/app_mounts/hermes/data/config.yaml` literal value in `mcp_servers.qbittorrent.headers.Authorization`. | `homelab/qbittorrent-mcp/bearer-token` | qbittorrent-mcp ASGI bearer middleware. Same shape as vault-rag-mcp bearer. | Same procedure as vault-rag-mcp bearer above (substitute `qbm-` prefix and `qbittorrent-mcp` paths). | 2026-05-01 (issued at install) |
| **Virtual key — `dev-pc-tools`** | Dev-box Claude Code MCP server config (`~/.claude/...` user-scope) + shell env for ad-hoc tooling | `homelab/litellm/dev-pc-tools` | Claude Code MCP `vault-rag` tool, OpenCode, ad-hoc curl. | (1) `/key/regenerate/key_alias/dev-pc-tools`. (2) `claude mcp remove vault-rag && claude mcp add vault-rag … -e LITELLM_API_KEY="$NEW" …`. (3) Restart Claude Code. (4) PM. | 2026-04-30 (issued, awaiting MCP rewire) |
| **Postgres password (LiteLLM sidecar)** | `/mnt/fast/databases/litellm/.env` (`POSTGRES_PASSWORD=`) | `homelab/litellm/postgres` | LiteLLM ↔ litellm-postgres connection (the `DATABASE_URL` env var also encodes this). Without it: virtual-key endpoints 500 with `DB not connected`. | (1) Pick new value. (2) Edit BOTH `POSTGRES_PASSWORD=` AND `DATABASE_URL=` lines in `.env` (the URL contains the password inline). (3) **Postgres has the OLD password baked into pg_hba** — to rotate without losing data: `docker exec litellm-postgres psql -U litellm -c "ALTER USER litellm PASSWORD '<new>'"` BEFORE editing `.env`. Then redeploy LiteLLM. (4) PM. | 2026-04-30 (issued at Phase 7 install) |
| **DATABASE_URL** | `/mnt/fast/databases/litellm/.env` (`DATABASE_URL=`) | (encodes the Postgres password — see PM under `homelab/litellm/postgres`) | LiteLLM virtual-key store connection. | Co-rotates with Postgres password row above. | 2026-04-30 |

See [`litellm/notes.md`](litellm/notes.md) for `/key/generate`, `/key/regenerate`, and `/spend/keys` curl patterns. The committed helper scripts `nas/litellm/issue-keys.sh` and `nas/litellm/swap-consumer-key.sh` cover the common rotation flows.

## Authelia (OIDC + 2FA)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Users database** | `network/authelia/data/users_database.yml` (Argon2id-hashed) | `homelab/authelia/<username>` per user | Every Caddy vhost with `forward_auth` (16+ services). | Per-user: `authelia hash-password '<new>'`, replace hash, `make deploy-authelia`. | 2026-03-XX |
| **Session secret** | `network/authelia/configuration.yml` (`session.secret`) | `homelab/authelia/session-secret` | Active user sessions; rotation invalidates all sessions (forces re-login). | (1) Edit configuration.yml. (2) `make deploy-authelia`. (3) Users re-auth. (4) PM. | (install) |
| **OIDC HMAC** | `network/authelia/data/oidc_hmac_secret.txt` | `homelab/authelia/oidc-hmac` | All OIDC clients (Proxmox, Gitea, future). Rotation invalidates issued tokens. | (1) `openssl rand -hex 64 > oidc_hmac_secret.txt`. (2) `make deploy-authelia`. (3) PM. | (install) |
| **OIDC RSA private key** | `network/authelia/data/oidc.key` | `homelab/authelia/oidc-key` | All OIDC clients (signs JWTs). | (1) `openssl genrsa -out oidc.key 4096`. (2) `make deploy-authelia`. (3) Each OIDC client may need to re-fetch `/jwks.json`. | (install) |
| **Proxmox OIDC client_secret** | `network/authelia/data/oidc_proxmox_client_secret.txt` | `homelab/authelia/oidc-proxmox-clientsecret` | Proxmox web SSO. | (1) Replace secret on NAS. (2) Update Proxmox `/etc/pve/domains.cfg` to match. (3) Both restart. | (install) |
| **Gitea OIDC client_secret** | `network/authelia/data/oidc_gitea_client_secret.txt` | `homelab/authelia/oidc-gitea-clientsecret` | Gitea web SSO. | (1) Replace secret on NAS. (2) Update Gitea OIDC provider config in admin UI to match. (3) Both restart. | (install) |
| **LiteLLM OIDC client_secret** | Hash on Pi at `network/authelia/data/oidc_litellm_client_secret.txt` (Argon2id); plaintext on NAS at `/mnt/fast/databases/litellm/.env` (`GENERIC_CLIENT_SECRET=`) | `homelab/authelia/oidc-litellm-clientsecret` | LiteLLM admin UI SSO ("Login with SSO" button on `litellm.mati-lab.online/ui`). Mismatch between hash and plaintext → SSO callback 401. | (1) `openssl rand -hex 32` for plaintext. (2) `docker exec authelia authelia crypto hash generate argon2 --password '<plain>'` → write `Digest:` value to the .txt on Pi. (3) Replace `GENERIC_CLIENT_SECRET=<plain>` in NAS .env. (4) `make deploy-authelia` + `midclt call app.redeploy litellm`. | 2026-04-30 |

## Caddy (Cloudflare DNS challenges)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **CF_API_TOKEN** | `network/caddy/.env` (`CF_API_TOKEN=`) | `homelab/cloudflare/dns-challenge` | TLS cert renewal for `*.mati-lab.online`. Without it: certs expire (90 days), all HTTPS dies. | (1) `dash.cloudflare.com` → API Tokens → roll. Scope: Zone:DNS:Edit on `mati-lab.online`. (2) Edit `.env` on Pi. (3) `make deploy-caddy`. (4) PM. | (install) |

## Cloudflared (tunnels)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Tunnel credential JSON** | `network/cloudflared/credentials.json` (Pi); `/mnt/fast/databases/cloudflared/credentials.json` (NAS, Phase 1A) | `homelab/cloudflare/tunnel-credentials-pi`, `homelab/cloudflare/tunnel-credentials-nas` | Public hostname routing: every `*.mati-lab.online` reaches Pi/NAS through these tunnels. | (1) `cloudflared tunnel rotate <name>`. (2) Replace credentials.json on the host. (3) Restart cloudflared container. (4) PM. | (install) |

## Pi-hole

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Admin password** | `network/pihole/.env` (`PIHOLE_ADMIN_PASS=`) | `homelab/pihole/admin` | Pi-hole web UI login. Rotation requires next deploy. | (1) Pick new value. (2) Edit `.env`. (3) `make deploy-pihole`. (4) PM. | (install) |
| **App password (Homepage widget)** | `network/pihole/.env` (`PIHOLE_API_KEY=`) — referenced by `homepage.widget.key` label on the pihole compose | `homelab/pihole/homepage-app-password` | Homepage Pi-hole widget. Without it: widget shows auth error; the rest of the dashboard is unaffected. Pi-hole 6 uses an "app password" (in UI: Settings → API → Generate app password). | (1) Pi-hole UI → Settings → API → Configure app passwords → Add. (2) Edit `network/.env` on Pi (`PIHOLE_API_KEY=`). (3) `make deploy-homepage`. (4) PM. | pending mint (afternoon 2026-05-06) |

## Grafana

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Admin password** | `network/grafana/.env` (`GF_SECURITY_ADMIN_PASSWORD=`) | `homelab/grafana/admin` | Grafana web login + dashboard-export scripts. | (1) Pick new value. (2) Edit `.env`. (3) `make deploy-grafana`. (4) PM. | (install) |
| **Service-account / API token** | NA (Grafana DB) | `homelab/grafana/api-token` | Dashboard sync scripts (Phase 7 Tasks 14–15). | Grafana UI → Admin → Service accounts → create / rotate. | (Phase 7 Task 14 issuance) |
| **Viewer user password (Homepage widget)** | `network/.env` on Pi (`GRAFANA_VIEWER_PASSWORD=`) — referenced by `homepage.widget.password` label on the grafana compose | `homelab/grafana/homepage-viewer` | Homepage Grafana widget. Read-only `Viewer` role, used to display dashboard counts. Without it: widget shows auth error. | (1) Grafana UI → Server admin → Users → New user (role: Viewer, username: `homepage`). (2) Edit `network/.env` on Pi. (3) `make deploy-homepage`. (4) PM. | pending mint (afternoon 2026-05-06) |

## ntfy

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Access token** | `network/ntfy/server.yml` (auth-users; password hash) + caller-side `network/grafana-ntfy-bridge/.env`, `network/uptime-kuma/.env`, etc. | `homelab/ntfy/<topic-or-user>` | Any service publishing to ntfy (uptime-kuma, grafana-ntfy-bridge, scripts). | (1) `ntfy user change-pass`. (2) Update every consumer's `.env`. (3) Redeploy each. (4) PM. | (install — re-created post-Pi-LTS per `reference_ntfy_post_install`) |

## Gitea

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Postgres `db_password`** | TrueNAS Custom App env (managed via `app.update gitea`) | `homelab/gitea/db-password` | Gitea ↔ Postgres. **`app.update` REPLACES nested groups** (see `feedback_truenas_app_update_replaces`) — include all required fields. | (1) Pick new. (2) Update both Gitea + Postgres app values atomically via `app.update`. (3) PM. | (install) |
| **`pi-registry-pull` PAT** | Pi `/opt/mati-lab/.env`-style location | `homelab/gitea/pat-pi-registry-pull` | Pi-side `docker login gitea.mati-lab.online`; pulls private images. | (1) Gitea UI → Settings → PATs → revoke + re-issue (scope: `read:package`). (2) Update on Pi. (3) `docker login gitea...`. (4) PM. | (install) |
| **`network-pi-metrics` PAT** | Pi `/opt/mati-lab/network-pi-metrics/.env` | `homelab/gitea/pat-network-pi-metrics` | network-pi-metrics container pushing metrics back to Gitea (Phase 4 follow-up). | Same shape as above. | (install) |
| **CI repo secrets `REGISTRY_USER` / `REGISTRY_TOKEN`** | Gitea repo-level secrets (per repo) | `homelab/gitea/repo-secrets/<repo>` | CI pipelines pushing images. | Gitea UI → repo → Settings → Secrets → rotate per repo. | (Phase 4 install) |
| **Runner registration token** | One-shot; consumed at registration, then deleted | (none — ephemeral) | act_runner registration. | Re-register: Site Admin → Actions → Runners → new token; re-run runner registration playbook. | (install — one-shot, never reused) |

## TrueNAS

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **truenas_admin SSH key** | `~/.ssh/id_ed25519` (dev box, public part installed on NAS) | `homelab/nas/ssh-truenas-admin-pubkey` | All `ssh truenas_admin@192.168.1.65` calls in this repo, all `make` targets that touch the NAS. | (1) Generate new keypair. (2) Add public key to `truenas_admin` authorized_keys via UI. (3) Remove old. (4) PM (private only on dev box). | (install) |
| **root password** | NA (rare-use; prefer `truenas_admin` SSH) | `homelab/nas/root` | Console / IPMI break-glass. | UI → Credentials → Local Users → root → Edit. | (install) |

## Proxmox

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **API token id + secret** | Vault (`compute/*_vm/group_vars/all/vault.yml`) — encrypted | `homelab/proxmox/api-token` | Ansible playbooks for VM/LXC lifecycle (`compute/{ollama_vm,gitea_runner_vm,...}/`). | (1) Proxmox UI → Datacenter → Permissions → API Tokens → roll. (2) `ansible-vault edit vault.yml`. (3) PM. | (install) |
| **root@pam password** | NA | `homelab/proxmox/root` | Web UI break-glass when API tokens fail. | UI → root → Change password. | (install) |
| **OIDC realm `client-key`** | `/etc/pve/domains.cfg` on Proxmox (line `client-key <hex>` under `openid: authelia`) | `homelab/authelia/oidc-proxmox-clientsecret` (paired w/ Authelia row above — they MUST match) | Proxmox web SSO via Authelia OIDC. Mismatch → 401 on login. | See [`compute/proxmox_host/notes.md`](../compute/proxmox_host/notes.md) "OIDC integration" — rotate Authelia + `domains.cfg` together, then `make deploy-authelia` + `systemctl reload pveproxy`. | (install — Phase 4) |
| **Read-only API token (Homepage)** | `network/.env` on Pi (`PROXMOX_HOMEPAGE_TOKEN_ID=` and `PROXMOX_HOMEPAGE_TOKEN_SECRET=`); referenced by `widgets.yaml` proxmox block via `HOMEPAGE_VAR_PROXMOX_TOKEN_*` | `homelab/proxmox/homepage-readonly` | Homepage Proxmox widget (VM/LXC counts + node CPU/memory). Separate from the Ansible/`pve-exporter` token for cleaner audit + independent revocation. Token user `homepage@pve`, token id `dashboard`, role `PVEAuditor` at path `/`. | (1) Proxmox UI → Datacenter → Permissions → API Tokens → roll. (2) Edit `network/.env` on Pi. (3) `make deploy-homepage`. (4) PM. | pending mint (afternoon 2026-05-06) |

## Hermes Agent

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Telegram bot token** | `/mnt/fast/databases/hermes/.env` (`TELEGRAM_BOT_TOKEN=`) on NAS | `homelab/openclaw/telegram-bot` (PM label kept from OpenClaw install for continuity; could be retitled to `homelab/hermes/telegram-bot` next rotation) | `@HermesMatiBot` (Telegram). | BotFather → `/revoke` + new. Edit `.env` on NAS, `midclt call app.redeploy hermes`. PM. | (BotFather install — preserved across OpenClaw → Hermes pivot 2026-05-01) |
| **Telegram allowed users** | `/mnt/fast/databases/hermes/.env` (`TELEGRAM_ALLOWED_USERS=`) | (no PM entry — list of numeric user IDs, not a secret) | Hermes Telegram allowlist. | Add comma-sep IDs in `.env`, `app.redeploy hermes`. | (install) |
| **Per-session dashboard tokens** | Ephemeral, Hermes-managed (embedded in dashboard HTML) | (none — managed in-band) | Per browser session at `https://hermes.mati-lab.online`. | New token issued each session; nothing to rotate manually. | (continuous) |

## qBittorrent

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **WebUI admin password** | qBit container config (in-app, persisted at `/mnt/fast/databases/qbittorrent-config/qBittorrent/qBittorrent.conf`) | `homelab/qbittorrent/admin` | qBittorrent UI login (LAN bypass; Authelia 2FA externally). | UI → Tools → Options → Web UI → password; or curl per `nas/qbittorrent/notes.md:87`. | 2026-XX-XX (post Phase 2 install) |

## vpn-stack (Gluetun / ProtonVPN)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **ProtonVPN account** | account.proton.me login | `homelab/protonvpn/account` | Login required to (re)generate WireGuard configs in Proton's UI. | Reset via Proton UI / email recovery. | (subscription purchased 2026-05-01) |
| **WireGuard config (full `.conf`)** | per-device, regenerated in Proton UI | `homelab/protonvpn/wireguard-config-vpn-stack-nas` | Source of truth for the private key staged on NAS. | Proton UI → VPN → WireGuard → delete + re-create with same name. Re-stage on NAS. | 2026-05-01 |
| **WireGuard private key** | NAS `/mnt/fast/databases/vpn-stack/.env` `WIREGUARD_PRIVATE_KEY=` (root:root 0600) | `homelab/protonvpn/wireguard-private-key` | Gluetun's tunnel establishment. Loss = no VPN egress (killswitch holds → qBit/Prowlarr go silent). | (1) New WG config in Proton UI → copy `PrivateKey` value. (2) `read -rs KEY && ssh -t truenas_admin@nas 'sudo install -m 0600 -o root -g root /dev/stdin /mnt/fast/databases/vpn-stack/.env <<<"WIREGUARD_PRIVATE_KEY=$KEY"'`. (3) `app.redeploy vpn-stack`. (4) PM. (5) Verify Gluetun's public IP via `/v1/publicip/ip`. | 2026-05-01 |

## *arr stack (Sonarr / Radarr / Prowlarr / Bazarr)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Sonarr API key** | `/mnt/fast/databases/sonarr/config/config.xml` `<ApiKey>` | `homelab/sonarr/api-key` | Prowlarr `Apps → Sonarr`, Bazarr `sonarr.apikey`, future Jellyfin-Connect or scrapers. | (1) Sonarr UI → Settings → General → Security → API Key → regenerate. (2) Update Prowlarr `Apps → Sonarr → Edit → API Key`. (3) Update Bazarr settings (UI or config.yaml at `/mnt/fast/databases/bazarr/config/config/config.yaml` `sonarr.apikey`, then `app.stop bazarr && app.start bazarr`). (4) PM. | 2026-05-01 (issued at install) |
| **Radarr API key** | `/mnt/fast/databases/radarr/config/config.xml` `<ApiKey>` | `homelab/radarr/api-key` | Prowlarr `Apps → Radarr`, Bazarr `radarr.apikey`. | Same shape as Sonarr's, mutatis mutandis. | 2026-05-01 (issued at install) |
| **Prowlarr API key** | `/mnt/fast/databases/prowlarr/config/config.xml` `<ApiKey>` | `homelab/prowlarr/api-key` | (None today — no external apps reference Prowlarr's key. Will become load-bearing if a scraper / MCP / dashboard is added.) | Settings → General → Security → API Key → regenerate. PM. | 2026-05-01 (issued at install) |
| **Bazarr API key** | `/mnt/fast/databases/bazarr/config/config/config.yaml` `auth.apikey` | `homelab/bazarr/api-key` | (None today — Bazarr is a leaf consumer.) | Settings → General → Security → API Key (UI). PM. | 2026-05-01 (issued at install) |
| **Subtitle provider creds (per provider)** | Bazarr's settings DB / `config.yaml` block per provider | `homelab/bazarr/provider-<name>` (added when each provider is wired) | Bazarr subtitle pulls. | Bazarr UI → Settings → Providers → click provider → paste/rotate creds. PM. | (set per provider at first use) |
| **Indexer creds in Prowlarr (per private tracker)** | Prowlarr's settings DB | `homelab/prowlarr/indexer-<name>` (added when each tracker is wired) | Prowlarr indexer searches; downstream Sonarr/Radarr searches via Prowlarr. | Prowlarr UI → Indexers → click indexer → rotate creds (cookies / API keys). PM. Some private trackers reject qBit's `anonymous_mode=true`; flip per-tracker if rejected, not globally. | (set per tracker at first use) |
| **Subtitle provider creds (paid: opensubtitles VIP)** | opensubtitles.com account | `homelab/bazarr/provider-opensubtitlescom` | Bazarr subtitle pulls. Free tier: 5/day; VIP: 1000/day. | opensubtitles.com → Account → password reset. Bazarr → Settings → Providers → opensubtitlescom → re-paste. | 2026-05-01 (VIP purchased) |

## *arr stack — backups + automation

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Recyclarr Kuma push URL** | NAS `/root/.backup-env` (`KUMA_URL_RECYCLARR_SYNC=`, root:root 600) | `homelab/uptime-kuma/push-recyclarr-sync` | Weekly recyclarr-sync heartbeat (Sun 04:30 UTC). | Mint new push monitor in Kuma UI; `read -rs URL && ssh ... "sudo sed -i '/^KUMA_URL_RECYCLARR_SYNC=/d' /root/.backup-env && sudo tee -a /root/.backup-env <<<\"KUMA_URL_RECYCLARR_SYNC=$URL\""`. PM. | 2026-05-01 (issued at install) |
| **`SONARR_API_KEY` / `RADARR_API_KEY` / `PROWLARR_API_KEY` / `BAZARR_API_KEY` env vars** | NAS `/root/.backup-env` (root:root 600) | (cleartext copies of the same `homelab/{sonarr,radarr,prowlarr,bazarr}/api-key` PM rows above) | `recyclarr-sync.sh` (Sonarr+Radarr) and `arr-config-backup.sh` (all four — API-issued backup ZIPs). | When rotating the *arr API key in its UI, also update the corresponding line in `/root/.backup-env`. PM stays the same row. | 2026-05-01 (initial stage) |

## Jellyseerr

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Jellyseerr admin login** | n/a (delegates to Jellyfin user DB) | (uses `homelab/jellyfin/admin`) | Jellyseerr UI auth — first Jellyfin user is auto-promoted to Jellyseerr admin. | Rotates with the Jellyfin admin password; no separate Jellyseerr-side action. | n/a |
| **Jellyseerr API key** (only minted if a future automation needs it) | Settings → General → API Key (in `/mnt/fast/databases/jellyseerr/config/db/db.sqlite3`) | `homelab/jellyseerr/api-key` (when needed) | Whatever uses it — not load-bearing today. | UI → Settings → General → API Key → regenerate. PM. | (not minted as of install) |

## Obsidian (CouchDB + Syncthing)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **CouchDB admin password** | TrueNAS Custom App form (managed via `app.update obsidian-couchdb` — must include all required fields) | `homelab/obsidian/couchdb-admin` | CouchDB admin operations only; **NOT** the LiveSync plugin. | Per `nas/obsidian/notes.md` install trace; rotate via `app.update`. | 2026-04-29 |
| **CouchDB `livesync` user password** | CouchDB internal users DB (in-app) | `homelab/obsidian/couchdb-livesync` | obsidian-livesync plugin on every Obsidian client device. Embedded in the **setup URI** (per-device QR). | (1) Per `nas/obsidian/notes.md`, PUT new password to `_users`. (2) Re-issue setup URI. (3) Each device re-applies setup URI. (4) PM. | 2026-04-29 |
| **Syncthing GUI password** | Syncthing config (in-app) | `homelab/syncthing/gui` | Syncthing web UI (LAN bypass; Authelia 2FA externally). | UI → Settings → GUI → set password. | 2026-04-29 |
| **Setup URI (per-device)** | Per device — pasted into obsidian-livesync settings | `homelab/obsidian/setup-uri-<device>` | The CouchDB `livesync` password is *embedded* in this URI. | Regenerate when livesync password rotates. | (continuous) |

## Homebridge

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **UI admin password** | Homebridge UI in-app users DB on Pi 4 (in the backup tar.gz as `auth.json`) | `homelab/homebridge/admin` | Homebridge UI login + the `homebridge-backup.sh` cron (uses these creds to mint a JWT and pull the backup endpoint). | (1) Homebridge UI → Users → Edit → set new password. (2) Update `HOMEBRIDGE_PASSWORD=` in NAS `/root/.backup-env`. (3) Verify with `midclt cronjob.run <id>` of the homebridge-backup cron. (4) PM. | 2026-05-04 (issued at install) |
| **`HOMEBRIDGE_USERNAME` / `HOMEBRIDGE_PASSWORD` env** | NAS `/root/.backup-env` (root:root 0600) | (cleartext copies of the same `homelab/homebridge/admin` PM row) | `homebridge-backup.sh`. | Co-rotate with the UI password row above. | 2026-05-04 |
| **Homepage dashboard user** | `network/.env` on Pi (`HOMEBRIDGE_USERNAME=` / `HOMEBRIDGE_PASSWORD=`); referenced by `widgets.yaml` homebridge block via `HOMEPAGE_VAR_HOMEBRIDGE_*` | `homelab/homebridge/homepage` | Homepage Homebridge widget (accessory state). Separate from the admin/backup user above to keep blast radius minimal. Read-only role if Homebridge supports it; standard user otherwise. | (1) Homebridge UI → Manage Users → Add `homepage` user. (2) Edit `network/.env` on Pi. (3) `make deploy-homepage`. (4) PM. | pending mint (afternoon 2026-05-06) |

## Dev PC

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Restic repo password** | Dev PC `~/.config/restic/repo-password` (0600) | `homelab/dev-pc/restic-repo-password` | Decrypts the entire dev-PC restic repo (`~/Projects`, `~/.claude`, `~/.ssh`, dotfiles). **Loss = unrecoverable backups** — same property as the NAS dump passphrase (intentional: the repo password is meaningful precisely because PM is the only holder). | Restic supports adding a second password to the repo before retiring the old one: (1) `restic key add` (paste new). (2) Replace contents of `~/.config/restic/repo-password`. (3) `restic key remove <old-id>`. (4) PM. | 2026-05-04 (issued at install) |

## Sentinel Trader (compute)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **XTB broker creds** | Sentinel Trader VM `.env` (`XTB_USER_ID`, `XTB_PASSWORD`) | `homelab/sentinel-trader/xtb` | Trading bot. | XTB account portal → roll → update VM `.env` → restart bot. | (Phase 5 install) |
| **Anthropic key** | Sentinel Trader VM `.env` (`ANTHROPIC_API_KEY`) | `homelab/sentinel-trader/anthropic` | Sentinel Trader's Claude calls (separate from LiteLLM). | Anthropic console → roll → update `.env`. | (install) |
| **Telegram bot** | Sentinel Trader VM `.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`) | `homelab/sentinel-trader/telegram` | Sentinel Trader notifications. | BotFather → roll → update `.env`. | (install) |

## Gitea Runner VM

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **VM root password** | `compute/gitea_runner_vm/group_vars/all/vault.yml` (Ansible-vault encrypted) | `homelab/gitea-runner-vm/root` | Console + Ansible bootstrap. | `ansible-vault edit vault.yml`. | (install) |
| **Runner registration token** | One-shot (consumed at register, then deleted) | (none) | act_runner identity. | Re-register on Gitea Site Admin → Actions → Runners. | (install) |

---

## Backups

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Backup encryption passphrase** | NAS `/mnt/bulk/backups/.secrets/dump-passphrase` (root:root 600) | `homelab/backups/dump-passphrase` | Every cron under `nas/backup-jobs/*.sh` (`gpg --symmetric --passphrase-file ...`), now including `arr-config-backup.sh`. **Loss = unrecoverable backups (intentional security property — encryption is meaningful precisely because the only key holder is the password manager).** | (1) `openssl rand -base64 48` for new value. (2) **Decrypt + re-encrypt every existing dump under `bulk/backups/{gitea,litellm,hermes,arr}*` with the new passphrase** — they were written under the old one. (3) Re-stage via `bash nas/backup-jobs/stage-passphrase.sh` (silent prompt + stdin pipe). (4) Update PM. | 2026-04-30 (issued at Phase 8 install) |
| **Kuma push URL — `arr-config-backup`** | NAS `/root/.backup-env` (`KUMA_URL_ARR_CONFIG=`, root:root 600) | `homelab/uptime-kuma/push-arr-config-backup` | `arr-config-backup.sh` weekly heartbeat. | Mint a new push monitor in Kuma UI; copy the bare URL (strip query string per `feedback_kuma_push_url_query_string`). Stage via `read -rs URL && ssh truenas_admin@nas "sudo tee -a /root/.backup-env <<<\"KUMA_URL_ARR_CONFIG=$URL\""`. PM. | 2026-05-01 (issued at install) |
| **Kuma push URL — `homebridge-backup`** | NAS `/root/.backup-env` (`KUMA_URL_HOMEBRIDGE=`, root:root 600) | `homelab/uptime-kuma/push-homebridge-backup` | `homebridge-backup.sh` weekly heartbeat. | Same shape as `arr-config-backup`. | 2026-05-04 (issued at install) |
| **Kuma push URL — `dev-pc-restic`** | Dev PC `~/.config/restic/kuma-push-url` (mode 0600) | `homelab/uptime-kuma/push-dev-pc-restic` | `restic-backup.sh` (dev PC, daily heartbeat). | Mint push monitor in Kuma UI (interval 86400s); paste bare URL into the file via `compute/dev_pc/backup/install.sh`. PM. | 2026-05-04 (issued at install) |

## Cross-references

- LiteLLM `/key/generate` curl pattern: [`litellm/notes.md`](litellm/notes.md) "Virtual keys" section (added in Phase 7 Task 9).
- TrueNAS Custom App `app.update` replacement footgun: [feedback memory `feedback_truenas_app_update_replaces`].
- ntfy post-install setup: [reference memory `reference_ntfy_post_install`].
- Caddyfile bind-mount + reload nuance: [feedback memory `feedback_caddy_bind_mount_recreate`].

## What this file is NOT

- A backup. Password manager is the backup; this file is the index.
- A list of *every* secret. Ephemeral / per-session tokens (OpenClaw dashboard URL, OAuth state cookies, JWT access tokens) are not here.
- Secret values. Ever.

## Adding a row

When you ship a new service, before its first `make deploy` runs:
1. Decide the secret's name + scope.
2. Generate the value.
3. Save in PM under `homelab/<service>/<role>`.
4. Add a row here with empty Last rotated.
5. Reference this row from the service's `notes.md`.

If step 5 is hard to phrase, the secret probably doesn't need to exist.

