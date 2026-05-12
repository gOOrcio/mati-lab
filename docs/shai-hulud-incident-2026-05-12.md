# Shai-Hulud audit — 2026-05-12

Triggered by Mini Shai-Hulud npm worm wave (TeamPCP, 2026-05-11) compromising
170+ npm packages incl. `@tanstack/*` (84 artifacts), `@mistralai/mistralai`,
`@uipath/*`, `@squawk/*`, `@beproduct/*`, `@opensearch-project/opensearch`,
plus PyPI `lightning` 2.6.2/2.6.3, `pytorch-lightning` 2.6.2/2.6.3,
`mistralai` 2.4.6, `guardrails-ai` 0.10.1.

## TL;DR

**No compromise found.** Every host and every user-built container scanned
clean against the full IOC set (poisoned package versions, payload filenames,
persistence units, exfil endpoints, marker strings, suspicious workflows).

The only flagged string ("PUSH UR T3MPRR" marker) appears in the dev box's
own Claude Code session transcript because Claude quoted the IOC during the
audit — false positive.

Client-side hardening applied to dev box and `gitea-runner`. Local registry
proxy recommended but not deployed (see `supply-chain-hardening.md`).

## What was checked

IOC set drawn from StepSecurity, Snyk, Socket.dev, Wiz, JFrog, ReversingLabs,
Datadog Security Labs (Sept 2025 + May 2026 waves):

- 170+ exact `name@version` pairs across npm + PyPI.
- Payload filenames: `router_init.js`, `tanstack_runner.js`,
  `opensearch_init.js`, `router_runtime.js`, `gh-token-monitor.sh`.
- Persistence: `~/.config/systemd/user/gh-token-monitor.service`,
  `~/.claude/router_runtime.js`, `~/.vscode/tasks.json` SessionStart hooks,
  macOS LaunchAgent (n/a on Linux), system-wide `gh-token-monitor` unit.
- Git artifacts: workflows containing `toJSON(secrets)`, commits authored by
  `claude@users.noreply.github.com`, Dune-themed dependabot branch names
  (fremen/sandworm/melange/atreides).
- Net exfil: `git-tanstack.com`, `*.getsession.org`, `api.masscan.cloud`,
  `83.142.209.194` in `/etc/hosts`, shell histories, live connections.
- npm token markers: `IfYouRevokeThisTokenItWillWipeTheComputerOfTheOwner`.
- Marker strings: `PUSH UR T3MPRR`, `A Mini Shai-Hulud has Appeared`.

Scanner: `/tmp/shai-hulud-scan/scan.sh` on dev box (166 lines). Reproducible.

## Host-by-host results

| Host                  | IP             | Coverage method     | npm manifests checked | Findings |
|-----------------------|----------------|---------------------|-----------------------|----------|
| dev-box               | localhost      | local fs scan       | 2879                  | clean (1 false-pos marker — own transcript) |
| network-pi            | 192.168.1.252  | ssh + sudo          | 29                    | clean |
| nas (host)            | 192.168.1.65   | ssh (truenas_admin) | 0 (no sudo)           | clean as-far-as-readable; docker volume contents reached via container exec instead |
| nas containers (×6 user-built) | (NAS)  | docker exec        | 2955 in hermes; 0 in others | clean — `mistralai-2.4.2` installed in hermes (legitimate pre-attack version, **SAFE**; poisoned version is 2.4.6) |
| proxmox (host)        | 192.168.1.184  | ssh root            | 0 (host has no app code) | clean |
| ollama-gpu (VM)       | 192.168.1.48   | ssh + sudo          | 0                     | clean |
| gitea-runner (VM)     | 192.168.1.49   | ssh + sudo          | 1836 (incl all CI build cache) | clean |
| smart-resume (LXC 110) | 192.168.1.200 | pct exec (root)     | 0 (Python-only app)   | clean; no poisoned PyPI installed |
| restorate (LXC 111)   | 192.168.1.203  | pct exec (root)     | 0 (SvelteKit pre-bundled, no `package.json` on disk) | clean |
| sentinel-trader       | 192.168.1.202  | —                   | —                     | **VM does not exist in Proxmox** (`qm list` confirms). Inventory in `compute/sentinel_trader_vm/inventory/hosts.yml` is stale — clean up. |

