# Restorate VM — Provisioning Instructions

## AI Prompt

Use this prompt with Claude Code (or similar) to generate the full Ansible provisioning for the Restorate VM. Run it from the `/home/gooral/Projects/mati-lab/compute/restorate_vm/` directory.

---

### Prompt

Create an Ansible-based VM provisioning setup for deploying the **Restorate** application (a Go + SvelteKit + PostgreSQL + Valkey restaurant rating app) on my Proxmox homelab.

**Follow the exact patterns from existing VMs in this repo** — look at `sonarqube_vm/` and `smart_resume_vm/` for structure, conventions, naming, and playbook patterns. Match them exactly.

#### VM Specification

| Setting | Value |
|---|---|
| VM ID | `105` (next available — check existing: 101-104) |
| VM Name | `restorate` |
| Template | `9000` (Debian 12 cloud-init) |
| IP | `192.168.1.203` (next in sequence after 202) |
| CPU | 2 cores |
| RAM | 2048 MB (2 GB — app uses ~250 MB total under load) |
| Disk | 20G |
| SSH user | `debian` (Debian template default) |

#### Application Stack

The app source is at `/home/gooral/Projects/resto-rate`. It's an Nx monorepo:

```
apps/
  api/      # Go backend (Connect-RPC, GORM, PostgreSQL, Valkey)
  web/      # SvelteKit frontend (Svelte 5, TailwindCSS)
packages/
  protos/   # Protobuf definitions
```

**Services to deploy via Docker Compose:**

1. **PostgreSQL 17 Alpine** — database
   - Volume: `pgdata:/var/lib/postgresql/data`
   - Health check: `pg_isready`

2. **Valkey 8.0 Alpine** — session cache (Redis-compatible)
   - Volume: `valkeydata:/data`
   - Copy `valkey.conf` from the synced source
   - Health check: `valkey-cli ping`

3. **Go API** — needs a multi-stage Dockerfile:
   - Build stage: `golang:1.25-alpine`, install protoc-gen-go + protoc-gen-connect-go, build with `-ldflags="-s -w"`
   - Runtime stage: `alpine:3.21`, copy binary, expose 3001
   - Depends on postgres + valkey (healthy)
   - Environment: database connection, Valkey URI, Google Places API key, Google OAuth client ID, session config, `ENV=prod`

4. **SvelteKit frontend** — needs a multi-stage Dockerfile:
   - Build stage: `oven/bun:1`, install deps, build with `bunx nx run web:build`
   - Runtime stage: `oven/bun:1` or `node:22-alpine`, serve the build output
   - Expose port 3000
   - Environment: `VITE_API_URL` pointing to the API

5. **Caddy** (reverse proxy) — serves both frontend and API:
   - Port 80/443
   - Auto-TLS with Let's Encrypt (or internal certs for LAN)
   - `/` → frontend (port 3000)
   - `/api/*` and all Connect-RPC service paths → API (port 3001)
   - The Connect-RPC paths follow the pattern: `/<package>.<version>.<ServiceName>/*` (e.g., `/restaurants.v1.RestaurantsService/*`)

#### Deployment Pattern

Follow the `smart_resume_vm` pattern:
- **rsync source code** from local machine to `/opt/restorate` on the VM (exclude `.git`, `node_modules`, `dist`, `.env`)
- **Write `.env` files** from Jinja2 templates using vault secrets
- **Build containers on the VM** via `docker compose build`
- **Pre-deploy checks**: `bunx nx run api:build` and `bunx nx run web:check` locally before syncing

#### Vault Secrets Needed

```yaml
# Proxmox (same as other VMs — reuse existing vault vars)
vault_proxmox_api_token_id
vault_proxmox_api_token_secret
vault_vm_root_password

# App-specific
vault_postgres_password        # PostgreSQL password
vault_valkey_password           # Valkey/Redis password
vault_google_places_api_key     # Google Places API key
vault_google_client_id          # Google OAuth client ID
vault_session_secret            # Cookie signing secret
```

#### UFW Firewall Rules

- Allow SSH (22) from anywhere
- Allow HTTP (80) from anywhere
- Allow HTTPS (443) from anywhere
- Default deny incoming

#### Environment Variables for the API (.env.j2)

Reference the existing `.env` in the restorate repo (`apps/api/.env` and root `.env`) for the full list. Key variables:

```env
ENV=prod
POSTGRES_HOST=postgres
POSTGRES_USER=restorate
POSTGRES_PASSWORD={{ vault_postgres_password }}
POSTGRES_DB=restorate
POSTGRES_PORT=5432
VALKEY_URI=valkey:6379
VALKEY_PASSWORD={{ vault_valkey_password }}
API_PORT=3001
API_HOST=restorate.mati-lab.online
API_PROTOCOL=https
WEB_UI_PORT=443
GOOGLE_PLACES_API_KEY={{ vault_google_places_api_key }}
GOOGLE_CLIENT_ID={{ vault_google_client_id }}
SEED=true
LOG_LEVEL=INFO
```

#### Important Notes

- The Go API loads `.env` from its working directory — make sure the Dockerfile sets `WORKDIR` correctly or copies `.env` to the right place
- Proto generation is needed at build time — the API Dockerfile must install `protoc-gen-go` and `protoc-gen-connect-go` and run `buf generate`
- The frontend needs `VITE_API_URL` set at BUILD time (not runtime) since Vite inlines it
- Docker daemon config should use the local registry mirror at `http://192.168.1.252:5000` (see `network/ansible/templates/daemon.json.j2`)
- All Dockerfiles should be created as Jinja2 templates in the `templates/` directory

#### Output

Generate the complete directory structure:
```
restorate_vm/
├── Makefile
├── ansible.cfg
├── requirements.yml
├── inventory/hosts.yml
├── group_vars/all/vars.yml
├── group_vars/all/vault.yml      # placeholder — I'll encrypt it
├── playbooks/site.yml
├── playbooks/create_vm.yml
├── playbooks/configure_vm.yml
├── playbooks/deploy_app.yml
└── templates/
    ├── docker-compose.yml.j2
    ├── api.env.j2
    ├── web.env.j2
    ├── Caddyfile.j2
    ├── Dockerfile.api.j2
    └── Dockerfile.web.j2
```
