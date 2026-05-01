# Followups Register

A single-pane index of every concrete piece of work that's been **intentionally deferred** out of a phase but is named, scoped, and can be picked up later. Generated 2026-04-30 from a sweep of `docs/superpowers/plans/*.md` and `nas/**/notes.md`.

## How this list stays useful

- **One-line title, one-or-two-line context, source pointer.** Don't re-state the runbook here; that lives in the plan or notes file already. This is an index, not a duplicate.
- **Add a row when you defer something** in a new plan. Reference it as "see followups.md" in the source plan instead of re-pasting the rationale next time.
- **Remove a row when it ships.** If it grew into its own plan, replace the entry with a one-line "→ shipped via `<plan-file>`".
- **Two views in one file.** Rows are grouped by **target phase** (where the work would land) — this is the layout the next-phase planner needs. The "By origin phase" rollup at the top is for retros: "what did Phase N leave behind?"

## By origin phase (rollup)

| Origin | Count | Rows |
|---|---|---|
| Phase 1 (TrueNAS foundation) | 0 | — closed cleanly, foundational |
| Phase 2 (media stack) | 8 | 2.r.1, 2.r.2, 2.r.3, 2.r.4, 2.r.5, 8.1, 8.3 (8.2 shipped Phase 8) |
| Phase 3 (LLM infrastructure) | 1 stays open | 7.1 (LiteLLM Prometheus → Grafana dashboard); 8.5/8.6/8.7/8.8 shipped via Followups Plan A+C |
| Phase 4 (Gitea + CI/CD) | 1 | ∞.1 (7.3 + 8.4 shipped Phase 7+8) |
| Phase 4 follow-up (CI/CD adoption) | 6 | 7.5, 7.6, 4.f.1, 4.f.2, 4.f.3, 4.f.4, 4.f.5, ∞.2 |
| Phase 5 (Obsidian sync) | 1 | ∞.3 — out-of-scope only; nothing real deferred |
| Phase 6 (RAG pipeline) | 3 | 6.x.2, 6.x.3 (6.x.1 + 6.x.4 shipped) |
| Phase 7 (hardening, in flight) | 1 stays + 4 new | 7.5 (madrale 17 manual ruff fixes); NEW 7.x.4 (verify other Kuma push monitors after Caddy fix), 7.x.5 (image-build CI workflows for both MCP servers), 7.x.6 (tighten qBit subnet bypass to docker-bridge only), 7.x.7 (revisit Hermes ${VAR} substitution in headers when upstream fixes). 7.x.1 closed via Followups Plan A. |
| Phase 8 (backups, in flight) | 2 stays open | 8.1 (off-box — accepted risk), 8.3 (Immich pg_dump pending Phase 2). 8.6 shipped via Followups Plan C. |
| (its own future plan) | 1 | Phase 6.2 — code-repo embedding |

## Phase 7 territory — Hardening & Polish

