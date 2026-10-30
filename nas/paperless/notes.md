# Paperless-ngx (NAS)

TrueNAS Scale **catalogue app** `paperless-ngx` (train `community`), serving
`https://paperless.mati-lab.online` (LAN/VPN only, no Cloudflared route). It's the
household document archive: per-user ownership, Gmail ingestion, OCR in Polish and
English. Stirling PDF (`nas/stirling-pdf/`) is the editing desk.
Design: `docs/superpowers/specs/2026-10-30-paperless-ngx-design.md` (local only).

## Layout

Web port **30125**. Dataset `bulk/paperless` (568:568, mode 755), host paths:

| Host path | Container path | Contents |
|---|---|---|
| `/mnt/bulk/paperless/data` | `/paperless/data` | Index, classifier, logs |
| `/mnt/bulk/paperless/media` | `/paperless/media` | Originals + archive PDFs (readable tree by owner) |
| `/mnt/bulk/paperless/consume` | `/usr/src/paperless/consume` | Inbox; per-user subdirs `consume/<user>/`, Stirling returns in `consume/<user>/stirling/` |
| `/mnt/bulk/paperless/trash` | `/paperless/trash` | Deleted documents (trash enabled) |
| ixVolume | Postgres data | **Not** a host path (see below) |

**Postgres data is an ixVolume.** The catalogue's postgres upgrade init container
fails on an empty host-path pgdata (`postgres_upgrade init container exit 1`; see
`nas/gitea/notes.md` gotcha 2). The database is backed up by the nightly `pg_dump`
job, not by dataset snapshots.

The in-container consume path stays `/usr/src/paperless/consume`. Workflow triggers
match `filter_path` against it, e.g. `/usr/src/paperless/consume/gooral/*`.

## Deploy / update

`app-config.json` is committed with `__FROM_PM__<pm-label>` placeholders. Never
put values in it. Run from the dev PC:

```bash
nas/paperless/deploy.sh create   # first install
nas/paperless/deploy.sh update   # after editing app-config.json (sends the full values)
```

`deploy.sh` stages `app-config.json` + `apply.sh` in a private dir
(`~truenas_admin/.paperless-deploy/<mktemp>`, 0700) and runs `apply.sh` as root
via a one-shot disabled cron job. `apply.sh`:
- refuses to run if anything in the staging dir isn't owned by `truenas_admin` or is
  group/world-writable;
- substitutes values from `/mnt/fast/databases/paperless-apply/values.conf` (root
  0600, lines `<pm-label>=<value>`, **hex values only**, generated with
  `openssl rand -hex 32`);
- calls `app.create`/`app.update` through `truenas_api_client`, so secrets never
  appear in argv or `ps`;
- prints a redacted log (`apply.out`), and the staging dir is removed afterwards.

Values file keys (PM label = key; username in Vaultwarden in brackets):
`homelab/paperless/db-password` [paperless], `homelab/paperless/redis-password`
[—], `homelab/paperless/secret-key` [—], `homelab/paperless/admin-password` [admin],
`homelab/authelia/oidc-paperless-clientsecret` [paperless], and from Task 5
`homelab/paperless/gmail-oauth-client-secret`.

Gotchas:
- `additional_envs` entries need `"container": "paperless"` or create fails with
  `additional_envs.0.container: Field required`.
- Containers: `ix-paperless-ngx-{paperless,postgres,redis,tika,gotenberg}-1`.
- Check secrets survived an update (lengths only):
  `midclt call app.config paperless-ngx | jq '.paperless | {db:(.db_password|length), key:(.secret_key|length)}'`.
- OCR: `PAPERLESS_OCR_LANGUAGES=pol` installs Polish at start; `tesseract --list-langs`
  in the container shows `pol` (verified 2026-10-30).
