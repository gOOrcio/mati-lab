# Phase 0 — Proxmox Optimization Design

**Goal:** Recover ~7 GB RAM on Proxmox by migrating VMs to LXC containers, removing SonarQube, and tuning host settings. Frees resources for the Gitea runner VM in Phase 4.

## Current State

| VM | ID | vCPU | RAM | Disk | IP | Purpose |
|----|-----|------|-----|------|----|---------|
| smart-resume | 102 | 2 | 2 GB | 20 GB | .200 | Astro frontend + FastAPI + RAG |
| sonarqube | 103 | 4 | 4 GB | 30 GB | .201 | SonarQube CE + PostgreSQL |
| restorate | 105 | 2 | 4 GB | 20 GB | .203 | Go API + SvelteKit SSR + PG + Valkey |
| ollama-gpu | 101 | 4 | 12 GB | 128 GB | .48 | GPU passthrough, Ollama |

All VMs run Docker Compose stacks internally. Each VM includes the Docker daemon overhead (~100-200 MB) plus VM overhead (kernel, QEMU, etc.).

## Target State

| Container | Type | vCPU | RAM | Disk | Temp IP | Final IP | Purpose |
|-----------|------|------|-----|------|---------|----------|---------|
| smart-resume | LXC | 1 | 1 GB | 10 GB | .210 | .200 | Native: Caddy + uvicorn + FAISS |
| restorate | LXC | 2 | 2 GB | 20 GB | .211 | .203 | Native: Caddy + Go binary + Node SSR + PG + Valkey |
| ollama-gpu | VM | 4 | 4-12 GB (balloon) | 128 GB | — | .48 | Unchanged, add ballooning |
| sonarqube | — | — | — | — | — | — | Removed entirely |

**RAM freed:** smart-resume 2→1 GB, restorate 4→2 GB, sonarqube 4→0 GB, ollama balloon min 12→4 GB. Net savings: ~7-11 GB depending on Ollama balloon pressure.

## Design Decisions

### Native services, no Docker-in-LXC

LXC is the container isolation layer — nesting Docker inside it defeats the optimization purpose. Docker daemon alone costs 100-200 MB RAM. Apps run as systemd services with packages installed directly.

### Unprivileged LXC

All containers run unprivileged (container root maps to non-root UID on host). No `nesting=1` feature needed since there's no Docker.

### Debian 12 LXC template

Consistent with existing VM template (9000). Alpine would save ~10-20 MB but risks musl libc issues with Python packages (faiss-cpu/numpy) and PostgreSQL. Not worth it.

### Ansible stays

The existing Ansible patterns work well at this scale. New LXC playbooks use `community.general.proxmox` instead of `proxmox_kvm`; configure/deploy playbooks replace Docker tasks with package installs and systemd units.

### Temporary IPs for safe cutover

New LXCs get temporary IPs (.210, .211) for testing. After validation, VMs are decommissioned and LXCs get the original IPs (.200, .203). This avoids downtime and lets both run simultaneously during testing.

## Directory Structure

```
compute/
  smart_resume_lxc/            # NEW
    ansible.cfg
    requirements.yml
    Makefile
    inventory/hosts.yml
    group_vars/all/vars.yml
    group_vars/all/vault.yml
    templates/
      smart-resume-api.service.j2
      Caddyfile.j2
      env.j2
    playbooks/
      site.yml
      create_lxc.yml
      configure_lxc.yml
      deploy_app.yml

  restorate_lxc/               # NEW
    ansible.cfg
    requirements.yml
    Makefile
    inventory/hosts.yml
    group_vars/all/vars.yml
    group_vars/all/vault.yml
    templates/
      restorate-api.service.j2
      restorate-web.service.j2
      Caddyfile.j2
      promtail.service.j2
      promtail-config.yml.j2
      api.env.j2
      valkey.conf.j2
      pg_backup.service.j2
      pg_backup.timer.j2
    playbooks/
      site.yml
      create_lxc.yml
      configure_lxc.yml
      deploy_app.yml

  proxmox_host/                # NEW — host-level tuning
    ansible.cfg
    inventory/hosts.yml
    group_vars/all/vars.yml
    group_vars/all/vault.yml
    Makefile
    playbooks/
      zfs_arc.yml
      ollama_balloon.yml
      verify_gpu.yml
      remove_sonarqube.yml

  smart_resume_vm/             # EXISTING — kept until decommission, then archived/removed
  restorate_vm/                # EXISTING — kept until decommission, then archived/removed
  sonarqube_vm/                # EXISTING — removed after decommission
  ollama_vm/                   # EXISTING — unchanged
```

## Task 1: Smart Resume LXC

### LXC Creation (`create_lxc.yml`)