| # | Item | Origin | Source |
|---|---|---|---|
| 7.1 | **LiteLLM Prometheus → Grafana cost/latency dashboard.** `/metrics` is scraped; dashboard not built. | Phase 3 | `docs/superpowers/plans/2026-04-24-phase-3-llm-infrastructure.md:513` |
| 7.2 | ~~**LiteLLM virtual-key scoping for rag-watcher.**~~ → shipped via Phase 7 Tasks 6–9 (see `nas/litellm/notes.md` "Virtual keys"). Required adding a Postgres sidecar to the LiteLLM Custom App. | Phase 6 | `nas/litellm/notes.md` |
| 7.3 | ~~**Proxmox OIDC fix.**~~ → shipped via Phase 7 Task 10 (see `compute/proxmox_host/notes.md` "OIDC integration"). Three-part bug: `username-claim sub` (default) → fixed to `preferred_username`; missing pre-staged ACL → granted Administrator on `/`; root-disk-full → unrelated but masking the real fix. | Phase 4 | `compute/proxmox_host/notes.md` |
| 7.4 | ~~**Promtail on the NAS.**~~ → shipped via Phase 7 Tasks 1–5 (see `nas/promtail/notes.md`). Loki host labels now include `nas`. | Phase 6 | `nas/promtail/notes.md` |
| 7.5 | ~~**Per-repo lint debt** (trailing-spaces, eslint, ruff, gofmt).~~ → mostly shipped via Phase 7 Task 17 (`phase-7-lint-fastpass` branches in `dietly-scraper`, `madrale`, `smart-resume`, `grafana-ntfy-bridge`). Pre-commit + CI lint job added to all four. **Residual:** 17 manual ruff fixes in `madrale` (B904 raise-from + UP038 isinstance tuple); pre-commit `--fix --exit-zero` keeps them off the CI critical path. Hand-edit + remove `--exit-zero` when ready. | Phase 4 follow-up | `~/Projects/madrale` |
| 7.6 | **Token rotation runbook in `nas/gitea/notes.md`** consolidating the per-PAT map (where each lives + what to update on rotation). | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:551-555` |

## Phase 8 territory — NAS Backups & Disaster Recovery

| # | Item | Origin | Source |
|---|---|---|---|
| 8.1 | **Off-box replication** for all NAS datasets. **Explicitly accepted as risk in Phase 8** (no off-box destination — single NAS, no cloud, no rotated USB). The fire / theft / double-disk-death scenarios are documented as data loss in `nas/disaster-rebuild.md`. Revisit if appetite to invest emerges (cheap external drive, rsync.net €30/yr, etc.). | Phase 2 | `nas/disaster-rebuild.md` |
| 8.2 | ~~**Postgres restore drills.**~~ → shipped via Phase 8 Tasks 8–9. Q1 drill ran 2026-04-30 (`nas/restore-drills/q1-postgres.md`); quarterly cadence documented; Q2/Q3/Q4 runbook stubs in place. | Phase 2 | `nas/restore-drills/` |
| 8.3 | **Immich logical `pg_dump`** — stays open. Immich app itself is still deferred (Phase 2 Task 3); when Immich ships, copy the `litellm-pgdump.sh` template + register as a fourth backup cron. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md` |
| 8.4 | ~~**Gitea logical dump.**~~ → shipped via Phase 8 Task 3 (`nas/backup-jobs/gitea-pgdump.sh`). Note: Gitea's catalog app uses Postgres, not SQLite as originally noted in the followup; updated. | Phase 4 | `nas/backup-jobs/notes.md` |
| 8.5 | ~~**LiteLLM backup recipe.**~~ → shipped via Phase 8 Task 4 (`nas/backup-jobs/litellm-pgdump.sh`). | Phase 3 | `nas/backup-jobs/notes.md` |
| 8.6 | ~~**OpenClaw backup recipe**~~ → shipped via Followups Plan Task C, retargeted from OpenClaw to Hermes. Nightly `hermes backup` zip via `docker exec`, gpg AES256 → `bulk/backups/hermes/hermes-<ISO>.zip.gpg`, 14-day retention, Kuma push monitor `backup-hermes-dump`, decrypt-roundtrip verified 2026-05-01, `nas/restore-drills/hermes-restore.md` runbook drafted. | Phase 3 | `nas/backup-jobs/notes.md` |
| 8.7 | ~~**Hermes `memory.db` backup**~~ — superseded by 8.6 closure (Hermes shipped 2026-05-01; logical-zip backup covers `state.db` plus everything else under `/opt/data`). | Phase 3 | (closed) |
| 8.8 | ~~**Hermes `/ping` health probe**~~ — superseded by 8.6 + Kuma HTTP-Keyword monitor on the Hermes dashboard sidecar at `192.168.1.65:30262/`. | Phase 3 | (closed) |

## Phase 7.x — Hardening followups

