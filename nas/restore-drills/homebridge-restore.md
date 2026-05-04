# Homebridge — restore drill

**Status:** pending — recipe verified at install (decrypt + tar list shows
expected payload), full restore-into-fresh-Pi-4 not yet exercised.

## Goal

Take a real Homebridge dump from `bulk/backups/homebridge/`, decrypt it,
upload it through a fresh (or scratch) Homebridge UI's Restore Backup
flow, confirm: (a) plugins re-install, (b) accessories repopulate from
`persist/`, (c) HomeKit pairings come back without re-pairing on the
phone (HomeKit identity lives inside the backup).

## Source

```bash
LATEST=$(ls -t /mnt/bulk/backups/homebridge/homebridge-*.tar.gz.gpg | head -1)
echo "$LATEST"
```

Same passphrase as every other dump (`/mnt/bulk/backups/.secrets/dump-passphrase`).

## Steps to run when the drill fires

```bash
# 1. Decrypt to a scratch path on the dev box (NAS doesn't need to
#    handle this — the .tar.gz goes into a browser upload).
gpg --batch --yes --decrypt \
    --passphrase-file /path/to/dump-passphrase \
    --output ~/Downloads/homebridge-restore.tar.gz \
    /mnt/bulk/backups/homebridge/homebridge-<ISO>.tar.gz.gpg

# 2. List to sanity-check payload
tar -tzf ~/Downloads/homebridge-restore.tar.gz | head -20
# Expect: config.json, auth.json, accessories/, persist/, package.json,
#         storage-path-X/...

# 3. Open https://homebridge.mati-lab.online (or http://192.168.1.155:8581)
#    → Settings → Backup → Restore Backup → choose
#    ~/Downloads/homebridge-restore.tar.gz → confirm.

# 4. Homebridge UI auto-restarts the bridge process. Watch the logs
#    panel for "Bridge is running on port ...".

# 5. Smoke
#    a) UI Status panel: bridge is "Running", plugin count matches expectation.
#    b) iPhone Home app: existing accessories online, no "No Response".
#    c) HomeKit pairing intact (no re-pair prompt).
```

## Acceptance

- [ ] Decrypted tar.gz extracts cleanly with no errors.
- [ ] Restore-Backup flow completes without UI errors.
- [ ] Bridge restarts and stays up (no restart loop in UI logs panel).
- [ ] Accessories from `persist/` come back online in iOS Home app.
- [ ] No HomeKit re-pair required.

## When the Pi 4 is genuinely gone

Fresh Pi 4 + fresh Homebridge OS image install → on first boot, walk
the setup wizard with **a placeholder admin password**, log in, then
Settings → Backup → Restore Backup → upload the `.tar.gz`. The restore
overwrites `auth.json` with the original users, so log out and log in
again with the *original* admin credentials from PM.

## Related

- Backup script: `nas/backup-jobs/homebridge-backup.sh`
- Cron: id `21`, schedule `45 4 * * 0` UTC
- Kuma monitor: `backup-homebridge-dump` (push, weekly heartbeat)
- Required env on NAS: `HOMEBRIDGE_USERNAME`, `HOMEBRIDGE_PASSWORD`,
  `KUMA_URL_HOMEBRIDGE` in `/root/.backup-env`.
