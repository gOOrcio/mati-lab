# Dev PC — restore drill

**Status:** pending — repo init verified at install; full restore-onto-fresh-Ubuntu
not yet exercised.

## Goal

Prove that a freshly installed Ubuntu box can recover the dev-PC working
state from the restic repo on the NAS: `~/Projects/`, `~/.claude/`,
dotfiles, `~/.ssh/`. Specifically: open the repo with the password from
PM, browse snapshots, restore a recent one, verify Claude Code memory +
gitignored plan docs are present.

## Source

```bash
restic -r sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic \
  snapshots
```

Password file `~/.config/restic/repo-password` (mode 0600). Value lives
in PM under `homelab/dev-pc/restic-repo-password`.

## Steps to run when the drill fires

```bash
# 1. On a scratch / replacement box, install restic + ssh access to NAS.
sudo apt install -y restic
ssh truenas_admin@192.168.1.65 true   # confirm SSH key works

# 2. Stage the repo password from PM.
mkdir -p ~/.config/restic
chmod 700 ~/.config/restic
read -rs PW && printf '%s' "$PW" > ~/.config/restic/repo-password
chmod 600 ~/.config/restic/repo-password
unset PW

export RESTIC_REPOSITORY=sftp:truenas_admin@192.168.1.65:/mnt/bulk/backups/dev-pc-restic
export RESTIC_PASSWORD_FILE=$HOME/.config/restic/repo-password

# 3. Browse.
restic snapshots                                # confirm hostnames + tags + counts
restic stats latest                             # rough size sanity check

# 4. Pick a restore target dir (NOT $HOME — restore into a scratch dir
#    first, then selectively rsync into place after sanity check).
RESTORE=$HOME/_dev-pc-restore
mkdir -p "$RESTORE"
restic restore latest --target "$RESTORE"

# 5. Verify expected paths exist with non-zero size.
for p in Projects/mati-lab/CLAUDE.md \
         .claude/projects \
         .ssh/id_ed25519 \
         .gitconfig; do
  test -s "$RESTORE/$HOME/$p" && echo "OK $p" || echo "MISSING $p"
done

# 6. Diff against a known-good file. The mati-lab repo on the dev box
#    should match what's in restic (modulo uncommitted edits since the
#    last snapshot).
diff -r --brief "$RESTORE/$HOME/Projects/mati-lab" "$HOME/Projects/mati-lab" \
  | head -40

# 7. After verifying: rsync the dirs you actually need into place.
#    DO NOT do `cp -a "$RESTORE/$HOME/" "$HOME/"` — collisions, ownership
#    corner cases.
rsync -av "$RESTORE/$HOME/.claude/"   "$HOME/.claude/"
rsync -av "$RESTORE/$HOME/.ssh/"      "$HOME/.ssh/"
chmod 700 "$HOME/.ssh"; chmod 600 "$HOME/.ssh/"*

# 8. Re-clone Projects/* if the working trees aren't already there.
#    Most repos are also pushed to Gitea / GitHub — restoring from
#    restic catches the gitignored files (plan docs, .env, etc.) the
#    git remotes don't have.
```

## Acceptance

- [ ] `restic snapshots` lists at least one snapshot tagged `dev-pc-systemd`
      from the expected hostname.
- [ ] `restic stats latest` returns a reasonable size (tens of GB,
      not megabytes — would indicate empty includes).
- [ ] `restic restore latest --target $RESTORE` completes with no errors.
- [ ] `~/.claude/projects/-home-gooral-Projects-mati-lab/memory/MEMORY.md`
      exists and matches the live file.
- [ ] `docs/superpowers/plans/*.md` (gitignored on the repo) are present
      under `$RESTORE/$HOME/Projects/mati-lab/`.
- [ ] `~/.ssh/id_ed25519` is recoverable (mode 600, key parses).
- [ ] `restic check` completes without errors (read-only — proves repo
      integrity).

## What this drill does NOT cover

- Ollama models — explicitly excluded; recover via `ollama pull` per
  Phase 3B.
- Browser profiles, app state under `.config/google-chrome`, etc. —
  explicitly excluded.
- Repos that exist only on the dev PC (no git remote) — restic has them,
  but ideally every working repo has a Gitea remote (see followup ∞.1
  for ones not migrated).

## Related

- Backup script: `compute/dev_pc/backup/restic-backup.sh`
- Installer: `compute/dev_pc/backup/install.sh`
- Notes: `compute/dev_pc/notes.md`
- Kuma monitor: `backup-dev-pc-restic` (push, daily heartbeat)
