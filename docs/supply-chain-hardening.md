# Supply-chain hardening (post-Shai-Hulud)

Triggered by the Mini Shai-Hulud worm (2026-05-11) that compromised 170+ npm
packages (TanStack, Mistral AI client, UiPath, Squawk, …) and 4 PyPI packages
(lightning, pytorch-lightning, mistralai, guardrails-ai). See attack write-ups
linked from the IOC scan output at `/tmp/shai-hulud-scan/` on the dev box.

This doc captures the two layers of defence:

1. **Client-side knobs** on every machine that runs `npm`/`pnpm`/`pip`/`uv` —
   primarily the dev box and `gitea-runner`. Already applied; documented here
   so the settings can be reproduced from scratch.
2. **A local proxying registry** as a single chokepoint — recommended, not yet
   deployed. Decision matrix below.

## 1. Client-side hardening (already applied)

### Threat model

Every Shai-Hulud variant follows the same pattern: a compromised maintainer
account publishes a malicious version of a popular package; `npm install` runs
its `postinstall` lifecycle script; the script harvests `~/.npmrc`,
`~/.aws/credentials`, `~/.ssh/id_*`, then republishes itself through whatever
other packages it can reach. The worm gets noticed and yanked within hours
(Sept 2025: ~12 h, May 2026: ~6 h). So the single biggest defence is **don't
install a version younger than the detection window**.

### npm (`~/.npmrc`)

Stock npm 11.x has *no* native `minimum-release-age`. The closest knob is
`--before <date>`, which is fixed not rolling. Two workarounds:

- **Shell wrapper** (preferred for interactive use): `safe-npm` alias that
  injects `--before` set to `now - 24h`. Add to `~/.zshrc`:

  ```bash
  safe-npm() {
    npm "$@" --before "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  }
  ```

- **Prefer pnpm**: pnpm 10+ honours `minimum-release-age=1440` natively (and
  blocks lifecycle scripts by default, with an `onlyBuiltDependencies` +
  `allowBuilds` allow-list in `pnpm-workspace.yaml`). Migrate npm and yarn
  projects to pnpm. **Bun stays bun** — speed > the gap, mitigated by the
  registry mirror layer (§2 below).

The committed `~/.npmrc` keeps `package-lock=true`, `audit-level=moderate`,
`fund=false`, and an opt-in commented-out `ignore-scripts=true`.

### pnpm (`~/.config/pnpm/rc` and `~/.npmrc`)

```
minimum-release-age=4320   # 3 days
verify-store-integrity=true
audit-level=moderate
```

**Do NOT** set `ignore-scripts=true` globally — it overrides the per-project
allow-list and silently breaks legit native builds (esbuild, sharp). pnpm 10+
is secure-by-default: no scripts run unless explicitly approved per package.

Per-project, when a package legitimately needs build scripts, in
`pnpm-workspace.yaml` (NOT `package.json` — pnpm 11 stopped honouring the
legacy `pnpm.onlyBuiltDependencies` block reliably):

```yaml
# pnpm-workspace.yaml
onlyBuiltDependencies:
  - esbuild
  - sharp
  - better-sqlite3

allowBuilds:
  esbuild: true
  sharp: true
  better-sqlite3: true
```

`onlyBuiltDependencies` declares the candidate list; `allowBuilds` opts each
one in. The CLI `pnpm approve-builds` writes the `allowBuilds` entries via an
interactive checklist.

### yarn

Yarn 1.x (Classic) has no min-release-age. Yarn 4 / Berry needs a plugin
(unofficial). Recommendation: **migrate yarn projects to pnpm**. The
conversion is a one-liner: `pnpm import` reads `yarn.lock` and produces
`pnpm-lock.yaml` preserving the resolved versions. After migrating, also:

- Delete `yarn.lock`.
- Add `pnpm-workspace.yaml` with allow-lists for any native-build deps
  (otherwise `pnpm install` will fail with `[ERR_PNPM_IGNORED_BUILDS]`).
- Update Dockerfile: `corepack enable && corepack prepare pnpm@11 --activate`
  then `pnpm install --frozen-lockfile`.
- Update CI: add `pnpm/action-setup@v3`, switch `cache: yarn` → `cache: pnpm`.

### bun

Bun has no min-release-age yet. The user keeps bun for resto-rate (speed
trade-off accepted) — mitigation is the local registry mirror (§2 below) which
filters at the proxy layer, plus `bun install --frozen-lockfile` always in CI
so the resolved tree only changes when the lockfile changes. Audit bun.lock by
hand on every bump until upstream lands native support.

### pip (`~/.config/pip/pip.conf`)

pip has no min-release-age. Mitigations:

- `require-virtualenv = true` (committed) — prevents accidental global install.
- Use `pip install --require-hashes -r requirements.lock` in CI (lockfiles
  generated with `pip-compile --generate-hashes`).
- Run `pip-audit -r requirements.lock` after every install.

### uv (`~/.config/uv/uv.toml`)

uv has `--exclude-newer <timestamp>`, fixed not rolling. Shell wrapper:

```bash
safe-uv() {
  uv "$@" --exclude-newer "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
}
```

For `uv add` / `uv pip install` against a `pyproject.toml`, set in the project:

