# gitea-runner VM (Proxmox)

Lightweight Debian 12 VM that hosts the Gitea Act Runner for our CI.
Lives on Proxmox at `192.168.1.49` (VM ID 102), provisioned and managed
via Ansible from this directory.

## Why a VM, not LXC

DinD-rootless needs full kernel namespace isolation. Privileged LXC works
but defeats LXC's reason for being. Plain VM is the simpler, safer answer.

## Why DinD-rootless instead of mounting `/var/run/docker.sock`

The socket-mount mode leaks `GITEA_RUNNER_REGISTRATION_TOKEN` via
`docker inspect` on the host. DinD-rootless contains the runner inside
its own privileged container with a nested rootless dockerd; jobs spawn
unprivileged sibling containers from there.

## VM spec

| Field | Value |
|---|---|
| VM ID | 102 |
| Name | gitea-runner |
| Template | `debian12-cloud` (vmid 9000 on Proxmox) |
| Cores | 2 |
| Memory | 3072 MB (no balloon) |
| Disk | 64 GB |
| IP | 192.168.1.49 (static) |
| SSH user | gitea-runner |

## Ansible workflow

```bash
make install     # install Ansible collections (one-time)
make site -K     # create VM + configure + deploy (one-shot)

# or step-by-step:
make create-vm
make configure   # needs -K for sudo password (first time only)
make deploy
```

The `deploy` playbook is idempotent — re-running it re-renders
`runner-config.yaml` and the systemd unit, then the runner picks them up
on the next restart.

## Runner registration (manual one-shot, NOT in Ansible)

Registration token is sensitive and one-shot per registration. Don't bake
it into vars.

1. Gitea UI → Site Admin → Actions → Runners → Create new Runner → copy token.
2. Plant token on the VM:

   ```bash
   ssh gitea-runner@192.168.1.49 "sudo install -m 600 -o 1000 -g 1000 /dev/stdin /var/lib/gitea-runner/secrets/runner-token <<< '<TOKEN>'"
   ```

   (uid 1000 because the rootless runner inside DinD reads as that uid.)
3. Start the systemd unit:

   ```bash
   ssh gitea-runner@192.168.1.49 'sudo systemctl enable --now gitea-runner.service'
   ```

4. Confirm in Gitea UI: runner status "Idle".
5. Delete token file: `ssh gitea-runner@192.168.1.49 'sudo rm /var/lib/gitea-runner/secrets/runner-token'` (registration is now permanent in `/data/.runner` inside the container).

## Runner labels

Single label: `ubuntu-latest:docker://catthehacker/ubuntu:act-latest`.

`catthehacker/ubuntu:act-latest` is the community-standard image for
act/act_runner — ships with Docker CLI + common toolchains. The first
build pulls ~700 MB; subsequent jobs reuse the layer.

We deliberately dropped `debian-stable` and `linux-arm64` labels:

- `debian-stable` was confusing (mapped to ubuntu image anyway).
- `linux-arm64` was misleading (this runner is amd64; arm64 jobs
  cross-emulate via qemu, not native).

If we ever add a real arm64 runner (e.g. on a separate Pi), it registers
with `linux-arm64` and arm64 workflows route there natively.

## arm64 cross-builds

Runner is x86_64; `caddy-cloudflare` and `grafana-ntfy-bridge` are arm64.
Cross-builds use qemu-user-static + binfmt_misc, registered at host boot
via `/etc/systemd/system/qemu-binfmt.service` (provisioned by Ansible).
DinD inherits the kernel-level binfmts, so `docker buildx --platform
linux/arm64` Just Works.

`docker/setup-qemu-action` is **deliberately NOT used** in our
`image-build-arm64.yml` reusable workflow — it tries to register binfmts
inside the inner Docker container with `--privileged`, which DinD-rootless
doesn't allow. The host-level systemd registration replaces it.

3-5× slower than native arm64 (xcaddy compile takes ~12 min via qemu).
Acceptable for our small images. Native arm64 hardware is a Phase 5
follow-up if build times become annoying — see
`docs/superpowers/plans/2026-04-29-followup-actions-replace-make.md`.

## Resource limits

`compose.yml` caps the runner container at 2.5G RAM and 1.8 CPU. Without
this, a runaway build can OOM the VM.

`config.yaml` sets `runner.capacity: 2` — two CI jobs run in parallel.
With a 2-vCPU VM this is the practical max; bump to 3 only if RAM allows
and quickly-failing jobs justify it.

## Restart / update

| Action | Command |
|---|---|
| Restart runner | `ssh gitea-runner@192.168.1.49 'sudo systemctl restart gitea-runner'` |
| Re-deploy config (Ansible) | `make deploy` (then restart) |
| Tail logs | `ssh gitea-runner@192.168.1.49 'sudo journalctl -u gitea-runner -f'` |
| Wipe workflow cache | `ssh -i ~/.ssh/id_ed25519 gitea-runner@192.168.1.49 'sudo docker exec gitea-runner-runner-1 sh -c "rm -rf /home/rootless/.cache/act/*"'` |

The cache wipe is needed when a reusable workflow at `@main` changes —
act_runner caches by ref and doesn't always re-pull on branch updates.
Long-term fix: tag releases of `gooral/ci-workflows` and consumers pin to
`@v1`.

## Gotchas / lessons

1. **State dirs need uid 1000.** `/var/lib/gitea-runner/{data,secrets}`
   must be `chown 1000:1000 mode 0700` for the rootless container to read
   the registration token and persist the runner identity. Baked into
   `playbooks/deploy_app.yml`.
2. **Inventory hostname matches play `hosts:` directive.** Inventory uses
   `gitea_runner` (underscore), not `gitea-runner` (hyphen).
3. **Don't use `vault_vm_initial_password`** — the variable is
   `vault_vm_root_password` (matches existing convention from other VMs).
4. **Template vmid is 9000** (`debian12-cloud`), not 100. The default
   Ubuntu template doesn't exist on this Proxmox; Debian works fine.
5. **CI secret naming**: `GITEA_*` is reserved by Gitea Actions. Use
   plain `REGISTRY_USER` / `REGISTRY_TOKEN`. Setting a `GITEA_*`-prefixed
   secret returns HTTP 400 "invalid variable or secret name".
6. **`secrets: inherit` on cross-repo `uses:` doesn't auto-pass.** Reusable
   workflow must declare expected secrets under
   `on: workflow_call: secrets:` for them to come through.
