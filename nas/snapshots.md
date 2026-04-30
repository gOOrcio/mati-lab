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
| 12 | `fast/databases` (non-recursive) | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 7 |
| 13 | `fast/databases` (non-recursive) | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 7 |
| 14 | `bulk/gitea` **(recursive)** | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 8 |
| 15 | `bulk/gitea` **(recursive)** | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 8 |
| 16 | `fast/databases/gitea` (non-recursive, Postgres data) | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 8 |
| 17 | `fast/databases/gitea` (non-recursive, Postgres data) | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 8 |
| 18 | `bulk/backups` (non-recursive — captures Phase-8 dumps + Pi rsync target + Proxmox vzdump) | daily 02:30 | 90 days | `auto-daily-%Y-%m-%d_%H-%M` | Phase 8 |
| 19 | `bulk/backups` (non-recursive) | hourly (min 0) | 2 weeks | `auto-%Y-%m-%d_%H-%M` | Phase 8 |

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
- ~~`bulk/backups` — was previously skipped as "self-referential."~~ Phase 8 enables snapshots here (tasks 18/19) — captures Phase-8 dumps + Pi rsync target + Proxmox vzdump. Diff-only storage cost is small; gives a multi-day rollback dimension on top of the in-script `find -mtime` retention.
- `fast/databases/gitea` — separate sub-dataset; explicitly excluded by the
  non-recursive snapshot on `fast/databases` (Phase 7 task 12/13). Logical
  SQLite dump pairing lands in Phase 8 (followups row 8.4).
- `fast/databases/immich-pgdata` — Postgres for Immich. Block snapshots
  alone are unsafe; pair with `pg_dump` in Phase 8 (followups row 8.3).
- `fast/ix-apps` — TrueNAS-managed; iX-IT recommends not snapshotting this
  (interferes with image GC and app upgrade machinery).

### Notable change in Phase 7

Adding the LiteLLM Postgres sidecar (Tasks 6–9) made `fast/databases` itself
stateful: the new directory `fast/databases/litellm-pgdata` is *inside* the
parent dataset, not a sub-dataset of its own. The non-recursive snapshot task
on `fast/databases` covers it without also sweeping `gitea` and
`immich-pgdata` (which are separate sub-datasets).

The snapshots are crash-consistent (ZFS snapshot of a running Postgres);
restore from one and Postgres will run WAL replay on first boot. Phase 8
will pair this with periodic `pg_dump` for transactional consistency.

## Encryption-at-rest posture (Phase 8 audit, 2026-04-30)

**Zero datasets on this NAS use ZFS-native encryption today.** Per the
single-NAS-no-off-box scope decided for Phase 8, the threat model that
ZFS encryption defends against (physical theft of disks) is real but
medium-priority. Migrating live data into encrypted children
(`zfs send | zfs recv` + mountpoint swap) is a sustained-downtime
operation; the call is to **encrypt-on-rebuild rather than encrypt-now**
for existing datasets, and to use **per-file gpg-symmetric** encryption
for new dump destinations rather than nesting that under ZFS-native too.

| Dataset | Sensitivity | Verdict |
|---|---|---|
| `bulk/photos` | high (when populated) | encrypt-on-rebuild |
| `bulk/obsidian-vault` | high | encrypt-on-rebuild |
| `bulk/obsidian-couchdb` | high | encrypt-on-rebuild |
| `bulk/gitea/*` | medium (mostly OSS code, but configs leak) | encrypt-on-rebuild |
| `fast/qdrant-data` | medium (vault embeddings reconstruct vault content) | encrypt-on-rebuild |
| `fast/databases/*` (litellm-pgdata, gitea pgdata, immich-pgdata) | high (DB contents) | encrypt-on-rebuild |
| `bulk/backups/*-pgdump` (new in Phase 8) | high | gpg-symmetric only — see `nas/backup-jobs/notes.md` |
| `bulk/media` | low | skip permanent |
| `bulk/downloads` | low (transient) | skip permanent |
| `bulk/immich-uploads` | medium (when populated) | encrypt-on-rebuild |
| `bulk/backups/network-pi` | medium | encrypt-on-rebuild |
| `fast/ix-apps` | mixed | skip — TrueNAS-managed |

**When the next NAS rebuild happens** (replacement hardware, re-pool, fresh
TrueNAS install, etc.), create every "encrypt-on-rebuild" dataset with
native encryption from creation time. Use a hex-key file on the boot
pool (auto-loaded) rather than a passphrase prompt, to avoid blocking
boot. Key file goes in PM under `homelab/nas/zfs-encryption-key`.

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
