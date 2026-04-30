# rag-watcher (NAS)

TrueNAS Scale Apps, **Custom App** (not in catalog). Installed 2026-04-30
as Phase 6's Obsidian-vault → Qdrant indexer. Headless background daemon;
no UI, no exposed ports.

The image is built on the dev box, pushed to the Gitea private registry,
and pulled by TrueNAS. Source lives at `compute/rag/` in this repo.

## What it does

1. On startup, runs **reconcile**: walks `/mnt/bulk/obsidian-vault/`,
   asks Qdrant for the `mtime` payload of every known point (paginated
   `scroll`), and re-embeds any file with `disk_mtime > stored_mtime`.
   Deletes points whose `path` payload no longer exists on disk.
2. Then enters **live watch** via `watchdog.Observer` recursively over
   `/vault`. File-change events feed a per-path debouncer (5s default);
   the last touch within the window triggers `chunk → embed → upsert`.
   `on_deleted` triggers `delete_by_path`.
3. Skips `.obsidian/`, `.trash/`, `.stversions/`, `.stfolder/`, and
   `*.sync-conflict-*` files (Syncthing's unresolved-conflict copies).

Per-file failures during reconcile or live events are caught + logged;
they don't take the watcher down.

## Endpoints

None. Background daemon. Inspect via:
- Container logs: TrueNAS UI → Apps → rag-watcher → Logs (live tail only;
  once the container exits, history is gone — see Loki gap below)
- Indirectly via Qdrant: `curl -sS http://192.168.1.65:30017/collections/obsidian-vault`

## Config on disk

| Path (NAS) | Content | Source of truth |
|---|---|---|
| `/mnt/fast/databases/rag-watcher/.env` | `LITELLM_API_KEY` (= LiteLLM master key) | Only on NAS. Never committed; password-manager-backed |
| (compose env in `app.create` JSON) | `VAULT_PATH=/vault`, `QDRANT_URL=http://192.168.1.65:30017`, `QDRANT_COLLECTION=obsidian-vault`, `LITELLM_BASE_URL=http://192.168.1.65:4000`, `DEBOUNCE_SECONDS=5`, `EMBED_BATCH=16` | `compute/rag/deploy/rag-watcher-create.json` in this repo |

The vault is bind-mounted **read-only** at `/vault`. Watcher should never
write to the vault — it only reads files and writes to Qdrant.

## Install trace (reproducibility)

```bash
# 1. Stage the env file on the NAS (LITELLM_API_KEY from password manager)
ssh truenas_admin@192.168.1.65 'mkdir -p /mnt/fast/databases/rag-watcher && chmod 700 /mnt/fast/databases/rag-watcher'
# Then create /mnt/fast/databases/rag-watcher/.env containing:
#   LITELLM_API_KEY=<paste from password manager>
# chmod 600 /mnt/fast/databases/rag-watcher/.env

# 2. Build + push the image
cd ~/Projects/mati-lab/compute/rag
make push     # = docker buildx --platform linux/amd64 + docker push

# 3. Create the Custom App (deploy JSON committed at deploy/rag-watcher-create.json)
make deploy   # = scp deploy JSON + midclt app.create

# 4. Verify
ssh truenas_admin@192.168.1.65 'midclt call app.query' | python3 -c '
import sys,json
for a in json.load(sys.stdin):
    if a["name"] == "rag-watcher":
        print(a["state"])'
# expect: RUNNING
```

## Update / restart

| Action | Command |
|---|---|
| Build + push new image | `cd compute/rag && make push` |
| Force pull + redeploy | `ssh truenas_admin@192.168.1.65 'midclt call -j app.pull_images rag-watcher "{\"redeploy\": true}"'` (see Lessons — `app.redeploy` alone reuses the cached image when the tag is `:latest`) |
| Plain restart (no image change) | `make redeploy` |
| Force a full re-embed | `cd compute/rag && make bulk-index` (sequential, ~30s for ~50 small notes; bigger vaults will want a `--workers N` flag — not yet implemented) |
| Skip reconcile on startup | Set `SKIP_RECONCILE=1` in compose env, redeploy. Live watch still runs. Useful for debugging a poisoned point in Qdrant. |
| Bump LiteLLM key | Edit `/mnt/fast/databases/rag-watcher/.env`, `midclt call app.redeploy rag-watcher` |

## How a re-index works

`bulk_index.py` walks the vault and force-re-embeds every note regardless
of `mtime`. Points are upsert-by-id (chunk_id is a deterministic UUID
derived from `path::heading_path::sub_idx`), so re-indexing is idempotent
when chunk structure is unchanged. If headings change, stale chunk IDs
linger — but `_process` always `delete_by_path` first, so on a
file-by-file basis the watcher self-prunes.

When to bulk re-index:
- Switching embedding model (= different vector dim → recreate the
  Qdrant collection first; `bulk-index` then refills)
- Changing chunker behaviour (heading parse rules, max_chars, overlap)
- Suspect-corruption recovery
- Schema migration of payload fields

## Backup

No persistent state lives in the watcher container — it's a pure consumer
of the vault and producer of Qdrant points. Backup = backup the vault
(`bulk/obsidian-vault`, Phase 5) + Qdrant (`fast/qdrant-data`,
[`../qdrant/notes.md`](../qdrant/notes.md)). Worst-case rebuild: drop the
collection, recreate, `make bulk-index`.

## Lessons

- **Loki doesn't see NAS containers.** Promtail is only running on the
  Pi, scraping the Pi's `/var/lib/docker`. So once the watcher container
  exits, container logs vanish from the TrueNAS UI and there's no Loki
  history to grep through. Two consequences during Phase 6:
  - Always wrap startup paths in try/except so a fatal error logs a
    full traceback before exit, not just a non-zero exit code.
  - Phase 6.x or a later phase should add Promtail to the NAS so all
    Custom App containers ship to Loki.

- **A single bad file shouldn't kill reconcile.** Initial implementation
  had reconcile crash on the first failing `_process` call (KeyError,
  Qdrant 4xx, embedder 5xx, oversize chunk, bad encoding). With
  `restart: unless-stopped` this respawned into the same crash loop.
  Now per-file failures are caught + counted; reconcile continues to the
  next file and the live watcher starts regardless. Operator sees
  `failed=N` in the summary line.

- **Image bind-mount + `:latest` tag = stale image after redeploy.** See
  the Lessons section in [`../qdrant/notes.md`](../qdrant/notes.md). Use
  `app.pull_images` not `app.redeploy` when you've pushed a new digest.

- **Qdrant point IDs must be UUID or unsigned int.** Sha1 hex digests
  are rejected. Watcher uses `uuid.UUID(bytes=sha1_digest[:16])` for a
  deterministic-but-valid ID. See [`../qdrant/notes.md`](../qdrant/notes.md).