Raw scan logs: `/tmp/shai-hulud-scan/results-*.log` on dev box.

## What was NOT covered

- **NAS host filesystem** under `/mnt/fast/databases/<app>/_data` — truenas_admin
  lacks read perms on the apps:apps-owned dataset content, and root SSH is
  disabled. Container-internal scans via `docker exec` cover the same files
  from the inside, so this is a coverage equivalence, not a gap. If a paranoid
  recheck is wanted, run the scanner as the `apps` user on NAS.
- **`sentinel-trader` VM** — not deployed (stale inventory).
- **Go modules / Cargo manifests** — these ecosystems weren't hit by
  Shai-Hulud. Scanner skipped them by design.
- **Upstream Docker images** on NAS (jellyfin, sonarr, etc.) — not user-built,
  pulled from official registries. Out of scope for a maintainer-account-takeover
  attack on npm/PyPI.

## Hardening applied

- Dev box (`/home/gooral/`): `~/.npmrc`, `~/.config/pnpm/rc`,
  `~/.config/pip/pip.conf`, `~/.config/uv/uv.toml`.
- `gitea-runner` (`~gitea-runner/`): same 4 files mirrored.
- pnpm gets `minimum-release-age=1440` (24 h) — the single biggest mitigation.
  npm 11.12 lacks native support; recommended `safe-npm` shell wrapper using
  `--before` instead.
- Lifecycle-script blocking left **opt-in** with prominent comments — too
  disruptive to enable by default (breaks esbuild/sharp/bcrypt installs).
- See `supply-chain-hardening.md` for the full rationale and the recommended
  local registry proxy (Nexus on NAS) deploy plan.

## Suggested follow-ups (user decides)

1. **Rotate dev-box credentials anyway** — even though no compromise was
   found, if the dev box did `npm install` *between 2026-05-11 06:00 UTC and
   the npm yank ~12 h later* on any of the listed scopes, treat the tokens
   as paper-thin. Specifically: GitHub PATs in `~/.npmrc` / `~/.config/gh/`,
   AWS keys in `~/.aws/credentials`, any cloud-CLI tokens in `~/.config/`.
2. **Decide on Nexus deployment** — see `supply-chain-hardening.md §2`.
3. **Add osv-scanner to ci-workflows** — single workflow step that fails on
   newly-disclosed advisories matching the lockfile. Cheap, high signal.
4. **Clean up sentinel-trader inventory** if the VM is truly retired.
5. **Re-run the IOC scanner** after the next major npm install on any host.
   Add to a weekly cron on `gitea-runner` for ongoing coverage.

## Reproducing the scan

```bash
# On dev box
SCAN_HOST_LABEL=dev-box /tmp/shai-hulud-scan/scan.sh /home/gooral /root /opt /etc

# On a remote with passwordless sudo (Pi, runner, ollama-gpu)
scp /tmp/shai-hulud-scan/scan.sh <host>:/tmp/scan.sh
ssh <host> 'sudo env SCAN_HOST_LABEL=<host> bash /tmp/scan.sh /home /root /opt /etc /var/lib'

# On Proxmox LXCs
ssh root@192.168.1.184 'pct push <CTID> /tmp/scan.sh /tmp/scan.sh && pct exec <CTID> -- env SCAN_HOST_LABEL=lxc-<CTID> bash /tmp/scan.sh /'
```

The scanner's IOC pattern list at the top of `scan.sh` needs updating per
campaign. Add new poisoned `name@version` pairs to `NPM_PATTERNS` /
`PY_PATTERNS` as advisories drop.

## Sources

- Unit 42 — "Shai-Hulud Worm Compromises npm Ecosystem"
- StepSecurity — "Mini Shai-Hulud Is Back" (May 2026 TanStack write-up + IOC table)
- Snyk — "TanStack npm Packages Hit by Mini Shai-Hulud"
- Wiz — "Shai-Hulud 2.0" + "Mini Shai-Hulud Strikes Again"
- Socket.dev — "TanStack npm Packages Compromised"
- JFrog, ReversingLabs, Datadog Security Labs, Aikido — corroborating IOC dumps
- CISA Alert — Sept 2025 wave
- TheCyberSecGuru — exhaustive `name@version` list (used as scanner ground truth)
