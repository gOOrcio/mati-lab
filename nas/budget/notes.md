# Budget (NAS): Actual Budget + mBank

Household budget. **Actual Budget** (envelope budgeting, local-first) serves
`https://budget.mati-lab.online`, which sits behind Authelia 2FA and is
LAN/VPN only. mBank transactions arrive by **Enable Banking** bank sync, or by
**CSV** for history. Categorisation runs **local** LLMs
via LiteLLM. A Postgres mirror feeds the Grafana dashboard **Budget**
(`https://grafana.mati-lab.online/d/budget`).

- Research brief: `nas/Household Budgeting Stack for mBank Poland_ November 2026 …md`
  (local, untracked).
- Build plan: `docs/superpowers/plans/2026-11-10-budget-stack.md` (local).
- Worker source: Gitea `gooral/budget-worker` (`~/Projects/budget-worker`).

## Architecture

TrueNAS **Custom App `budget`** (compose in `compose.yml`, values in `budget.conf`):

| Container | Image | Port | Role |
|---|---|---|---|
| `ix-budget-actual-1` | `actualbudget/actual-server:26.11.0` | **30127** → 5006 | The app + sync server. Data in `/mnt/fast/databases/budget/actual-data` |
| `ix-budget-budget-db-1` | `postgres:18-alpine` | **30128** → 5432 (LAN) | Mirror for Grafana. Derived data, not backed up |
| `ix-budget-worker-1` | `gitea.mati-lab.online/gooral/budget-worker:<sha>` | — | Bank sync 3×/day, export every 30 min, CSV inbox |
| `ix-budget-actual-ai-1` | `sakowicz/actual-ai:3.0.4` | — | LLM categorisation at 07:20, 15:20 and 22:20 |

Categorisation pipeline:
0. **Own-account transfers** (JDG ↔ osobiste ↔ oszczędności, card repayments) are
   linked by the worker's `link-transfers` right after each bank sync. It matches
   the opposite amount within ±3 days on legs marked `PRZELEW WŁASNY` / `SPŁATA KARTY`,
   and card legs only pair with card legs. Both legs already exist, so it sets
   `transfer_id` on both. **Don't use the UI's "Make transfer" on a single
   row**: it creates a duplicate counterpart. 91 historical pairs were linked
   2026-11-10.
1. **Actual rules** run on every import, deterministically. After each sync the
   worker also runs `rules run`, which applies rule categories to anything still
   uncategorised (so a new rule fixes history without clicking "Apply actions").
2. **actual-ai** handles anything still uncategorised, via LiteLLM `budget-classifier`.
   That alias tries qwen3.5:9b on the 3070 first, then the dev-PC gpt-oss:20b, with
   `think: false`. It is **local only** because no PII masking happens before the call.
3. Whatever the model can't place is tagged `#actual-ai-miss`. It shows up on the
   dashboard's **Review queue** with the `[mBank: …]` hint in the notes.
4. When you fix one by hand, make it a **rule** in Actual (payee → category) so the
   payee never reaches the LLM again.

Deviations from the brief:
- TrueNAS app instead of a Proxmox VM, the same pattern as Paperless and Vaultwarden.
- actual-ai **3.0.4** (the brief assumed 2.4.1; 3.0 changed `ENABLED_TOOLS` → `FEATURES`).
- No cloud fallback for the classifier (followups BUD.3).

Rule hygiene (operator):
```bash
nas/budget/root-run.sh cli rules list            # human-readable
nas/budget/root-run.sh cli rules dedupe --apply  # drop exact duplicates
nas/budget/root-run.sh cli link-transfers        # dry run (add --apply)
nas/budget/root-run.sh sql "select …"            # read-only Postgres mirror
```
Live rule worth knowing: JDG + payee `MATEUSZ GÓRAL MGT` + notes contain `VAT`
→ **Podatki**. These are the split-payment moves to and from the unlinked VAT
account, so *Podatki* nets to the VAT and PIT actually paid. The rule is scoped
to the JDG account because the same payee name appears on the incoming
JDG → osobiste transfers.

## Investments (net worth)

The worker's `investments` job (nightly **22:45**) reads the investor-dashboard
LAN API (`INVEST_API_URL=http://192.168.1.65:30032`, read-only GETs). It sums
`valuation.value_pln` per eMakler account and posts the difference to that
account's current balance as one **"Wycena portfela"** transaction, in three
**off-budget** accounts:
`eMakler (rachunek maklerski)`, `eMakler IKE`, `eMakler IKZE`.

