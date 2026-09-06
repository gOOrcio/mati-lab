# Secrets management consolidation — proposal (2026-09-06)

Written after the full-stack sweep, with the complete picture of where every
secret actually lives. No secret values in this file.

## The problem, evidenced

The 2026-09-06 sweep found four incidents whose common root cause was **the
same secret living in more than one place, drifting silently**:

1. Homebridge UI password changed → NAS-side copy in `/root/.backup-env`
   went stale → backups silently dead for 11 weeks.
2. Alertmanager had *no* ntfy credential (its publisher identity was simply
   lost in the June Pi reinstall) → alerting dead for 3 months.
3. CouchDB admin credential embedded in a cron *command string* (visible in
   `cronjob.query`, `ps`, middleware DB) — one-off shortcut that outlived
   its excuse by four months.
4. `hermes-backup.sh` hotfixed live-only in July → repo copy stale → a
   "restore from repo" would have silently backed up a dead data path.

None of these were detected by anything. Each was found by manual sweep.

## Where secrets live today (the sprawl map)

| Store | Examples | Writable by | Notes |
|---|---|---|---|
| **Password manager** | everything (intended SoT) | human | The declared source of truth; no automation reads it |
| NAS per-app `.env` (`/mnt/fast/databases/<svc>/.env`) | LiteLLM keys, WG private key, Hermes bot token, MCP bearers | root via stage scripts | The healthiest pattern today |
| NAS `/root/.backup-env` | *arr API keys, Kuma push URLs, Homebridge + CouchDB admin creds | root | Cleartext *copies* of secrets whose SoT is elsewhere — the #1 drift site |
| NAS `/mnt/bulk/backups/.secrets/dump-passphrase` | gpg passphrase | root | Single-purpose, fine |
| TrueNAS app compose env (via `midclt app.update`) | Gitea db_password, CouchDB admin | middleware | `app.config` returns plaintext; full-blob replace footgun |
| Hermes `config.yaml` literal headers | vault-rag/qbit MCP bearers | root | Forced duplicate (upstream `${VAR}`-in-headers gap, followup 7.x.7) |
| Pi `network/*/.env` + `network/.env` | CF token, Pi-hole admin, Grafana admin, widget creds | gooral | Survive deploys via gitignore; **dev PC keeps a second copy that `copy_env_file` scp's on every deploy** |
| Pi Authelia data files | session secret, OIDC HMAC + RSA key, client secrets | gooral | File-per-secret, fine |
| Dev PC | restic repo password, Kuma push URL, MCP env in `~/.claude`, working-tree `.env` copies | gooral | The working-tree `.env` copies make the dev PC a *third* home for Pi secrets |
| Ansible vault (`compute/*/group_vars/all/vault.yml`) | Proxmox API token, VM root passwords | human (vault password) | Encrypted at rest — the only store with that property |
| Gitea repo/CI secrets | registry PATs | Gitea UI | Write-only, fine |
| In-app DBs | *arr `config.xml` keys, qBit conf, Grafana, Kuma, CouchDB `_users` | apps | Apps own these; we only mirror into `.backup-env` |

Rough count: ~45 long-lived secrets, ~10 of which exist in 2–3 places.

## Options considered

**A. Central secrets service (Vault/OpenBao/Infisical on the NAS).**
Proper answer at company scale: one API, audit, versioning, dynamic creds.
Rejected for now: it becomes the most critical service in the lab (bootstrap
ordering on NAS reboot, its own unseal/backup/DR story, agent sidecars or
template renderers on every host), all to serve ~45 mostly-static secrets
with one human operator. The failure modes it *adds* are exactly the class
of silent breakage this sweep was cleaning up.

**B. SOPS + age, encrypted env files in the repo.**
Nice Git-native fit (encrypted `.env` per service, per-host age keys,
deploy scripts decrypt on the target). Two real costs: (1) it repeals the
hard "no secret values in committed files" rule — encrypted or not, a
mirrored repo now carries material whose safety rests on one age key per
host; (2) every deploy path (Pi make targets, midclt app blobs, root crons)
needs a decrypt step, including the TrueNAS middleware ones where we don't
control the runtime. Viable later; not the first move.

**C. Discipline + drift detection on the current layout (recommended).**
Keep PM as the only human-facing source of truth; make the machine-facing
layout boring and *verified*:

1. **One secrets home per host, file-per-consumer.**
   - NAS: `/root/.backup-env` stays the single root-cron env (it already
     is, post-sweep); per-app `.env` files stay per-app.
   - Pi: per-service `.env` + file-mounted tokens (the new
     `alertmanager/ntfy-token` pattern). Nothing inline in configs, crons,
     or compose commands. ✅ *cron #1 de-embedded during the sweep.*
2. **Every secret write goes through a stage script** (`stage-passphrase.sh`
   / `swap-consumer-key.sh` pattern): silent `read -rs` prompt, correct
   perms, immediate consumer verification. No ad-hoc `sed` into env files.
3. **`secrets-drift-check.sh` — the piece that would have caught all four
   incidents.** A read-only cron (weekly, NAS + Pi) that *authenticates as
   each consumer* and pushes one Kuma monitor:
   - Homebridge login with `/root/.backup-env` creds → expect 200
   - ntfy publish (alertmanager token) → 200; Kuma push URLs → 200
   - each *arr key vs its API; CouchDB `_up`; LiteLLM virtual keys vs
     `/v1/models`; Gitea PAT vs `/api/v1/user`
   - Report only up/down per consumer — never values.
4. **Repo == live for every root script**, enforced: the drift check also
   hashes `/mnt/bulk/backups/.scripts/*` against the repo and flags
   divergence (would have caught the July hermes hotfix).
5. **Inventory hygiene stays the human layer**: `nas/secrets-inventory.md`
   rows updated on every rotation (already the convention; the sweep added
   rows for the new ntfy token + CouchDB layout).

## Recommendation

Adopt **C** now. Revisit **B** (SOPS/age) only if a second operator joins or
the secret count doubles; revisit **A** only alongside a broader multi-user
story. The single highest-value next step is the drift-check script — the
sweep found four silent credential failures and zero of any other class.

## Status

- Quick wins shipped with the sweep: CouchDB cron de-embed + rotation,
  alertmanager token-file pattern, `/root/.backup-env` as the uniform cron
  env, repo/live re-sync of backup scripts, inventory rows updated.
- Next (needs a green light): `secrets-drift-check.sh` + Kuma monitor
  (`secrets-drift`) + weekly cron on NAS and Pi. Tracked in followups.
