# Homepage

File-configured dashboard at https://home.mati-lab.online (Authelia-gated).
Replaces Homarr. See `docs/superpowers/specs/2026-05-06-homepage-dashboard-migration-design.md`.

## Source of truth

- `config/*.yaml` in this directory are the truth — bind-mounted into the container at `/app/config`.
- Per-service entries are auto-discovered from `homepage.*` Docker labels (Pi local socket + NAS remote socket-proxy). Manual entries in `services.yaml` are only for things we can't label (router, raw nodes, catalogue apps without label support).

## Deploy

```bash
cd ~/Projects/mati-lab/network && make deploy-homepage
```

## After config edits

Homepage hot-reloads `config/*.yaml`, but to be safe:

```bash
ssh gooral@192.168.1.252 "cd /opt/mati-lab/network/homepage && docker compose restart"
```

## Docker label cheatsheet

```yaml
labels:
  - homepage.group=Network
  - homepage.name=Pi-hole
  - homepage.icon=pi-hole.png
  - homepage.href=https://pihole.mati-lab.online
  - homepage.description=DNS sinkhole
  # Optional service-specific widget (https://gethomepage.dev/widgets/services/):
  - homepage.widget.type=pihole
  - homepage.widget.url=http://pihole:80
  - homepage.widget.key=${PIHOLE_API_KEY}
```

## Widget credentials

Defined in `network/.env` on the Pi (NOT committed). Sourced into the container as `HOMEPAGE_VAR_*`:

| Var | Source |
|---|---|
| `PROXMOX_HOMEPAGE_TOKEN_ID` / `_SECRET` | password manager `homelab/proxmox/homepage-readonly` |
| `HOMEBRIDGE_USERNAME` / `_PASSWORD` | password manager `homelab/homebridge/homepage` |

Tokens are minted in the afternoon deployment pass; until then the widget queries fail silently and the rest of the dashboard is unaffected.

## Backup

Stateless beyond `config/`. Backed up via `network/backup/backup-services.conf` (`homepage:bind:homepage/config`).

## Health monitor

Uptime-Kuma HTTP monitor: `https://home.mati-lab.online`. Authelia returns 401 for unauth requests — accept `200-299, 401` as up.
