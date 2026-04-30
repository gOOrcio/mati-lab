# Gitea (NAS)

TrueNAS Scale Apps, **official catalog app** (`gitea/1.26.1-rootless`,
Community train). Installed 2026-04-29 as part of Phase 4. Replaces our
GitHub usage for private + personal repos; selected repos push-mirror back
to GitHub for public visibility.

## Endpoints

- **Web (LAN+VPN, behind Caddy):** `https://gitea.mati-lab.online`
- **Web (direct LAN):** `http://192.168.1.65:30008`
- **SSH (LAN+VPN only, no Caddy):** `git@gitea-ssh.mati-lab.online:30009`
  - Pi-hole DNS override: `gitea-ssh.mati-lab.online → 192.168.1.65`
    (specific entry; sidesteps the `*.mati-lab.online → Caddy` wildcard
    since SSH isn't proxied). Kept *separate* from `nas.mati-lab.online`
    on purpose — a previous override pinned `nas.mati-lab.online` to
    192.168.1.65 too, which made browser HTTPS hit TrueNAS's self-signed
    cert instead of Caddy. See
    `docs/superpowers/plans/2026-04-30-split-nas-hostname-from-gitea-ssh.md`.
  - Add to `~/.ssh/config`:

    ```
    Host gitea-ssh.mati-lab.online
        Port 30009
        User git
        IdentityFile ~/.ssh/id_ed25519
    ```

- **Container registry:** `gitea.mati-lab.online/gooral/<image>:<tag>`
  - `docker login gitea.mati-lab.online -u gooral` once per host (PAT from password manager)

## Auth model

- **Web SSO:** Authelia OIDC. First login auto-creates linked Gitea account.
- **git CLI HTTPS:** Personal Access Tokens (Settings → Applications). Authelia is bypassed at Caddy for this vhost — Caddy has NO `forward_auth` here, on purpose.
- **git CLI SSH:** SSH keys uploaded to Gitea (Settings → SSH/GPG Keys), port 30009.
- **Container registry push:** PAT with `write:package` scope.
- **Container registry pull (Pi etc.):** PAT with `read:package` scope.
- **CI runner registration:** one-shot token (rotated only when re-registering a fresh runner).

## App config (TrueNAS catalog form values — for install reference)

| Field | Value |
|---|---|
| Application Name | `gitea` |
| Web Port (host) | `30008` |
| SSH Port (host) | `30009` |
| Storage Data | `/mnt/bulk/gitea/data` (host path) |
| Storage Repos | `/mnt/bulk/gitea/git` (host path) |
| Storage LFS | `/mnt/bulk/gitea/lfs` (host path) |
| Storage Packages | `/mnt/bulk/gitea/packages` (host path) |
| Postgres Data | ixVolume (catalog-managed; switched from host path during install) |
| App Config | ixVolume |
| Database | Postgres 18 (catalog-managed) |
| User/Group | `568` / `568` (apps user) |

## app.ini overrides applied post-install

Edited inside the running container via `vi /etc/gitea/app.ini` after
catalog form-controlled fields proved insufficient. The `app.update`
midclt route also works for the form-controlled subset (`root_url`,
`db_password`, etc.) — but **`app.update` REPLACES nested groups instead
of merging**, so include all fields when patching or db_password etc.
gets blanked.

Highlights:

- `[server] ROOT_URL=https://gitea.mati-lab.online/`
- `[actions] ENABLED=true` (CI runner needs this)
- `[packages]` enabled (container registry needs this)
- `[indexer] REPO_INDEXER_ENABLED=false` (avoids 6× repo disk bloat)
- `[cron.archive_cleanup] OLDER_THAN=168h` (kills archive ZIPs after 7 days)
- `[oauth2_client] ENABLE_AUTO_REGISTRATION=true ACCOUNT_LINKING=auto`
- `[repository] DEFAULT_BRANCH=main DEFAULT_PUSH_CREATE_PRIVATE=true`
- `[repository.pull-request] DEFAULT_MERGE_STYLE=squash ALLOWED_MERGE_STYLES=squash`

These survive catalog redeploys (verified 2× during install).

## Authelia OIDC

Client config in `network/authelia/configuration.yml` under
`identity_providers.oidc.clients`:

- `client_id: gitea`
- `client_secret`: pbkdf2 hash via `/config/data/oidc_gitea_client_secret.txt`; plaintext in password manager
- `authorization_policy: two_factor`
- `redirect_uris: [https://gitea.mati-lab.online/user/oauth2/authelia/callback]`

In Gitea: Site Admin → Authentication Sources → OAuth2 (provider:
OpenID Connect, discovery URL `https://authelia.mati-lab.online/.well-known/openid-configuration`).

## Container registry

- Path: `gitea.mati-lab.online/gooral/<image>:<tag>`
- Push: `docker login` with PAT (scope `write:package`), then `docker push`.
- CI workflows use repo secrets `REGISTRY_USER` + `REGISTRY_TOKEN` (NOT
  `GITEA_REGISTRY_*` — Gitea reserves the `GITEA_` secret-name prefix).
- Retention: weekly cleanup, keep `latest` + 5 most recent versions, delete >30d.

## Push-mirror to GitHub

Per-repo: Settings → Mirror Settings → Push Mirror.

- URL: `https://github.com/gOOrcio/<repo>.git`
- Auth: GitHub PAT with `Contents: RW + Metadata: RO` (fine-grained) or `repo` (classic)
- Sync period: 8h, sync-on-commit: enabled
- Squash-only merge style ensures clean GitHub history

## Migration to Gitea (Phase 4D summary)

- 9 repos migrated: dietly-scraper, grafana-ntfy-bridge, leet-code,
  madrale, mati-lab, resto-rate, sentinel-trader, smart-resume,
  sonarqube-sandbox.
- Migrate API requires GitHub PAT with `Issues: Read` + `Pull requests: Read`
  scopes for private repos with metadata. Without these, migration leaves a
  half-migrated repo where SSH ops 500 but HTTPS works.
- After migrate: repo is configured with push-mirror back, branch
  protection (push whitelist `gooral`), and squash-only merge.
- Special case `smart-resume`: had `upstream` (no `origin`) — renamed
  to `github-archive` and added `origin → Gitea` to preserve provenance.

## Update / restart / remove

| Action | Command |
|---|---|
| Restart | `ssh truenas_admin@192.168.1.65 'midclt call app.redeploy gitea'` |
| Stop / Start | `midclt call app.stop gitea` / `midclt call app.start gitea` |
| Bump version | TrueNAS UI → Apps → gitea → Edit → Image Selector |
| View logs | UI → Apps → gitea → Logs |
| Remove (keeps data) | UI → Delete (uncheck "remove ixVolumes") |
| Remove fully | Delete + check "remove ixVolumes" — DESTROYS app config (NOT repo data, which is on bulk/gitea) |

## Backup (Phase 8 scope)

| Surface | Backup |
|---|---|
| `bulk/gitea/{data,git,lfs,packages}` | ZFS snapshot (hourly, retain 24h + daily 30d) |
| Postgres (ixVolume) | nightly `pg_dump` to `/mnt/bulk/backups/gitea/gitea-<ts>.sql` |
| App config (ixVolume) | TrueNAS app config snapshot |

(Add to `nas/snapshots.md` when Phase 8 runs.)

## Lessons from the install

1. **NO `forward_auth` on the Caddy vhost.** Putting Authelia in front via
   forward_auth breaks `git push` over HTTPS — every push 302-redirects to
   a 2FA browser flow. Web SSO is via OIDC inside Gitea instead.
2. **Postgres data: ixVolume, not host path.** First install attempt with
   host-path pgdata hit `postgres_upgrade init container exit 1` (empty
   directory confused the catalog upgrade detector). ixVolume avoids this;
   tradeoff is backup story shifts from raw pgdata snapshots to `pg_dump`.
3. **`midclt call app.update` REPLACES nested groups.** Always include all
   required fields (`db_password`, `root_url`, `postgres_image_selector`,
   `additional_envs`) when patching, or sibling values get wiped.
4. **Server Domain typo persists into ROOT_URL.** Catalog stores `root_url`
   separately and regenerates app.ini's ROOT_URL on each redeploy. Fixing
   only the in-container app.ini gets reverted on redeploy. Patch via
   `app.update` instead.
5. **Squash-only merge** is enforced both via `app.ini`
   (`ALLOWED_MERGE_STYLES`) AND per-repo settings — belt-and-suspenders.
6. **Pull-through cache (`registry-mirror` on Pi) stays** even after Gitea
   registry exists. Different role: Gitea = our images;
   Pi cache = Docker Hub bandwidth/outage protection.
7. **Authelia Proxmox OIDC is broken** (Pi LTS migration aftermath); Gitea
   OIDC works fine. Don't conflate them when debugging.
8. **CI secret naming**: `GITEA_*` prefix is reserved by Gitea Actions for
   built-in env vars. Use `REGISTRY_USER` / `REGISTRY_TOKEN`, not
   `GITEA_REGISTRY_*`.
9. **`secrets: inherit` doesn't auto-pass cross-repo.** Reusable workflows
   must declare their secrets explicitly under
   `on: workflow_call: secrets:` for them to be passed through.
10. **act_runner caches reusable workflows by `@ref`.** Pushing fixes to a
    `@main` reusable doesn't invalidate the runner's cache. Either tag
    releases (consumers pin to `@v1`) or wipe `~/.cache/act/` after
    library changes during dev.
