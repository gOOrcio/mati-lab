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
