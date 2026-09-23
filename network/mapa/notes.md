# Wysowa map — `mapa.mati-lab.online`

Private static map (`mapa/mapa.html` + `mapa/podklady/` from `gooral/wysowa`)
for a short list of family members. Contains third-party personal data
(neighbours' names, land-register numbers, mortgage info) — **never expose it
without Cloudflare Access in front.**

## How it fits together

```
browser ──https──▶ Cloudflare edge ──▶ Access (email OTP allow-list)
                                         │
                         dedicated tunnel "mapa" (outbound from the Pi)
                                         │
Pi: mapa-tunnel (cloudflared) ──mapa-internal (no egress)──▶ mapa (nginx:80)
                                                               │ ro bind
                                                   /opt/wysowa/mapa  ◀── mapa-sync.timer (git, every 5 min)
```

- **Separate tunnel**, not the main homelab one: its only public hostname is
  `mapa.mati-lab.online → http://mapa:80`. Its token can't be used to reach
  anything else, and the main tunnel's config is untouched.
- **nginx has no host port** and sits on an `internal: true` network — only
  the tunnel container can reach it.
- **Two layers keep the rest of the repo private:**
  1. `/opt/wysowa` is a *sparse* checkout (`/mapa/mapa.html`, `/mapa/podklady/`)
     — `dane/`, `cache/`, `context/`, PDFs are never on the Pi's disk. The
     pattern is re-asserted on every sync run.
  2. `nginx.conf` whitelists `/mapa.html` and `/podklady/*`; everything else
     is 404. `.git` lives above the mounted dir.
- Headers on every response: `X-Robots-Tag: noindex, nofollow`,
  `Cache-Control: no-cache`, `Referrer-Policy: strict-origin-when-cross-origin`
  (not `no-referrer` — tile.openstreetmap.org rejects requests without a
  Referer). No CSP: the map loads Leaflet from cdnjs and tiles/WMS from
  geoportal.gov.pl, gugik.gov.pl, gison.pl, openstreetmap.org.
- **LAN DNS:** Pi-hole's `*.mati-lab.online → Caddy` wildcard is overridden for
  `mapa` (`pihole/etc-dnsmasq.d/99-host-overrides.conf`) so home clients also
  go through Cloudflare + Access. Public DNS: the tunnel's proxied CNAME beats
  the public wildcard A record.

## Updating the map

The owner rebuilds locally (`mapa/build.py`) and pushes `mapa/mapa.html` +
`mapa/podklady/` to `main`. `mapa-sync.timer` pulls within 5 min; nginx
serves straight from the checkout, and `no-cache` makes browsers revalidate.

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
value in the password manager (see `.env.example`).

## Cloudflare side (dashboard, Zero Trust)

- **Tunnel:** Zero Trust → Networks → Tunnels → `mapa` (Cloudflared,
  docker). Public hostname: `mapa.mati-lab.online`, service `HTTP` →
  `mapa:80`. Nothing else.
- **Access application:** Zero Trust → Access → Applications → `Mapa Wysowa`
  (self-hosted, domain `mapa.mati-lab.online`, session 30 days, login method
  One-time PIN only).
- **Policy** `Rodzina` (Allow, Include → Emails): the allow-list.

### Add / remove a person

Zero Trust → Access → Applications → `Mapa Wysowa` → Policies → `Rodzina` →
edit the **Emails** list → Save. Removing someone also needs revoking their
existing session (up to 30 days otherwise): Zero Trust → My Team → Users →
the user → **Revoke session**.

## Verify

```bash
curl -sI https://mapa.mati-lab.online/            # 302 → <team>.cloudflareaccess.com (login)
ssh gooral@192.168.1.252 'docker run --rm --network mapa_mapa-internal curlimages/curl -s -o /dev/null -w "%{http_code}\n" http://mapa/dane/dzialki.json'   # 404
```
