# Known flake — act_runner Docker cleanup race

**First seen:** 2026-05-08, hermes-investor builds 334 (push) + 337 (push merge commit).
**Symptom:** `ci / python (push)` reports failure, but the test job actually passed cleanly (`434 passed`, coverage uploaded). Failure happens AFTER `Post actions/checkout — Success`, during runner-level container teardown.

**Diagnostic line in logs:**
```
failed to copy content to container: Error response from daemon:
Could not find the file /var/run/act/ in container <hash>
```

**Notable:** the same code on the `pull_request` trigger passes. Only `push` triggers exhibit the race so far.

## Action taken (2026-05-09 — pending verification)

Bumped image `gitea/act_runner:0.2.13-dind-rootless` → `gitea/runner:0.6.1-dind-rootless`.
The `act_runner` repo on Docker Hub is deprecated; upstream renamed to `gitea/runner`
at the 0.5/0.6 line. YAML config + env vars + labels unchanged, so this is a tag swap.
Newer `nektos/act` bundled with 0.6.x is expected to fix the cleanup race.

Re-deploy: `cd compute/gitea_runner_vm && make deploy` then watch the next `push`
build on `hermes-investor`. If it still races, the next steps are below.

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
