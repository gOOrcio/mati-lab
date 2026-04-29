# Phase 5 — User-side setup guide

Server-side is fully done (CouchDB, Caddy vhost, snapshots, nightly
dump cron, Syncthing on NAS). What remains needs your hands on the
Mac, iPhone, iPad, and a couple of GUI clicks.

Open `nas/obsidian/notes.md` in this repo for the canonical reference;
this file is the linear "do these in order" checklist.

---

## Credentials in your password manager

You will need (look these up in your password manager — they are
deliberately not in this file):

- CouchDB **admin** password — used rarely, only for config changes.
- CouchDB **livesync** user password — pasted into the obsidian-livesync
  plugin on every device.

> **Why placeholders here:** an earlier draft of this guide had the
> generated values inline; that committed them to git history. The
> values were rotated 2026-04-29; treat any password you might still
> see in `git log -p` as burned. See `notes.md` "Lessons" #7.

---

## 0. First-time Syncthing housekeeping (~30 sec)

On first load Syncthing pre-creates a "Default Folder" pointing at
`/var/syncthing/Sync` and a "permission denied" notice. Delete the
Default Folder entry — we'll add the right one in step 2:

1. Folders panel → Default Folder → ⚙ → **Remove** → confirm.
2. Click the OK on the "permission denied" notice (it's stale; the
   parent dir has been chowned to apps:apps already).

## 1. Syncthing GUI auth on NAS (~2 min)

The Syncthing GUI is exposed at `https://syncthing.mati-lab.online`
behind Authelia 2FA. The raw LAN port `192.168.1.65:30016` is also
listening (Caddy reaches it that way, so we can't bind it to localhost
only without breaking the proxy) — set Syncthing's own GUI password as
defense-in-depth so anyone on LAN can't bypass Authelia.

1. Open `https://syncthing.mati-lab.online` → log in via Authelia.
2. Actions menu (top right) → Settings → GUI tab.
3. Set **GUI Authentication User** + **Password**, save.
4. (Optional) Settings → General → set a friendly **Device Name**,
   e.g. `nas-syncthing`.

NAS device ID for your records:
`FU3YUUS-HAMFNJJ-HJTMPYW-RHFE2PK-ZDYWRUR-ARNJ3OY-SLZJEXK-C2SXTAP`

## 2. Pre-create the Syncthing folder on NAS (~2 min)

In the same GUI:

1. Folders panel → **Add Folder**.
2. Folder Label: `obsidian-vault`. Folder ID: `obsidian-vault`.
3. Folder Path: `/var/syncthing/Sync/obsidian-vault` (the dataset is
   already mounted there).
4. **Advanced tab** → Folder Type → **Receive Only**.
5. **File Versioning** tab → **No File Versioning**.
6. Save. (No remote devices yet — that comes after Mac is up.)

## 3. Install Obsidian + plugins on Mac (~5 min)

```bash
brew install --cask obsidian
brew install --cask syncthing
```

(Both auto-start on login by default; Syncthing GUI lands at
`http://127.0.0.1:8384`.)

1. Open Obsidian → "Create new vault" → choose path
   `~/Documents/Obsidian/notes` (or whatever you want; this becomes
   the canonical greenfield vault).
2. Settings (gear) → Community plugins → **Turn on community plugins**.
3. Browse → search `Self-hosted LiveSync` → **Install** → **Enable**.

## 4. Run the obsidian-livesync setup wizard (Mac, ~3 min)

Settings → Self-hosted LiveSync → **Setup wizard**.

| Field | Value |
|---|---|
| Server Type | `CouchDB` |
| URI | `https://obsidian.mati-lab.online` |
| Username | `livesync` |
| Password | (livesync password from password manager) |
| Database name | `obsidian-vault` |

Click **Test connection** — should report success. The wizard offers
to apply the recommended CouchDB tweaks; **already done** at install,
but re-applying is harmless.

Let it perform the **first sync** (uploads your vault into CouchDB).
For an empty greenfield vault this is instant.

## 5. Generate the setup URI for mobile (~1 min)

Plugin settings → **Setup URI** → "Copy current settings to setup URI".

You get a string starting with `obsidian://setuplivesync?...`.

**SAVE THIS IN YOUR PASSWORD MANAGER.** It contains creds. Do not
paste it into chat or commit it to a repo.

Sanity check: open the URI in a Mac browser — Safari/Chrome should
prompt "Open in Obsidian?" and pre-fill settings if you click yes.

## 6. iPhone setup (~5 min)

1. App Store → install **Obsidian — Connected Notes**.
2. Open Obsidian → **Create new vault** with the SAME name as on Mac.
3. Settings → Community plugins → enable → Browse → install
   **Self-hosted LiveSync** → enable.
