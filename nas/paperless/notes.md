# Paperless-ngx (NAS)

TrueNAS Scale **catalogue app** `paperless-ngx` (train `community`), serving
`https://paperless.mati-lab.online` (LAN/VPN only, no Cloudflared route). It's the
household document archive: per-user ownership, Gmail ingestion, OCR in Polish and
English. Stirling PDF (`nas/stirling-pdf/`) is the editing desk.
Design: `docs/superpowers/specs/2026-10-30-paperless-ngx-design.md` (local only).

## Layout

Web port **30125**. Dataset `bulk/paperless` (568:568, mode 755), host paths:

| Host path | Container path | Contents |
|---|---|---|
| `/mnt/bulk/paperless/data` | `/paperless/data` | Index, classifier, logs |
| `/mnt/bulk/paperless/media` | `/paperless/media` | Originals + archive PDFs (readable tree by owner) |
| `/mnt/bulk/paperless/consume` | `/usr/src/paperless/consume` | Inbox; per-user subdirs `consume/<user>/`, Stirling returns in `consume/<user>/stirling/` |
| `/mnt/bulk/paperless/trash` | `/paperless/trash` | Deleted documents (trash enabled) |
| ixVolume | Postgres data | **Not** a host path (see below) |

**Postgres data is an ixVolume.** The catalogue's postgres upgrade init container
fails on an empty host-path pgdata (`postgres_upgrade init container exit 1`; see
`nas/gitea/notes.md` gotcha 2). It is **not** covered by the dataset snapshots
(tasks 25/26). It is backed up by `nas/backup-jobs/paperless-pgdump.sh` (cron 79,
nightly 04:00, gpg-encrypted, 14 days, Kuma push `backup-paperless-dump`). Restore:
decrypt with the dump passphrase → `psql -U paperless -d paperless` in
`ix-paperless-ngx-postgres-1`.

The in-container consume path stays `/usr/src/paperless/consume`. Workflow triggers
match `filter_path` against it, e.g. `/usr/src/paperless/consume/gooral/*`.

## Deploy / update

`app-config.json` is committed with `__FROM_PM__<pm-label>` placeholders. Never
put values in it. Run from the dev PC:

```bash
nas/paperless/deploy.sh create   # first install
nas/paperless/deploy.sh update   # after editing app-config.json (sends the full values)
```

`deploy.sh` stages `app-config.json` + `apply.sh` in a private dir
(`~truenas_admin/.paperless-deploy/<mktemp>`, 0700) and runs `apply.sh` as root
via a one-shot disabled cron job. `apply.sh`:
- refuses to run if anything in the staging dir isn't owned by `truenas_admin` or is
  group/world-writable;
- substitutes values from `/mnt/fast/databases/paperless-apply/values.conf` (root
  0600, lines `<pm-label>=<value>`, **hex values only**, generated with
  `openssl rand -hex 32`);
- calls `app.create`/`app.update` through `truenas_api_client`, so secrets never
  appear in argv or `ps`;
- prints a redacted log (`apply.out`), and the staging dir is removed afterwards.

Values file keys (PM label = key; username in Vaultwarden in brackets):
`homelab/paperless/db-password` [paperless], `homelab/paperless/redis-password`
[—], `homelab/paperless/secret-key` [—], `homelab/paperless/admin-password` [admin], and since the Gmail step
`homelab/paperless/gmail-oauth-client-secret`.

Gotchas:
- `additional_envs` entries need `"container": "paperless"` or create fails with
  `additional_envs.0.container: Field required`.
- Containers: `ix-paperless-ngx-{paperless,postgres,redis,tika,gotenberg}-1`.
- Check secrets survived an update (lengths only):
  `midclt call app.config paperless-ngx | jq '.paperless | {db:(.db_password|length), key:(.secret_key|length)}'`.
- OCR: `PAPERLESS_OCR_LANGUAGES=pol` installs Polish at start; `tesseract --list-langs`
  in the container shows `pol` (verified 2026-10-30).