- Off-budget, so it never touches the envelopes or `v_flows`. It *does* count in
  Actual's Net Worth report and the Grafana "Net worth (all accounts)" panel.
- The value is gross market value. Belka tax on the standard account isn't deducted.
- If any position is stale, or the dashboard is unreachable, the job fails before
  writing anything, so a dashboard outage never zeroes an account. Grafana alert
  **Budget investment valuation stale** fires after 36 h without a good run.
- History starts 2026-11-10, so the net-worth line steps up on that day. There
  are no earlier valuations to backfill.
- Manual run: `nas/budget/root-run.sh cli investments [--dry-run]`.

### Mortgage (liability)

Off-budget account **`Kredyt hipoteczny (mBank)`**, created with
`cli account create-offbudget`. The monthly payment stays a normal budget
expense (`Rata kredytu hipotecznego`); this account only carries the remaining
principal for net worth. Enable Banking can't read mBank loan accounts, so you
update it by hand. Every few months, open the account → **Reconcile** →
enter the remaining principal **as a negative number** from the mBank app.
Actual books the difference.

## Report dashboards (as code)

`nas/budget/root-run.sh cli dashboard apply [--dry-run]` (definitions are in
budget-worker `src/commands/dashboards.ts`). It replaces every widget on the
pages **Budżet** (renamed from the default *Main*), **Rok** and **Majątek**.
Other pages are left alone, so UI edits belong on your own page or in code.
It also switches on the experimental `budgetAnalysisReport` / `sankeyReport`
flags those widgets need.

Definitions, so the numbers mean something:
- **Wpływy z pracy**: categories B2B + Wynagrodzenie, **gross incl. VAT**. The VAT
  goes back out under *Podatki*.
- **Wydatki na życie**: outflows excluding Podatki, ZUS, Oszczędności i
  inwestycje and Koszty firmowe.
- All of these are on-budget only, with own transfers excluded.
- Actual's default "Total Income/Expenses (YTD)" counted every non-transfer
  inflow. That included the VAT round-trips (`PRZELEW VAT PRZYCH. WŁASNY US`),
  matured deposits, and a one-off 164k PLN FX conversion on 2026-05-12.
  The result was a misleading ~584k "income".
- `cli dashboard list` dumps what is on every page.
- The 2026-05-12 conversion (the FX account emptied into savings and a mortgage
  overpayment) is in the income category **Przewalutowanie oszczędności
  (CHF/EUR)**, so it stays out of *Wpływy z pracy*. The FX conversions from
  Nov 2025 to Apr 2026 stay as B2B income: that was the user's pay, received in
  CHF/EUR and converted month by month.
- One-off fixes: `cli tx set-category <id> "<category>"`.

## Deploy / update

```bash
nas/budget/deploy.sh render            # print the compose that would be sent
nas/budget/deploy.sh update            # after editing compose.yml / budget.conf
nas/budget/deploy.sh create            # first install only
nas/budget/root-run.sh status          # containers + worker log (root channel)
nas/budget/root-run.sh logs actual-ai 200
nas/budget/root-run.sh cli bank-sync   # any worker CLI command
```

- `budget.conf` holds the non-secret parameters: `WORKER_TAG` (the full commit SHA
  of a budget-worker release build), `SYNC_ID`, and actual-ai `FEATURES`.
- **Bump the worker:** merge to budget-worker `main` (CI builds `:<sha>`), set
  `WORKER_TAG`, then `deploy.sh update`.
- `truenas_admin` can't use docker, so `root-run.sh` runs fixed verbs as root
  through a one-shot cron job.
- First install, in order:
  1. Dataset `fast/databases/budget` with `actual-data`/`pgdata` (568 0750/0700),
     `inbox` (NFSv4 ACL: 568 + truenas_admin full, inherited), and `secrets`
     (truenas_admin 0700).
  2. `init-secrets.sh` on the NAS.
  3. `deploy.sh create` with an empty `SYNC_ID`. That leaves actual-ai out.
  4. `root-run.sh cli bootstrap`, which sets the server password and creates
     the "Household" budget with Polish envelope categories, PLN, and
     `dd.MM.yyyy`.
  5. Put the printed Sync ID in `budget.conf`, then `deploy.sh update`.

Live since 2026-11-10. Sync ID `7291a11b-7c0f-4f9f-b952-002a16a08978`.

## Bank sync (Enable Banking) — one-time setup, needs you

