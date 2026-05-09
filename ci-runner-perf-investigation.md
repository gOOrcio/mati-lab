# Investigate Gitea CI runner performance — Hermes-investor builds

You are working in `~/Projects/mati-lab/` (the homelab infra repo). Investigate why Gitea Actions builds for `gooral/hermes-investor` are taking ~10-12 minutes when the bottleneck is moving 1.79GB of Docker layers between machines that are nominally on the same LAN. **Do NOT make any changes without confirming the root cause first** — read mode for diagnosis, propose changes for review, only then apply.

## Context

- **Repo under build:** `gooral/hermes-investor` at `gitea.mati-lab.online`. Workflows `.gitea/workflows/build-and-publish.yml` and `.gitea/workflows/rebase-hermes-base.yml`. Path: `~/Projects/hermes-investor/` (open it as a sibling reference if needed).
- **Image being built:** `gitea.mati-lab.online/gooral/hermes-agent-investor:dev`. Derives `FROM nousresearch/hermes-agent:v2026.4.23` (1.79GB upstream).
- **Buildkit cache configured:** `cache-from: type=registry,ref=…/hermes-agent-investor:buildcache` and `cache-to: type=registry,ref=…:buildcache,mode=max`.
- **Topology** (from `docs/design/homelab-master-plan.md` Phase 4):
  - Gitea server: TrueNAS Custom App on NAS at `192.168.1.65`, public hostname `gitea.mati-lab.online`. **Confirmed by user: NOT routed via Cloudflare tunnel.** Likely served via Caddy on Pi (192.168.1.252) with split-horizon DNS or LAN-only public DNS.
  - `act_runner`: Proxmox VM with Docker Engine + DinD. IP unknown; last documented as on the homelab LAN.
  - SSH endpoint for git: `ssh://git@gitea-ssh.mati-lab.online:30009/...`.
  - There's a `network/registry-mirror/` Pi-stack — exists but I don't know if the runner's Docker daemon actually consumes it.

Cloudflare is NOT in the registry path, so a "Cloudflare WAN round-trip" hypothesis is wrong. Real culprit is likely (1) no Docker Hub mirror and (2) Caddy buffering / single-connection behavior, OR (3) buildkit `mode=max` re-uploading the entire layer chain on every cache-invalidating build.

## Symptoms observed during a real deploy session (2026-05-04)

| Run | Trigger | Duration | Notes |
|---|---|---|---|
| First-ever build (cold cache) | small Dockerfile change | 12 min | most of it spent pulling 1.79GB upstream then re-uploading 1.79GB to buildcache tag |
| Subsequent builds (warm cache, supposedly) | Dockerfile path-filter touched | 4-5 min | STILL re-pulled 1.79GB base; STILL re-uploaded 1.79GB cache; install step itself was ~3s |
| Pure `src/**` changes (Dockerfile untouched) | path-filter touched | similar 4-5 min | same — full base re-pull |

Reading the runner logs (`tea actions runs logs <id>`) shows `#5 sha256:b50fb2ff... 1.79GB / 1.79GB 233.3s done` — i.e., 1.79GB pulled in ~4 minutes. That works out to ~7-8 MB/s effective throughput, which is **WAN-tier**, not LAN. On a 1Gb LAN we should see ~100MB/s.

## Hypotheses (ranked, since Cloudflare is ruled out)

1. **Upstream `nousresearch/hermes-agent:v2026.4.23` (~1.79GB) re-pulled from Docker Hub every build.** No registry mirror wired into the runner's Docker daemon. Home internet WAN bandwidth dominates. The 7-8MB/s observed throughput maps cleanly to a typical home connection's download from Docker Hub's Frankfurt edge.
2. **Buildkit `cache-to: mode=max` re-uploads the entire cached layer set** to `gitea.mati-lab.online/.../buildcache` on every cache-invalidating build. Even on LAN, that's still 1.79GB upload every time the Dockerfile changes.
3. **Runner's Docker daemon falls back to slow HTTP-1.1 single-connection pulls** for the Gitea registry — possibly because Caddy doesn't negotiate HTTP/2 cleanly with the registry endpoint.
4. **Caddy reverse proxy buffers full blobs in memory before relaying** — would cap throughput at whatever Caddy's CPU + memory bandwidth can manage. Default Caddy buffers are conservative for non-streaming workloads.

## What to investigate (in order)

1. **Where is `act_runner` actually running?**
   - Check `~/Projects/mati-lab/compute/` for Ansible / VM definitions.
   - SSH into it. Confirm IP. Confirm it's on the same LAN as the NAS.
   - Note: the homelab CLAUDE.md hard rule says NEVER read `.env` files via shell. Don't.

2. **DNS resolution + actual destination IP from the runner.**
   - `host gitea.mati-lab.online` from the runner. Should be a LAN IP (likely `192.168.1.252` if Caddy on Pi terminates, or `192.168.1.65` if direct). Should NOT be a Cloudflare IP.
   - `tcpdump -i any host gitea.mati-lab.online -c 50` for 10s during a manual `docker pull` will reveal: destination IP, # of TCP connections, observed throughput per connection.

3. **Docker daemon's view of the registry — IS a registry-mirror configured?**
   - Inspect `/etc/docker/daemon.json` on the runner. Look for `registry-mirrors`. If empty: the runner is hitting Docker Hub directly for `nousresearch/hermes-agent` every build.
   - Try `docker info | grep -A 5 "Registry Mirrors"`.
   - If `network/registry-mirror/` exists in mati-lab and is a working pull-through cache, this is the obvious connection to make.

