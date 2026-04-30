# Qdrant (NAS)

TrueNAS Scale Apps, **Custom App** (not in catalog). Installed 2026-04-30
as Phase 6's vector store. Holds embeddings of every Markdown note in the
Obsidian vault (`bulk/obsidian-vault`); Phase 6.2 will add a second
collection for code-repo embeddings.

## Endpoints

- **Direct (LAN, used by `rag-watcher`):**
  - REST: `http://192.168.1.65:30017` — root, `/collections`, `/healthz`, `/metrics`
  - gRPC: `192.168.1.65:30018`
- **Dashboard behind Authelia 2FA:** `https://qdrant.mati-lab.online/dashboard`
  → Caddy on Pi → `192.168.1.65:30017`. The watcher hits Qdrant directly on
  the LAN; Caddy is here only so the dashboard has a 2FA gate.

The dashboard is the one place you'll inspect collection state by hand
(point counts, payload schema, sample search). REST and gRPC ports are
identical for the on-host watcher.

## Collections

| Name | Vectors | Distance | Source | Notes |
|---|---|---|---|---|
| `obsidian-vault` | 768d (`nomic-embed-text` via LiteLLM `embeddings` alias) | Cosine | `rag-watcher` daemon walks `/mnt/bulk/obsidian-vault/` | Payload indexes on `path` (keyword), `tags` (keyword), `mtime` (integer). Indexes pre-created so first thousand upserts don't block on lazy indexing. |

Vector dim **768 is locked** until the collection is recreated — it was
chosen by the 2026-04-30 bake-off (recall@5=1.00 on a 5-query corpus
across `nomic-embed-text` 768d, `mxbai-embed-large` 1024d, `bge-m3` 1024d;
nomic won on latency and storage). Bake-off harness lives at
`compute/rag/eval/bakeoff.py` — re-run if/when the corpus changes
materially or recall feels weak. Switching models with a different output
dim means dropping and recreating the collection then re-embedding
everything via `make bulk-index` (see `nas/rag-watcher/notes.md`).

## Config on disk

| Path (NAS) | Content |
|---|---|
| `/mnt/fast/qdrant-data` | Vector segments + payloads + WAL. Owned by `apps:apps` (568:568); Qdrant container runs as that UID. Hourly + daily ZFS snapshots on `fast/qdrant-data` (see below). |

No `.env` here — Qdrant has no auth. Defense is "LAN-only port + Authelia
on the dashboard vhost." If we ever expose REST publicly, switch on the
Qdrant API key and put it in an `.env` like LiteLLM has.

## Install trace (reproducibility)

```bash
# 1. Make sure the dataset exists with correct chown
ssh truenas_admin@192.168.1.65 'midclt call -j filesystem.chown "{
  \"path\": \"/mnt/fast/qdrant-data\", \"uid\": 568, \"gid\": 568,
  \"options\": {\"recursive\": true}
}"'

# 2. Create the Custom App
cat > /tmp/qdrant-create.json <<'EOF'
{
  "app_name": "qdrant",
  "custom_app": true,
  "values": {"ix_context": {}},
  "custom_compose_config": {
    "services": {
      "qdrant": {
        "image": "qdrant/qdrant:v1.13.0",
        "restart": "unless-stopped",
        "environment": {
          "QDRANT__SERVICE__HTTP_PORT": "6333",
          "QDRANT__SERVICE__GRPC_PORT": "6334",
          "QDRANT__TELEMETRY_DISABLED": "true"
        },
        "ports": [
          {"mode": "host", "protocol": "tcp", "published": 30017, "target": 6333},
          {"mode": "host", "protocol": "tcp", "published": 30018, "target": 6334}
        ],
        "volumes": [
          {"type": "bind", "source": "/mnt/fast/qdrant-data", "target": "/qdrant/storage"}
        ]
      }
    }
  }
}
EOF
scp /tmp/qdrant-create.json truenas_admin@192.168.1.65:/tmp/
ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/qdrant-create.json)"'

# 3. Create the obsidian-vault collection at 768d Cosine
curl -sS -X PUT http://192.168.1.65:30017/collections/obsidian-vault \
  -H "Content-Type: application/json" \
  -d '{"vectors":{"size":768,"distance":"Cosine"},
       "optimizers_config":{"default_segment_number":2},
       "hnsw_config":{"m":16,"ef_construct":100}}'

# 4. Pre-create payload indexes
for spec in 'path:keyword' 'tags:keyword' 'mtime:integer'; do
  field="${spec%%:*}"; schema="${spec##*:}"
  curl -sS -X PUT "http://192.168.1.65:30017/collections/obsidian-vault/index" \
    -H "Content-Type: application/json" \
    -d "{\"field_name\":\"$field\",\"field_schema\":\"$schema\"}"
done
```

## Update / restart

| Action | Command |
|---|---|
| Restart in place | `ssh truenas_admin@192.168.1.65 'midclt call app.redeploy qdrant'` |
| Bump image tag | Edit the compose JSON above, `app.update qdrant '{"custom_compose_config": {...}}'` (see `feedback_truenas_app_update_replaces.md` — partial updates wipe siblings) |
| View collection state | Dashboard, or `curl -sS http://192.168.1.65:30017/collections/obsidian-vault` |
| Drop collection | `curl -sS -X DELETE http://192.168.1.65:30017/collections/obsidian-vault` (irreversible — re-create + `make bulk-index` on `compute/rag` to refill) |
| Stop / start | `midclt call app.stop qdrant` / `midclt call app.start qdrant` |
| Delete | `midclt call app.delete qdrant '{"remove_images":true}'` then `rm -rf /mnt/fast/qdrant-data/*` |

## Backup

`fast/qdrant-data` has a periodic snapshot task (created during Phase 6
closeout, mirrors the Phase 5 obsidian-couchdb pattern):

| Schedule | Retention | Naming |
|---|---|---|
| Hourly (`0 * * * *`) | 2 weeks | `auto-%Y-%m-%d_%H-%M` |
| Daily (`30 2 * * *`) | 90 days | `auto-daily-%Y-%m-%d_%H-%M` |

The dataset is small (current: ~180 chunks × 768 floats × 4 bytes ≈ 0.5 MB
of vectors plus payload + HNSW index; expect single-digit MB even after
embedding the whole homelab plus a few code repos). Snapshot cost is
negligible. Restore = stop the app, ZFS rollback `fast/qdrant-data`,
restart. Worst case: drop and re-bulk-index from the vault.

## Lessons

- **Qdrant point IDs must be unsigned int or UUID, not arbitrary strings.**
  An early version of the watcher used 40-char sha1 hex digests as point
  IDs and Qdrant rejected every upsert with HTTP 400. Fix: take the first
  16 bytes of the sha1 digest and format as a UUID string. Same
  determinism, valid ID. Caught only in deployment because tests used
  `MagicMock` for the qdrant client (mocks happily accept any string).
  Lesson: at least one integration test against a real Qdrant container
  for ID-shape contracts.

- **`midclt call app.redeploy` does NOT pull a new image when the tag is
  unchanged.** If you push a new `:latest` digest to Gitea registry and
  call `app.redeploy <name>`, the daemon will reuse the cached local
  image. Use
  `midclt call -j app.pull_images <name> '{"redeploy": true}'`
  to force a pull + restart. This bit twice during Phase 6 watcher
  deploy. The `app.outdated_docker_images` method also returns `[]` even
  when there's a newer digest on the registry — don't rely on it. (Same
  mechanism applies to the `litellm` and `qdrant` apps if they're ever
  on a moving tag; production should pin to a digest or a versioned tag,
  not `:latest`.)
