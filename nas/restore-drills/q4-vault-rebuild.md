# Q4 — Vault rebuild end-to-end

**Status:** pending (target 2027 Q1).

## Goal

Most ambitious of the four drills: prove that if the NAS lost the
Obsidian vault entirely, you could rebuild from a healthy Mac client +
ZFS snapshot + Phase 6 RAG pipeline coming back up clean.

Five things must work together:
1. Snapshot of `bulk/obsidian-vault` exists and has yesterday's writes.
2. CouchDB on NAS (`obsidian-couchdb`) can be restored from its snapshot.
3. The `livesync` user creds in PM still match what the Mac client
   has saved (or both can be re-issued without losing client state).
4. `rag-watcher` reconciles the restored vault content into Qdrant
   without manual intervention.
5. Vault search via `mcp__vault-rag__vault_search` returns hits
   against the restored content.

## Suggested steps

```bash
# Phase 1: simulate loss WITHOUT actually losing anything
# Clone the current vault to a scratch path; verify content; clean up.
zfs snapshot bulk/obsidian-vault@drill-q4-baseline   # extra safety
zfs clone bulk/obsidian-vault@drill-q4-baseline bulk/_drill-q4-vault
zfs set mountpoint=/mnt/_drill-q4-vault bulk/_drill-q4-vault
ls /mnt/_drill-q4-vault    # confirm content

# Phase 2: simulated restore from a non-recent snapshot
# Pick a daily snapshot from a week ago, clone it instead of the live state.
SNAP="bulk/obsidian-vault@auto-daily-2026-XX-XX_02-30"
zfs clone "$SNAP" bulk/_drill-q4-vault-old
diff -r /mnt/_drill-q4-vault /mnt/_drill-q4-vault-old   # see what's drifted

# Phase 3: end-to-end rag-watcher rebuild
# Spin a scratch Qdrant on a different port, point a scratch rag-watcher
# at the cloned vault, confirm reconcile produces the expected point count.
# (Outside scope of a quarterly drill if it gets too elaborate; document
# the gap and revisit when an actual incident teaches us what's missing.)

# Cleanup
zfs destroy bulk/_drill-q4-vault
zfs destroy bulk/_drill-q4-vault-old
zfs destroy bulk/obsidian-vault@drill-q4-baseline
```

## Honesty check

This drill is the closest thing to a "DR exercise" we run. It does
NOT prove recovery from physical disk loss — that scenario is
explicitly accepted as data loss in `nas/disaster-rebuild.md`. What
it proves: ZFS snapshot retention is meaningful, CouchDB restore
flow is documented, the Phase 6 RAG pipeline survives a vault rebuild
without manual surgery.

## Findings / gotchas

(Run the drill, fill this in.)
