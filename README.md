# mati-lab

Personal homelab configuration running on a Proxmox host with a Raspberry Pi as the network layer. This repo exists primarily to persist and version-control my setup — it's also a showcase of how the pieces fit together. Some parts can serve as a starting point or recipe, but this isn't designed to be a generic, plug-and-play solution.

## Architecture

**Hardware**
- Proxmox host (16 CPUs, 32GB RAM) — runs all VMs
- Raspberry Pi — runs network services (DNS, reverse proxy, tunnel)

**Network layer** (`network/`) — Docker Compose services on the Pi
- **Caddy** — reverse proxy and TLS termination for all internal services
- **Cloudflare Tunnel** — exposes services publicly without port forwarding
- **Pi-hole** — local DNS, resolves `*.mati-lab.online` to Caddy internally
- **Authelia** — SSO and 2FA for selected services
- Supporting services: Grafana, Prometheus, Homarr, Uptime Kuma, ntfy, DIUN

**Compute layer** (`compute/`) — Ansible-provisioned VMs on Proxmox
- Each VM follows the same pattern: `create_vm.yml` → `configure_vm.yml` → `deploy_app.yml`
- VMs are cloned from a Debian 12 cloud-init template (ID 9000)
- Secrets managed with Ansible Vault (`~/.vault_pass`)

| VM | ID | IP | Purpose |
|----|----|----|---------|
| ollama-gpu | 101 | 192.168.1.48 | Local LLM inference (RTX 3070, GPU passthrough) |
| smart-resume | 102 | 192.168.1.200 | Personal AI-powered CV app |
| sonarqube | 103 | 192.168.1.201 | Code quality platform (SonarQube CE + community-branch-plugin) |

## Traffic flow

```
Internet → Cloudflare edge → Cloudflare Tunnel → Caddy (Pi) → VM
```

Local traffic resolves directly to Caddy via Pi-hole.

## Repo structure

```
compute/          # Ansible playbooks per VM
network/          # Docker Compose + management scripts per service
docs/             # Architecture specs and implementation plans
```

Management scripts in `network/scripts/` handle deploy/update/restart operations over SSH from the developer machine to the Pi.
