# Q2 — ZFS rollback drill

**Status:** pending (target Jul–Sep 2026).

## Goal

Pick a recent snapshot of a non-trivial dataset (`fast/qdrant-data`
suggested — has ~180 chunks, easy to verify by point count), clone it
to a scratch mountpoint via `zfs clone`, mount it, and confirm the
data matches the expected state at snapshot time.

## Why a clone, not a rollback

`zfs rollback` is destructive — discards all writes since the snapshot.
A drill should never destroy production state. `zfs clone` creates a
read/write copy at a new mountpoint, leaving the original untouched.
After the drill, `zfs destroy` the clone.

## Suggested steps

```bash
# Pick a snapshot
zfs list -t snapshot -o name,creation -s creation fast/qdrant-data | tail -5

# Clone it to a scratch path
SNAP="fast/qdrant-data@auto-2026-XX-XX_XX-XX"
zfs clone "$SNAP" fast/_drill-q2-qdrant
zfs set mountpoint=/mnt/_drill-q2-qdrant fast/_drill-q2-qdrant

# Verify content
ls -la /mnt/_drill-q2-qdrant
# (For Qdrant specifically, the storage layout is
# collections/<name>/<segment-id>/... — verify the obsidian-vault
# collection dir is present.)

# Tear down
zfs destroy fast/_drill-q2-qdrant
```

## Findings / gotchas

(Run the drill, fill this in.)
