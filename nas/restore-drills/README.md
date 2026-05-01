# Restore drills

Quarterly. The drill IS the documentation — runbooks live as siblings
in this directory. Goal: prove the backup is restorable, before you
need it.

## Cadence (target dates)

| Quarter | Drill | Runbook | Last run |
|---|---|---|---|
| Q2 (Apr–Jun 2026) | Postgres restore (LiteLLM) | [`q1-postgres.md`](q1-postgres.md) | 2026-04-30 ✅ |
| Q3 (Jul–Sep 2026) | ZFS rollback to scratch dataset | [`q2-zfs-rollback.md`](q2-zfs-rollback.md) | (pending) |
| Q4 (Oct–Dec 2026) | vzdump VM restore | [`q3-vzdump.md`](q3-vzdump.md) | (pending) |
| 2027 Q1 | Vault rebuild end-to-end | [`q4-vault-rebuild.md`](q4-vault-rebuild.md) | (pending) |
| 2027 Q2 | Hermes Agent restore (logical zip) | [`hermes-restore.md`](hermes-restore.md) | (pending — recipe smoke-tested 2026-05-01) |

## Rules

- A drill counts only if it touches **real backup artifacts** + restores
  to a **scratch destination** (never the production path).
- The runbook captures every command actually run + every gotcha hit.
  No "should work" — only "did work."
- Failure is interesting. If a drill fails, file the gap as a `docs/followups.md`
  row and retry next quarter.
- Soft cadence: missing one is OK. Don't reset the clock; pick up next
  quarter.
- After each drill update the "Last run" cell + the runbook with the
  date and any new findings.
