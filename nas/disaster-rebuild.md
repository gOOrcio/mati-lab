# Disaster rebuild runbook

The honest doc. If the NAS is gone — fire, theft, dual-disk death,
ransomware that touches the array, accidental `zpool destroy`, etc. —
this is the sequence to come back up.

**Per the Phase-8 scope decision: there is no off-box copy.** Anything
not separately versioned (the `mati-lab` repo, GitHub-mirrored personal
repos, password manager) is **lost**. Don't pretend otherwise; the rest
of this document is honest about what survives and what doesn't.

## What survives (because it lives somewhere else)

| Asset | Where it survives | How it survives |
|---|---|---|
| `mati-lab` repo (this repo) | Gitea on NAS — *gone* if NAS is gone. **Fallback: GitHub push-mirror** at `github.com/<your-mirror>/mati-lab`. | Phase-4 mirror config |
| Personal repos (sentinel-trader, smart-resume, restorate, dietly-scraper, madrale, etc.) | GitHub mirrors per-repo | Phase-4 mirror config; `~/.git-mirrors-status` on dev box has the inventory |
| All long-lived secrets | Password manager | `nas/secrets-inventory.md` is the index — every PM label is `homelab/<service>/<role>` |
| Phase docs + plans | `docs/superpowers/plans/*.md` are gitignored — local on dev box only | Dev box is a separate machine; survives unless it dies too |
| Master plan (`docs/design/homelab-master-plan.md`) | Gitignored, dev-box-local | Same — separate machine |
| Memory entries | `~/.claude/projects/-home-gooral-Projects-mati-lab/memory/*.md` on dev box | Separate machine |

If the dev box dies in the same incident (apartment fire), your last
hope is: GitHub-mirrored repos + password manager (cloud-replicated).
Memory + master plan + plan docs would be lost. That's an accepted
gap; documenting it forces you to consider whether to push more of
that to GitHub later.

## What's gone forever

| Asset | What's lost |
|---|---|
| Obsidian vault content | All notes since the last surviving Mac-client local copy. If your Mac is healthy, the vault IS on the Mac (LiveSync mirrors both ways). If both NAS and Mac are gone, vault is gone. |
| Immich photos | All photos. Hopefully also on phone(s) and a separate cloud (your call to make). |
| Jellyfin media | All media. Re-acquire from sources. |
| qBittorrent downloads in flight | Whatever was downloading. Re-add the .torrent. |
| vzdump archives | Last surviving VM snapshots. Phases 1–7 can rebuild VMs from Ansible/scratch; you lose VM state since whenever they were last redeployed from the playbooks. |
| OpenClaw pairing tokens / device approvals | Re-pair every device after rebuild. |
| Authelia user sessions, TOTP enrolments | Re-enrol TOTP on every account; existing browser sessions fail closed. |
| Gitea contents | Everything in Gitea. Push-mirrored repos restore from GitHub; non-mirrored content (issues, PRs, releases) is gone. |
| Qdrant vectors | Rebuildable from vault content via `make bulk-index` once vault is back. |

## Rebuild order (Phases 1 → 8)

Each phase has its own plan file (`docs/superpowers/plans/...`) and
operational notes (`nas/<service>/notes.md`, `compute/<thing>/notes.md`,
`network/<thing>/notes.md`). Follow them in original implementation
order; don't try to parallelise across phases.

### Pre-rebuild — recover the source of truth

```bash
# 1. Clone mati-lab from GitHub mirror
git clone git@github.com:<your-mirror>/mati-lab.git ~/Projects/mati-lab

# 2. Verify the secrets inventory exists
cat ~/Projects/mati-lab/nas/secrets-inventory.md   # confirms PM labels

# 3. Confirm password manager access — every secret in the inventory is
#    needed during rebuild. If PM is also gone, **stop and rotate every
#    upstream credential before continuing** (Cloudflare, providers,
#    GitHub, etc).
```

### Phase 1 — TrueNAS foundation

- Provision new NAS hardware (or reinstall TrueNAS Scale on existing).
- Recreate datasets per `docs/superpowers/plans/<phase-1>...md` and
  `nas/snapshots.md`.
- **Apply ZFS-native encryption from creation time** for every row
  marked `encrypt-on-rebuild` in the audit table. This is the moment
  you've been deferring; do it now.
- Restore Pi rsync target dataset (`bulk/backups/network-pi`) — if
  the new NAS is genuinely from-scratch, this starts empty and Pi
  rsyncs fresh.

### Phase 2 — Media + photo stack

- Redeploy via NAS catalog apps + the per-app notes.
- **Jellyfin / qBittorrent: re-acquire content.** No backup of media.
- Immich: deferred per the original plan; nothing to restore.

### Phase 2.r — *arr automation (Sonarr / Radarr / Prowlarr / Bazarr)

- Pre-req: `bulk/data` dataset exists (single dataset replacing the old
  `bulk/downloads` + `bulk/media` split — see `nas/snapshots.md`).
  Subdirs `torrents/{complete,incomplete}` and `media/{movies,tv,anime}`
  all owned `568:568` mode `0775`.
- Re-create the four Custom Apps from the committed payloads:
  ```bash
  for app in prowlarr sonarr radarr bazarr; do
    scp nas/$app/app-config.json truenas_admin@nas:/tmp/$app-app-config.json
    ssh truenas_admin@nas "midclt call -j app.create \"\$(cat /tmp/$app-app-config.json)\""
  done
  ```