| # | Item | Origin | Source |
|---|---|---|---|
| 7.x.1 | ~~**OpenClaw cutover to its virtual key.**~~ → shipped via Followups Plan Task A (path A.NAS.1, `2026-04-30-hermes-pivot-followups.md`). Pivoted from OpenClaw to Hermes Agent (Path A.3 from the cleanup plan): OpenClaw `app.delete remove_ix_volumes:true` 2026-05-01 after snapshotting `.openclaw/` to `bulk/backups/openclaw-final-20260430.tar.gz`. Hermes deployed as TrueNAS Custom App (root + gosu drop-priv to 568 with `HERMES_UID=568 HERMES_GID=568`) plus `hermes dashboard --insecure` sidecar exposed at host port 30262 behind Caddy `hermes.mati-lab.online` + Authelia 2FA. LiteLLM virtual key alias renamed `openclaw` → `hermes`. Telegram round-trip + `/sethome` (config in-band edit) verified. | Phase 7 | `nas/hermes/notes.md` |
| 7.x.4 | **Verify other Kuma push monitors flip green** (`backup-litellm-pgdump`, `backup-gitea-pgdump`, `nas-zfs-health`) after the Caddy `/api/push/*` Authelia bypass shipped 2026-05-01. They were silently broken since install (curl `-fsS` treated the 302-to-Authelia as success). After their next scheduled cron run (03:15 / 03:30 / 00:07 UTC), check Kuma; if any are still red, fall back to triggering `cronjob.run <id>` to confirm. | Followups Plan Task 7 | `network/caddy/Caddyfile` |
| 7.x.5 | **Image-build CI workflows** for `vault-rag-mcp`, `qbittorrent-mcp`, and (if ever revived) `hermes-image` custom Dockerfile. Manual trigger (`workflow_dispatch`) plus optional path-based trigger on changes under the respective dirs. Mirror the workflow shape in other Gitea repos. Today: images are built locally on dev box via `docker buildx ... --push`. | Followups Plan Task 6 | `compute/rag/mcp/Dockerfile`, `compute/qbittorrent_mcp/Dockerfile` |
| 7.x.6 | **Tighten qBittorrent subnet bypass to docker-bridge only** (`172.16.0.0/12, 10.0.0.0/8`) — drop `192.168.1.0/24`. Today qBit's "Bypass authentication for clients in whitelisted IP subnets" trusts the entire LAN, which means any compromised LAN device can hit `/api/v2/torrents/add` directly, bypassing the qbit-mcp bearer entirely. Tightening makes the qbit-mcp bearer load-bearing and forces LAN-direct callers (browser at `qbit.mati-lab.online`, ad-hoc curl from a laptop) through Authelia 2FA → admin login. Trigger: more devices on the LAN, IoT VLAN merge, or paranoid posture upgrade. | mcp-bearer-auth-and-qbit branch | `nas/qbittorrent-mcp/notes.md`, `nas/qbittorrent/notes.md` |
| 7.x.7 | **Hermes `${VAR}` substitution inside `headers` blocks** — upstream limitation today (only URL fields interpolate). When upstream fixes, replace literal Bearer values in canonical config.yaml with `${VAULT_RAG_MCP_TOKEN}` / `${QBITTORRENT_MCP_TOKEN}` references reading from Hermes `.env`, removing the duplicate-of-truth between PM, NAS env files, and Hermes config. | mcp-bearer-auth-and-qbit branch | `nas/hermes/config.yaml.example` |

## Phase 6.x — RAG followups (own future plan when batched)

| # | Item | Origin | Source |
|---|---|---|---|
| 6.x.1 | ~~**Deploy `vault-rag-mcp` Custom App**~~ → shipped via Followups Plan Task B (`2026-04-30-hermes-pivot-followups.md`). Image `gitea.mati-lab.online/gooral/vault-rag-mcp:v2` (Dockerfile at `compute/rag/mcp/Dockerfile`, multi-arch); deployed at `http://192.168.1.65:30019/mcp`; Hermes consumes via `mcp_servers.vault-rag.url` in its config.yaml. Note: required a server.py fix to construct FastMCP with the bind host from env BEFORE construction — default-host construction auto-enables DNS-rebinding protection with localhost-only allowlist, rejecting LAN with 421 "Invalid Host header". | Phase 6 | `nas/vault-rag-mcp/notes.md` |
| 6.x.2 | **`--workers N` parallelism flag for `bulk_index.py`.** Sequential is fine for the current vault. Lands in Phase 6.2 once code-repo volumes warrant it. | Phase 6 | `docs/superpowers/plans/2026-04-30-phase-6-rag-pipeline.md:46, 2113`; `nas/rag-watcher/notes.md:75` |
| 6.x.3 | **Cross-encoder reranking.** Only revisit if recall feels weak in real use (top-1 < 0.5). Current empirical: 0.806 on smoke query. | Phase 6 | `docs/superpowers/plans/2026-04-30-phase-6-rag-pipeline.md:2102` |
| 6.x.4 | ~~**Auth on the HTTP MCP**~~ → shipped 2026-05-01. ASGI bearer-token middleware on `vault-rag-mcp:v3` and `qbittorrent-mcp:v1` (same shape — wraps `mcp.streamable_http_app()` only when `MCP_BEARER_TOKEN` env is set; stdio transport unaffected). Tokens stored in PM under `homelab/<service>/bearer-token`. Hermes config holds the literal Bearer value (Hermes's `${VAR}` substitution doesn't fire inside `headers` blocks today; followup if upstream fixes). | Phase 6 | `nas/vault-rag-mcp/notes.md`, `nas/qbittorrent-mcp/notes.md` |

