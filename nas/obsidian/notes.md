# Obsidian self-hosted sync (NAS)

TrueNAS Scale Apps, **Custom App** (no official catalog entry for
CouchDB). Installed 2026-04-29 as part of Phase 5 to replace the paid
Obsidian Sync subscription. Sync transport is the `obsidian-livesync`
community plugin talking to a local CouchDB; plain-markdown vault is
mirrored to NAS via Syncthing for Phase 6 (RAG) consumption.

> **First-time setup steps for the user (Mac/iOS/iPad/Syncthing GUI)
> live in [`SETUP.md`](SETUP.md).** This file is the
> install / operations reference.

## Topology

```
Mac ⇄ Linux ⇄ iPhone ⇄ iPad     ←  LiveSync (chunked, encrypted)  →  CouchDB on NAS
                                                                     (obsidian-vault DB)
Mac ───────► NAS                ←  Syncthing (plain .md files)     →  bulk/obsidian-vault
(canonical, send-only)             (NAS receive-only)                (consumed by Phase 6 RAG)
```

**Two transports, two jobs.** LiveSync handles device-to-device sync
(via CouchDB) for every Obsidian client. Syncthing handles **only**
the Mac → NAS plain-file mirror that Phase 6 RAG will index. They
share no state and don't talk to each other.

**Why Mac is the only Syncthing peer:**
- Adding Linux→NAS Syncthing risks write-races on the receive-only
  NAS folder when LiveSync hasn't yet propagated an edit between Mac
  and Linux — produces `*.sync-conflict-*` files in the RAG corpus.
- Mac↔Linux Syncthing would duplicate LiveSync, two processes
  writing the same vault folder; same race-condition class.
- iOS/iPad don't run Syncthing reliably anyway.

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
  **Per-DB admin on `obsidian-vault` only** (server-admin still
  restricted to `admin`). This is the privilege level the
  `obsidian-livesync` project's setup_own_server.md recommends — it
  lets the plugin's "Rebuild Everything" / "Lock Remote DB" flows work
  without a 401, while still preventing a leaked livesync password
  from touching `_users`, `_replicator`, server config, or any future
  DB.
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
# vault database + ACL (livesync as per-DB admin so the plugin's
# rebuild/lock flows don't 401; member-only would also work but
# breaks Rebuild Everything)
curl -X PUT -u "$ADMIN:$PASS" "$URL/obsidian-vault"
curl -X PUT -u "$ADMIN:$PASS" "$URL/obsidian-vault/_security" \
  -H "Content-Type: application/json" \
  -d '{"admins":{"names":["admin","livesync"],"roles":[]},"members":{"names":[],"roles":[]}}'
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
  `bulk/obsidian-vault`, mounted same path; chowned `apps:apps` /
  `568:568`).
- **Transport:** Syncthing — Mac is **send-only**, NAS is
  **receive-only** (prevents NAS-side accidental edits creating
  conflicts).
