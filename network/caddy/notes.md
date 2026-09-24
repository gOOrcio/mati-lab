# Caddy (network Pi) — image lifecycle

Caddy fronts every `*.mati-lab.online` vhost, and its own custom image
(`gitea.mati-lab.online/gooral/caddy-cloudflare:latest`, Caddy + the
Cloudflare DNS module for ACME DNS-01) is pulled **through Caddy itself**.
So there is one normal path and one recovery path, nothing else.

## Normal path (Dockerfile / base-image change, e.g. a Renovate PR)

1. **PR** — `config-checks` builds the Dockerfile natively on the CI runner
   and runs `caddy validate` on the Caddyfile (fake, correctly-shaped CF
   token). Same check locally: `cd network && make check`.
2. **Merge** — `.gitea/workflows/build-caddy-cloudflare.yml` builds the
   arm64 image on the always-on runner VM (emulated, ~15 min) and pushes
   `:latest`. Wait for it to succeed.
3. **Deploy** — `cd network && make update-caddy`. It tags the running image
   as `caddy-cloudflare:previous` on the Pi, then pulls and recreates.
4. **Verify** — every vhost answers as before, e.g. compare status codes
   before/after for the `@x host …` matchers in the Caddyfile:
   `grep -oE "host [a-z0-9.-]+\.mati-lab\.online" Caddyfile` → curl each
   with `--resolve <host>:443:192.168.1.252`.

Caddyfile-only edits don't need an image: `make deploy-caddy`
(`--force-recreate` is required — see `feedback_caddy_bind_mount_recreate`).

## Rollback

```bash
ssh gooral@192.168.1.252 'sudo docker tag caddy-cloudflare:previous \
  gitea.mati-lab.online/gooral/caddy-cloudflare:latest && \
  cd /opt/mati-lab/network/caddy && sudo docker compose up -d --force-recreate'
```

No pull involved, so it works while Caddy is broken.

## Recovery (Caddy down and no usable local image)

The registry is unreachable because it sits behind Caddy — build on the dev
PC and load the image onto the Pi directly (memory:
`reference_caddy_image_bootstrap_deadlock`):

```bash
docker buildx build --platform linux/arm64 --load \
  -t gitea.mati-lab.online/gooral/caddy-cloudflare:latest network/caddy
docker save gitea.mati-lab.online/gooral/caddy-cloudflare:latest \
  | ssh gooral@192.168.1.252 'sudo docker load'
ssh gooral@192.168.1.252 'cd /opt/mati-lab/network/caddy && sudo docker compose up -d --force-recreate'
```

`make rebuild-caddy` (local build + push + pull) is the same build when the
registry *is* reachable but CI isn't — not the normal path.

Large pulls on the Pi can stall its disk writeback (see
`feedback_pi_big_image_pull_stall`); the Caddy image is ~50 MB, so this
doesn't apply here.