## Phase 6.2 (its own future plan)

→ **Code-repo embedding pipeline.** Separate Qdrant collection (`code-repos`), separate watcher container, tree-sitter chunker, Gitea webhook trigger. Architecture sketched at the end of the Phase 6 plan; lives in `docs/superpowers/plans/<future-date>-phase-6-2-code-repo-rag.md` when written. Reuses `embedder.py` + `store.py` from Phase 6.

Origin: Phase 6. Source: `docs/superpowers/plans/2026-04-30-phase-6-rag-pipeline.md:2106-2139`.

## Phase-4 CI/CD residue (own one-off triggers)

| # | Item | Origin | Source |
|---|---|---|---|
| 4.f.1 | **arm64 runner strategy decision** — Phase 4 follow-up Task 8 is a decision-required gate (Defer / Mac stopgap / dedicated arm64 box). Tasks 9 implementation contingent on the choice. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:423-462` |
| 4.f.2 | **Gitea→ntfy bridge service** (own repo `gooral/gitea-ntfy-bridge`). Trigger: "after a week of MVP if webhook formatting becomes annoying." | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:509-523` |
| 4.f.3 | **`pi-registry-pull` PAT rotation** — currently in use; rotate later if leaked. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:537` |
| 4.f.4 | **`madrale` repo into CI** — explicit opt-out; revisit if PoC promotes. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:46` |
| 4.f.5 | **`actions-replace-make` plan** — separate plan file already drafted at `docs/superpowers/plans/2026-04-29-followup-actions-replace-make.md`; not yet executed. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:601` |

## Phase 2 residue (mostly-Phase-8-shaped)

| # | Item | Origin | Source |
|---|---|---|---|
| 2.r.1 | **Sonarr / Radarr** — Optional / not delivered. Pick up if media library demands automation. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:938` |
| 2.r.2 | **VPN for qBittorrent** (Gluetun pattern documented but not applied). Pick up if ISP/legal posture changes. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:438` |
| 2.r.3 | **qBittorrent incoming-peer port 51413** router/firewall forward — only matters if you want to seed. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:367` |
| 2.r.4 | **Immich + qBittorrent Prometheus exporters** — community exporters exist; not maintained for Phase 2. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:621` |
| 2.r.5 | **Jellyfin HW transcode revisit** if `renderD128` ever appears (currently no iGPU render node). | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:145` |

## Out of scope, no phase named

| # | Item | Origin | Source |
|---|---|---|---|
| ∞.1 | **External GitHub repos not migrated to Gitea** (`kinia_ratings`, `rest-assured-kotlin-taurus`, `kraken-performance`, `vibe-cv-resume`) — explicit "everything in `~/Projects`" rule excluded them. | Phase 4 | `docs/superpowers/plans/2026-04-25-phase-4-gitea-cicd.md:2474` |
| ∞.2 | **Network/infra (`mati-lab`) deploy automation** — too risky for the lockout potential; CI validation only, deploy stays manual. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:39-43` |
| ∞.3 | **Mobile-only / Windows-canonical Obsidian** — Phase 5 assumed Mac-canonical; setting up sync the other way is undocumented. | Phase 5 | `docs/superpowers/plans/2026-04-29-phase-5-obsidian-self-hosted-sync.md:35-36` |