Uses `community.general.proxmox` module:
- Debian 12 standard template (downloaded via `pveam` if missing)
- Unprivileged, no nesting
- 1 vCPU, 1024 MB RAM, 256 MB swap, 10 GB disk
- Static IP .210 (temporary), onboot enabled

### Configuration (`configure_lxc.yml`)

Targets the LXC via SSH. Installs:
- `python3`, `python3-venv`, `python3-dev`, `libgomp1` (required by faiss-cpu)
- `uv` (installed via official installer script)
- `caddy` (from official APT repo — serves static files + reverse proxy)
- `ufw`, `fail2ban` (same security baseline as VMs)

Configures:
- UFW: allow SSH (22) and HTTP (80)
- fail2ban enabled
- Caddy service enabled

No Docker, no Docker GPG key, no daemon.json.

### Deployment (`deploy_app.yml`)

**Pre-tasks (on localhost):**
1. Lint API code: `uv run ruff check src/ tests/`
2. Run API tests: `uv run pytest tests/ -q --tb=short`
3. Build Astro static site: `yarn build` in `apps/web/` (produces `dist/`)

**Tasks (on LXC):**
1. Create app directories: `/opt/smart-resume/{api,web}`
2. Rsync `apps/api/pyproject.toml`, `apps/api/uv.lock`, `apps/api/src/` → `/opt/smart-resume/api/`
3. Rsync `apps/web/dist/` → `/opt/smart-resume/web/`
4. Install Python deps on LXC: `cd /opt/smart-resume/api && uv sync --frozen --no-dev`
5. Template `.env`, `Caddyfile`, `smart-resume-api.service`
6. Enable and restart services