## Accounts and SSO

- `admin`: break-glass **superuser** (catalogue `admin_user`, password in PM
  `homelab/paperless/admin-password`).
- `gooral`: **ordinary user** (no superuser/staff) with view/add/change/delete on
  documents, tags, correspondents, document types, storage paths, saved views,
  mail accounts, mail rules, workflows, custom fields, share links and notes. Sees
  only own and shared documents.
- SSO: Authelia client `paperless` is **public + PKCE (S256), no secret**
  (`token_endpoint_auth_method: none`). Swift Paperless (iOS) exchanges the code
  itself using the client_id Paperless advertises, and can't hold a secret.
  django-allauth strips the empty secret, so web login uses the same client.
  Redirect URIs: `https://paperless.mati-lab.online/accounts/oidc/authelia/login/callback/`
  and `x-paperless://oidc-callback`.
- **SSO-only web login** (`PAPERLESS_DISABLE_REGULAR_LOGIN=true`,
  `PAPERLESS_REDIRECT_LOGIN_TO_SSO=true`). `/admin/login/` also redirects to SSO,
  so there is no web password route at all. The API still accepts local
  credentials (basic auth).
- **Break-glass** (Authelia/SSO broken): drop those two envs from
  `app-config.json` → `nas/paperless/deploy.sh update` → log in as `admin` with
  the password. Or use the API with `admin` basic auth.

## Mobile (iPhone)

**Swift Paperless** (App Store): server `https://paperless.mati-lab.online` (home
Wi-Fi or VPN), login type **OpenID Connect → Authelia**. No API token needed.
Verified 2026-10-30.

## Gmail ingestion (per user)

Google Cloud project **`mati-lab-paperless`** (separate from restorate's on purpose:
consent-screen scopes and verification status are project-wide). Gmail API
enabled. Consent screen External, **In production, unverified** (Testing mode
expires refresh tokens after 7 days). Production needs a homepage + privacy URL
on an authorised domain (`mati-lab.online`); **no logo**, because a logo forces
verification. Scope `https://mail.google.com/`. Web client `paperless`, redirect
`https://paperless.mati-lab.online/api/oauth/callback/`. Client id in
`app-config.json`, secret via values.conf.

Per user:
1. Gmail: labels `paperless` and `paperless/done`; filter
   `category:primary has:attachment filename:pdf` → apply label `paperless` (no
   "also apply to existing"; the backfill is done in batches, see below).
   Paperless can't see Gmail categories over IMAP, which is why the label is needed.
2. Paperless (as that user): Mail → **Connect Gmail Account** → click through
   "unverified app" → rename the account `gmail-<user>`.
3. Mail rule `gmail-pdfs`: folder `paperless`, max age **2600** days
   (must reach 2020-01-01: 2497 days on 2026-11-02; 2200 silently cut Jan–Oct 2020), consumption
   scope + attachment type *Only process attachments*, include `*.pdf`, action
   **Move to specified folder** `paperless/done` (over Gmail IMAP this swaps
   the label), tag `gmail`, title from attachment filename, correspondent
   **Use name (or mail address)** (auto-creates correspondents; not retroactive, so
   pilot documents have none), **Assign owner from rule** ticked.

Verified 2026-10-30 for `gooral`: test mail → filter label → document tagged
`gmail`, owned by `gooral`, mail moved to `paperless/done`.

### Backfill (PL.2) and the two re-fetch traps

Paperless remembers processed mail by **(folder, UID)** and only records it after the
mail's consume tasks finish. Two ways that duplicated pilot documents:
- **Re-labelling a done mail.** Putting `paperless` back on a mail that is already in
  `paperless/done` gives it a new UID in that folder, so it's fetched again. Always add
  `-label:paperless-done` to the bulk-label search.
- **Overlapping fetches.** With the default 10-minute fetch, a big batch is still
  consuming when the next fetch runs; mails not yet recorded are queued a second time
  (3 pilot mails, same UID twice a minute apart). During the backfill the fetch runs
  every 3 h (`PAPERLESS_EMAIL_TASK_CRON=7 */3 * * *`); revert after (followups PL.7).

