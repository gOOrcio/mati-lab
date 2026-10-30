# Vaultwarden restore drill

**Last run:** 2026-10-30 ✅ pass (install-day baseline)

## Goal

Prove the nightly `vaultwarden-backup.sh` pair restores: the gpg'd `pg_dump` replays
into a scratch Postgres, and the `/data` tar gives back `rsa_key.pem`. The vault
itself stays encrypted with the master password, so a restore without it is useless
by design. This drill checks the server side only.

## Steps run

Script: [`vaultwarden-restore.sh`](vaultwarden-restore.sh). It prints counts and file
names only. Run it as root through the temp-cron channel, because `truenas_admin`
can't read the passphrase:

```bash
scp nas/restore-drills/vaultwarden-restore.sh truenas_admin@192.168.1.65:.deploy/vaultwarden/drill.sh
ssh truenas_admin@192.168.1.65 'S=/home/truenas_admin/.deploy/vaultwarden
ID=$(midclt call cronjob.create "{\"user\":\"root\",\"command\":\"bash $S/drill.sh > $S/drill.out 2>&1; chown truenas_admin: $S/drill.out\",\"enabled\":false,\"schedule\":{\"minute\":\"0\",\"hour\":\"0\",\"dom\":\"1\",\"month\":\"1\",\"dow\":\"*\"}}" | jq .id)
midclt call -j cronjob.run "$ID" >/dev/null 2>&1; midclt call cronjob.delete "$ID" >/dev/null; cat $S/drill.out; rm -f $S/drill.*'
```

## Result (2026-10-30)

```
users      1
ciphers    0      # run before any items were migrated
folders    1
devices    3
twofactor  1
data files:
  rsa_key.pem 1679 bytes
```

About 6 s end to end (the `postgres:18.6-trixie` image is already on the NAS from the app).

## Production restore (not drilled)

1. `midclt call -j app.stop vaultwarden`.
2. Restore `/data`: decrypt the tar into `/mnt/fast/databases/vaultwarden/data` (568:568),
   or `zfs rollback` / clone a `fast/databases/vaultwarden` snapshot.
3. Start only the postgres container, or reinstall the app with the same `values.conf`
   for an empty DB, then pipe the decrypted dump into
   `docker exec -i ix-vaultwarden-postgres-1 psql -U vaultwarden -d vaultwarden`.
   The dump has `--clean --if-exists`, so it replaces the tables.
4. `midclt call -j app.start vaultwarden`, log in, and `bw sync` on clients.

Clients keep an offline copy of the vault, so a few hours of server downtime doesn't
lose access.

## Next run

Re-run once items are migrated (expect `ciphers` > 0), then yearly with the other drills.
