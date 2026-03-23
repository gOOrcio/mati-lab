# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`mati-lab` is a personal homelab infrastructure repository. It manages two concerns:

- **`compute/`** — Ansible playbooks to provision and configure VMs on a Proxmox cluster
- **`network/`** — Docker Compose stacks for self-hosted network services

## Infrastructure

**Proxmox host:** 192.168.1.184 — 16 CPUs, 31GB RAM

| VM | ID | IP | RAM | CPUs | Purpose |
|----|----|----|-----|------|---------|
| ollama-gpu | 101 | — | 12GB | 4 | Local LLM inference (GPU passthrough) |
| smart-resume | 102 | 192.168.1.200 | 2GB | 2 | Resume web app |
| sonarqube | 103 | 192.168.1.201 | 4GB | 4 | Code quality platform (planned) |
| openclaw | 104 | 192.168.1.202 | 6GB | 2 | AI agent runtime (planned) |

All VMs are cloned from template ID 9000 (debian12-cloud) via cloud-init.

## Ansible — compute/

Every VM follows the same three-playbook pattern:

```
{vm_name}/
├── ansible.cfg                  # vault_password_file = ~/.vault_pass
├── Makefile                     # provision / configure / deploy targets
├── requirements.yml             # ansible-galaxy collection dependencies
├── inventory/hosts.yml
├── group_vars/all/
│   ├── vars.yml                 # VM spec, app config (plaintext)
│   └── vault.yml                # secrets (ansible-vault encrypted)
└── playbooks/
    ├── site.yml                 # imports create → configure → deploy
    ├── create_vm.yml            # clone template, cloud-init, resize, start
    ├── configure_vm.yml         # apt, Docker, UFW, fail2ban, sysctl
    └── deploy_app.yml           # rsync/template files, start Docker Compose
```

**Run from inside the VM directory** (not from `compute/`):

```bash
cd compute/sonarqube_vm
make provision    # full: install deps + create + configure + deploy
make configure    # re-run OS configuration only
make deploy       # re-deploy app only
```

Secrets use explicit `vars_files` in every playbook (not auto-loading). `smart_resume_vm` is the canonical reference — all other VMs mirror it exactly.

**Ansible collections** (declared in `requirements.yml`, auto-installed by `make provision`):
- `community.general` — proxmox_kvm, ufw
- `community.docker` — docker_compose_v2
- `ansible.posix` — sysctl

## Network — network/

Self-hosted services running on a separate host (Raspberry Pi / NUC), all managed via Docker Compose. Traffic flows: Cloudflare Tunnel → Caddy (reverse proxy) → individual services.

**Domain:** `*.mati-lab.online` (wildcard TLS via Cloudflare DNS challenge)

**Services:**

| Service | URL | Auth |
|---------|-----|------|
| Caddy | (reverse proxy) | — |
| Authelia | authelia.mati-lab.online | — |
| Pihole | pihole.mati-lab.online | Authelia |
| Grafana | grafana.mati-lab.online | Authelia |
| Prometheus | prometheus.mati-lab.online | Authelia |
| Homarr | homarr.mati-lab.online | Authelia |
| Uptime Kuma | uptime-kuma.mati-lab.online | Authelia |
| Proxmox UI | proxmox.mati-lab.online | Authelia |
| Homebridge | homebridge.mati-lab.online | Authelia |
| ntfy | ntfy.mati-lab.online | — |
| smart-resume | smart-resume.mati-lab.online | — |
| sonarqube | sonarqube.mati-lab.online | SonarQube own auth |

**Common network commands (run from `network/`):**

```bash
make deploy              # deploy all services
make deploy-caddy        # deploy only Caddy
make status              # show all service status
make logs                # show all service logs
make save                # export Grafana dashboards + save configs to git
make rebuild-caddy       # rebuild Caddy Docker image (after Caddyfile/plugin changes)
```

**Adding a new service to Caddy:** edit `network/caddy/Caddyfile`. Add a matcher + handle block before the catch-all `handle` block. Redeploy with `make deploy-caddy`.

## Active Plans

### SonarQube Infrastructure (Plan 1)

**Plan:** `docs/superpowers/plans/2026-03-23-sonarqube-infrastructure.md`
**Spec:** `docs/superpowers/specs/2026-03-23-sonarqube-enterprise-setup-design.md`

Creates `compute/sonarqube_vm/` and updates `network/caddy/Caddyfile`. Tasks 1–9 and 11 write files; Tasks 10 and 12–15 require your Proxmox credentials and Cloudflare dashboard access.

The broader SonarQube project (Spring Boot demo app, CI pipelines, quality gates, docs) lives in the companion repo: `~/Projects/sonarqube-sandbox`.
