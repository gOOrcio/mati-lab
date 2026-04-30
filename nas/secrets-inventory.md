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
| **Virtual key — `rag-watcher`** | `/mnt/fast/databases/rag-watcher/.env` (`LITELLM_API_KEY=`) | `homelab/litellm/rag-watcher` | rag-watcher Custom App. | (1) LiteLLM `/key/regenerate` w/ alias. (2) Edit `.env` on NAS. (3) `midclt call -j app.pull_images rag-watcher '{"redeploy":true}'`. (4) PM. | (issued by Phase 7 Task 6) |
| **Virtual key — `openclaw`** | OpenClaw config (in-app via `openclaw config`) | `homelab/litellm/openclaw` | OpenClaw LLM provider config. | (1) LiteLLM `/key/regenerate`. (2) `openclaw config set ...` from container shell. (3) PM. | (issued by Phase 7 Task 6) |
| **Virtual key — `dev-pc-tools`** | Dev-box `~/.config/litellm/key` or shell env | `homelab/litellm/dev-pc` | Local CLI LLM tools (OpenCode, ad-hoc curl, etc.). | (1) `/key/regenerate`. (2) Update local config. (3) PM. | (issued by Phase 7 Task 6) |

See [`litellm/notes.md`](litellm/notes.md) for `/key/generate` and `/key/regenerate` curl patterns.

## Authelia (OIDC + 2FA)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Users database** | `network/authelia/data/users_database.yml` (Argon2id-hashed) | `homelab/authelia/<username>` per user | Every Caddy vhost with `forward_auth` (16+ services). | Per-user: `authelia hash-password '<new>'`, replace hash, `make deploy-authelia`. | 2026-03-XX |
| **Session secret** | `network/authelia/configuration.yml` (`session.secret`) | `homelab/authelia/session-secret` | Active user sessions; rotation invalidates all sessions (forces re-login). | (1) Edit configuration.yml. (2) `make deploy-authelia`. (3) Users re-auth. (4) PM. | (install) |
| **OIDC HMAC** | `network/authelia/data/oidc_hmac_secret.txt` | `homelab/authelia/oidc-hmac` | All OIDC clients (Proxmox, Gitea, future). Rotation invalidates issued tokens. | (1) `openssl rand -hex 64 > oidc_hmac_secret.txt`. (2) `make deploy-authelia`. (3) PM. | (install) |
| **OIDC RSA private key** | `network/authelia/data/oidc.key` | `homelab/authelia/oidc-key` | All OIDC clients (signs JWTs). | (1) `openssl genrsa -out oidc.key 4096`. (2) `make deploy-authelia`. (3) Each OIDC client may need to re-fetch `/jwks.json`. | (install) |
| **Proxmox OIDC client_secret** | `network/authelia/data/oidc_proxmox_client_secret.txt` | `homelab/authelia/oidc-proxmox-clientsecret` | Proxmox web SSO. | (1) Replace secret on NAS. (2) Update Proxmox `/etc/pve/domains.cfg` to match. (3) Both restart. | (install) |
| **Gitea OIDC client_secret** | `network/authelia/data/oidc_gitea_client_secret.txt` | `homelab/authelia/oidc-gitea-clientsecret` | Gitea web SSO. | (1) Replace secret on NAS. (2) Update Gitea OIDC provider config in admin UI to match. (3) Both restart. | (install) |

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

## Grafana

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Admin password** | `network/grafana/.env` (`GF_SECURITY_ADMIN_PASSWORD=`) | `homelab/grafana/admin` | Grafana web login + dashboard-export scripts. | (1) Pick new value. (2) Edit `.env`. (3) `make deploy-grafana`. (4) PM. | (install) |
| **Service-account / API token** | NA (Grafana DB) | `homelab/grafana/api-token` | Dashboard sync scripts (Phase 7 Tasks 14–15). | Grafana UI → Admin → Service accounts → create / rotate. | (Phase 7 Task 14 issuance) |

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
| **root@pam password** | NA | `homelab/proxmox/root` | Web UI break-glass when API tokens fail (e.g. the OIDC issue tracked in followup 7.3). | UI → root → Change password. | (install) |

## OpenClaw

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **Gateway shared bearer token** | TrueNAS Custom App form value | `homelab/openclaw/gateway-token` | Every browser/CLI/Telegram client → gateway. | Apps → openclaw → Edit → new value → save. | (install) |
| **Telegram bot token** | OpenClaw in-app config (wizard) | `homelab/openclaw/telegram-bot` | @HermesMatiBot. | BotFather → revoke + new. Update via `openclaw config`. | (install) |
| **Per-device pairing tokens** | Ephemeral, OpenClaw-managed | (none — managed in-band) | Per browser/device session. | `openclaw devices remove <id>` → re-pair. | (continuous) |

## qBittorrent

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **WebUI admin password** | qBit container config (in-app) | `homelab/qbittorrent/admin` | qBittorrent UI login (LAN bypass; Authelia 2FA externally). | UI → Tools → Options → Web UI → password; or curl per `nas/qbittorrent/notes.md:87`. | 2026-XX-XX (post Phase 2 install) |

## Obsidian (CouchDB + Syncthing)

| Role | File on disk | PM label | Dependents | Procedure | Last rotated |
|---|---|---|---|---|---|
| **CouchDB admin password** | TrueNAS Custom App form (managed via `app.update obsidian-couchdb` — must include all required fields) | `homelab/obsidian/couchdb-admin` | CouchDB admin operations only; **NOT** the LiveSync plugin. | Per `nas/obsidian/notes.md` install trace; rotate via `app.update`. | 2026-04-29 |
| **CouchDB `livesync` user password** | CouchDB internal users DB (in-app) | `homelab/obsidian/couchdb-livesync` | obsidian-livesync plugin on every Obsidian client device. Embedded in the **setup URI** (per-device QR). | (1) Per `nas/obsidian/notes.md`, PUT new password to `_users`. (2) Re-issue setup URI. (3) Each device re-applies setup URI. (4) PM. | 2026-04-29 |
| **Syncthing GUI password** | Syncthing config (in-app) | `homelab/syncthing/gui` | Syncthing web UI (LAN bypass; Authelia 2FA externally). | UI → Settings → GUI → set password. | 2026-04-29 |
| **Setup URI (per-device)** | Per device — pasted into obsidian-livesync settings | `homelab/obsidian/setup-uri-<device>` | The CouchDB `livesync` password is *embedded* in this URI. | Regenerate when livesync password rotates. | (continuous) |

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
