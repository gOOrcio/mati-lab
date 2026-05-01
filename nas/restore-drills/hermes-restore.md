# Hermes Agent — restore drill

**Status:** pending — recipe verified at install (decrypt-roundtrip 2026-05-01),
full restore-and-resume drill not yet run. Schedule alongside the next regular
quarterly drill.

## Goal

Take a real Hermes dump from `bulk/backups/hermes/`, decrypt it, restore into
a scratch `/opt/data` directory, redirect a Hermes container at the restored
data, and confirm: (a) Telegram round-trip works (gateway sees the recovered
.env + bot token); (b) recent conversation history is visible in the
dashboard / sessions list (state.db restored).

## Source

Pick the freshest:

```bash
LATEST=$(ls -t /mnt/bulk/backups/hermes/hermes-*.zip.gpg | head -1)
echo "$LATEST"
```

Backups encrypt with `--symmetric` AES-256 against `/mnt/bulk/backups/.secrets/dump-passphrase`.
Same passphrase as `litellm-pgdump.sh` and `gitea-pgdump.sh`.

## Steps to run when the drill fires

```bash
# 1. Stop production Hermes — drill must not race in-flight writes.
ssh truenas_admin@192.168.1.65 'midclt call -j app.stop hermes'

# 2. Decrypt to a scratch path on the NAS.
sudo bash -c '
  TMP=/mnt/.ix-apps/app_mounts/hermes/_drill-restore
  rm -rf "$TMP"; mkdir -p "$TMP"
  gpg --batch --yes --decrypt \
    --passphrase-file /mnt/bulk/backups/.secrets/dump-passphrase \
    --output /tmp/drill.zip \
    '"$LATEST"'
  unzip -q /tmp/drill.zip -d "$TMP"
  chown -R 568:568 "$TMP"
  ls -la "$TMP" | head -10
  rm -f /tmp/drill.zip
'

# 3. Swap the bind-mount target. Do this via app.update (NOT by mucking
#    with symlinks under /mnt/.ix-apps — that path is TrueNAS-managed).
#    Take a copy of nas/hermes/app-config.json, change the data volume
#    source from /mnt/.ix-apps/app_mounts/hermes/data to the _drill-restore
#    path, then app.update hermes.

# 4. Start it back up
ssh truenas_admin@192.168.1.65 'midclt call -j app.start hermes'

# 5. Smoke
#    a) Dashboard: open https://hermes.mati-lab.online — sessions list should
#       show your real conversation history up to the dump time.
#    b) Telegram: send @HermesMatiBot a "ping" → coherent reply.
#    c) Vault search: ask "search vault for litellm" → cited answer.

# 6. After the drill: revert app-config.json to point back at the real
#    /mnt/.ix-apps/app_mounts/hermes/data, app.update hermes again, restart.

# 7. Clean up
sudo rm -rf /mnt/.ix-apps/app_mounts/hermes/_drill-restore
```

## Acceptance

- [ ] Decrypted zip extracts without errors and matches expected layout
      (state.db, config.yaml, .env, SOUL.md, sessions, memory).
- [ ] Hermes starts cleanly against the restored data dir (no crashloop in
      Loki `{container=~"ix-hermes-.*"}` for 5 min).
- [ ] Telegram round-trip works.
- [ ] Dashboard sessions list shows the conversations from before the dump.
- [ ] Production data dir is untouched — drill swaps via `app.update`,
      doesn't write to the real path.

## Why not just `hermes import`

Hermes ships `hermes import <zip>` for restoring its own dumps in-place.
But that's a one-way "merge into running Hermes" — risk of mixing drill
data into production sessions. The bind-mount swap above keeps the drill
fully out-of-band: production never sees the restored data.

## Related

- Backup script: `nas/backup-jobs/hermes-backup.sh`
- Cron: `id=16`, schedule `15 4 * * *` UTC
- Kuma monitor: `backup-hermes-dump`
- Recipe verified at install 2026-05-01: decrypt-roundtrip on
  `hermes-20260430T223713Z.zip.gpg` showed expected file list (state.db,
  config.yaml, .env, etc.).