4. Open the setup URI you saved in step 5 in Mobile Safari → "Open in
   Obsidian" → confirm.
5. First sync pulls the vault from CouchDB. On a slow connection this
   may take a couple of minutes for a populated vault.

## 7. iPad setup (~3 min)

Same as iPhone, but if you turned on iCloud Drive / Handoff between
your devices, double-check the vault name matches exactly so you don't
end up with two parallel vaults.

## 7b. Linux dev box setup (~3 min)

No Syncthing needed on Linux — only the Mac feeds the plain-file
mirror to NAS. Linux is just another LiveSync peer.

1. Open Obsidian → "Open another vault" / "Create new vault" with
   the **same name** as your Mac vault (matters for plugin sanity
   only; what binds them is the CouchDB DB name).
2. Settings → Community plugins → **Turn on community plugins** →
   Browse → search `Self-hosted LiveSync` → Install → Enable.
3. Settings → Self-hosted LiveSync → **Setup wizard**, manually
   fill (no URI needed if password manager isn't handy):

   | Field | Value |
   |---|---|
   | Server Type | `CouchDB` |
   | URI | `https://obsidian.mati-lab.online` |
   | Username | `livesync` |
   | Password | (livesync password from password manager) |
   | Database name | `obsidian-vault` |

4. Test connection → Apply → first sync downloads vault from CouchDB.

## 8. Sync sanity test (~2 min)

- Create a note on Mac → confirm it appears on iPhone within ~5s.
- Edit on iPhone → confirm the change appears on Mac.
- Take iPhone offline (airplane mode), edit a note, re-enable network
  → confirm change syncs up.
- Edit the same note on Mac + iPhone simultaneously (briefly offline
  on one) → LiveSync should preserve both edits as a conflict.

## 9. Pair Mac Syncthing ↔ NAS Syncthing (~5 min)

Mac Syncthing GUI is at `http://127.0.0.1:8384`.

1. **Mac → Add Remote Device** → paste the NAS device ID
   (`FU3YUUS-...` from the top of this guide). Friendly name: `nas`.
   Save.
2. NAS Syncthing GUI will pop up an "incoming connection" prompt within
   ~30s. Accept it; assign the NAS device a friendly name.
3. **Mac → Add Folder**:
   - Folder Label: `obsidian-vault`
   - Folder ID: `obsidian-vault` (must match the ID you set on NAS)
   - Folder Path: `~/Documents/Obsidian/notes` (or whatever you
     created in step 3)
   - Advanced → Folder Type → **Send Only**
   - Sharing → check **nas**
   - File Versioning → leave default (versioning on Mac is fine; it's
     the canonical store)
   - Save
4. NAS will prompt to accept the share — confirm; the path it offers
   should already match `/var/syncthing/Sync/obsidian-vault`.
5. Wait for first sync. For an empty vault: instant.

## 10. Mac `.stignore` (~1 min)

In `~/Documents/Obsidian/notes` (the vault root) create
`.stignore` with these lines:

```
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache
.trash/
```

This keeps Obsidian's transient UI state out of the NAS mirror so
Phase 6 RAG only ingests your notes.

## 11. Verify NAS sees the .md files (~30 sec)

```bash
ssh truenas_admin@192.168.1.65 'ls /mnt/bulk/obsidian-vault/'
```

You should see your note tree. Empty if you haven't created any notes
yet — that's fine.

## 12. Tell me when you're done

I'll then:
- Flip Phase 5 row in `docs/design/homelab-master-plan.md` to ✅.
- Add any device-side surprises to the "Lessons" section of
  `nas/obsidian/notes.md` (Tasks 9 step 3).
- Note the plain-file vault path for the Phase 6 RAG plan to consume.
- Optionally: drop a Caddy vhost in front of the Syncthing GUI behind
  Authelia — currently it's LAN-IP only, which is fine but inconsistent
  with the rest of the stack.

---

## Cheat-sheet (no fluff)

```text
NAS Syncthing GUI:   https://syncthing.mati-lab.online   (Authelia 2FA)
                     http://192.168.1.65:30016           (LAN backstop, set Syncthing GUI auth)
NAS device ID:       FU3YUUS-HAMFNJJ-HJTMPYW-RHFE2PK-ZDYWRUR-ARNJ3OY-SLZJEXK-C2SXTAP
CouchDB URL:         https://obsidian.mati-lab.online   (LAN/VPN)
CouchDB DB:          obsidian-vault
CouchDB user:        livesync   (password in password manager)
Mac vault path:      ~/Documents/Obsidian/notes
NAS vault path:      /mnt/bulk/obsidian-vault   (Syncthing-managed; receive-only)
```
