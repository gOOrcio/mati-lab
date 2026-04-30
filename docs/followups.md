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
| Phase 2 (media stack) | 8 | 2.r.1, 2.r.2, 2.r.3, 2.r.4, 2.r.5, 8.1, 8.2, 8.3 |
| Phase 3 (LLM infrastructure) | 5 | 7.1, 8.5, 8.6, 8.7, 8.8 |
| Phase 4 (Gitea + CI/CD) | 2 | 7.3, 8.4, ∞.1 |
| Phase 4 follow-up (CI/CD adoption) | 6 | 7.5, 7.6, 4.f.1, 4.f.2, 4.f.3, 4.f.4, 4.f.5, ∞.2 |
| Phase 5 (Obsidian sync) | 1 | ∞.3 — out-of-scope only; nothing real deferred |
| Phase 6 (RAG pipeline) | 6 | 7.2, 7.4, 6.x.1, 6.x.2, 6.x.3, 6.x.4 |
| Phase 7 (hardening, in flight) | 1 | 7.x.1 (OpenClaw key cutover deferred) |
| (its own future plan) | 1 | Phase 6.2 — code-repo embedding |

## Phase 7 territory — Hardening & Polish

| # | Item | Origin | Source |
|---|---|---|---|
| 7.1 | **LiteLLM Prometheus → Grafana cost/latency dashboard.** `/metrics` is scraped; dashboard not built. | Phase 3 | `docs/superpowers/plans/2026-04-24-phase-3-llm-infrastructure.md:513` |
| 7.2 | ~~**LiteLLM virtual-key scoping for rag-watcher.**~~ → shipped via Phase 7 Tasks 6–9 (see `nas/litellm/notes.md` "Virtual keys"). Required adding a Postgres sidecar to the LiteLLM Custom App. | Phase 6 | `nas/litellm/notes.md` |
| 7.3 | ~~**Proxmox OIDC fix.**~~ → shipped via Phase 7 Task 10 (see `compute/proxmox_host/notes.md` "OIDC integration"). Three-part bug: `username-claim sub` (default) → fixed to `preferred_username`; missing pre-staged ACL → granted Administrator on `/`; root-disk-full → unrelated but masking the real fix. | Phase 4 | `compute/proxmox_host/notes.md` |
| 7.4 | ~~**Promtail on the NAS.**~~ → shipped via Phase 7 Tasks 1–5 (see `nas/promtail/notes.md`). Loki host labels now include `nas`. | Phase 6 | `nas/promtail/notes.md` |
| 7.5 | **Per-repo lint debt** (trailing-spaces, eslint, ruff, gofmt). CI surfaces; cleanup at the human's pace. | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:44-45` |
| 7.6 | **Token rotation runbook in `nas/gitea/notes.md`** consolidating the per-PAT map (where each lives + what to update on rotation). | Phase 4 follow-up | `docs/superpowers/plans/2026-04-29-cicd-followup-after-phase-4.md:551-555` |

## Phase 8 territory — NAS Backups & Disaster Recovery

| # | Item | Origin | Source |
|---|---|---|---|
| 8.1 | **Off-box replication** for all NAS datasets. ZFS snapshots are the local-rollback down-payment; replication is the "fire / theft / double-disk-death" answer. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:776, 885`; `nas/README.md` |
| 8.2 | **Postgres restore drills** documented per service in the relevant `nas/<service>/notes.md`. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:818` |
| 8.3 | **Immich logical `pg_dump`** to `bulk/backups/immich/` paired with the ZFS snapshot of `bulk/photos` + `bulk/immich-uploads`. | Phase 2 | `docs/superpowers/plans/2026-04-17-phase-2-nas-media-stack.md:348, 760` |
| 8.4 | **Gitea SQLite nightly `.backup` dump** + retention policy. ZFS snapshots already in place; logical dump remaining. | Phase 4 | `nas/gitea/notes.md:133-141` |
| 8.5 | **LiteLLM backup recipe.** Note section reserved; just snapshots of `fast/databases/litellm` are documented today. | Phase 3 | `nas/litellm/notes.md:87` |
| 8.6 | **OpenClaw backup recipe.** Same shape as LiteLLM — note section reserved for Phase 8. | Phase 3 | `nas/openclaw/notes.md:174-181` |
| 8.7 | **Hermes `memory.db` backup** flag. Bot abandoned per memory note, but if revived the location is documented for inclusion. | Phase 3 | `docs/superpowers/plans/2026-04-24-phase-3-llm-infrastructure.md:810-816` |
| 8.8 | **Hermes `/ping` health probe** — no HTTP health endpoint; indirect monitor via cron. Phase 8 concern. | Phase 3 | `docs/superpowers/plans/2026-04-24-phase-3-llm-infrastructure.md:778` |

## Phase 7.x — Hardening followups

| # | Item | Origin | Source |
|---|---|---|---|
| 7.x.1 | **OpenClaw cutover to its virtual key.** Paste-token wrote the new key to `~/.openclaw/openclaw.json` cleanly (sha256 changed, .bak made), but post-restart the gateway hangs at `[gateway] starting...` and Telegram never reconnects. Rollback to `openclaw.json.last-good` also hangs. Need to either (a) re-investigate the hang (likely a non-config issue introduced by the paste-token / secrets-reload flow, possibly a stale lock in `/home/node/.openclaw/devices/` or the pending scope-upgrade approval state); (b) **fresh-install OpenClaw** reusing the existing Telegram bot token (@HermesMatiBot) — straight `app.delete openclaw` then re-onboard with `--secret-input-mode ref --custom-api-key "$OPENCLAW_VKEY"` per the wizard-cli-automation docs; (c) **revive the original Hermes agent** since OpenClaw was already an attempted-replacement-due-to-friction (per `nas/openclaw/notes.md` install lesson "OpenClaw replaces the originally-attempted Hermes Agent install"). The `openclaw` virtual key is already issued in LiteLLM under `homelab/litellm/openclaw`; consumer-side cutover is the only remaining work. App is currently STOPPED on the NAS. | Phase 7 | `nas/openclaw/notes.md`; followup paste-token investigation outside Phase 7 scope |

## Phase 6.x — RAG followups (own future plan when batched)

| # | Item | Origin | Source |
|---|---|---|---|
| 6.x.1 | **Deploy `vault-rag-mcp` Custom App** (streamable-http MCP for OpenClaw on host port 30019). All artefacts already drafted: server supports `MCP_TRANSPORT=streamable-http`, runbook lives in `nas/openclaw/notes.md` "RAG integration (Phase 6)". Just needs Dockerfile + image push + `app.create` + `openclaw mcp set`. | Phase 6 | `nas/openclaw/notes.md:215-271`; `compute/rag/mcp/server.py` |
| 6.x.2 | **`--workers N` parallelism flag for `bulk_index.py`.** Sequential is fine for the current vault. Lands in Phase 6.2 once code-repo volumes warrant it. | Phase 6 | `docs/superpowers/plans/2026-04-30-phase-6-rag-pipeline.md:46, 2113`; `nas/rag-watcher/notes.md:75` |
| 6.x.3 | **Cross-encoder reranking.** Only revisit if recall feels weak in real use (top-1 < 0.5). Current empirical: 0.806 on smoke query. | Phase 6 | `docs/superpowers/plans/2026-04-30-phase-6-rag-pipeline.md:2102` |
| 6.x.4 | **Auth on the HTTP MCP** if/when we expose it beyond LAN. v1 relies on LAN-only port + `mode: host` binding + no Caddy exposure. Bearer-token middleware on FastMCP for the public path. | Phase 6 | `nas/openclaw/notes.md` |

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
