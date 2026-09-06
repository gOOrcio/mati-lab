# Claude Code guardrail hooks (dev PC)

Turns three CLAUDE.md *rules* into *enforcement*. Installed 2026-09-06.

## Why here and nowhere else

The dev PC is the only agent host that runs **unsandboxed** with SSH keys to
every box in the lab. Hermes on the NAS needs no equivalent: its container
mounts only `/mnt/fast/databases/hermes/data` (rw) plus a read-only bundle,
has no docker socket, `CapDrop: ALL`, and isn't privileged — the container
boundary already enforces, in the kernel, what a hook would only ask for.
Enforce where the isolation is weakest.

## What is blocked

| Rule | Trigger | Why |
|---|---|---|
| force-push | `git push` + `--force` / `-f` / `--force-with-lease` / `+refspec` | Non-negotiable CLAUDE.md rule. Force does not scrub mirrored history; it only drops others' commits. |
| secret read via shell | `cat/head/tail/less/grep/awk/strings/base64/…` targeting `.env`, `*.key`, `*.pem`, `vault.yml`, `dump-passphrase`, `.backup-env`, `.runner`, `id_ed25519`, token files — including over `ssh` | Closes the documented hole: `.claudeignore` filters the **Read tool only**; Bash bypasses it. |
| push to GitHub | `git push` + `github.com` or a remote named `github` | Repos mirror Gitea→GitHub with **force**; a direct GitHub push is silently reverted on the next Gitea sync (cost a real commit 2026-09-06). |

Deliberately allowed: `sed -E 's/=.*/=<redacted>/'` (list key names safely),
`stat`/`ls` (metadata), `install`/`chmod`/`printf >` (staging a secret),
`curl -H "… $(cat tokenfile)"` (use a credential without echoing it).
This catches accidents, not a determined bypass — that is the intent.

## Wiring

`~/.claude/settings.json` → `hooks.PreToolUse`, matcher `Bash`, alongside the
pre-existing `rtk hook claude` entry (both run; either can block).
Backup of the pre-install file: `~/.claude/settings.json.bak-20260906`.

The command is deliberately wrapped:

```sh
if [ -r "<guard>" ]; then exec python3 "<guard>"; else exit 0; fi
```

**Do not simplify this to a bare `python3 <guard>`.** Python exits with code
**2** when it cannot open a script file — and exit 2 is precisely the
"block" signal. A missing or moved guard would therefore block *every* Bash
call and wedge the agent, with only `python3: can't open file` as the clue.
The `-r` test makes a missing guard fail **open**. Regression-tested.

## Testing

```bash
bash compute/dev_pc/claude-hooks/test-guard-bash.sh   # 41 cases, must be 0 failed
```

The suite weights false positives as heavily as misses: a guard that blocks
legitimate work gets disabled, and then it protects nothing. Add a case to
the ALLOW list whenever a real command trips it.

Hooks load at session start — after editing, restart Claude Code (or start a
new session) for changes to take effect.

## Known interaction: commit messages that quote commands

The guard inspects the whole Bash command string, so a `git commit -m "…"`
whose **message text** quotes a blocked command (e.g. describing a process
listing, or a force-push) is blocked as if it were the real thing. It has no
way to tell prose from intent.

Write such messages to a file and use `git commit -F <file>`. That also
avoids a second trap hit the same day: backticks inside a double-quoted
`-m` string are command-substituted by the shell, which once launched an
interactive interpreter that hung the commit until it timed out.
