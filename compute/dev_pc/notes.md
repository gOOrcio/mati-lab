# Dev PC

The Ryzen 9 7900x / RTX 5070 Ti workstation. Dual-boot Ubuntu 24.04 +
Windows. Ubuntu side runs Ollama (Phase 3B), Claude Code, OpenCode,
and the Hermes/vault-rag tooling.

This directory exists to hold dev-PC-side automation that runs on the
box itself (vs. things on Proxmox or NAS). Today: the restic backup
job. May grow over time.

## What lives outside this repo

- `~/Projects/` (working directory for everything)
- `~/.claude/` (Claude Code state — memory entries, project history, MCP config)
- Personal dotfiles (`~/.config/`, `~/.zshrc`, `~/.gitconfig`, `~/.ssh/`)
- Ollama models under `~/.ollama/` — reproducible from `ollama pull`,
  not backed up

## Backup posture

`backup/restic-backup.sh` runs nightly via systemd user timer, pushes
into a restic SFTP repo on the NAS at
`sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic`.

- **Encryption:** restic-native AES-256, repo password file
  `~/.config/restic/repo-password` (mode 0600). PM label
  `homelab/dev-pc/restic-repo-password`.
- **Includes:** `~/Projects`, `~/.claude`, `~/.config`, `~/.ssh`,
  `~/.zshrc`, `~/.bashrc`, `~/.gitconfig`, `~/.profile`. (See
  `backup/restic-includes.txt`.)
- **Excludes:** `node_modules`, `.venv`, `__pycache__`, `*.pyc`,
  `.cache`, `target/`, `dist/`, `build/`, `~/.ollama`. (See
  `backup/restic-excludes.txt`.)
- **Schedule:** systemd user timer, `OnCalendar=*-*-* 02:30:00`,
  `Persistent=true` so the job catches up after the PC was off.
- **Retention:** `forget --keep-daily 14 --keep-weekly 8
  --keep-monthly 6 --prune`. Runs at the end of each Sunday backup.
- **Heartbeat:** Uptime Kuma push monitor `backup-dev-pc-restic`. URL
  in `~/.config/restic/kuma-push-url` (mode 0600). Push fires only on
  successful completion. Missed heartbeat = ntfy alert via Kuma's
  default routing.

## Why restic + SFTP (not rsync over NFS)

- **Dedup.** `~/.claude` and `~/Projects/*/dist` churn a lot — restic
  chunks + dedupes across snapshots, so 14 daily snapshots cost ~1.05×
  one snapshot, not 14×. Plain rsync to dated dirs would 14× the
  storage.
- **Encryption at rest.** Repo is AES-256 encrypted by restic. The NAS
  side cannot read the contents even with NFS / sudo. Means it's safe
  to include `~/.ssh/` (the gating concern was a future off-box copy of
  `bulk/backups` exposing keys; restic encryption survives that).
- **No fstab.** SFTP backend talks to the NAS over the same SSH key
  that `ssh truenas_admin@nas` already uses. No kernel NFS client,
  no mount-at-boot races.
- **Integrity verification.** `restic check` actually proves the repo
  is restorable. The Pi 5 rsync flow has no equivalent.

## Operational

```bash
# Manual run
~/Projects/mati-lab/compute/dev_pc/backup/restic-backup.sh

# Status
systemctl --user status dev-pc-backup.timer
systemctl --user list-timers dev-pc-backup.timer

# Browse snapshots
restic -r sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic snapshots

# Mount latest read-only (great for "what was the state of file X 5 days ago")
mkdir -p /tmp/restic-mnt
restic -r sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic mount /tmp/restic-mnt

# Integrity (slow; --read-data downloads everything, run quarterly)
restic -r sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic check
```

The repo password file is read by `restic`'s `--password-file` flag —
the `restic-backup.sh` script wires this up automatically. For
interactive `restic` calls, set `RESTIC_PASSWORD_FILE=$HOME/.config/restic/repo-password`
or paste the password from PM.

## Install / re-install

`backup/install.sh` is idempotent and is what you run on a fresh Ubuntu
install. It:

1. `apt install restic` if needed.
2. Creates `~/.config/restic/` (0700).
3. Generates a fresh repo password if `~/.config/restic/repo-password`
   doesn't exist, displays it once, and waits for you to confirm
   it's saved to PM (`homelab/dev-pc/restic-repo-password`).
4. Initialises the repo on the NAS (no-op if already initialised).
5. Prompts for the Kuma push URL and stages it at
   `~/.config/restic/kuma-push-url` (0600).
6. Installs the systemd user units to `~/.config/systemd/user/`,
   reloads, enables + starts the timer.
7. Enables `loginctl enable-linger` so the timer runs while you're
   logged out.

Run it once. Re-run it later if any of the above is missing — every
step is conditional.

## Restore

See `nas/restore-drills/dev-pc-restore.md`.

## Lessons

- **`loginctl enable-linger` is required** for user timers to fire when
  not logged in. Without it the timer is silently inactive whenever
  you log out — which on a single-user dev box is most of the time
  the PC is on but unused.
- **SFTP backend needs the NAS host in `~/.ssh/known_hosts`** before
  restic init works. If `ssh truenas_admin@192.168.1.65 'true'` works
  manually, restic SFTP works too.
- **Password file must be `0600`**; restic refuses 0644 with no error
  message.
- **Repo dir under `/mnt/bulk/backups/` must be owned by the SFTP user
  (`truenas_admin`)**, not root. The parent dataset is root-owned, so a
  bare `mkdir -p /mnt/bulk/backups/dev-pc-restic` over SSH-as-truenas_admin
  fails with `Permission denied`. Installer uses
  `sudo install -d -o truenas_admin -g truenas_admin -m 0700` for this.