4. **Caddy reverse-proxy tuning for `gitea.mati-lab.online`.**
   - Read `~/Projects/mati-lab/network/caddy/Caddyfile`. Find the gitea vhost. Look for `request_body` / `transport http` / `flush_interval` directives — Caddy's defaults can throttle large blob transfers.
   - Confirm Caddy is using HTTP/2 to the upstream Gitea (registry blob endpoints support HTTP/2 streaming and benefit massively).
   - If Caddy adds nothing useful for the registry endpoint specifically, consider exposing the registry on a separate hostname that's served directly by Gitea (no Caddy) — `registry.mati-lab.online:3000` or similar.

5. **Existing Docker-Hub mirror situation (`network/registry-mirror/`).**
   - What is it? Is it `registry:2` in pull-through mode, Harbor, or something else?
   - Is it currently consumed by the runner's Docker daemon (via `daemon.json` `registry-mirrors`)?
   - If yes, why is `nousresearch/hermes-agent` not being served from the mirror? Maybe it hasn't been pre-pulled, or the mirror hasn't been wired into `daemon.json`, or its container lives elsewhere unreachable from the runner.

6. **Buildkit cache effectiveness.**
   - Look at `cache-from`/`cache-to` semantics. With `mode=max`, every cache layer (including the giant base) is exported on every build whose Dockerfile invalidates a step. The first 4 commits of hermes-investor each touched the Dockerfile — that's why every build re-uploaded the cache. After Dockerfile stability, future builds should NOT re-upload (only the changed layers do).
   - Confirm with the latest hermes-investor build whose Dockerfile DIDN'T change: did it skip the cache export?
   - Question worth raising: should we use `mode=min` instead, accepting cache misses for parent layers but cutting upload size dramatically?

## Likely fixes (rank-ordered, propose for review before applying)

### Tier 1 — runner-local (high impact, low risk)

- **Wire the existing registry-mirror into the runner's Docker daemon.** Edit `/etc/docker/daemon.json` on the runner: `{"registry-mirrors": ["http://<mirror-host>:<port>"]}`, restart docker. Subsequent pulls of `nousresearch/hermes-agent` and other Docker Hub images become local hits. **This is almost certainly the biggest single win** — kills 4 minutes of Docker Hub pull per build.
- **`/etc/hosts` override on the runner host:** map `gitea.mati-lab.online` to the actual LAN IP it should resolve to. Belt-and-suspenders even if DNS is already correct — eliminates DNS-cache hiccups and ensures Docker doesn't accidentally take a different path.

### Tier 2 — workflow-level (lower impact, more friction)

- **Switch `cache-to: mode=max` → `mode=min`** in both `build-and-publish.yml` and `rebase-hermes-base.yml`. Trades cache hit rate for upload size. Worth it if Tier 1 alone isn't enough.
- **Pin upstream image by digest** rather than tag, so Docker doesn't re-validate manifests on every build. Lower priority.

### Tier 3 — architectural

- **Move the buildcache to a side-car registry on Pi or NAS** that bypasses Caddy entirely (insecure-registry config). Significant reshuffle — only do if Tier 1+2 fail.
- **Self-host a Harbor instance with proxy-cache projects** for Docker Hub + GHCR + GCR. Future-proof but heavy.
- **Pre-pull the upstream Hermes image into the registry-mirror's seed layer** so cold runs don't have to round-trip Docker Hub.

## Constraints

- Don't break sentinel-trader, mati-lab's own CI, or other homelab repos that share the runner. Whatever you change to runner config should benefit them too.
- No sudo on production NAS without an explicit human paste-the-password step (per homelab CLAUDE.md). The runner host is fair game once you confirm whose machine it is.
- Don't commit secrets. Don't commit IPs that aren't already in mati-lab (the IPs above ARE already documented there).
- Validate every "this should be faster" with a TIMED before/after measurement against the same workflow run on the same commit. No "feels faster" claims.

## Deliverables

1. **Diagnosis writeup** in `~/Projects/mati-lab/docs/design/ci-runner-perf-2026-05-04.md`: what was actually slow, why, with measurements that prove it.
2. **Fix PR** (or branch) in `mati-lab` with the minimum set of changes that gives the biggest speedup. Each change has a one-line "why" comment.
3. **Re-measure**: trigger a hermes-investor build (or any Dockerfile-touching build of comparable image size), compare wall-clock duration before vs after.
4. **Update `~/Projects/hermes-investor/docs/INTEGRATION.md`** § CI/CD if any visible behavior changes (e.g., new env var, new daemon.json section that future repos need to mimic).

## Where to look for context

- `~/Projects/mati-lab/CLAUDE.md` — homelab conventions (hard rules, Caddy/Authelia, Loki).
- `~/Projects/mati-lab/docs/design/homelab-master-plan.md` — phase status, runner setup, registry mirror.
- `~/Projects/mati-lab/docs/followups.md` — outstanding items; check if CI perf is already a tracked followup.
- `~/Projects/mati-lab/network/caddy/Caddyfile`, `network/cloudflared/`, `network/registry-mirror/`, `nas/gitea/notes.md` — relevant config.
- `~/Projects/hermes-investor/.gitea/workflows/build-and-publish.yml` and `rebase-hermes-base.yml` — the workflows themselves.
- Recent build logs via `tea actions runs --repo gooral/hermes-investor` and `tea actions runs logs <id> --job <id>`.

Investigate first. Propose. Then change. Report back with measurements.
