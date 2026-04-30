# Q3 — vzdump VM restore drill

**Status:** pending (target Oct–Dec 2026).

## Goal

Pick a vzdump archive from `/mnt/pve/nas-backups/dump/`, restore it to
a scratch VMID on Proxmox, boot it, log in, confirm content, then
destroy the scratch VM.

Easiest target: VM 9000 (the cloud-init template) — small (~315 MB
compressed), fast to restore, no real state to worry about. If the
Q3 drill happens to need a meatier exercise, restore VM 100 (Ollama
template) instead.

## Why a scratch VMID

Restoring on top of an existing VMID will ask Proxmox to overwrite a
running VM. Always use a scratch VMID (e.g. 999 or 998) so the live
VMs are untouched.

## Suggested steps

```bash
# Pick latest archive
ls -lh /mnt/pve/nas-backups/dump/vzdump-qemu-9000-*.vma.zst | tail -3

# Restore to scratch VMID 999
qmrestore /mnt/pve/nas-backups/dump/vzdump-qemu-9000-2026-XX-XX.vma.zst 999

# Verify the VM exists + is bootable
qm config 999
qm start 999
sleep 30
qm status 999      # expect: status: running

# Optional: SSH in / inspect cloud-init log to confirm boot finished cleanly
# (cloud-init template defaults to no SSH key; needs configure_vm.yml run first
# in real deploy.)

# Clean up
qm stop 999
qm destroy 999
```

## Findings / gotchas

(Run the drill, fill this in.)
