# Vaultwarden (NAS)

TrueNAS Scale **catalogue app** `vaultwarden` (train `community`), serving
`https://vaultwarden.mati-lab.online` (LAN/WireGuard only, no Cloudflared route).
It's the homelab password manager: every `homelab/<service>/<role>` PM label in
[`../secrets-inventory.md`](../secrets-inventory.md) is a Vaultwarden item of that
name. Apple Passwords remains the personal password manager.
Plan: `docs/superpowers/plans/2026-10-30-vaultwarden.md` (local only).

Clients: Bitwarden desktop (Linux), browser extension, `bw` CLI
(`bw config server https://vaultwarden.mati-lab.online`), optionally the iOS app
over WireGuard.

## Layout

Web port **30126**. Dataset `fast/databases/vaultwarden`:

| Host path | Container path | Contents |
|---|---|---|
| `/mnt/fast/databases/vaultwarden/data` (568:568, 750) | `/data` | `rsa_key.pem` (signs login tokens), attachments, sends, icon cache |
| ixVolume | Postgres data | **Not** a host path: the catalogue's postgres upgrade init container fails on an empty host-path pgdata (`nas/gitea/notes.md` gotcha 2). Backed up by `pg_dump`. |
| `/mnt/fast/databases/vaultwarden-apply/values.conf` (dir root 700, file 600) | none | Secret values for `apply.sh` |

Snapshot tasks 23 (hourly, 2w) and 24 (daily 02:30, 90d) on `fast/databases/vaultwarden`
(recursive). Backups: `nas/backup-jobs/vaultwarden-backup.sh` (nightly 03:45 UTC, cron id 60, installed
at `/mnt/bulk/backups/.scripts/`, log `/var/log/vaultwarden-backup.log`). Containers:
`ix-vaultwarden-vaultwarden-1`, `ix-vaultwarden-postgres-1`.

## Deploy / update

`app-config.json` is the full source of truth; secrets are `__FROM_PM__<pm-label>`
placeholders. `apply.sh` substitutes them on the NAS from `values.conf` and runs
`app.create` / `app.update` (full `values`, since **`app.update` replaces nested
groups**). `deploy.sh` ships both files to `/home/truenas_admin/.deploy/vaultwarden/` (700, not
world-writable `/tmp`, since root runs what's staged there) and runs `apply.sh` as
root through the temp-cron channel, because `truenas_admin` has no passwordless sudo.

```bash
nas/vaultwarden/deploy.sh create   # first time
nas/vaultwarden/deploy.sh update   # after editing app-config.json
```

`values.conf` has one line per secret, `<pm-label>=<value>`. Values must match
`[A-Za-z0-9_.~-]` (they go into JSON and `DATABASE_URL`), so generate them with
`openssl rand -hex 32`. To write it, run this in a real terminal on the NAS (not under
`!`, which has no stdin):

```bash
read -rs P && printf 'homelab/vaultwarden/db-password=%s\n' "$P" | sudo tee /mnt/fast/databases/vaultwarden-apply/values.conf >/dev/null && sudo chmod 600 /mnt/fast/databases/vaultwarden-apply/values.conf; unset P
```

Never print `midclt call app.config vaultwarden`: it returns `db_password` in plaintext.

## Access model

- **No Authelia `forward_auth`** on the vhost. The Bitwarden clients call the API
  directly and can't follow a 2FA browser redirect. Vaultwarden's master password +
  TOTP is the gate, and the vault is end-to-end encrypted with the master password.
- **Client IP**: Caddy overwrites `X-Real-IP` (Vaultwarden's default `IP_HEADER`)
  with the real peer, so login rate limiting can't be dodged by spoofing it.
- **LAN-direct `:30126`** skips Caddy (same as every NAS app). It's plain HTTP, but
  the vault is end-to-end encrypted and still needs master password + TOTP. Use the
  Caddy hostname in clients.
- **`/admin` is disabled**: `admin_token` is empty, and Caddy also answers `/admin*` with 403.
- **Signups**: `SIGNUPS_ALLOWED=true` only until the first account exists, then `false`.
  `INVITATIONS_ALLOWED=false`. No SMTP configured.

## Break-glass: temporary admin page

1. In a real terminal: `docker run --rm -it ghcr.io/dani-garcia/vaultwarden:1.37.4 /vaultwarden hash`
   (any machine), then put the PHC string in the PM as `homelab/vaultwarden/admin-token`.
2. Set `admin_token` in `app-config.json` to `__FROM_PM__homelab/vaultwarden/admin-token`
   and add the line to `values.conf`. **Note:** the PHC string contains `$` and `=`,
   which `apply.sh` rejects. Either relax its character check for that key or set the
   token through the TrueNAS UI for the duration.
3. Reach it LAN-direct at `http://192.168.1.65:30126/admin` (Caddy blocks it).
4. Afterwards, revert `admin_token` to `""` and `deploy.sh update`.

## Recovery

Zero-knowledge: **a lost master password means a lost vault**, and backups don't help.
Keep the master password and the 2FA recovery code on paper.
