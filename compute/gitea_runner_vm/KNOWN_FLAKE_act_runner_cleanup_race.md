# Known flake — act_runner Docker cleanup race

**First seen:** 2026-05-08, hermes-investor builds 334 (push) + 337 (push merge commit).
**Symptom:** `ci / python (push)` reports failure, but the test job actually passed cleanly (`434 passed`, coverage uploaded). Failure happens AFTER `Post actions/checkout — Success`, during runner-level container teardown.

**Diagnostic line in logs:**
```
failed to copy content to container: Error response from daemon:
Could not find the file /var/run/act/ in container <hash>
```

**Notable:** the same code on the `pull_request` trigger passes. Only `push` triggers exhibit the race so far.

## What to check (in order)

1. **act_runner version.** `ssh runner-vm 'systemctl status act_runner | grep version'` — current pin is `v0.2.13`. Upstream issues mention this race fixed in newer `nektos/act` releases. Bump to latest stable, restart, smoke-test.
2. **Docker daemon health.** `journalctl -u docker -n 200` for "container removed before exec" / "no such container". If frequent → restart Docker on the runner VM.
3. **Disk pressure on runner VM.** `df -h /var/lib/docker` — if >85% used, the daemon's container GC can race with workflow teardown. Prune via `docker system prune -af --volumes`.
4. **Concurrency.** If multiple workflows run on the same VM simultaneously, the cleanup races compound. Check `act_runner.yaml` `runner.capacity`. Drop to 1 temporarily if reproducible.

## Workaround until fixed

- The image-build (`build-and-publish / build`) workflow is **independent** and not affected — deploys can proceed.
- PR merge gates rely on `pull_request`-trigger checks (which pass), so this doesn't block development.
- If a `push`-only workflow needs to actually be required, retrigger via empty commit or remove the cleanup-affected step.

## Followup pointer

→ Linked from `docs/followups.md` row **7.x.10**.
