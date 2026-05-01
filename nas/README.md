# NAS-side state (AOOSTAR / TrueNAS Scale 25.10 Goldeye)

The NAS lives at `192.168.1.65` (`nas.mati-lab.online`). It runs TrueNAS
Scale and hosts apps via the official catalog. Unlike `compute/` and
`network/` in this repo, NAS apps are **not** managed by Ansible or Docker
Compose — TrueNAS owns the container lifecycle. This directory holds
operational notes per app: what was deployed, where data lives, and where
backups end up.

## Apps deployed (Phase 2)

| App | URL | Data location | Notes |
|---|---|---|---|
| Jellyfin | `jellyfin.mati-lab.online` | `bulk/data/media` | AMD VAAPI hardware transcoding (currently STOPPED — start when needed) |
| qBittorrent | `qbit.mati-lab.online` (LAN + Authelia) | `bulk/data/torrents` | see [qbittorrent/notes.md](qbittorrent/notes.md) |
| Prowlarr | `prowlarr.mati-lab.online` (LAN + Authelia 2FA) | `fast/databases/prowlarr/config` | Indexer aggregator; syncs into Sonarr + Radarr. See [prowlarr/notes.md](prowlarr/notes.md) |
| Sonarr | `sonarr.mati-lab.online` (LAN + Authelia 2FA) | `fast/databases/sonarr/config` | TV + anime; hardlink imports onto `bulk/data/media/{tv,anime}`. See [sonarr/notes.md](sonarr/notes.md) |
| Radarr | `radarr.mati-lab.online` (LAN + Authelia 2FA) | `fast/databases/radarr/config` | Movies; hardlink imports onto `bulk/data/media/movies`. See [radarr/notes.md](radarr/notes.md) |
| Bazarr | `bazarr.mati-lab.online` (LAN + Authelia 2FA) | `fast/databases/bazarr/config` | Subtitles for Sonarr + Radarr libraries. See [bazarr/notes.md](bazarr/notes.md) |
| Immich | deferred | `bulk/photos` + `fast/databases/immich-pgdata` | blocked on `pgvecto_upgrade`; Task 3 of Phase 2 plan |
| obsidian-couchdb | `obsidian.mati-lab.online` (LAN/VPN) | `bulk/obsidian-couchdb` + plain-file mirror at `bulk/obsidian-vault` | Phase 5; see [obsidian/notes.md](obsidian/notes.md) |
| qdrant | `qdrant.mati-lab.online` (LAN/VPN, Authelia) | `fast/qdrant-data` | Phase 6; vector store for RAG. See [qdrant/notes.md](qdrant/notes.md) |
| rag-watcher | (background daemon) | `/mnt/fast/databases/rag-watcher/.env` | Phase 6; tails `bulk/obsidian-vault`, embeds via LiteLLM, upserts to Qdrant. See [rag-watcher/notes.md](rag-watcher/notes.md) |
| promtail | (background daemon) | `/mnt/fast/databases/promtail/` | Phase 7; ships every NAS container's logs to Loki on Pi (`192.168.1.252:3100`). See [promtail/notes.md](promtail/notes.md) |
| litellm-postgres | (sidecar to litellm; not exposed) | `/mnt/fast/databases/litellm-pgdata` | Phase 7; backs LiteLLM's virtual-keys store. See [litellm/notes.md](litellm/notes.md) "Architecture" |

Future phases will add: LiteLLM, OpenClaw, Gitea, CouchDB, file watcher
for code repos (Phase 6.2).

## Supporting pieces wired up in Phase 2

- **Caddy + Authelia** on the Pi front every NAS service at `*.mati-lab.online`.
  Jellyfin routes unauth'd (own login); qBittorrent sits behind Authelia 2FA
  with LAN-only reach.
- **Uptime Kuma** monitors `jellyfin` and `qbittorrent` (ntfy push on
  failure). Inventory in [network/uptime-kuma/monitors.md](../network/uptime-kuma/monitors.md).
- **ZFS snapshots** on `bulk/photos` (hourly+daily) and `bulk/data` (daily, 14d).
  Full policy in [snapshots.md](snapshots.md). `bulk/downloads` intentionally
  unprotected.
- **Prometheus + Grafana** pulling NAS metrics through a
  Netdata-Graphite-to-Prometheus bridge. Dashboard + pipeline in
  [monitoring.md](monitoring.md). Dashboard UID `truenas-nas-overview`.

## Backups

Snapshot tasks for Phase 2 datasets are configured (local rollback, same pool
— not disaster-proof). Logical backups (`pg_dump` for Postgres),
off-box replication (ZFS `send | receive`), and restore drills land in
**Phase 8**. Until then, assume: `bulk/photos` is safe against
human mistakes for 2 weeks hourly + 90 days daily; media is convenience-only;
downloads are throwaway; disaster scenarios (fire/theft/double-disk-death)
are not covered yet.

## Restore drill

Empty until Phase 8D. When drills run, procedures get documented per service
in the relevant `nas/<service>/notes.md`.

## File map

- `README.md` — this file (index + phase state)
- `snapshots.md` — ZFS snapshot policy, UI restore paths, manual operations
- `monitoring.md` — TrueNAS → Graphite → Prometheus → Grafana pipeline
- `qbittorrent/notes.md` — qBit install, storage mapping gotcha, privacy
  toggles, credential model
- `jellyfin/notes.md` — (to add when deeper notes are needed; see
  [docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md](../docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md)
  Task 2 for the install context)
