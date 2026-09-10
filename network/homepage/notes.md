# Homepage

File-configured dashboard at https://home.mati-lab.online (Authelia-gated).
Replaces Homarr. See `docs/superpowers/specs/2026-05-06-homepage-dashboard-migration-design.md`.

## Source of truth

- `config/*.yaml` in this directory are the truth — bind-mounted into the container at `/app/config`.
- Per-service entries are auto-discovered from `homepage.*` Docker labels (Pi local socket + NAS remote socket-proxy). Manual entries in `services.yaml` are only for things we can't label (router, Proxmox guests, catalogue apps without label support).
- `.env` (gitignored) lives on the **dev PC** at `network/homepage/.env`. `make deploy-homepage` scp's it to the Pi (`common.sh :: copy_env_file`) and passes it to compose with `--env-file`. Editing the Pi copy in place gets overwritten on the next deploy.

## Deploy

```bash
cd ~/Projects/mati-lab/network && make deploy-homepage
```

## After config edits

Homepage hot-reloads `config/*.yaml`, but to be safe:

```bash
ssh gooral@192.168.1.252 "cd /opt/mati-lab/network/homepage && docker compose restart"
```

## After editing another stack's homepage.* labels

**Restart Homepage too.** Redeploying the labelled container is not enough — Homepage
builds the service list in `getStaticProps` and keeps serving the cached page, so a
changed label shows the *old* widget until Homepage itself restarts. A browser
hard-reload does not help. Symptom: `/api/services` already shows the new config
while the rendered card still shows the old one.

```bash
cd network && make deploy-<service> && \
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

### Label values are strings; nest via the label KEY

Label values get env-var substitution and nothing else — **no YAML/JSON parse**. A
JSON array as a value arrives as a string and the widget throws (customapi:
`s.slice(...).map is not a function`). Homepage's shvl splits the label *key* on
`[.[]]` and creates an array when the next segment is numeric, so arrays and nested
objects have to be spelled out index by index:

```yaml
  - "homepage.widget.mappings[0].field=status"
  - "homepage.widget.mappings[0].label=Health"
  - "homepage.widget.headers.Authorization=Bearer {{HOMEPAGE_VAR_SOME_TOKEN}}"
```

Anything with real structure is easier to write as a `services.yaml` entry instead.

### Info widgets vs service widgets

`config/widgets.yaml` is the **header strip** and accepts only info widgets:
`datetime, glances, greeting, kubernetes, logo, longhorn, openmeteo,
openweathermap, resources, search, stocks, unifi_console, weather`. Anything else
(`proxmox`, `homebridge`, `uptimekuma`, …) is a *service* widget and belongs on a
service entry or a Docker label; put one in `widgets.yaml` and it renders as
`Missing<type>` across the header.

Likewise, a `widget.type` Homepage doesn't know renders as
`Missing Widget Type: <type>` on the card. There is **no `authelia` widget** (only
`authentik`) — Authelia uses `customapi` against its unauthenticated `/api/health`.
`ls /app/src/widgets` inside the container is the authoritative list.

## Proxmox integration

`config/proxmox.yaml` holds the PVE connection; the top-level key **must be the node
name** (`pvesh get /nodes` → `proxmox`, not the `pve` default). Services carrying
`proxmoxNode` / `proxmoxVMID` / `proxmoxType` then render live status + CPU/RAM for
that guest — that's what the Proxmox group does for ollama-gpu (101), gitea-runner
(102), smart-resume (110) and restorate (111). VMIDs: `pvesh get /cluster/resources
--type vm`.

The same token drives the `proxmox` service widget on the Proxmox UI card. Homepage
sets `rejectUnauthorized: false` on widget requests, so the self-signed 8006 cert is fine.

## Widget credentials

Defined in `network/homepage/.env` on the dev PC (NOT committed). Sourced into the
container as `HOMEPAGE_VAR_*` — see `.env.example` for how each is minted.

| Var | Source |
|---|---|
| `PROXMOX_HOMEPAGE_TOKEN_ID` / `_SECRET` | `homepage@pve!dashboard`, role PVEAuditor. Password manager: `homelab/proxmox/homepage-readonly` |
| `HOMEBRIDGE_USERNAME` / `_PASSWORD` | Homebridge Config-UI-X user, created via the UI (that Pi has no SSH). Password manager: `homelab/homebridge/homepage` |

An empty var breaks only its own widget; the rest of the dashboard is unaffected.

## No Grafana widget — on purpose

gethomepage's `grafana` widget calls `/api/admin/stats`, which needs a Grafana
**server** admin. Org Admin is not enough (`gooral@authelia` is org Admin and still
gets 403), and the widget renders an API error if that single call fails — so a
read-only service-account token cannot drive it. The card is a plain link with
`siteMonitor` instead. If it's ever wanted back, the options are the
`GF_SECURITY_ADMIN_PASSWORD` account, or a `customapi` widget with a Viewer token
against `/api/alertmanager/grafana/api/v2/alerts` + `format: size` for a firing-alert count.

Grafana's API is reachable from inside `pihole-net` without a password via the
auth-proxy header Caddy already sets — `wget --header="Remote-User: gooral"
http://grafana:3000/api/...` — which is how service accounts get minted without
touching `.env`.

## Hostnames

Every card href must match a `@name host <fqdn>` matcher in
`network/caddy/Caddyfile`. The wildcard cert resolves *any* `*.mati-lab.online`, so a
typo'd host reaches Caddy and 404s rather than failing DNS — it looks like the service
is down. Three of these shipped in the May migration (`truenas.`, `auth.`, `kuma.`).
Check with:

```bash
grep -oE 'host [a-z0-9.-]+\.mati-lab\.online' network/caddy/Caddyfile | sed 's/host //' | sort -u
```

## Backup

Stateless beyond `config/`. Backed up via `network/backup/backup-services.conf` (`homepage:bind:homepage/config`).

## Health monitor

Uptime-Kuma HTTP monitor: `https://home.mati-lab.online`. Authelia returns 401 for unauth requests — accept `200-299, 401` as up.
