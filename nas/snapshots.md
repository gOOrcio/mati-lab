# NAS ZFS snapshot policy

Source of truth is `midclt call pool.snapshottask.query` on the NAS. This file
is a human inventory — keep roughly in sync after UI/API changes.

## Active tasks

| id | Dataset | Schedule | Retention | Naming | Origin |
|---:|---|---|---|---|---|
| 1 | `bulk/photos` | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 2 |
| 2 | `bulk/photos` | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 2 |
| 3 | `bulk/media` | daily 03:00 | 14 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 2 |
| 6 | `bulk/obsidian-couchdb` | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 5 |
| 7 | `bulk/obsidian-couchdb` | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 5 |
| 8 | `bulk/obsidian-vault` | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 5 |
| 9 | `bulk/obsidian-vault` | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 5 |
| 10 | `fast/qdrant-data` | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 6 |
| 11 | `fast/qdrant-data` | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 6 |

**Pattern:** every protected dataset gets the same hourly+daily pair
(2w / 90d). Different services occupy different id-blocks because of
when they were created; the `id` is just a TrueNAS row key, not
meaningful order. Dataset name is the source of truth.

**Combined effect:** fine-grained rollback for 2 weeks (`@auto-...`) +
monthly-ish archive points for 90 days (`@auto-daily-...`) without any
complex retention math.

## Adding a new dataset's snapshot task

```bash
# Edit DATASET to taste, then:
DATASET="fast/<your-new-dataset>"
cat > /tmp/snap-$DATASET-hourly.json <<EOF
{"dataset":"$DATASET","recursive":false,"lifetime_value":2,"lifetime_unit":"WEEK","enabled":true,"exclude":[],"naming_schema":"auto-%Y-%m-%d_%H-%M","allow_empty":false,"schedule":{"minute":"0","hour":"*","dom":"*","month":"*","dow":"*","begin":"00:00","end":"23:59"}}
EOF
cat > /tmp/snap-$DATASET-daily.json <<EOF
{"dataset":"$DATASET","recursive":false,"lifetime_value":90,"lifetime_unit":"DAY","enabled":true,"exclude":[],"naming_schema":"auto-daily-%Y-%m-%d_%H-%M","allow_empty":false,"schedule":{"minute":"30","hour":"2","dom":"*","month":"*","dow":"*","begin":"00:00","end":"23:59"}}
EOF
scp /tmp/snap-*.json truenas_admin@192.168.1.65:/tmp/
ssh truenas_admin@192.168.1.65 'midclt call pool.snapshottask.create "$(cat /tmp/snap-*-hourly.json)"'
ssh truenas_admin@192.168.1.65 'midclt call pool.snapshottask.create "$(cat /tmp/snap-*-daily.json)"'
```

Then add the two new ids to the table above.

## Intentionally *not* snapshotted

- `bulk/downloads` — transient torrent data; snapshots would balloon
- `bulk/immich-uploads` — dataset exists but Immich is deferred (Phase 2 Task 3)
- `fast/databases/immich-pgdata` — live Postgres; block snapshots alone are
  unsafe. Pair with `pg_dump` in Phase 8C before enabling.
- `bulk/backups` — recursive/self-referential (it already *is* the backup
  destination from the Pi)
- `fast/databases/litellm`, `fast/databases/rag-watcher`, `fast/databases/promtail`
  — service-config datasets; small, redeployable from this repo + the password
  manager. Phase 8 may add light snapshots if config drift becomes a concern,
  but they're not on a ZFS-rollback criticality tier.
- `fast/ix-apps` — TrueNAS-managed; iX-IT recommends not snapshotting this
  (interferes with image GC and app upgrade machinery).

## Datasets to consider for Phase 8

- `bulk/gitea-data` (Postgres for Gitea — needs `pg_dump` pairing first)
- `bulk/gitea-actions` (CI artifacts — may not be high-value enough to back up)
- `fast/databases/openclaw` (state DB; per `nas/openclaw/notes.md` Phase-8 row 8.6)

These are tracked in `docs/followups.md` Phase 8 section.

## Monitoring failures

TrueNAS has no webhook alert service in 25.10 ("Goldeye"), so we can't route
`SnapshotFailed` → ntfy directly. Interim:

- Failures appear in the **TrueNAS alert bell** (`SnapshotFailed` class is on
  by default).
- Phase 8E: add an Uptime Kuma HTTP-Keyword monitor on a TrueNAS
  `/api/v2.0/alert/list` endpoint or a `midclt`-powered relay, route through
  ntfy like the rest of the homelab.

## Manual operations

```bash
# List all snapshot tasks
ssh truenas_admin@192.168.1.65 'midclt call pool.snapshottask.query'

# Run a task on demand (by id from the list above)
ssh truenas_admin@192.168.1.65 'midclt call pool.snapshottask.run 1'

# See what snapshots actually exist on a dataset
ssh truenas_admin@192.168.1.65 'zfs list -t snapshot -o name,creation -s creation bulk/photos'

# Roll back (DESTRUCTIVE — loses changes after the snapshot)
ssh truenas_admin@192.168.1.65 'sudo zfs rollback bulk/photos@auto-YYYY-MM-DD_HH-MM'

# Clone a snapshot somewhere non-destructive to inspect
ssh truenas_admin@192.168.1.65 'sudo zfs clone bulk/photos@auto-... bulk/_restore-test'
```
