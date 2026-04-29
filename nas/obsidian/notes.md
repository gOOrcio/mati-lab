# Obsidian self-hosted sync (NAS)

TrueNAS Scale Apps, **Custom App** (no official catalog entry for
CouchDB). Installed 2026-04-29 as part of Phase 5 to replace the paid
Obsidian Sync subscription. Sync transport is the `obsidian-livesync`
community plugin talking to a local CouchDB; plain-markdown vault is
mirrored to NAS via Syncthing for Phase 6 (RAG) consumption.

Deployed via `midclt call app.create` (not the TrueNAS UI) — the JSON
payload in `Install trace` below is the canonical record.

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

## Install trace (Task 2 — `app.create` payload)

CouchDB host path was pre-created and chowned `apps:apps` (uid 568)
before deploy:

```bash
ssh truenas_admin@192.168.1.65 \
  'mkdir -p /mnt/bulk/obsidian-couchdb/etc && \
   midclt call -j filesystem.chown \
     "{\"path\":\"/mnt/bulk/obsidian-couchdb\",\"uid\":568,\"gid\":568,\"options\":{\"recursive\":true}}"'
```

Custom app created with this `app.create` payload:

```json
{
  "app_name": "obsidian-couchdb",
  "custom_app": true,
  "values": {"ix_context": {}},
  "custom_compose_config": {
    "services": {
      "couchdb": {
        "image": "couchdb:3.5",
        "restart": "unless-stopped",
        "environment": {
          "COUCHDB_USER": "admin",
          "COUCHDB_PASSWORD": "<admin-password-from-password-manager>"
        },
        "ports": [
          {"mode": "host", "protocol": "tcp", "published": 30015, "target": 5984}
        ],
        "volumes": [
          {"type": "bind", "source": "/mnt/bulk/obsidian-couchdb",     "target": "/opt/couchdb/data"},
          {"type": "bind", "source": "/mnt/bulk/obsidian-couchdb/etc", "target": "/opt/couchdb/etc/local.d"}
        ]
      }
    }
  }
}
```

Resolved image: `couchdb:3.5.1` (welcome endpoint reports
`{"version":"3.5.1","git_sha":"44f6a43d8"}`). Container ran healthy
on first boot; `/_up` returns `{"status":"ok"}`.

## CouchDB config applied (Task 3)

The obsidian-livesync **wizard inside Obsidian** (Settings → Self-hosted
LiveSync → Setup wizard) configures these automatically. They were
**already applied** at install time via the API calls below — values
land in `/opt/couchdb/etc/local.d/docker.ini` (host:
`/mnt/bulk/obsidian-couchdb/etc/docker.ini`) and survive container
restarts. If you ever need to set them by hand:

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

1. **Custom App via `midclt`, not UI.** TrueNAS Scale 25 (Goldeye)
   `app.create` accepts `custom_app: true` + `custom_compose_config`
   inline JSON. The host path layout (chowned `apps:apps` upfront,
   `etc/` subdir for `local.d`) had to be in place before deploy or the
   container would write to a root-owned dir.
2. **CORS / config writes use the single-node path.** TrueNAS catalog
   only runs CouchDB as a single node; URL prefix is `_node/_local`
   (NOT `_node/nonode@nohost`, which is what some older docs show).
3. **PUTs to `_config/<key>` return the prior value, not the new one.**
   Empty string return on first set is normal — read back with GET to
   verify.
4. **`_users` and `_replicator` aren't auto-created on a fresh CouchDB.**
   Plain `couchdb:3.5` image ships without them; create both before
   adding the LiveSync user, otherwise user PUT fails.
5. **NO `forward_auth` on the Caddy vhost.** The `obsidian-livesync`
   plugin sends HTTP basic auth on every request; Authelia's
   forward_auth would 302-redirect to a 2FA browser flow and break
   sync. Same trap as Gitea's `git push`.
6. **Phase 1 snapshot policy gap.** Hourly+daily snapshot tasks exist
   only for `bulk/photos` and `bulk/media` — `bulk/obsidian-*` is
   uncovered. Periodic snapshot tasks for both obsidian datasets are
   pending (TrueNAS UI → Data Protection → Periodic Snapshot Tasks).
