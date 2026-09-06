# MacBook Gitea runner (conditional, arm64/macOS)

Conditionally-available act_runner on the MacBook — the "Mac stopgap"
resolution of followup 4.f.1 (arm64 runner strategy). Online whenever the
laptop is awake; queued jobs targeting its labels simply wait while it's
away.

## Identity

| | |
|---|---|
| Runner name | `macbook-arm64` |
| Labels | `macos-arm64:host`, `linux-arm64:docker://ghcr.io/catthehacker/ubuntu:act-latest` |
| Instance | `https://gitea.mati-lab.online` |
| Config | `~/.config/act_runner/config.yaml` on the Mac (canonical copy: [`config.yaml`](config.yaml)) |
| Service | user LaunchAgent (canonical copy: [`io.gitea.act_runner.plist`](io.gitea.act_runner.plist) → `~/Library/LaunchAgents/`) |
| Logs | `~/Library/Logs/act_runner.log` |

## Hard rules

- **Nothing required may target this runner.** Jobs using `macos-arm64` /
  `linux-arm64` labels must be `workflow_dispatch` or otherwise optional —
  a required PR check would hang whenever the lid is closed.
- **`~/.config/act_runner/.runner` is a credential** (created at
  registration; contains the runner token/UUID). Never commit it; treat
  loss as "re-register", not "restore". Row in `nas/secrets-inventory.md`.

## Operations

```bash
# pause / resume (on the Mac)
launchctl unload ~/Library/LaunchAgents/io.gitea.act_runner.plist
launchctl load   ~/Library/LaunchAgents/io.gitea.act_runner.plist

# re-register (new token from Site Admin → Actions → Runners → Create new Runner)
# (binary is `gitea-runner`; labels come from config.yaml — the --labels flag is
#  ignored when the config file defines them, so keep them in sync there)
cd ~/.config/act_runner && gitea-runner register --no-interactive \
  --config ~/.config/act_runner/config.yaml \
  --instance https://gitea.mati-lab.online \
  --token <one-shot token> \
  --name macbook-arm64 \
  --labels "macos-arm64:host,linux-arm64:docker://ghcr.io/catthehacker/ubuntu:act-latest"
```

Online/offline status: Site Admin → Actions → Runners.

## Install trace

Set up via a self-contained Claude prompt (2026-09-06 session; see
`docs/sweep-2026-09-06.md` era). Docker runtime on the Mac: recorded here
after first registration — reconcile this file with the Mac-side setup
summary (runtime used, any deviations).

- [x] Reconciled with actual Mac install (2026-09-06)
  - Docker runtime: **Docker Desktop** (already installed; `AutoStart` was
    already on, nothing changed). Daemon 27.4.0, aarch64, 8 CPU.
  - Runner: Homebrew formula `gitea-runner` **3.3.2** (formula renamed from
    `act_runner`; binary is `/opt/homebrew/bin/gitea-runner`). Registered as
    runner id 6.
  - Deviations from the original scaffold:
    - `container.docker_host` set explicitly to Docker Desktop's socket
      (`~/.docker/run/docker.sock`) — launchd has no docker CLI context and
      `/var/run/docker.sock` was absent.
    - `host.workdir_parent` made absolute (runner does not expand `~`).
    - plist `__ACT_RUNNER__` → `/opt/homebrew/bin/gitea-runner`.
    - `~/.config/act_runner/.runner` chmod 600.
  - Verified: LaunchAgent running (KeepAlive), log shows
    `declare successfully` with both labels; `docker run --rm arm64v8/alpine
    uname -m` → `aarch64`.

## What targets it

Planned (7.x.5): dispatch-only arm64 image-build workflows for
`vault-rag-mcp` and `qbittorrent-mcp` — native arm64 builds replacing
dev-PC buildx/QEMU cross-compiles. Until those land, nothing targets this
runner.
