#!/usr/bin/env python3
"""PreToolUse guard for Claude Code Bash calls on the dev PC.

Turns three CLAUDE.md *rules* into *enforcement*. The rules were advisory
until 2026-09-06; the dev PC is the only agent host that runs unsandboxed
with SSH keys to every box in the lab, so it is the one place where a hook
earns its keep (Hermes is contained by its container boundary instead).

Blocks:
  1. force-push in any form (--force, -f, --force-with-lease, +refspec)
  2. reading secret-shaped files via shell readers (the documented hole:
     .claudeignore filters the Read tool, Bash bypasses it)
  3. git push to GitHub (repos mirror Gitea->GitHub with force; a direct
     GitHub push is silently reverted on the next Gitea sync — this cost
     us a commit on 2026-09-06)

Contract: exit 0 = allow (silent), exit 2 = block with stderr fed back to
the model. Any internal error fails OPEN — a guard that wedges the agent
is worse than the risk it prevents.

Deliberately NOT blocked:
  - `sed`/`stat`/`ls`/`install`/`printf >` against secret paths: these are
    the sanctioned ways to *write* a secret or inspect metadata, and the
    `sed -E 's/=.*/=<redacted>/'` idiom is how key NAMES get listed safely.
  - anything not matching a segment that actually invokes the tool.
This guard catches accidents, not a determined bypass. That is the point.
"""

import json
import re
import sys

# Split compound commands so `git push origin main && rm -f x` does not
# trip the force-push rule on rm's -f.
SEGMENT_SPLIT = re.compile(r"(?:\|\||&&|[;\n|])")

GIT_PUSH = re.compile(r"\bgit\b.*\bpush\b", re.I)
FORCE_FLAG = re.compile(r"(--force\b|--force-with-lease\b|(?<![\w-])-f(?=\s|$))", re.I)
PLUS_REFSPEC = re.compile(r"\bpush\b.*\s\+[^\s:]+:", re.I)
GITHUB_TARGET = re.compile(r"(github\.com|\bpush\s+github\b)", re.I)

READERS = re.compile(
    r"(?<![\w./-])(cat|less|more|head|tail|strings|xxd|od|base64|nl|tac|bat|"
    r"grep|egrep|fgrep|rg|ag|awk)(?![\w./-])",
    re.I,
)
SECRET_PATH = re.compile(
    r"("
    r"/\.env\b|\b\.env\b|\.env\.[\w-]+|"
    r"\.backup-env\b|"
    r"[\w./-]*\.key\b|[\w./-]*\.pem\b|"
    r"id_ed25519|id_rsa|"
    r"vault\.ya?ml|"
    r"dump-passphrase|"
    r"\.runner\b|"
    r"ntfy-token|smtp_password|"
    r"[\w-]*secret[\w-]*\.txt|"
    r"credentials\.json"
    r")",
    re.I,
)

BLOCK_FORCE_PUSH = (
    "BLOCKED: force-push.\n"
    "Rule (CLAUDE.md, non-negotiable): never `git push --force` / "
    "`--force-with-lease` / `-f` / `+refspec`.\n"
    "If a push is rejected as non-fast-forward, the fix is to fetch, inspect "
    "with `git log --oneline HEAD..origin/main`, confirm fast-forward safety "
    "via `git merge-base --is-ancestor`, and push normally — or STOP and ask "
    "the human. A force-push does not scrub mirrored history; it only drops "
    "someone else's commits."
)

BLOCK_SECRET_READ = (
    "BLOCKED: reading a secret-shaped file through the shell.\n"
    "Rule (CLAUDE.md): .claudeignore filters the Read tool only — Bash "
    "bypasses it, so shell reads of .env / *.key / *.pem / vault.yml / "
    "dump-passphrase / .backup-env / .runner are off-limits, including over ssh.\n"
    "Allowed instead: `stat`/`ls` for metadata; `sed -E 's/=.*/=<redacted>/' <file>` "
    "to list key NAMES; use a credential in-process without echoing it "
    "(e.g. `curl -H \"Authorization: Bearer $(cat tokenfile)\"`); or ask the "
    "human to paste the value into a `read -rs` prompt."
)

BLOCK_GITHUB_PUSH = (
    "BLOCKED: pushing to GitHub.\n"
    "These repos mirror Gitea -> GitHub, and the mirror FORCE-pushes GitHub on "
    "every Gitea update — so a direct GitHub push is silently reverted on the "
    "next sync (this dropped a real commit on 2026-09-06).\n"
    "Push to Gitea instead: ssh://git@gitea-ssh.mati-lab.online:30009/gooral/<repo>.git "
    "and verify the (push) line with `git remote -v`."
)


def violation(segment: str):
    """Return a block message for this shell segment, or None."""
    is_push = bool(GIT_PUSH.search(segment))

    if is_push and (FORCE_FLAG.search(segment) or PLUS_REFSPEC.search(segment)):
        return BLOCK_FORCE_PUSH

    if is_push and GITHUB_TARGET.search(segment):
        return BLOCK_GITHUB_PUSH

    if READERS.search(segment) and SECRET_PATH.search(segment):
        return BLOCK_SECRET_READ

    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or ""
    except Exception:
        return 0  # fail open: never wedge the agent on a parse error

    if not command:
        return 0

    for segment in SEGMENT_SPLIT.split(command):
        message = violation(segment)
        if message:
            sys.stderr.write(message + "\n")
            return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
