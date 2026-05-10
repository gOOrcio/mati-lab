# Known flake — act_runner Docker cleanup race

**First seen:** 2026-05-08, hermes-investor builds 334 (push) + 337 (push merge commit).
**Symptom:** `ci / python (push)` reports failure, but the test job actually passed cleanly (`434 passed`, coverage uploaded). Failure happens AFTER `Post actions/checkout — Success`, during runner-level container teardown.

**Diagnostic line in logs:**
```
failed to copy content to container: Error response from daemon:
Could not find the file /var/run/act/ in container <hash>
```

**Notable:** the same code on the `pull_request` trigger passes. Only `push` triggers exhibit the race so far.

## Actions taken

### 2026-05-09 — image bump (did NOT fix it)

Bumped `gitea/act_runner:0.2.13-dind-rootless` → `gitea/runner:0.6.1-dind-rootless`.
The `act_runner` repo on Docker Hub is deprecated; upstream renamed to `gitea/runner`
at the 0.5/0.6 line. YAML config + env vars + labels unchanged, so this was a tag swap.
**Race recurred** on hermes-investor build 2026-05-10 10:00 UTC.

### 2026-05-10 — rootless → rootful DinD (root cause)

Smoking gun in the runner logs:

```
WARNING: Running in rootless-mode without cgroups. Systemd is required
         to enable cgroups in rootless-mode.
```

The inner dockerd was silently degrading to a no-cgroups mode because rootless
dockerd needs systemd-delegated cgroupv2 to enable them, and our runner container
isn't a systemd PID-1 environment. With no cgroups, dockerd can't subscribe to
container lifecycle events (`failed to add inotify watch for memory.events: no
such file or directory`), so the cleanup path races itself (`removal of container
... is already in progress`) and act's docker-cp during Post-actions hits a
container that's already been reaped (`Could not find the file /var/run/act/`).

Fix: switch image variant `gitea/runner:0.6.1-dind-rootless` → `gitea/runner:0.6.1-dind`
and bind-mount daemon.json at `/etc/docker/daemon.json` instead of
`/home/rootless/.config/docker/daemon.json`. The runner container is already
`privileged: true` and lives on its own dedicated VM, so the rootless security
delta was minimal anyway.

Re-deploy: `cd compute/gitea_runner_vm && make deploy` then watch the next
`push` build on `hermes-investor`. The cgroup warning should be gone from the
runner logs.

## Where the runner actually lives

- **VM:** `gitea-runner` at `192.168.1.49`, Proxmox VM 102.
- **Container:** `gitea-runner-runner-1` (Docker Compose project `gitea-runner` at `/var/lib/gitea-runner/compose.yml`).
- **Wrapping systemd unit:** `gitea-runner.service` (NOT `act_runner.service` — that unit doesn't exist).
- **Deployed via:** `compute/gitea_runner_vm/playbooks/deploy_app.yml` (Ansible).

## What to check (in order, if 0.6.1 still races)

1. **Container version inside the box.**
   `ssh gitea-runner@192.168.1.49 'sudo docker exec gitea-runner-runner-1 gitea-runner --version'`
   (Pre-rename: the binary is `act_runner --version`. Image tag pin is in `group_vars/all/vars.yml` as `gitea_runner_version`.)
2. **Docker daemon health on the VM.**
   `ssh gitea-runner@192.168.1.49 'sudo journalctl -u docker -n 200 --no-pager'` for "container removed before exec" / "no such container". If frequent → `sudo systemctl restart docker`.
3. **Disk pressure on runner VM.**
   `ssh gitea-runner@192.168.1.49 'df -h /var/lib/docker'` — if >85% used, the daemon's container GC can race with workflow teardown. Prune via `sudo docker system prune -af --volumes`.
4. **Concurrency.**
   If multiple workflows run on the same VM simultaneously, the cleanup races compound. Check `runner.capacity` in `templates/runner-config.yaml.j2` (currently 2). Drop to 1 temporarily if reproducible.

## Workaround until fully resolved

- The image-build (`build-and-publish / build`) workflow is **independent** and not affected — deploys can proceed.
- PR merge gates rely on `pull_request`-trigger checks (which pass), so this doesn't block development.
- If a `push`-only workflow needs to actually be required, retrigger via empty commit or remove the cleanup-affected step.

## Followup pointer

→ Linked from `docs/followups.md` row **7.x.10**.