Procedure: one year per batch. Gmail search
`category:primary has:attachment filename:pdf after:2020/01/01 before:2021/01/01 -label:paperless-done`
→ select all conversations → label `paperless`. Wait for the next fetch (hh:07 every
3 h, or Mail → Process mail) and until the task list is idle, then the next year.
Gmail only offers "select all conversations that match this search" when the results
are sorted by **most recent** ("Najnowsze"); under the default "most relevant" sort
("1–50 of many") the link never appears.

**A slow batch strands mails in `paperless` (2020 batch, 2026-11-05).** The Gmail
OAuth access token is refreshed only when a fetch starts and lives one hour, while
the "move to `paperless/done`" action (`apply_mail_action`) runs after the consume
queue and does not refresh it. That batch (235 mails, 255 documents, one worker)
took 68 minutes: 37 moves succeeded, 149 failed with `AUTHENTICATIONFAILED` and
were recorded as `ProcessedMail.status = FAILED`. Those mails are consumed and are
never fetched again (the (folder, UID) record exists), but they keep the `paperless`
label. Prevention: `PAPERLESS_TASK_WORKERS=3` (default 1; 16 cores, so 5 OCR threads
per worker) keeps a year under the hour.

**Mails without a matching PDF also stay in `paperless`.** A labelled mail whose
attachments don't pass the rule (thread replies, inline images, excluded names) is
recorded as `PROCESSED_WO_CONSUMPTION` and the move action is never run for it (50
after the 2020 batch). So the label is not empty after a clean batch either.

**Clear the label after every batch, before labelling the next year.** Everything in
`paperless` that has a `ProcessedMail` record (same UIDVALIDITY, same subject or date)
is finished: move it to `paperless/done`. Leave anything without a record, that is
mail still waiting for a fetch. Don't use Gmail's "select all → move" while new mail
may be arriving in the label: it would sweep pending mail into `done` and it would
never be imported. Done on 2026-11-06 for 199 mails from the Paperless side: Django
shell as `paperless`, refresh the token as the fetch does
(`PaperlessMailOAuth2Manager().refresh_account_oauth_token`), `get_mailbox` +
`mailbox_login`, then `get_rule_action(rule).post_consume(M, uid, "paperless/done")`
per matched UID.

## Adding a user (partner)