```toml
[tool.uv]
exclude-newer = "2026-05-10T00:00:00Z"
```

(update periodically).

### gitea-runner

Same configs need to live on `192.168.1.49` (gitea-runner VM). The runner pulls
the same `~/.npmrc` if installed under its user. Propagate via:

```bash
scp ~/.npmrc gitea-runner@192.168.1.49:~
scp ~/.config/pnpm/rc gitea-runner@192.168.1.49:~/.config/pnpm/rc
```

Plus add an `osv-scanner` / `socket scan` step to every CI workflow in
`~/Projects/ci-workflows` so lockfile drift trips a build BEFORE deps land on
the runner host (and from there into a published image).

## 2. Local proxying registry (recommended; not yet deployed)

### Why bother

The client-side `minimum-release-age` only protects the **direct user** of
`npm`/`pnpm`. A proxy chokepoint adds:

- One enforcement surface for every machine on the LAN (dev box, runner, future
  hosts) — no risk of a new machine being misconfigured.
- **Cache** — survives upstream yanks (a worm that's been pulled is still
  served from cache as long as you don't re-resolve).
- **Audit log** of every package pulled.
- **Allow/block lists** — pin to a known-good scope set; refuse everything else.
- Closes a CI race where `gitea-runner` hits upstream before client config is
  honoured (e.g. a stale runner image without `~/.npmrc`).

### Decision matrix

| Tool                 | Formats              | RAM   | Min-age filtering | Quarantine | Notes |
|----------------------|----------------------|-------|--------------------|------------|-------|
| **Nexus Repo OSS**   | npm, PyPI, Docker, Maven, Helm, … | ~1.5 GB | No (paid add-on)   | Manual via groovy script / cleanup task | One tool replaces the existing `network/registry-mirror`. Heavy. Best long-term consolidation play. |
| **Verdaccio**        | npm only             | ~150 MB | No (plugin: `verdaccio-audit`) | Manual (delete from storage) | Lightweight, easy compose. Pair with devpi for Python. |
| **devpi-server**     | PyPI only            | ~200 MB | No (mirror filter via index inheritance) | Yes (block index) | The standard for self-hosted PyPI proxy. |
| **JFrog Artifactory CE** | npm, Maven      | ~2 GB  | No                 | No         | CE is too restricted; only worth it for paid. Skip. |
| **Existing `network/registry-mirror`** | Docker Hub only | ~50 MB | n/a              | n/a        | Already on Pi. Keep or fold into Nexus. |

### Recommendation: Nexus Repository OSS on NAS

Reasoning:

- NAS has the RAM headroom; Pi does not (it already runs Caddy, Authelia,
  Grafana, Loki, Prometheus, Pi-hole, …).
- Replaces the single-purpose `network/registry-mirror` with one box that
  proxies npm + PyPI + Docker, all under the same auth and audit log. Fewer
  moving parts long-term.
- Native Docker image: `sonatype/nexus3:latest`. Runs as TrueNAS Custom App.
  Bind-mount `/nexus-data` to `/mnt/fast/databases/nexus/` (chown 200:200).
- Front it with `nexus.mati-lab.online` on Caddy (Pi), behind Authelia for the
  admin UI (`/`) but open for read traffic from the LAN.

If Nexus feels too heavy or its UI a turn-off, **fallback**: Verdaccio +
devpi-server as two separate Custom Apps. Lighter, but two more things to
operate. Both fit the existing pattern in `nas/`.

### What Nexus does *not* solve

- A poisoned package that pre-dates your release-age window still gets cached
  and served. Quarantine without paid IQ Server is manual: a nightly cron that
  queries `osv-dev` for new advisories and yanks matching versions from the
  proxy.
- Compromised maintainer accounts publishing to a *fresh* scope you've never
  used still get through if your allow-list isn't tight.

So the proxy is necessary but not sufficient. The full picture is:

```
client (.npmrc min-age) --> Nexus (cache + audit + allow-list) --> upstream
                                  ^
                          nightly osv-scanner cron yanks newly-disclosed CVEs
```

### Deploy plan (when ready)

1. `nas/nexus/` — new Custom App dir following the existing `nas/<svc>/`
   convention (Phase-style ix-chart values + `notes.md`).
2. `network/caddy/Caddyfile` — add `nexus.mati-lab.online` vhost, Authelia on
   the admin path, raw proxy for `/repository/*`.
3. Migrate `~/Projects/ci-workflows` actions to set
   `npm_config_registry=https://nexus.mati-lab.online/repository/npm-proxy/`
   and `PIP_INDEX_URL=https://nexus.mati-lab.online/repository/pypi-proxy/simple/`.
4. Update `compute/gitea_runner_vm/` cloud-init / ansible to drop `~/.npmrc`
   pointing at the proxy.
5. Decommission `network/registry-mirror` once Nexus' docker-proxy is verified.

Track this as a phase in `docs/design/homelab-master-plan.md`.

## Aftercare

- Re-run the IOC scanner (`/tmp/shai-hulud-scan/scan.sh`) on every host after
  each major package install or after npm publishes a new "everything pulled"
  advisory.
- The scanner pattern list at the top of `scan.sh` needs updating per
  campaign — keep adding to it as new variants land.