Actual's Enable Banking integration is **experimental** (26.11.0). Do the setup in a
**browser**, not the desktop app.

1. Log in at `https://budget.mati-lab.online`: Authelia first, then the Actual
   password (PM `homelab/budget/actual-password`).
2. Settings → Show advanced settings → **Experimental features** → tick **Enable
   Banking sync (EU banks)**.
3. Go to `enablebanking.com` → sign up → Control Panel → **Applications** → new app:
   - Environment **Production**, name `Actualbudget`.
   - Redirect URL `https://budget.mati-lab.online/enablebanking/auth_callback`.
   - Leave Privacy/ToS empty, or use `https://` URLs.
   - Register, then **download the private key (.pem)** into Vaultwarden
     `homelab/budget/enable-banking-app`.
4. Activate restricted production: **link your own mBank accounts in the Enable
   Banking control panel** (SCA in the mBank app). Skip this and Actual shows no
   banks. Copy the **Application ID**.
5. In Actual go to **More → Bank Sync → Set up Enable Banking**, paste the App ID
   and upload the .pem.
6. For each account: **Add account → Link bank account → Enable Banking → PL → mBank**
   (MBank or MBankV2). Linked 2026-11-10: `mBank osobiste` (mKonto Intensive),
   `mBank karta`, `mBank oszczędności`, `mBiznes JDG`. **Not linked:** the joint
   eKonto (unused, to be closed) and the eKonto walutowe FX accounts.
7. Write down the consent expiry Enable Banking shows (`valid_until`) in the
   "Consent log" below. Actual's docs say "90 days at most".

From then on, the worker syncs every linked account at **06:20, 14:20 and 21:20**.
PSD2 allows 4 unattended fetches per 24 h, so one stays free for a manual sync
in the UI. actual-ai runs an hour after each sync. Its `syncAccountsBeforeClassify`
is deliberately **off**, because it would add fetches.

### Reauthorizing (every ≤ 90 days)

Grafana alert **Budget bank sync failing** fires (ntfy) when a linked account's
last sync errored, or when it hasn't synced OK in 26 h. The fix: in Actual, the
account shows "This account is experiencing connection problems" → **Reauthorize**
→ go through the mBank SCA → map it to the **existing** account. Then add a line
to the consent log.

### Consent log

| Date linked | Accounts | valid_until |
|---|---|---|
| 2026-11-10 | osobiste, karta, oszczędności, mBiznes JDG | ≤ 2027-02-08 (90 d; confirm in mBank → Usługi zewnętrzne) |

## CSV import (history, fallback)

From mBank: **Historia → Lista operacji → Eksportuj → CSV**, one account per file.
Both the new 5-column UTF-8 layout and the legacy 8-column CP1250 layout parse.

```bash
scp lista.csv "truenas_admin@192.168.1.65:/mnt/fast/databases/budget/inbox/<Actual account name>/"
```

- Within 10 minutes the worker imports it and moves it to `<account>/done/`.
- A rejected file goes to `<account>/failed/` with a `.error.txt`, and the Grafana
  alert *Budget CSV import failed* fires.
- The account is created if it doesn't exist. The directory name must match the
  Actual account name exactly.
- Re-importing the same export, or one that overlaps it, is a no-op:
  `imported_id = sha256(account|date|amount|description|ordinal)`.
- On a **bank-linked** account only rows **before** the first bank-synced transaction
  are imported, so CSV history and bank sync can't double up. Backfill whenever.
- Dry run: `root-run.sh cli import-csv "/inbox/<acct>/x.csv" "<acct>" --dry-run`.

## Grafana

- Datasource `budget-postgres` (file-provisioned,
  `network/grafana/provisioning/datasources/budget.yml`) connects to
  `192.168.1.65:30128` as `grafana_ro` (SELECT only). Its password is
  `BUDGET_PG_RO_PASSWORD` in `network/grafana/.env`, synced by
  `sync-grafana-secret.sh`.
- Dashboard **Budget** (uid `budget`) is API-managed. Its first version came from
  `nas/budget/dashboard/build_dashboard.py` → `network/grafana/dashboards/budget.json`
  → `network/scripts/manage-grafana.sh import …`.
- What's on it: cash, spend and income this month, runway, review count, last
  sync, spending by group, income vs spending, envelope table, net worth, a
  **what-if cash projection** (variables: months without income, income cut %,
  extra fixed cost such as ZUS, averaging window), top payees, review queue, and
  sync/job status.