**Systemd unit** (`smart-resume-api.service.j2`):
```ini
[Unit]
Description=Smart Resume API
After=network.target

[Service]
Type=exec
User=www-data
WorkingDirectory=/opt/smart-resume/api
EnvironmentFile=/opt/smart-resume/api/.env
ExecStart=/opt/smart-resume/api/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Caddyfile:**
```
:80 {
    handle /api/* {
        reverse_proxy 127.0.0.1:8000
    }
    root * /opt/smart-resume/web
    file_server
}
```

## Task 2: Restorate LXC

### LXC Creation (`create_lxc.yml`)

Same pattern as smart-resume:
- 2 vCPU, 2048 MB RAM, 256 MB swap, 20 GB disk
- Static IP .211 (temporary)

### Configuration (`configure_lxc.yml`)

Installs:
- `postgresql` (17 via PGDG APT repo)
- `valkey` (via official Valkey APT repo — Debian 12 doesn't ship it)
- `caddy` (from official APT repo)
- `node` (Node.js 22 LTS via NodeSource — required for SvelteKit SSR)
- `ufw`, `fail2ban`

Configures:
- PostgreSQL: create `restorate` user and database
- Valkey: write config with auth password
- UFW: allow SSH (22), HTTP (80), Prometheus scrape (3001 from LAN only)
- Dedicated `restorate` system user for running services

### Deployment (`deploy_app.yml`)

**Pre-tasks (on localhost):**
1. Generate protobuf code: `buf generate --template apps/api/buf.gen.yaml` (requires buf + protoc-gen-go + protoc-gen-connect-go on dev machine)
2. Build Go binary: `cd apps/api && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /tmp/restorate-api ./src`
3. Build SvelteKit app: `bunx nx run protos:generate:web && cd apps/web && bunx vite build` (produces `apps/web/build/`)
4. Install production node_modules: `bun install --production --frozen-lockfile`

**Tasks (on LXC):**
1. Create app directories: `/opt/restorate/{api,web,backups}`
2. Copy Go binary → `/opt/restorate/api`
3. Rsync `apps/web/build/` → `/opt/restorate/web/`
4. Rsync production `node_modules/` → `/opt/restorate/web/node_modules/`
5. Template `api.env`, `Caddyfile`, `valkey.conf`, systemd units, promtail config
6. Enable and restart all services

**Systemd units:**

`restorate-api.service.j2`:
```ini
[Unit]
Description=Restorate API
After=network.target postgresql.service valkey.service
Requires=postgresql.service valkey.service

[Service]
Type=exec
User=restorate
EnvironmentFile=/opt/restorate/api.env
ExecStart=/opt/restorate/api
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`restorate-web.service.j2`:
```ini
[Unit]
Description=Restorate Web (SvelteKit SSR)
After=network.target restorate-api.service

[Service]
Type=exec
User=restorate
WorkingDirectory=/opt/restorate/web
Environment=HOST=0.0.0.0
Environment=PORT=3000
ExecStart=/usr/bin/node index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Caddyfile:**
```
:80 {
    handle /api/* {
        reverse_proxy 127.0.0.1:3001
    }
    handle {
        reverse_proxy 127.0.0.1:3000
    }
}
```

**PostgreSQL backup** (`pg_backup.timer.j2` + `pg_backup.service.j2`):
- Timer fires daily at 03:00
- Service runs: `pg_dump -Fc restorate > /opt/restorate/backups/restorate-$(date +%F).dump` (custom format, restore with `pg_restore`)
- Cleanup: `find /opt/restorate/backups -name '*.dump' -mtime +7 -delete`

**Promtail:**
- Installed as a standalone binary + systemd service
- Reads systemd journal logs (not Docker socket)
- Labels: `job=restorate`, `host=restorate` (replaces `compose_project=restorate`)

## Task 3: SonarQube Removal

Playbook `proxmox_host/playbooks/remove_sonarqube.yml`:
1. Stop VM 103 via Proxmox API
2. Delete VM 103 and its disk via Proxmox API
3. (Manual) Remove `compute/sonarqube_vm/` directory from git

Network stack cleanup (separate commit in mati-lab):
- Remove `sonarqube.mati-lab.online` block from `network/caddy/Caddyfile`

## Task 4: ZFS ARC Capping

Playbook `proxmox_host/playbooks/zfs_arc.yml` targets Proxmox host via SSH:
1. Write `/etc/modprobe.d/zfs.conf`:
   ```
   options zfs zfs_arc_max=3221225472
   options zfs zfs_arc_min=2147483648
   ```
2. Run `update-initramfs -u -k all`
3. Print reminder that a reboot is required (does NOT auto-reboot)

## Task 5: Ollama Memory Ballooning

Playbook `proxmox_host/playbooks/ollama_balloon.yml`:
- Uses Proxmox API to set `balloon: 4096` (min 4 GB) on VM 101
- Memory max stays at 12288 (12 GB)
- Requires VM restart to take effect — playbook prints reminder

## Task 6: GPU Passthrough Verification

Playbook `proxmox_host/playbooks/verify_gpu.yml` — read-only checks:
1. **On Proxmox host:**
   - Verify `amd_iommu=on iommu=pt` in kernel cmdline
   - Verify `nouveau` is blacklisted
   - List IOMMU groups for the GPU PCI device
2. **On Ollama VM (via SSH):**
   - Verify CPU type is `host` (from VM config)
   - Run `nvidia-smi` and report GPU status
   - Verify `OLLAMA_HOST=0.0.0.0:11434` is set
   - Test Ollama API: `curl localhost:11434/api/tags`

Reports findings. Does not auto-fix.

## Network Stack Changes

| File | Change | When |
|------|--------|------|
| `network/caddy/Caddyfile` | Remove sonarqube block (lines ~192-195) | After SonarQube decommission |
| `network/prometheus/prometheus.yml` | No change (same IP + port after cutover) | — |
| `network/grafana/provisioning/alerting/rules.yml` | No change (queries by `job` label) | — |
| `network/grafana/provisioning/dashboards/restorate.json` | Update log panel queries: `compose_project="restorate"` → `job="restorate"` | During Restorate LXC deploy |

## Migration Workflow

For each app (smart-resume, restorate):

1. **Create LXC** with temporary IP (.210 / .211)
2. **Configure** — install packages, configure services
3. **Deploy** — build locally, rsync artifacts, start services
4. **Test** — hit temporary IP, verify all endpoints work
5. **Cutover** — stop VM, change LXC IP to original (.200 / .203), restart LXC
6. **Verify** — confirm services work on final IP, external routing (Caddy) still works
7. **Decommission VM** — delete from Proxmox, remove `_vm` directory from git

## Dependencies and Ordering

```
Task 4 (ZFS ARC)          — independent, do first (needs reboot)
Task 5 (Ollama balloon)   — independent, do alongside ZFS
Task 6 (GPU verify)       — independent, do after reboot
Task 1 (Smart Resume LXC) — after reboot, independent of Task 2
Task 2 (Restorate LXC)    — after reboot, independent of Task 1
Task 3 (SonarQube remove) — independent, can do anytime
Network stack updates      — after Task 2 cutover (dashboard logs) and Task 3 (Caddy)
```

## No App Repo Changes

The application code in `smart-resume` and `resto-rate` repos stays unchanged. Dockerfiles remain for reference. Only the deployment method changes (Ansible rsync + systemd instead of Docker image push + compose).

## Risks and Mitigations

- **Data loss during migration:** Back up PostgreSQL (pg_dump) and any persistent data from VMs before starting LXC work.
- **LXC kernel isolation is weaker than VM:** Acceptable for homelab running own apps. Untrusted workloads (Ollama, Gitea runner) stay as VMs.
- **PostgreSQL in LXC has no Docker volume abstraction:** Mitigated by daily pg_dump backup timer.
- **Promtail label change breaks existing Grafana log panels:** Dashboard update is included in the plan.
