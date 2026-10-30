# Stirling PDF (NAS)

TrueNAS Scale **catalogue app** `stirling-pdf` (train `community`), serving
`https://pdf.mati-lab.online`. PDF workbench plus each user's *My Files*
working shelf. It is not the archive; the long-term archive will be Paperless-ngx.
Design: `docs/superpowers/specs/2026-10-30-stirling-pdf-design.md` (local only).

## Layout

Dataset `bulk/stirling-pdf` (owned `568:568`, mode 755), all mounts are host paths:

| Host path | Container path | Contents |
|---|---|---|
| `/mnt/bulk/stirling-pdf/storage` | `/storage` | Server-side file storage (*My Files*), `STORAGE_LOCAL_BASEPATH` |
| `/mnt/bulk/stirling-pdf/configs` | `/configs` | `settings.yml` (holds the OIDC client secret), embedded user DB |
| `/mnt/bulk/stirling-pdf/customFiles` | `/customFiles` | Custom static files |
| `/mnt/bulk/stirling-pdf/pipeline` | `/pipeline` | Pipeline watch folders (unused) |
| `/mnt/bulk/stirling-pdf/tessdata` | `/usr/share/tessdata` | Extra OCR languages (`pol`) |
| ixVolume | `/logs` | Disposable; logs also reach Loki via Alloy |

## OCR languages

The image ships `eng osd deu fra por chi_sim` in
`/usr/share/tesseract-ocr/5/tessdata` (`TESS_BASE_PATH`). On start,
`/scripts/init.sh` copies anything mounted at `/usr/share/tessdata` into
that directory (`cp -rn`), so the mount **adds** languages and doesn't hide the
bundled ones. Only `pol` needs seeding:

```bash
# dev PC
curl -fsSL -o pol.traineddata https://github.com/tesseract-ocr/tessdata_fast/raw/main/pol.traineddata
# sha256 c4476cdbc0e33d898d32345122b7be1cbf85ace15f920f06c7714756e1ef79b2 (2026-10-30)
scp pol.traineddata truenas_admin@192.168.1.65:/tmp/
```

`truenas_admin` can't write the `568`-owned dir. Install it as root via the
temp-cron channel: a script doing
`install -o 568 -g 568 -m 644 /tmp/pol.traineddata /mnt/bulk/stirling-pdf/tessdata/`,
run with `cronjob.create` (disabled) → `cronjob.run -j` → `cronjob.delete`.

`tessdata_fast` matches the speed/accuracy class of the Debian-packaged
bundled models.

Verify inside the container: `tesseract --list-langs` lists `pol`; startup log
shows `Found user-mounted tessdata in /usr/share/tessdata, copying ...`.
**Users must tick Polish in the OCR tool.** The default is English only, which
flattens Polish (`ą`→`g`, `ł`→`t`). Verified 2026-10-30 with `pol` ticked:
"Zażółć gęślą jaźń" survives OCR with diacritics intact.

Verification 2026-10-30: share links opened LAN-direct without login return only
the SPA shell, and every `/api/v1/storage/share-links/<token>[/*]` returns 401.
Stored files survive `app.redeploy`.

## Ownership

The container starts as root and `init-without-ocr.sh` chowns `/configs`,
`/customFiles`, `/pipeline`, `/storage`, `/logs` to `stirlingpdfuser`,
remapped by `PUID`/`PGID`. Both are set to `568` so host files stay `apps:apps`.

## Deploy / update

`app-config.json` is the full source of truth. **`app.update` replaces nested
groups**, so always send the whole `values` block, never a partial patch.

```bash
# create (first time)
scp nas/stirling-pdf/app-config.json truenas_admin@192.168.1.65:/tmp/sp.json
ssh truenas_admin@192.168.1.65 'midclt call -j app.create "$(cat /tmp/sp.json)"; rm /tmp/sp.json'
# update (after editing app-config.json)
python3 -c "import json;print(json.dumps({'values':json.load(open('nas/stirling-pdf/app-config.json'))['values']}))" > /tmp/sp-upd.json
scp /tmp/sp-upd.json truenas_admin@192.168.1.65:/tmp/ && ssh truenas_admin@192.168.1.65 'midclt call -j app.update stirling-pdf "$(cat /tmp/sp-upd.json)"; rm /tmp/sp-upd.json'
```

Gotchas:
- Don't put `PUID`/`PGID` in `additional_envs`. The TrueNAS library sets them from
  `run_as` (568) and render-fails on duplicates.
- Settings are Spring relaxed-binding env vars (`SECURITY_OAUTH2_ISSUER` →
  `security.oauth2.issuer`). The full key list is in `settings.yml.template` inside
  `/app/app.jar`. In 3.x, login is on by default; `DOCKER_ENABLE_SECURITY` (form
  toggle) is legacy and harmless.
- `/api/v1/proprietary/ui-data/login` (unauthenticated) shows the effective
  `loginMethod`, `ssoAutoLogin` and `providerList`. Use it to verify auth config.

## Auth (Authelia OIDC)

- Authelia client `stirling-pdf` (`network/authelia/configuration.yml`), redirect
  `https://pdf.mati-lab.online/login/oauth2/code/authelia`.
- The client **secret is not in app env**. It lives in
  `/mnt/bulk/stirling-pdf/configs/custom_settings.yml` (568:568, 0600), Stirling's
  override file, which survives `settings.yml` regeneration on upgrades:
  ```
  read -rs P && printf 'security:\n  oauth2:\n    clientSecret: "%s"\n' "$P" | sudo tee /mnt/bulk/stirling-pdf/configs/custom_settings.yml >/dev/null && sudo chown 568:568 /mnt/bulk/stirling-pdf/configs/custom_settings.yml && sudo chmod 600 /mnt/bulk/stirling-pdf/configs/custom_settings.yml; unset P
  ```
  then `midclt call -j app.redeploy stirling-pdf`. See `nas/secrets-inventory.md`.
- `AUTOCREATEUSER=false` + `BLOCKREGISTRATION=true`: only accounts pre-created in
  Stirling can sign in. `USEASUSERNAME=preferred_username` = Authelia username.
- `SECURITY_LOGINMETHOD=oauth2` + `SECURITY_SSOAUTOLOGIN=true` (since 2026-10-30):
  no password login; the login page goes straight to Authelia. `gooral` is Org Owner.
  The bootstrap local `admin` is suspended (password in PM `homelab/stirling-pdf/admin`).

**Rollback / break-glass** (SSO broken → nobody can log in): set
`SECURITY_LOGINMETHOD=all`, drop `SECURITY_SSOAUTOLOGIN`, `app.update`, then log in
locally (un-suspend `admin` from the DB if needed). For claim debugging, add
`SECURITY_OAUTH2_DEBUGLOGGING=true` temporarily (logs personal data, so remove after).

## Adding the second user

1. Authelia: `cd network && make add-authelia-user` (dev PC), then they enrol
   2FA at `https://authelia.mati-lab.online`.
2. Stirling (as `gooral`): Settings → Workspace → Users → Invite people → Create
   account directly. Username = their Authelia username, sign-in method
   **OAuth2 / SSO**, role User. Free tier = 5 seats; the suspended `admin` may count.
3. They sign in and see an empty *My Files*. Share one file each way to test.
