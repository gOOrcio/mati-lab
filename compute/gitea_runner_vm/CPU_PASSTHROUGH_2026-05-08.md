# Gitea runner CPU passthrough fix — 2026-05-08

## What changed

VM 102 (gitea-runner, `192.168.1.49`) had no `cpu:` line in its Proxmox config and was using the default `kvm64` model. That model masks SSE4.1, SSE4.2, SSSE3, and POPCNT — instructions x86-64-v2 baseline binaries need. NumPy 2.x and pandas 2.x ship with x86-64-v2 baseline by default, so any CI job that imports pandas would fail at module load with:

```
RuntimeError: NumPy was built with baseline optimizations: (X86_V2)
but your machine doesn't support: (X86_V2).
```

This had been worked around in `hermes-investor` by mocking yfinance at a local shim level (commit 066dbe7, see `docs/ci-runner-cpu-issue.md` in that repo), but the workaround was incomplete — 4 tests still patched `yfinance.Ticker` directly, forcing yfinance/pandas import. Those 4 tests have been failing on `main` since the discovery extensions landed.

## What I did (live, then made idempotent)

### Live fix on Proxmox host (`192.168.1.184`)

```bash
ssh root@192.168.1.184
qm set 102 --cpu host
qm shutdown 102 --timeout 60
qm start 102
```

Total downtime ≈ 30s. Runner systemd unit auto-restarts on boot, container `gitea-runner-runner-1` was up 13 seconds after VM boot.

Post-fix verification on the runner:

```
$ cat /proc/cpuinfo | grep "model name" | head -1
model name : AMD Ryzen 7 3700X 8-Core Processor

$ cat /proc/cpuinfo | grep flags | head -1 | tr ' ' '\n' | grep -E '^(sse4_1|sse4_2|ssse3|popcnt|avx)$' | sort
avx
popcnt
sse4_1
sse4_2
ssse3
```

(Pre-fix, the same VM reported "Common KVM processor" with NONE of those flags.)

### Idempotency in ansible

- `compute/gitea_runner_vm/group_vars/all/vars.yml` — added `vm_cpu_type: "host"` to the VM-spec block.
- `compute/gitea_runner_vm/playbooks/create_vm.yml` — the "Set VM resources" task now passes `cpu: "{{ vm_cpu_type | default('host') }}"` to `community.general.proxmox_kvm`.

A future `make site` or `make create-vm` will preserve the setting; if the VM is destroyed and re-created, it comes back with `cpu: host` from the start.

## Why `host` and not `x86-64-v3`

Both work for our current host (Zen 2 supports v3). `host` exposes the actual host CPU directly — slightly higher performance (no instruction filtering layer), exact compatibility, and simpler to reason about. The trade-off is that VM live-migration to a CPU with different features would break. We have one Proxmox host (`pve` / `192.168.1.184`); migration is not a concern.

## Verification

PR `wave/0-characterization-tests` on hermes-investor (PR #11) was failing 4 yfinance/pandas tests pre-fix. After this change those tests should pass without any code edit on the hermes-investor side; that PR's CI was rerun to confirm.

## Cross-references

- `hermes-investor/docs/ci-runner-cpu-issue.md` — the original incident report, now updated with this resolution.
- `hermes-investor/docs/REFACTOR_ROADMAP.md` — the refactor plan that surfaced the latent failures during Wave 0.
