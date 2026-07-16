# Dev PC — rtk (Rust Token Killer) setup

One-time setup on the Ubuntu side of the dev PC. Not automated — no
Ansible, no playbooks. Re-run these steps after any Ubuntu reinstall.

## What rtk is (and isn't)

[`rtk`](https://github.com/rtk-ai/rtk) is a single Rust binary that
**compresses command output** (git, `ls`, pytest, docker logs, ~100+
commands) *before it reaches the model's context*. Typical savings
60–90% on shell-heavy turns; `<10 ms` overhead. It hooks into CLI coding
agents so the compression is transparent.

It is **not** a caching proxy, a gateway, or a LiteLLM component. It
operates purely at the client's shell-output layer and never initiates a
command on its own — it only reshapes the output of commands the agent
was already going to run. It is therefore **orthogonal to the LiteLLM
gateway** (see `nas/litellm/`): rtk cuts tokens *per request* on the
client; LiteLLM routes/bills/observes requests on the server.

## Prerequisites

- Homebrew (Linuxbrew) on PATH (`/home/linuxbrew/.linuxbrew/bin/brew`)
- The CLI agents you want to wire: Claude Code, `opencode`, `codex`
  (all already present on this box)

## Install

```bash
brew install rtk          # homebrew-core formula, Apache-2.0
rtk --version             # expect >= 0.43.0
```

`cargo` is absent on this box (only `rustc`), so the `cargo install`
path is out; Homebrew is the clean, verifiable route.

## Wire the agents

Three independent commands — one per agent. **Back up Claude's
`settings.json` first** (rtk also writes its own `.bak`, but keep our
own):

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.pre-rtk.bak
```

### Claude Code — hook-only (deliberate)

```bash
rtk init -g --hook-only --auto-patch
```

This adds **only** a `PreToolUse` hook to `~/.claude/settings.json`:

```json
"hooks": {
  "PreToolUse": [
    { "matcher": "Bash",
      "hooks": [ { "type": "command", "command": "rtk hook claude" } ] }
  ]
}
```

The hook transparently rewrites eligible Bash commands
(`git status` → `rtk git status`, `ls` → `rtk ls`, `pytest` →
`rtk pytest`, …) and passes through excluded ones untouched.

**Why `--hook-only` and not the full `rtk init -g`:** the full install
also injects an `@RTK.md` reference into `~/.claude/CLAUDE.md` (our
curated homelab instructions) and ships an `RTK.md` that nudges the
agent to prefer `rtk read`/`rtk grep` over the native Read/Grep/Glob
tools. That conflicts with Claude Code's "prefer the dedicated
file/search tools" guidance, and the native tools already emit compact,
paginated output — so the marginal saving isn't worth mutating the
global instructions file. The `PreToolUse` hook (Bash-output
compression) is the real, automatic win and needs neither.

> The hook activates on the **next Claude Code restart** — it does not
> affect an already-running session.

### opencode — plugin (global-only)

```bash
rtk init -g --opencode      # writes ~/.config/opencode/plugins/rtk.ts
```

Thin delegating plugin; self-disables with a warning if `rtk` ever
leaves PATH. Restart opencode to load it.

### codex — global instructions (no hook mechanism)

```bash
rtk init -g --codex         # writes ~/.codex/RTK.md + ~/.codex/AGENTS.md
```

Codex has no PreToolUse hook, so rtk can only *instruct* it (via
`~/.codex/AGENTS.md` → `@RTK.md`) to call `rtk` commands proactively.
Weaker than Claude's transparent hook, but the best codex supports.
Uses the **global** codex config dir — does not touch any project repo.

### cursor (opt-in, not done here)

Cursor's rtk integration is **project-scoped** (per-repo config files),
not a global hook, and it's used more as a GUI agent than an autonomous
CLI. Wire it per-project only if wanted:

```bash
cd <project> && rtk init --agent cursor
```

## Safety config — `~/.config/rtk/config.toml`

`brew install` ships no config; `rtk config --create` writes the default
(telemetry already `false`, `tee.mode` already `failures`). The only
change we make is the hooks exclude list:

```toml
[hooks]
# curl is load-bearing in this homelab: API calls, health checks, and JSON we
# parse byte-exact (litellm /health, midclt round-trips via curl, etc.). Never
# let rtk reshape its output. playwright output is consumed by the browser tools.
exclude_commands = ["curl", "playwright"]
transparent_prefixes = []
```

Hard-rule interactions worth stating explicitly:

- **The `.env` / secrets rule is unchanged.** rtk does not weaken "never
  read `.env` via shell." It reshapes output of commands already being
  run; it never initiates a read. The prohibition stands; rtk is not
  relied on for secret safety.
- **`git` is intentionally *not* excluded.** `rtk git diff` was measured
  at 284/299 lines on a real diff (~5% trim) with full hunk fidelity
  (`@@` headers, `+`/`-`, context all intact) — accurate enough to write
  commits from. `git status`/`git log` compaction is harmless. rtk's big
  wins are verbose output (test runners, `ls`, docker logs, builds), not
  git.
- **`tee` writes raw output of *failed* commands** to
  `~/.local/share/rtk/tee/` (local only, failures only) so nothing
  critical (e.g. a pre-push ruff/pytest failure) is truncated away.
  A small on-disk surface; acceptable and noted.

### Telemetry — off, twice

rtk telemetry is opt-in and defaults to disabled (`rtk telemetry status`
shows `consent: never asked`, `enabled: no`; config has
`[telemetry] enabled = false`). Belt-and-suspenders, `~/.zshrc` exports:

```bash
export RTK_TELEMETRY_DISABLED=1
```

## Verify

```bash
rtk init --show            # Hook: configured; OpenCode: plugin installed
rtk --version

# Simulate the Claude hook's rewrite decision for a command:
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | rtk hook claude
#   -> updatedInput.command = "rtk git status", permissionDecision "allow"
echo '{"tool_name":"Bash","tool_input":{"command":"curl -s http://x/health"}}' | rtk hook claude
#   -> no output (passthrough — curl is excluded)

rtk gain                   # running token-savings tally (feeds the Grafana
                           # dashboard in the LiteLLM observability sub-project)
```

## Rotation / updates

```bash
brew upgrade rtk
rtk init --show            # confirm integrations survived the upgrade
```

The agent hooks/plugins reference `rtk` by name on PATH, so an in-place
`brew upgrade` needs no re-init.

## Uninstall / revert

```bash
rtk init -g --hook-only --uninstall     # remove Claude hook
rtk init -g --opencode --uninstall      # remove opencode plugin
rtk init -g --codex --uninstall         # remove codex files
brew uninstall rtk
# and, if needed:
cp ~/.claude/settings.json.pre-rtk.bak ~/.claude/settings.json
```