- Alerts (folder *Budget*, rules in `rules.yml` group `budget`):
  `budget-bank-sync-failing`, `budget-export-stale` (> 2 h, for 30 min),
  `budget-csv-import-failed`.
- Postgres mirror tables: `accounts`, `categories`, `payees`, `transactions`,
  `budget_months` (amounts in PLN), plus `sync_runs` and `job_runs`.
  - `v_flows` holds real income and spending only. It excludes split parents,
    transfers, opening balances and off-budget accounts.
  - `v_review_queue` holds what still needs a human.

## actual-ai dry run → live

**Live since 2026-11-10 15:30, `FEATURES=[]`**. Each row it categorises gets `#actual-ai` in its notes, so wrong guesses can be found. **`classifyOnStartup` stays off on purpose**: every
TrueNAS `app.update` restarts all containers, and in dry-run mode each pass
re-classifies *every* uncategorised row (about 10 s each on the 3070, so hours).
The three cron runs are enough. Once live, a pass only sees new rows.

First dry run (2026-11-10, qwen3.5:9b, 449 rows sampled): usable, but weak on
merchants that aren't self-describing. It dumped Allegro/Amazon into Subskrypcje
and put random card spend abroad into Koszty firmowe. So **payee rules carry the
load**: about 23 seeded rules (`rules list`) categorised 626 historical rows
deterministically. actual-ai only gets the long tail.

Rows still unsure after the live run carry `#actual-ai-miss` and show up in the
dashboard's Review queue. To pause it again, set `FEATURES='["dryRun"]'`.

## Backups and restore

- `/mnt/fast/databases/budget` (recursive): snapshot tasks **27** (hourly, 2 weeks)
  and **28** (daily 02:30, 90 days).
- `nas/backup-jobs/budget-backup.sh`, cron **181**, nightly 04:30. It tars
  `actual-data` from a temporary ZFS snapshot (crash-consistent SQLite) and
  encrypts it with gpg →
  `/mnt/bulk/backups/budget/budget-data-<ISO>.tar.gz.gpg`, kept 30 days.
- Optional Kuma push: `KUMA_URL_BUDGET_BACKUP` in `/root/.backup-env`.
- `root-run.sh verify-backup` decrypts the newest backup and lists it.
- **Restore**:
  1. Stop the app.
  2. Empty `actual-data/`.
  3. Run `gpg -d … | tar -xzf - -C /mnt/fast/databases/budget/actual-data`.
  4. `chown -R 568:568`, then start the app.
  5. The worker's next export rebuilds Postgres.
- Portable alternative: Actual UI → Settings → Export data (.zip), which any
  Actual instance can import.

## Monitoring (to add in Kuma; push URLs are secrets)

| Monitor | Type | Target |
|---|---|---|
| `budget` | HTTP keyword | `https://budget.mati-lab.online/health`, keyword `UP` (no auth on that path) |
| `budget-export` | Push, heartbeat 60 min | URL → `secrets/kuma.env` as `KUMA_PUSH_URL=…`, then `deploy.sh update` |
| `backup-budget` | Push, heartbeat 25 h | URL → `/root/.backup-env` as `KUMA_URL_BUDGET_BACKUP=…` |

## Gotchas

- The Actual API keeps module-level state that drifts. The worker runs **every job
  in a fresh process**; don't turn it into a long-lived loop.
- `runBankSync()` without an account id throws on the first failing account and
  loses the others' results. The worker syncs one account at a time on purpose.
- Changing the server password (26.11) signs out the worker and actual-ai too.
  Update `actual.env` in the same step.
- Postgres has a LAN port (30128). The mirror holds transaction history, so an
  inline `pg_hba` (compose `configs`) admits only `grafana_ro` (SELECT) from the
  Pi (192.168.1.252) and `budget` from the app's own Docker network (`samenet`).
  Both have 48-hex passwords. No TLS: it's same-LAN plaintext, like the other
  NAS Postgres instances.
- Actual's port 30127 is reachable LAN-direct without Authelia, the same as every
  NAS app. Actual's own password still applies. Hardening option, if that's ever
  wanted: `ACTUAL_LOGIN_METHOD=header` with Caddy forwarding Authelia's
  `Remote-User`, or a firewall rule limiting 30127 to the Pi.
- `.../budget` uses NFSv4 ACLs (inherited from `fast/databases`). POSIX
  `setfacl` payloads fail with "ACL type is invalid".
