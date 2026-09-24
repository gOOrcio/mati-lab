# Wysowa family site — `mapa.mati-lab.online`

Private static site ("Działka 459": map, plan, selected documents) built from
`public/` in `gooral/wysowa`, for a short list of family members. Contains
third-party personal data (neighbours' names, land-register numbers, mortgage
info) — **never expose it without Cloudflare Access in front.**

## How it fits together

```
browser ──https──▶ Cloudflare edge ──▶ Access app "mapa" (email OTP allow-list)
                                         │
                         dedicated tunnel "mapa" (outbound from the Pi)
                                         │
Pi: mapa-tunnel (cloudflared) ──mapa-internal (no egress)──▶ mapa (nginx:80)
                                                               │ ro bind
                                                 /opt/wysowa/public  ◀── mapa-sync.timer (git, every 5 min)
```

- **Separate tunnel**, not `mati-lab-tunnel`: its only published application
  is `mapa.mati-lab.online → http://mapa:80`. Its token can't reach anything
  else, and the main tunnel's config is untouched.
- **nginx has no host port** and sits on an `internal: true` network — only
  the tunnel container can reach it.
- **Only `public/` ever reaches the Pi.** `/opt/wysowa` is a *sparse* checkout
  (`/public/`); the rest of the repo — raw land-register extracts with PESELs,
  bank data, `mapa/dane/`, build scripts — is never on disk here. The pattern
  is re-asserted on every sync run. What goes into `public/` is decided in the
  wysowa repo (`strona/pliki.json` → `strona/publikuj.py`).
- nginx: `/` → `index.html`, no directory listings (404, not 403), dotfiles
  404, `.md` served as `text/markdown; charset=utf-8` (fetched by `doc.html`,
  which only loads files from its own allow-list).
- Headers on every response: `X-Robots-Tag: noindex, nofollow`,
  `Cache-Control: no-cache`, `Referrer-Policy: strict-origin-when-cross-origin`
  (not `no-referrer` — tile.openstreetmap.org rejects requests without a
  Referer). No CSP: pages load Leaflet + marked.js from cdnjs and tiles/WMS
  from geoportal.gov.pl, gugik.gov.pl, gison.pl, openstreetmap.org.
- **Shared checklist state** (`mapa-stan`, `stan.py`, stdlib Python): nginx
  proxies exactly `/api/stan` to it. `GET` returns the checkbox state of
  `plan.html`; `POST {"id","v"}` sets one box and records who (the
  `Cf-Access-Authenticated-User-Email` header — trustworthy only because nginx
  is reachable solely through the tunnel) and when. Data:
  `network/mapa/data/stan.json` + append-only `historia.jsonl` (gitignored,
  survives `git clean -fd`, backed up to the NAS via `backup-services.conf`).
  Container: read-only rootfs, runs as gooral (1000:1003), no host port.
  CLI: `docker exec mapa-stan python /app/stan.py pokaz` /
  `… ustaw <id> 0|1 --kto <name>`.
- **LAN DNS:** both Pi-holes' `*.mati-lab.online → Caddy` wildcard is
  overridden for `mapa` (`pihole/etc-dnsmasq.d/99-host-overrides.conf`) so home
  clients also go through Cloudflare + Access. Public DNS: the tunnel's
  proxied CNAME beats the public wildcard A record.

## Updating the site

The owner rebuilds locally (`mapa/build.py`, then `strona/publikuj.py`) and
pushes `public/` to `main`. `mapa-sync.timer` pulls within 5 min; nginx serves
straight from the checkout, and `no-cache` makes browsers revalidate.

Force an immediate pull: `cd network && make sync-mapa`
(= `sudo systemctl start mapa-sync.service` on the Pi). Logs:
`journalctl -u mapa-sync.service`.

The Pi reads `gooral/wysowa` with its own SSH key (`~/.ssh/config` →
`gitea-ssh.mati-lab.online:30009`), same as the mati-lab sync.

## Deploy

```bash
cd ~/Projects/mati-lab/network
make deploy-mapa     # syncs repo, copies mapa/.env, installs + runs mapa-sync, recreates containers
```

`network/mapa/.env` (gitignored, dev PC only) holds `MAPA_TUNNEL_TOKEN` —
value in the password manager (see `.env.example`). Write it with
`read -rs` in a real terminal (Claude Code's `!` has no stdin).

## Cloudflare side (dashboard)

- **Tunnel:** Zero Trust → Networks → Tunnels → `mapa` → Routes: one
  *Published application* `mapa.mati-lab.online` → `http://mapa:80`. Nothing
  else.
- **Access application:** Zero Trust → Access controls → Applications → `mapa`
  (self-hosted, destination `mapa.mati-lab.online`, session 1 month, identity
  provider One-time PIN only, instant auth on).
- **Policy** `Rodzina` (Allow, Include → Emails): the allow-list.

Create/verify Access **before** adding the tunnel route — the route makes the
hostname live immediately.

### Add / remove a person

Zero Trust → Access controls → Policies → `Rodzina` (or Applications → `mapa`
→ Policies) → edit the **Emails** list → Save. Removing someone also needs
revoking their existing session (up to 1 month otherwise): Zero Trust →
Team & Resources → Users → the user → **Revoke session**.

## Verify

```bash
curl -sI https://mapa.mati-lab.online/            # 302 → mati-lab.cloudflareaccess.com (login)
ssh gooral@192.168.1.252 'docker run --rm --network mapa_mapa-internal curlimages/curl -s -o /dev/null -w "%{http_code}\n" http://mapa/mapa/dane/dzialki.json'   # 404
for s in 192.168.1.252 192.168.1.65; do dig +short mapa.mati-lab.online @$s; done   # Cloudflare IPs from both Pi-holes
```