- **Versioning:** disable on NAS folder (no `.stversions/` polluting
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

### Syncthing on NAS (deployed)

| Field | Value |
|---|---|
| App name | `syncthing` (TrueNAS Custom App, deployed via `midclt`) |
| Image | `syncthing/syncthing:1.30` |
| GUI (Caddy + Authelia 2FA) | `https://syncthing.mati-lab.online` |
| GUI (direct LAN backstop) | `http://192.168.1.65:30016` (set Syncthing's own GUI auth) |
| Sync port | `22000/tcp+udp` (peer-to-peer Syncthing protocol; not through Caddy) |
| Discovery | `21027/udp` |
| State dir | `/mnt/bulk/syncthing-config` (host) → `/var/syncthing` (container) |
| Folder mount | `/mnt/bulk/obsidian-vault` (host) → `/var/syncthing/Sync/obsidian-vault` (container) |
| Run as | `568:568` (PUID/PGID env) |
| **NAS device ID** | `FU3YUUS-HAMFNJJ-HJTMPYW-RHFE2PK-ZDYWRUR-ARNJ3OY-SLZJEXK-C2SXTAP` |

**Manual steps remaining (user, in NAS Syncthing GUI):**
1. Settings → GUI → set username + password (currently no auth).
2. Folder list → "Add Folder" → Folder ID `obsidian-vault`, path
   `/var/syncthing/Sync/obsidian-vault`, **Folder Type: Receive Only**,
   versioning **No file versioning**.
3. Once Mac Syncthing is up, add Mac's device ID under Remote Devices,
   share the folder with it; accept share on Mac side.

## Backup

| Surface | Backup |
|---|---|
| `bulk/obsidian-couchdb` | ZFS snapshot — hourly retain 2w (id 6), daily 02:30 retain 90d (id 7). |
| `bulk/obsidian-vault` | ZFS snapshot — hourly retain 2w (id 8), daily 02:30 retain 90d (id 9). |
| CouchDB logical dump | TrueNAS cron id 1, daily 03:15: `curl -fsS -u admin:<pwd> http://127.0.0.1:30015/obsidian-vault/_all_docs?include_docs=true -o /mnt/bulk/backups/obsidian/obsidian-vault-$(date +%F).json`; deletes dumps older than 30 days. |

CouchDB logical dump is the consistent layer (snapshots can capture
mid-write state). Restore = either ZFS rollback the dataset OR re-import
the JSON dump into a fresh CouchDB.

Inspect or re-run via:
```bash
ssh truenas_admin@192.168.1.65 'midclt call cronjob.query "[[\"id\",\"=\",1]]" | python3 -m json.tool'
ssh truenas_admin@192.168.1.65 'midclt call cronjob.run 1'
```

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
   only for `bulk/photos` and `bulk/media` — `bulk/obsidian-*` was
   uncovered. Periodic snapshot tasks for both obsidian datasets are
   in place now (ids 6/8 hourly, 7/9 daily).
7. **Syncthing's "Default Folder" trap.** On first run the official
   image creates a `Default Folder` pointing at `/var/syncthing/Sync`
   and tries to write `.stfolder` there. The parent dir
   (`/mnt/bulk/syncthing-config/Sync`) is auto-created by Docker as
   root because it's the parent of the bind-mounted
   `obsidian-vault` subdir — so 568 can't write into it. Two ways
   out: (a) chown the parent recursively to `568:568` (done), and
   (b) delete the Default Folder entry in the Syncthing GUI — you
   only want `obsidian-vault`.
8. **macOS TCC blocks Syncthing on `~/Documents/`.** First Mac
   Syncthing scan failed with `open ~/Documents/Obsidian/notes:
   operation not permitted`. macOS Catalina+ requires explicit
   user grant for protected dirs (Documents, Desktop, Downloads,
   iCloud). Fix: System Settings → Privacy & Security → Full Disk
   Access → add the Syncthing app/binary, toggle on, **fully quit
   and relaunch Syncthing** (TCC only takes effect on next process
   start). No equivalent gate on Linux or NAS/container.
9. **E2EE passphrase mismatch produces "Decryption with HKDF
   failed" spam.** LiveSync E2EE is a per-passphrase chunk-encrypt
   layer; if you wipe the CouchDB DB and rebuild, but the local
   plugin IndexedDB on a device still has chunks encrypted under
   the OLD passphrase, the plugin tries to decrypt them with the
   current passphrase and floods the log. Recovery: plugin →
   Hatch → "Discard local database to reset or uninstall" → quit
   Obsidian fully → reopen → re-run setup wizard with the SAME
   E2EE setting on every device (all-off OR all-same-passphrase).
   For a homelab with HTTPS + Authelia + per-DB livesync user, the
   recommendation is to **disable E2EE entirely** — it adds the
   passphrase-mismatch failure mode for marginal incremental
   security.
10. **`Default Folder` template on first Syncthing run.** Both Mac
    and NAS Syncthing first-run create a `Default Folder` pointing
    at `<home>/Sync` and try to drop `.stfolder` there. On NAS the
    parent dir was Docker-created root-owned and 568 couldn't
    write into it (chowned recursively now). Either way: **delete
    the Default Folder entry on every Syncthing instance** before
    adding the real `obsidian-vault` folder.
11. **Mac↔NAS direct LAN may fall back to Relay WAN** depending on
    the home network. Symptoms: `tcp://192.168.1.65:22000 — no
    route to host` despite both being on `192.168.1.0/24`. Cause
    is usually UniFi VLAN segregation, client isolation, or a
    Tailscale-style routed-subset VPN that doesn't carry LAN
    traffic. Pinning `tcp://192.168.1.65:22000, dynamic` in the
    Mac's "Edit device → Advanced → Addresses" works when the LAN
    path exists. When it doesn't, Relay WAN is fine for note-sized
    edits — bandwidth is negligible, just adds latency + uses a
    public relay. Debug LAN path separately if it matters.
12. **Secret leak via SETUP.md (rotated 2026-04-29).** First draft of
   `SETUP.md` had the generated CouchDB admin + livesync passwords
   inline; committed to Gitea + mirrored to GitHub. Both passwords
   rotated immediately: livesync via `_users` doc PUT, admin via
   `/_node/_local/_config/admins/admin` PUT, app env var via
   `app.update`, cron job command via `cronjob.update 1`. History was
   left intact (no force push) — old commits are still reachable by
   SHA but the credentials they contain are dead. **Going forward:
   placeholders only in any committed markdown — never inline values
   for passwords/tokens/setup URIs.**
