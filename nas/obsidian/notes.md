# Obsidian self-hosted sync (NAS)

TrueNAS Scale Apps, **Custom App** (no official catalog entry for
CouchDB). Installed as part of Phase 5 to replace the paid Obsidian Sync
subscription. Sync transport is the `obsidian-livesync` community plugin
talking to a local CouchDB; plain-markdown vault is mirrored to NAS via
Syncthing for Phase 6 (RAG) consumption.

## Endpoints

- **LiveSync API (LAN + VPN, behind Caddy):** `https://obsidian.mati-lab.online`
- **LiveSync API (direct LAN):** `http://192.168.1.65:30015`
- **No Cloudflared route on purpose.** Sync only needs to work on home
  network + WireGuard VPN; iOS goes over VPN when off-LAN. Removes the
  attack surface of a public CouchDB endpoint.

## Auth model

- **CouchDB admin** (`admin`): rare use — only for config changes via
  `/_node/_local/_config`. Password in password manager.
- **CouchDB user** (`livesync`): daily use; what the obsidian-livesync
  plugin connects with on every device. Password in password manager.
- **NO Authelia forward_auth** on the Caddy vhost — same trap as Gitea.
  forward_auth would intercept the LiveSync plugin's HTTP basic auth
  and break sync entirely. Caddy `@obsidian` block in
  `network/caddy/Caddyfile` mirrors the `@gitea` no-forward_auth pattern.

## App config (TrueNAS Custom App form values — for install reference)

| Field | Value |
|---|---|
| Application Name | `obsidian-couchdb` |
| Image | `couchdb:3.5` (or latest 3.x at install time) |
| Container Port | `5984` (CouchDB default) |
| Host Port | `30015` |
| Env: `COUCHDB_USER` | `admin` |
| Env: `COUCHDB_PASSWORD` | (generated; password manager) |
| Storage (data) | host path `/mnt/bulk/obsidian-couchdb` → `/opt/couchdb/data` |
| Storage (etc) | host path `/mnt/bulk/obsidian-couchdb/etc` → `/opt/couchdb/etc/local.d` |
| User/Group | container handles internally; host path chowned to `568:568` (apps) |

The `bulk/obsidian-couchdb` dataset (Phase 1) is mounted at
`/mnt/bulk/obsidian-couchdb`; chowned `apps:apps` on Phase 5 Task 1.

## CouchDB config applied (Task 3)

The obsidian-livesync **wizard inside Obsidian** (Settings → Self-hosted
LiveSync → Setup wizard) configures these automatically. If you ever
need to set them by hand:

```bash
ADMIN=admin; PASS='<password>'; URL=http://192.168.1.65:30015
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/httpd/enable_cors" -d '"true"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/cors/origins" -d '"app://obsidian.md,capacitor://localhost,http://localhost"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/cors/credentials" -d '"true"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/cors/methods" -d '"GET, PUT, POST, HEAD, DELETE"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/cors/headers" -d '"accept, authorization, content-type, origin, referer"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/chttpd/require_valid_user" -d '"true"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/chttpd_auth/require_valid_user" -d '"true"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/couchdb/max_document_size" -d '"50000000"'
curl -X PUT -u "$ADMIN:$PASS" "$URL/_node/_local/_config/chttpd/max_http_request_size" -d '"4294967296"'
```

Plus the per-vault setup:

```bash
# non-admin user the plugin authenticates as
curl -X PUT -u "$ADMIN:$PASS" "$URL/_users/org.couchdb.user:livesync" \
  -H "Content-Type: application/json" \
  -d '{"name":"livesync","password":"<separate-password>","roles":[],"type":"user"}'
# vault database + ACL
curl -X PUT -u "$ADMIN:$PASS" "$URL/obsidian-vault"
curl -X PUT -u "$ADMIN:$PASS" "$URL/obsidian-vault/_security" \
  -H "Content-Type: application/json" \
  -d '{"admins":{"names":["admin"]},"members":{"names":["livesync"]}}'
```

## Setup URI

`obsidian-livesync` plugin generates a single `obsidian://setuplivesync?...`
URI that encodes server + creds + sync options. Stored in the password
manager (do NOT paste here — contains creds).

To re-issue: Mac Obsidian → Settings → Self-hosted LiveSync → "Copy
current settings to setup URI" → save in password manager → open URI on
target device.

## Plain-file vault copy (consumed by Phase 6 RAG)

- **Canonical store:** Mac at `~/Documents/Obsidian/<vault-name>`.
- **NAS mirror:** `/mnt/bulk/obsidian-vault/<vault-name>` (dataset
  `bulk/obsidian-vault`, mounted same path).
- **Transport:** Syncthing — Mac is **send-only**, NAS is
  **receive-only** (prevents NAS-side accidental edits creating
  conflicts).
- **Versioning:** disabled on NAS folder (no `.stversions/` polluting
  the RAG corpus).
- **Mac `.stignore`:**

  ```
  .obsidian/workspace.json
  .obsidian/workspace-mobile.json
  .obsidian/cache
  .trash/
  ```

Phase 6 file watcher should index `*.md` only; ignore `.obsidian/`
(plugin state, not content).

## Backup

| Surface | Backup |
|---|---|
| `bulk/obsidian-couchdb` | ZFS snapshot — **needs explicit task** (Phase 1's `bulk` recursive policy was never created; existing tasks cover only `bulk/photos` + `bulk/media`) |
| `bulk/obsidian-vault` | ZFS snapshot — same caveat as above |
| CouchDB logical dump | nightly `curl /_all_docs?include_docs=true` to `/mnt/bulk/backups/obsidian/obsidian-vault-<date>.json`, scheduled via TrueNAS UI → Cron Jobs |

CouchDB logical dump is the consistent layer (snapshots can capture
mid-write state). Restore = either ZFS rollback the dataset OR re-import
the JSON dump into a fresh CouchDB.

## Update / restart / remove

| Action | Command / path |
|---|---|
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call app.redeploy obsidian-couchdb'` |
| Stop / Start | `midclt call app.stop obsidian-couchdb` / `midclt call app.start obsidian-couchdb` |
| Bump version | TrueNAS UI → Apps → obsidian-couchdb → Edit → Image |
| View logs | UI → Apps → obsidian-couchdb → Logs |
| Remove (keeps data) | UI → Delete (uncheck "remove ixVolumes") — bulk/obsidian-couchdb dataset survives |

## Lessons from the install

(Filled in as install proceeds. Expected hits:
chunk-size tuning if vault has large attachments, periodic full-sync
behavior on iOS, conflict-marker patterns when devices edit offline.)
