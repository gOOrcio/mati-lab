# NAS ZFS snapshot policy

Source of truth is `midclt call pool.snapshottask.query` on the NAS. This file
is a human inventory — keep roughly in sync after UI/API changes.

## Phase 2 tasks

| id | Dataset | Schedule | Retention | Naming |
|---:|---|---|---|---|
| 1 | `bulk/photos` | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` |
| 2 | `bulk/photos` | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` |
| 3 | `bulk/media` | daily 03:00 | 14 days | `auto-daily-%Y-%m-%d_%H-%M` |

**Combined effect for photos:** fine-grained rollback for 2 weeks
(`bulk/photos@auto-...`) + monthly-ish archive points for 90 days
(`bulk/photos@auto-daily-...`) without any complex retention math.

## Intentionally *not* snapshotted

- `bulk/downloads` — transient torrent data; snapshots would balloon
- `bulk/immich-uploads` — dataset exists but Immich is deferred (Task 3)
- `fast/databases/immich-pgdata` — live Postgres; block snapshots alone are
  unsafe. Pair with `pg_dump` in Phase 8C before enabling.
- `bulk/backups` — recursive/self-referential (it already *is* the backup
  destination from the Pi)

## Other datasets worth a later pass

- `bulk/obsidian-vault`, `bulk/obsidian-couchdb` — user data, high value
- `bulk/gitea-data`, `bulk/gitea-config` — self-hosted git, high value

These aren't Phase 2 but should land early in Phase 8 when the full snapshot
policy gets formalized.

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
