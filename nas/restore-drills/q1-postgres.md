# Q1 — Postgres restore drill

**Last run:** 2026-04-30 ✅ pass

## Goal

Take a real LiteLLM dump from `bulk/backups/litellm-pgdump/`, decrypt
it, restore into a scratch Postgres container, and verify two known
rows survived: the SSO admin user (`gooral` / `proxy_admin`) and all
three Phase 7 virtual keys (`rag-watcher` / `openclaw` / `dev-pc-tools`).

## Source

`/mnt/bulk/backups/litellm-pgdump/litellm-20260430T123203Z.sql.gz.gpg`

## Steps run

```bash
# 1. Pick the freshest dump
LATEST=$(ls -t /mnt/bulk/backups/litellm-pgdump/litellm-*.sql.gz.gpg | head -1)

# 2. Spin up a scratch postgres on the NAS docker daemon
docker run -d --name pg-drill-q1 \
  -e POSTGRES_DB=litellm \
  -e POSTGRES_USER=litellm \
  -e POSTGRES_PASSWORD=drill-throwaway-pw \
  postgres:16-alpine
sleep 8     # wait for it to come up

# 3. Decrypt → unzip → restore into the scratch container
cp "$LATEST" /tmp/drill.gpg
gpg --batch --yes --decrypt \
  --passphrase-file /mnt/bulk/backups/.secrets/dump-passphrase \
  /tmp/drill.gpg \
  | gunzip \
  | docker exec -i pg-drill-q1 psql -U litellm -d litellm

# 4. Query
docker exec pg-drill-q1 psql -U litellm -d litellm -tAc \
  'SELECT user_id, user_role FROM "LiteLLM_UserTable";'
docker exec pg-drill-q1 psql -U litellm -d litellm -tAc \
  'SELECT key_alias, max_budget FROM "LiteLLM_VerificationToken" WHERE key_alias IS NOT NULL;'

# 5. Clean up
docker rm -f pg-drill-q1
rm -f /tmp/drill.gpg
```

## Result (2026-04-30)

```
gooral|proxy_admin
rag-watcher|1
openclaw|20
dev-pc-tools|30
```

End-to-end time: ~25 seconds (most of which is `docker run` warmup +
psql replay; the actual decrypt is millisecond-scale because the dump
is small at 64 KB).

## Findings / gotchas

- `truenas_admin` can't read `/mnt/bulk/backups/.secrets/dump-passphrase`
  (root:root 600). Run the drill from a midclt-driven cronjob (which
  runs as root), not from a regular SSH session. The drill above ran
  as a one-shot `cronjob.create` + `cronjob.run` + `cronjob.delete`.
- The `-i` flag on `docker exec ... psql` is mandatory — without it
  stdin gets closed and psql exits before the dump finishes streaming.
- `pg_dump --clean --if-exists` (used by the dump cron) means the SQL
  contains `DROP TABLE IF EXISTS` first; restoring into an empty DB
  works because the IF EXISTS makes the DROPs no-ops.
- The dump replays 200+ `ALTER TABLE` and 50+ `CREATE INDEX` statements
  — entirely normal for a Prisma-managed schema. None of them is an error.

## What's NOT covered

- The restore goes into a scratch container, not back to the live
  `litellm-postgres`. We don't test the production-overwrite path
  (which would require stopping LiteLLM, doing the swap, restarting).
- The dump is recent (issued today). Drills against multi-week-old
  dumps would surface schema-drift surprises that this run didn't.

## Next drill

**Q3 (Jul–Sep 2026) — ZFS rollback to scratch dataset.** Pick a
snapshot, `zfs clone` it to a scratch mountpoint, verify content
matches expectations. See `q2-zfs-rollback.md`.
