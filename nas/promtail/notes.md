# Promtail (NAS)

TrueNAS Scale Apps, **Custom App** (not in catalog). Installed 2026-04-30
as Phase 7 Task 1—5. Headless log shipper; tails Docker container logs
on the NAS and pushes to the Pi-side Loki at `192.168.1.252:3100`. No
ports exposed, no UI.

The Pi runs a parallel Promtail (`network/promtail/`) doing the same job
for Pi-side containers. Both push to the same Loki, distinguished in
queries by the `host` label (`nas` vs `network-pi`).

## Endpoints

None. Background daemon. Inspect via Loki queries against host="nas":

```bash
curl -sS -G 'http://192.168.1.252:3100/loki/api/v1/series' \
  --data-urlencode 'match[]={host="nas"}'
```

## Config on disk

| Path (NAS) | Content |
|---|---|
| `/mnt/fast/databases/promtail/config.yml` | Scrape config + clients + relabel rules. Source of truth: `nas/promtail/promtail-config.yml` in this repo (scp on changes). |
| `/mnt/fast/databases/promtail/positions/positions.yaml` | Tail-position checkpoint (Promtail-managed; persists across restarts so we don't re-ship history) |

The container also bind-mounts:
- `/var/run/docker.sock:ro` — service discovery via Docker API
- `/mnt/.ix-apps/docker/containers:ro` — Docker's per-container log files (Promtail tails them directly)

Runs as `0:0` (root). Promtail is the only thing using the docker socket
on the NAS, so the Pi's `tecnativa/docker-socket-proxy` least-privilege
pattern was skipped here. If we ever add a second consumer, switch to
the proxy pattern (Phase 7.x followup).

## Install trace (reproducibility)

```bash
# 1. Stage config + positions dir on NAS (root-owned because container runs as root)
ssh truenas_admin@192.168.1.65 'mkdir -p /mnt/fast/databases/promtail/positions'
scp nas/promtail/promtail-config.yml truenas_admin@192.168.1.65:/mnt/fast/databases/promtail/config.yml
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.chown "{
  \"path\":\"/mnt/fast/databases/promtail\",\"uid\":0,\"gid\":0,
  \"options\":{\"recursive\":true}
}"'

# 2. Create the Custom App
scp nas/promtail/deploy/promtail-create.json truenas_admin@192.168.1.65:/tmp/
ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/promtail-create.json)"'

# 3. Verify
curl -sS 'http://192.168.1.252:3100/loki/api/v1/label/host/values' \
  | python3 -c "import sys,json; assert 'nas' in json.load(sys.stdin)['data']; print('ok')"
```

## Update / restart

| Action | Command |
|---|---|
| Edit scrape config | Edit `nas/promtail/promtail-config.yml`, `scp` to NAS, `midclt call app.redeploy promtail` |
| Bump image tag | Edit compose JSON, `midclt call app.update promtail '{...}'` (or use `app.pull_images` if just bumping `:latest`) |
| Restart | `midclt call app.redeploy promtail` |
| Stop / start | `midclt call app.stop promtail` / `midclt call app.start promtail` |
| Inspect what containers it sees | `curl -sS -G 'http://192.168.1.252:3100/loki/api/v1/series' --data-urlencode 'match[]={host="nas"}'` |

## How discovery works

Promtail's `docker_sd_configs` polls the Docker API every 10s and emits
a target per container. New containers (e.g. on `app.create`) get picked
up automatically — no Promtail restart needed. Containers that exit are
dropped on next refresh.

Each container's logs come from
`/mnt/.ix-apps/docker/containers/<container-id>/<container-id>-json.log`
(Docker's default JSON file driver). Promtail tails these via its
filesystem mount and ships to Loki.

Idle containers don't show up as Loki **series** until they emit their
first log line — that's a Loki property, not a Promtail one. If a
container looks "missing" from Loki, provoke a log line (e.g.
`midclt call app.redeploy <name>`) and re-query.

## Backup

Stateful surface is `/mnt/fast/databases/promtail/positions/`
(small file, megabytes at most). Loses tail-position on data loss —
Promtail will re-tail from the start of each container's current log
file, which means duplicate log lines in Loki for as much history as the
log-rotation retains. Annoyance, not a real problem; not Phase 8 scope.

The config file (`config.yml`) is source-controlled in `nas/promtail/`,
so a fresh-NAS rebuild just re-runs the install trace.

## Lessons

- **TrueNAS docker root is `/mnt/.ix-apps/docker`, not `/var/lib/docker`.**
  The `dataset` field on `midclt call docker.config` (here: `fast/ix-apps`)
  tells you the mountpoint. Plan-time assumption ("`/var/lib/containers`")
  was wrong; verified at deploy time.

- **Containers don't show up in Loki until they log.** Saw 3 NAS
  containers immediately (gitea, gitea-postgres, litellm — chatty), 4
  after a `curl` against Qdrant (it logs request lines), 5 after
  `app.redeploy rag-watcher`. The other apps (jellyfin, qbittorrent,
  syncthing, openclaw, obsidian-couchdb, cloudflared) will appear when
  they next emit a line. Don't panic when an idle container is "missing."

- **The Pi Promtail uses tecnativa/docker-socket-proxy; the NAS one
  doesn't.** Trade-off documented at the top of the config. Keep them in
  sync on label conventions (`container`, `compose_project`,
  `compose_service`, `host`) so existing Grafana queries work for both.

- **Run as `0:0` is required** for raw `unix:///var/run/docker.sock`
  access. Acceptable here because Promtail is read-only (bind-mounts are
  `:ro`, Promtail itself doesn't issue write API calls). If we add a
  second docker-socket consumer, switch to the proxy pattern instead of
  granting more containers root.

- **`could not inspect container info` errors after `app.redeploy`** are
  benign. When TrueNAS recreates a container, Promtail's tail target
  briefly outlives the container ID; the next 10s discovery refresh
  drops it and adds the replacement. If you see *persistent* inspect
  errors (the same container ID failing repeatedly minute over minute),
  something is actually wrong — but transient ones at deploy time are
  normal cleanup churn.
