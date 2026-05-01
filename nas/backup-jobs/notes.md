# NAS backup jobs

Cron payloads for Phase 8. All scripts here are committed; the
TrueNAS-side state they need (passphrase + ntfy token + Kuma push URLs)
lives outside the repo per the secrets-inventory pattern.

## Layout

| Script | Schedule | Output | Dependents |
|---|---|---|---|
| `gitea-pgdump.sh` | nightly 03:15 UTC | `/mnt/bulk/backups/gitea-pgdump/gitea-<ISO>.sql.gz.gpg` | Gitea Postgres sidecar |
| `litellm-pgdump.sh` | nightly 03:30 UTC | `/mnt/bulk/backups/litellm-pgdump/litellm-<ISO>.sql.gz.gpg` | LiteLLM Postgres sidecar (Phase 7) |
| `hermes-backup.sh` | nightly 04:15 UTC | `/mnt/bulk/backups/hermes/hermes-<ISO>.zip.gpg` | Hermes Agent Custom App (logical backup via `hermes backup` inside the container, encrypted on the host) |
| `arr-config-backup.sh` | weekly Sun 04:15 UTC | `/mnt/bulk/backups/arr/arr-<ISO>.tar.gz.gpg` | Prowlarr/Sonarr/Radarr/Bazarr config dirs (SQLite + XML/YAML). 8-week retention. Cron id 17 (registered disabled until script staged + Kuma URL added — see "Required NAS-side state" row). |
| `zfs-health-cron.sh` | daily 00:07 UTC | (no file — direct ntfy on non-OK) | `zpool`, `midclt`, ntfy |
| `stage-passphrase.sh` | one-shot, run from dev box | NAS `/mnt/bulk/backups/.secrets/dump-passphrase` | password manager |

## Required NAS-side state

| Path | Owner | Mode | Content |
|---|---|---|---|
| `/mnt/bulk/backups/.secrets/dump-passphrase` | `root:root` | `600` | Symmetric gpg passphrase. Loss = unrecoverable backups. PM label `homelab/backups/dump-passphrase`. Stage via `bash nas/backup-jobs/stage-passphrase.sh`. |
| `/mnt/bulk/backups/.secrets/ntfy-token` | `root:root` | `600` | ntfy bearer token for the `homelab-alerts` topic. PM label `homelab/ntfy/homelab-alerts`. Optional — script falls back to anonymous post if missing. |
| `/root/.backup-env` | `root:root` | `600` | sourced by every cron; defines `KUMA_URL_GITEA_DUMP`, `KUMA_URL_LITELLM_DUMP`, `KUMA_URL_HERMES_DUMP`, `KUMA_URL_ARR_CONFIG`, `KUMA_URL_ZFS_HEALTH`, optionally `NTFY_URL`. PM label per push monitor: `homelab/uptime-kuma/push-<name>`. |

## Encryption posture

`gpg --symmetric --cipher-algo AES256` per file. The dump destination
datasets themselves are NOT ZFS-native-encrypted — see
`nas/snapshots.md` "Encryption-at-rest posture". gpg-symmetric covers
the disk-level read threat (anyone reading the .sql.gz.gpg sees
ciphertext). The threat ZFS-native would *additionally* cover —
metadata leakage at the dataset level, key-rotation without re-write —
isn't worth the complexity at our scale.

## Scheduling

All three crons are TrueNAS `cronjob` entries (created via
`midclt call cronjob.create`), running as `root`. Times chosen to
stagger:

```
00:07  zfs-health-cron.sh
03:15  gitea-pgdump.sh
03:30  litellm-pgdump.sh
04:15  hermes-backup.sh
```

ZFS snapshots run hourly at minute 0; daily at 02:30. Dumps are
intentionally AFTER the daily snapshot window so a daily snapshot
captures the prior day's dump alongside the live data.

## Running on demand

```bash
ssh truenas_admin@192.168.1.65 'sudo /root/gitea-pgdump.sh'
```

(Won't work — `truenas_admin` has no sudo. Run via the TrueNAS UI cron
"Run Now" button, or via `midclt call cronjob.run <id>`.)

## Decrypt-roundtrip verify

The Q1 restore drill (`nas/restore-drills/q1-postgres.md`) walks the
full path: pick a dump, decrypt, restore into a scratch container,
query a known row. Run quarterly per `nas/restore-drills/README.md`.

Quick sanity (read-only — doesn't touch a real DB):

```bash
ssh truenas_admin@192.168.1.65 '
  cd /tmp
  cp /mnt/bulk/backups/litellm-pgdump/litellm-*.sql.gz.gpg ./test.gpg
  gpg --batch --yes --decrypt --passphrase-file /mnt/bulk/backups/.secrets/dump-passphrase ./test.gpg \
    | gunzip | head -20
  rm -f ./test.gpg
'
```

(`truenas_admin` cant read the passphrase file — run from TrueNAS UI Shell as root, or via a midclt-driven one-shot.)

## Lessons

- **Kuma push URLs land with a `?status=up&msg=OK&ping=` query string** in the example shown in the Kuma UI's "How to use Push monitor" panel. **Don't paste that suffix.** When dropped into the env file, bash reads `&` as a background-job separator and `?` as a glob, silently emptying the variable. The cron scripts append their own `?status=up&msg=ok` — you only need the base path. `stage-kuma-urls.sh` strips the query suffix and quotes the values defensively.
- **Always validate by sourcing in a real shell before relying on the env file.** A one-shot midclt cron with `bash -c '. /file; echo URL_LEN=${#KEY}'` catches this in seconds; absence of the heartbeat in Kuma is a 5-min-grace-window away from being noticed.
- **truenas_admin can't read root-owned files** even at 644. Every "what's actually in this file" check has to go through a midclt-driven cron (which runs as root) or the chmod-write-revert dance.