The web UI is SSO-only, so `admin` can't create users in the browser. `gooral` holds
user add/change/delete permissions for this reason (it's still not a superuser).

1. Authelia: `cd network && make add-authelia-user`; they enrol 2FA.
2. They sign in at `https://paperless.mati-lab.online` → Authelia → allauth's
   signup form creates their account (`PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS` is
   left at its default `true`; `SOCIAL_AUTO_SIGNUP=false` only means they confirm
   the form). **The gate is the Authelia user list:** any Authelia user can create
   an account, but a new account has **no permissions** and sees nothing.
3. Grant the ordinary-user profile: `nas/paperless/grant-perms.py <user> --profile full`
   (admin password prompt; refuses superusers). Run with `--dry-run` first.
4. Before giving them real documents: the privacy check (followups PL.3), i.e. their
   `/api/documents/` count must not include `gooral`'s.
5. Then Gmail (their own labels/filter/mail rule), `consume/<user>/` + workflows,
   and the Stirling mount/pipeline (`nas/stirling-pdf/notes.md`).

## Classification: document types → folders

Document types (matching **Auto**): Bank, Contract, Government, Insurance, Invoice,
Manual, Medical, Personal, Terms and Conditions; plus **Other** (matching **None**,
assigned only by the fallback so the classifier doesn't learn to over-predict it). Each has a storage path of the same name
(`{{ owner_username }}/<Folder>/{{ correspondent }}/{{ created_year }}/{{ title }}`,
matching None) and a workflow `folder-<type>` (triggers **Document Added** and
**Document Updated**, filter *has document type*, action *assign storage path*), so
fixing a document's type moves its file. **`fallback-Other`** (order 99, trigger
Document Added, `filter_has_not_document_types` = *all* types) sets type Other +
path Others on anything the classifier left untyped. **When adding a new document
type, append its id to that workflow's not-list**, or new-type documents also get
"Other". Verified 2026-11-02: an untyped drop into `consume/gooral/` →
`gooral/Others/2026/…`, owner gooral. Workflows are global, so the partner's
documents land in `<partner>/<Folder>/…` too. Tags `gmail` and `edited-in-stirling`
use matching **None**: they're set by the mail rule / workflow, and Auto would
learn "everything is gmail". The classifier retrains hourly; classify ~5–10
documents per type by hand before trusting Auto.

### Bank PDFs, unlock, inbox, views (2026-11-02)

- **Taxonomy:** document type = what kind of paper, correspondent = who sent it (from
  the mail rule), tags = area of life (`home`, `car`, `travel`; Auto, but tag by hand
  until each has ~10 examples). Don't add a type when a tag will do.
- **`bank-by-filename`** (order 4, consumption started, sources all): filename
  triggers `*konto* nr *`, `VISA *`, `TwojeDokumenty*`, `*_NE_*`, `*deponent*` →
  type Bank. Needed because password-protected statements arrive with no text, so the
  classifier guesses from nothing, and unlocking never reclassifies the original.
- **`unlock-bank-pdfs`** (order 3): triggers Document Added (all) + Document Updated
  with tag `unlock` (matching **None**); actions Password Removal (passwords entered in
  the UI, never in the repo), then **Removal of tag `unlock`**, so the tag is one-shot
  and edits don't re-run the unlock. In 3.x the unlocked file is a hidden **version**
  (`<title>_v1.pdf`, `root_document` = original): search and the UI use its text. The
  version gets its own classifier guess; keep its type equal to the original's or it
  trains the classifier on wrong labels. Unprotected PDFs are left alone.
- **Inbox:** tag `inbox` (`is_inbox_tag`), added to every new document. Review it,
  remove the tag. Dashboard view **Inbox**.
- **Saved views** (owner gooral): dashboard: Inbox, Recently added (14 days),
  Invoices – last 3 months, Bank statements, Contracts & insurance. Sidebar also:
  Home, Car, Travel, Duplicates, Edited in Stirling. Relative dates are fulltext
  queries (`added:[-14 day to now]`), so they depend on the search index.

### OCR of signed PDFs, search index

- `PAPERLESS_OCR_USER_ARGS={"invalidate_digital_signatures": true}`. OCRmyPDF refuses
  digitally signed PDFs (Polish e-government, e-invoices) and Paperless then stores
  them with **no text**. The flag only affects the archive copy; the original keeps a
  valid signature (download "original" for proof). Fix older ones with
  bulk edit → Reprocess.
- Search index (tantivy, `data/index`): if search misses documents that exist, rebuild
  with `docker exec -u paperless ix-paperless-ngx-paperless-1 python3 manage.py document_index reindex`.
  **Always `-u paperless`**: a root run left root-owned 0600 index files, Paperless
  logged "Search index is corrupted or incomplete" and kept ~10 of 100 documents.

## Calling the API as a user without a token

For bulk config (created 2026-11-02 this way), run Django's test client inside the
container via the root channel. Requests go through normal API validation and
objects are owned by that user, and no password or token is needed:

```python
# docker exec -u paperless -i ix-paperless-ngx-paperless-1 python3 manage.py shell <<'PY'
from django.test import Client; from django.contrib.auth.models import User
c = Client(HTTP_HOST="paperless.mati-lab.online", secure=True)
c.force_login(User.objects.get(username="gooral"))
c.get("/api/workflows/", HTTP_ACCEPT="application/json; version=9").json()
# PY
```
Workflow JSON (v9): trigger `{"type": 2|3, "filter_has_document_type": <id>,
"matching_algorithm": 0, "sources": []}` (1 = consumption started, 2 = added,
3 = updated); assignment action `{"type": 1, "assign_storage_path": <id>}`.
The root channel's `/tmp` is **noexec**: the cron command must be `bash /tmp/x.sh`
(a bare path dies with exit 137 and no output).

## Duplicates (3.x default: allow + flag)

Paperless-ngx 3.x does **not** reject duplicates (2.x did). A file whose checksum
matches an existing document is still consumed, a warning is logged, and both get
a **Duplicates** tab (including twins in the trash). Find them all via the document
list's text-filter dropdown → **Duplicates**, or `has_duplicates=true` in the API.
Kept deliberately (decision 2026-11-02): nothing is ever silently dropped.
- Same PDF attached to two emails → two documents; delete the extra after review.
- The same email *can* be fetched twice (re-labelling, overlapping fetches); see
  Gmail → Backfill. The **Duplicates** saved view lists every flagged document.
- **Joint documents** (in both partners' mailboxes): each person gets their own
  copy, flagged as duplicates. This replaces the design's "first wins, then
  share", which assumed 2.x rejection.
- Edited returns from Stirling are different files, so they're separate documents
  (tag `edited-in-stirling`).
- Opt-in rejection: `PAPERLESS_CONSUMER_DELETE_DUPLICATES=true` (duplicate file
  deleted, task fails "Document already exists"). Not used.

## Allegro and other mail noise (2026-11-02)

- **Mail rule excludes** (`filter_attachment_filename_exclude`, case-insensitive
  wildcards): `*z Allegro Pay*, *Projekt umowy Allegro Pay*, Regulamin*Allegro*,
  *Polityka prywatno*ci*`. These are the generic Allegro Pay info sheets, blank
  contract templates, Allegro service regulations and privacy policies. Real
  `Umowa Allegro Pay <nr>` contracts and invoices in the same mail still come in.
  Exclusion is done here, not in the Gmail filter, because Gmail can only drop
  whole mails.
- **Seller terms are kept** ("information from the seller as shown at purchase"; useful
  in a return/warranty dispute): workflow `seller-terms` (order 5, consumption
  started, sources all, filename triggers `*Warunki reklamacji*`,
  `*Warunki odst*pienia*`, `*Informacje o gwarancjach*`, `*wzor_odstapienia*`,
  `*Regulamin_sklepu*`) → type Terms and Conditions + tag `seller-terms`
  (→ folder TaCs).
- Pilot cleanup: 53 existing seller-terms docs reclassified; 32 boilerplate
  docs (+ the fallback test) moved to trash (30-day recovery).

## Ignored dates

`PAPERLESS_IGNORE_DATES` comes from values.conf (`homelab/paperless/ignore-dates`,
comma list; kept out of the repo because it includes a personal date). Contains
`1964-04-23`, a fixed date in every Allegro Pay template that Paperless otherwise
picked as "created" (contracts filed under `1964/`), plus the owner's birth date.
Only affects new consumption; fix existing documents' `created` by hand.
`apply.sh` allows commas in values for this.

## ISO dates are read as year-day-month

With the default `PAPERLESS_DATE_ORDER=DMY`, dateparser reads `2026-11-05` as
11 May 2026, and drops ISO dates whose day is above 12 (the next date in the text
wins, or the consumption date). `YMD` is not a fix: it reads `5.11.2026` as 11 May
and `05.11.26` as 2005. Documents with no parseable date get the consumption date.

2026-11-06: 96 documents corrected through the API (`PATCH created`), found by
"the stored date is absent from the text but its day/month swap is present in ISO
form". 83 of them were housing-administration printouts (`Obciążenie YYYY-MM`,
`Rozliczenie_korekta YYYY-MM`, `Kartoteka YYYY[-n]`), which all carried the print
date; they now use the period in the title (ledgers: year end, or the print date for
the current year). Re-run the check after each backfill batch (followups PL.8).