- Restore latest config archive:
  ```bash
  ssh truenas_admin@nas \
    'gpg -d --passphrase-file /mnt/bulk/backups/.secrets/dump-passphrase \
       /mnt/bulk/backups/arr/arr-<latest>.tar.gz.gpg \
     | tar -C /mnt/fast/databases -xzf -'
  ```
  Then restart each app: `midclt call -j app.stop <app>` + `app.start <app>`.
- API keys persist inside the SQLite DB (Sonarr/Radarr/Prowlarr) and
  `config.yaml` (Bazarr). Prowlarr's `Apps → Sonarr/Radarr` entries also
  persist. After restore, smoke-test by hitting each app's
  `/api/.../system/status` with the `X-Api-Key` from PM.
- Re-add Caddy vhosts (`network/caddy/Caddyfile` `@prowlarr` / `@sonarr`
  / `@radarr` / `@bazarr` blocks) and force-recreate Caddy.
- Indexers in Prowlarr come back from the restored DB; private trackers
  may need session-cookie refresh per `nas/prowlarr/notes.md`.
- **Media library data:** under `bulk/data/media/{movies,tv,anime}` —
  same accepted-risk bucket as the old `bulk/media` (no off-box backup,
  followup 8.1).

### Phase 3 — LLM stack (LiteLLM + OpenClaw + Hermes)

- Deploy LiteLLM Custom App per `nas/litellm/notes.md` install trace.
- Bring up the Postgres sidecar before LiteLLM (depends_on healthcheck
  enforces this).
- **Restore from `bulk/backups/litellm-pgdump/litellm-*.sql.gz.gpg`**
  IF the bulk pool is recoverable (this whole document is about the
  case where it isn't). If not, **re-issue all virtual keys** via
  `bash nas/litellm/issue-keys.sh` and update each consumer:
  - `rag-watcher` `.env` — `bash nas/litellm/swap-consumer-key.sh rag-watcher`
  - `openclaw` — in-app config wizard
  - `dev-pc-tools` — `claude mcp add vault-rag …` on dev box
- LiteLLM SSO env vars: `GENERIC_*` from the install — see
  `nas/litellm/notes.md` "Admin UI SSO".
- Authelia OIDC client `litellm` — config in `network/authelia/configuration.yml`.
- Provider API keys (DeepSeek, Anthropic) — from PM.

### Phase 4 — Gitea + CI/CD

- Deploy Gitea catalog app per `nas/gitea/notes.md`.
- **Restore from `bulk/backups/gitea-pgdump/gitea-*.sql.gz.gpg`** IF
  the bulk pool survived. If not, **re-clone every personal repo from
  GitHub mirrors** + push to the new Gitea. Issues, PRs, releases not
  in the mirror are gone.
- Re-create Gitea PATs per `nas/secrets-inventory.md` Gitea row.
- Authelia OIDC client `gitea` — same shape as LiteLLM's.

### Phase 5 — Obsidian self-hosted sync

- Deploy `obsidian-couchdb` Custom App.
- **The vault content lives on the Mac client.** If the Mac is healthy,
  the LiveSync plugin will push back to the rebuilt CouchDB once you
  re-issue the `livesync` user creds. If the Mac is also gone, the
  vault is lost.
- Syncthing on Mac → NAS for the plain-file mirror.

### Phase 6 — RAG pipeline

- Deploy Qdrant Custom App + create the `obsidian-vault` collection
  at 768d Cosine.
- Deploy `rag-watcher` Custom App.
- `make bulk-index` from `compute/rag/` to refill Qdrant from the
  restored vault.
- Re-register the MCP server on dev box: `claude mcp add vault-rag …`.

### Phase 7 — Hardening (re-apply)

- Promtail on NAS (Custom App).
- Authelia OIDC clients for Proxmox + Gitea + LiteLLM.
- Proxmox `username-claim preferred_username` in `/etc/pve/domains.cfg`
  (if Proxmox is also being rebuilt — see `compute/proxmox_host/notes.md`).
- vzdump destination = NAS NFS again (Phase 7 setup applies).
- LiteLLM virtual keys re-issued per Phase 3 above.

### Phase 8 — Backups (re-apply this document's own setup)

- Re-stage backup encryption passphrase via `bash nas/backup-jobs/stage-passphrase.sh`.
- Re-deploy the three backup crons via `midclt cronjob.create`.
- Recreate the snapshot tasks per `nas/snapshots.md`.
- Recreate the Kuma push monitors via UI.
- Run the Q1 drill again to prove the new install works end-to-end.

## Exit criteria

You are rebuilt when all of the below pass:

```bash
# Network plane
curl -sS https://authelia.mati-lab.online/api/health | grep OK
curl -sS http://192.168.1.65:4000/health/liveliness | grep alive
curl -sS http://192.168.1.65:30017/healthz | grep passed
curl -sS http://192.168.1.65:30009/api/v1/version | grep version

# RAG end-to-end (in a Claude Code session)
# "search my obsidian vault for X" → returns hits

# Backup baseline restored
ls /mnt/bulk/backups/litellm-pgdump/ /mnt/bulk/backups/gitea-pgdump/

# Alerting works
# (Trigger a deliberate condition — e.g. add a fake-down scrape target —
# and confirm an ntfy lands on phone within 5min.)
```

## When this runbook gets stale

The rebuild order assumes the phase plans + service notes are still
accurate. Sweep this doc whenever:
- A new phase ships (add a Phase N section)
- A service moves between phases or gets deleted
- The "what survives" list changes (e.g. adding off-box backup later
  flips the "what's gone forever" rows to "recoverable from X")

Last sweep: 2026-04-30 (Phase 8 install).
