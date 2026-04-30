# Proxmox VE (host)

The Proxmox host (`proxmox.mati-lab.online`, LAN `192.168.1.184`) lives outside `compute/` because it's the substrate for everything in `compute/`, not a thing managed by Ansible from the dev box. This file captures Phase-7-era operational stuff (OIDC fix, vzdump → NAS, retention).

## Endpoints

- **Direct (LAN):** `https://192.168.1.184:8006` (self-signed cert)
- **Through Caddy + Authelia 2FA + Proxmox OIDC:** `https://proxmox.mati-lab.online`
  - OIDC realm `authelia` is the default; `pam` (`root@pam`) is the break-glass realm.
  - On the login screen pick "OpenID Connect (authelia)" → bounces through Authelia → lands as `gooral@authelia` with Administrator on `/`.

## OIDC integration with Authelia (Phase 4 → fixed Phase 7)

Lives in `/etc/pve/domains.cfg`:

```
openid: authelia
        client-id proxmox
        issuer-url https://authelia.mati-lab.online
        autocreate 1
        client-key <secret — see secrets-inventory.md row "Proxmox OIDC client-key">
        default 1
        query-userinfo 1
        scopes openid profile email
        username-claim preferred_username
```

Three lines that matter and weren't obvious:

- **`username-claim preferred_username`** — without this, Proxmox uses the `sub` claim (an opaque UUID) as the user identity. Each login auto-creates a fresh `<uuid>@authelia` user with no permissions; UI looks empty + "no admin permissions." With `preferred_username`, login arrives as `gooral@authelia` (matches Authelia's user record). **Note:** add this via `nano /etc/pve/domains.cfg` directly, not via `pveum realm modify` — that subcommand doesn't accept `--username-claim` despite docs hinting it does.
- **`autocreate 1`** — first login of a new claim auto-creates the Proxmox user record. Combined with a pre-staged ACL (next bullet) the new user is admin on first login.
- **ACL grant has to exist BEFORE login** — Proxmox's auth/authz are separate. OIDC just authenticates; permissions come from `/etc/pve/user.cfg` (managed via `pveum`). Pre-create:
  ```bash
  pveum user add gooral@authelia
  pveum acl modify / --users gooral@authelia --roles Administrator
  ```

After config edits: `systemctl reload pveproxy` (lighter than `restart`; no in-flight session reset).

### If login starts failing again

Do this *in order*:
1. Tail Proxmox logs: `journalctl -u pveproxy --since "5 min ago" | grep -iE 'openid|claim|userinfo|jwt'`.
2. Tail Authelia logs on the Pi: `ssh gooral@192.168.1.252 'docker logs authelia --since 5m 2>&1 | grep -i proxmox'`.
3. **Check `df -h /`** — if root is full, every pveproxy worker dies trying to write the access log and OIDC handshakes 401. (Yes, this is how the typo got found in Phase 7. `local` storage filled up, workers crashed before they could complete the token exchange.)
4. Check `/etc/pve/user.cfg | grep authelia` — orphan UUID-named users from earlier `username-claim sub` attempts hold ACL rules for non-existent identities; purge with `pveum user delete <uuid>@authelia`.
5. Browser cookie: clear cookies for both `proxmox.mati-lab.online` and `authelia.mati-lab.online` to drop a stale state token from a failed handshake.

## Backups (vzdump → NAS)

**Storage:** `nas-backups` is registered as Proxmox NFS storage pointing at `192.168.1.65:/mnt/bulk/backups/proxmox` (NFSv4.2). The matching NAS share exists in `sharing.nfs` allowing `192.168.1.0/24` with `maproot_user: root` so vzdump can write as root.

**Default destination:** `/etc/vzdump.conf`:

```
storage: nas-backups
mode: snapshot
compress: zstd
prune-backups: keep-last=2,keep-weekly=2
notification-mode: notification-system
```

**Scheduled job:** `/etc/pve/jobs.cfg`:

```
vzdump: backup-268aee6e-c688
        schedule sun 01:00
        compress zstd
        enabled 1
        mode snapshot
        node proxmox
        notes-template {{guestname}}
        notification-mode notification-system
        prune-backups keep-last=2
        repeat-missed 0
        storage nas-backups
        vmid 9000,102,101,100
```

(VM 100 is the cloud-init template; backing up a template is cheap and gives a known-good pristine snapshot. VM 9000 is small/idle.)

**`local` storage was stripped of `backup` content type:** `pvesm set local --content iso,vztmpl,import`. This makes it impossible for a misconfigured one-shot vzdump to fall back to the root volume. The previous default behaviour (vzdump + `local` + no retention) filled `pve-root` to 100% over 6 weeks, which broke pveproxy and OIDC.

### Run a backup right now

```bash
ssh root@192.168.1.184 'vzdump <vmid> --storage nas-backups --compress zstd --mode snapshot'
```

### Inspect existing dumps on NAS

```bash
ssh root@192.168.1.184 'ls -lh /mnt/pve/nas-backups/dump/'
```

### Restore from a dump

UI path: Datacenter → `nas-backups` → Backups → pick → Restore. CLI:

```bash
qmrestore /mnt/pve/nas-backups/dump/vzdump-qemu-<vmid>-<date>.vma.zst <new-vmid>
```

### Pruning

Both retention is set in three places (intentionally redundant — defence-in-depth):
- `/etc/vzdump.conf` global default
- `/etc/pve/jobs.cfg` per-job override (keep-last=2)
- Storage definition `prune-backups keep-last=2,keep-weekly=2`

Storage-level pruning runs after every job that targets it, regardless of the job's own setting. So even an ad-hoc `vzdump <vmid>` against `nas-backups` gets bounded.

## Disk hygiene

| Mount | What it holds | Watch when |
|---|---|---|
| `/dev/mapper/pve-root` (94GB) | OS, logs, /var/lib/vz (now empty of dumps) | Monitor at >75%; current ~9% |
| `local-lvm` (832GB thin pool) | VM disks (`local-lvm:vm-<vmid>-disk-<n>`) | Monitor pool fill — thin overcommit can bite if all VMs go full simultaneously |
| `nas-backups` (7.6TB NFS) | vzdumps | Monitored via the existing TrueNAS quota / pool free-space alerts |

Phase 8 will add a Prometheus scrape of Proxmox's own `/metrics` (the `pve-exporter` already running per `network/pve-exporter/`) for free-space alerting.

## Lessons

- **`local` (i.e. `/var/lib/vz`) is on the small root volume, not the big thin pool.** Default Proxmox installs put dumps there; this is a footgun. Phase 7 moved them to NAS NFS; do the same on any future Proxmox host.

- **vzdump retention isn't on by default.** Without `prune-backups`, dumps accumulate forever. Set it at compose-config time and at job-config time both, so a forgotten override doesn't silently produce unbounded growth. Storage-level retention is the catch-all.

- **`pveum realm modify` has fewer flags than `pveum realm add`.** `--username-claim` exists at create-time only. Edit `/etc/pve/domains.cfg` directly for changes to that field, then `systemctl reload pveproxy`.

- **Disk-full = all 401s.** A pveproxy worker that can't write `/var/log/pveproxy/access.log` exits non-zero before completing the OIDC token exchange. The browser sees `OpenID login failed (401)` and the actual error is buried in `journalctl -u pveproxy`. Always check `df -h /` first when OIDC stops working out of nowhere.

- **OIDC orphans accumulate.** Every login attempt with a misconfigured `username-claim` creates a fresh `<uuid>@authelia` user record + potential ACL rules. Sweep `/etc/pve/user.cfg | grep authelia` after fixing the claim configuration; orphans are harmless but confusing.
