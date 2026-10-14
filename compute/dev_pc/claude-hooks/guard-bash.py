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
     us a commit on 2026-09-06). The push target is resolved through
     `git remote get-url --push`, so `origin` pointing at GitHub in a repo
     that also has a Gitea remote is caught too. Exception: GitHub repos in
     NON_MIRRORED_GITHUB (no Gitea mirror exists, so nothing reverts them).

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
import os
import re
import shlex
import subprocess
import sys

# Split compound commands so `git push origin main && rm -f x` does not
# trip the force-push rule on rm's -f.
SEGMENT_SPLIT = re.compile(r"(?:\|\||&&|[;\n|])")

GIT_PUSH = re.compile(r"\bgit\b.*\bpush\b", re.I)
FORCE_FLAG = re.compile(r"(--force\b|--force-with-lease\b|(?<![\w-])-f(?=\s|$))", re.I)
PLUS_REFSPEC = re.compile(r"\bpush\b.*\s\+[^\s:]+:", re.I)
GITHUB_TARGET = re.compile(r"(github\.com|\bpush\s+github\b)", re.I)
# Anchored: optional scheme, optional user@, host exactly github.com, then owner/repo and nothing else.
GITHUB_SLUG = re.compile(
    r"^(?:[a-z][a-z0-9+.-]*://)?(?:[^@/\s]+@)?github\.com(?::\d+)?[:/]+([^/\s:]+/[^/\s]+?)(?:\.git)?/?$", re.I)
GITHUB_REF = re.compile(r"\S*github\.com\S*", re.I)
# Flags that change where/how `git push` sends, which the simple parser below does not model.
PUSH_OVERRIDES = re.compile(r"(--repo\b|--push-option\b|(?<![\w-])-o\b|--git-dir\b|\bGIT_DIR=|(?<![\w-])(?-i:-c)\s)", re.I)
GITEA_HOST = "mati-lab.online"

# GitHub repos that are NOT push-mirrored from Gitea: a direct push is the only
# way to update them, and no sync will revert it. Lowercase "owner/repo".
NON_MIRRORED_GITHUB = {
    "wargovsky/portfolio",  # client's repo for kamilpiotrowski.actor (wara-portfolio), 2026-10-14
}

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
    r"credentials\.json|"
    r"/proc/[^/\s]+/(environ|cmdline)"
    r")",
    re.I,
)

# Process listings that print FULL command lines. On this box that reliably
# dumps the Claude Code process, whose --mcp-config embeds a live LiteLLM
# key — exactly how one leaked into a transcript on 2026-09-06. PID-only and
# comm-only forms stay allowed.
# Committed placeholder templates (values are `<from password manager>`), not
# secrets. Stripped before the SECRET_PATH check so reading `.env.example`
# works, while a command that also names the real `.env` still blocks.
ENV_PLACEHOLDER = re.compile(r"\.env\.(example|sample|template|dist)\b", re.I)

PROC_DUMP = re.compile(
    r"(?<![\w./-])(ps\s+(aux|-ef|axww|auxww|aux?ww?)|pgrep\s+(-\w*[al]\w*))",
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

BLOCK_PROC_DUMP = (
    "BLOCKED: process listing that prints full command lines.\n"
    "On this machine that dumps the Claude Code process, whose --mcp-config "
    "carries a live LiteLLM key inline — this is how one leaked into a "
    "transcript on 2026-09-06 (it had to be rotated).\n"
    "Allowed instead: `pgrep -f <pattern>` (PIDs only), "
    "`ps -o pid,etime,comm -p <pid>`, `pidof <name>`, or "
    "`systemctl status <unit>` when you just need to know if something runs."
)

BLOCK_GITHUB_PUSH = (
    "BLOCKED: pushing to GitHub.\n"
    "These repos mirror Gitea -> GitHub, and the mirror FORCE-pushes GitHub on "
    "every Gitea update — so a direct GitHub push is silently reverted on the "
    "next sync (this dropped a real commit on 2026-09-06).\n"
    "Push to Gitea instead: ssh://git@gitea-ssh.mati-lab.online:30009/gooral/<repo>.git "
    "and verify the (push) line with `git remote -v`."
)


def _git(cwd: str, *args: str) -> str:
    out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    return out.stdout.strip() if out.returncode == 0 else ""


def push_target(segment: str, cwd: str):
    """(push URLs, all remotes' URLs) for a `git push` segment, or None if unresolvable."""
    try:
        tokens = shlex.split(segment)
        i = tokens.index("git")
        rest = tokens[i + 1:]
        while rest and rest[0] != "push":
            if rest[0] == "-C" and len(rest) > 1:
                cwd = os.path.join(cwd, rest[1])
                rest = rest[2:]
            else:
                rest = rest[1:]
        args = [t for t in rest[1:] if not t.startswith("-")]
        remote = args[0] if args else ""
        if not remote:
            branch = _git(cwd, "branch", "--show-current")
            remote = (_git(cwd, "config", f"branch.{branch}.pushRemote")
                      or _git(cwd, "config", "remote.pushDefault")
                      or _git(cwd, "config", f"branch.{branch}.remote") or "origin")
        if re.search(r"(://|@|^/|^\.)", remote):
            urls = [remote]
        else:
            urls = _git(cwd, "remote", "get-url", "--push", "--all", remote).splitlines()
        remotes = [u for r in _git(cwd, "remote").split()
                   for u in _git(cwd, "remote", "get-url", "--push", "--all", r).splitlines()]
        return (urls, remotes) if urls else None
    except Exception:
        return None


def _allowlisted(ref: str) -> bool:
    slug = GITHUB_SLUG.match(ref.strip("'\""))
    return bool(slug) and slug.group(1).lower() in NON_MIRRORED_GITHUB


def github_push_blocked(segment: str, cwd: str) -> bool:
    # The old text rule is the floor: anything it blocks stays blocked unless EVERY GitHub
    # reference (in the text and in the resolved push URLs) parses as an allowlisted repo.
    text_hit = bool(GITHUB_TARGET.search(segment))
    if PUSH_OVERRIDES.search(segment):
        return text_hit or bool(re.search(r"github", segment, re.I))  # unmodelled flags: stricter
    target = push_target(segment, cwd) if cwd else None
    if target is None:
        return text_hit  # unresolvable or unmodelled flags: text rule only
    urls, remotes = target
    gh_refs = GITHUB_REF.findall(segment) + [u for u in urls if "github.com" in u.lower()]
    if not gh_refs:
        return text_hit  # e.g. `push github` naming a remote that resolves elsewhere: keep the floor
    if all(_allowlisted(r) for r in gh_refs):
        return False
    # Named GitHub explicitly, or the repo lives on Gitea too (so a mirror may revert it).
    return text_hit or any(GITEA_HOST in r for r in remotes)


def violation(segment: str, cwd: str = ""):
    """Return a block message for this shell segment, or None."""
    is_push = bool(GIT_PUSH.search(segment))

    if is_push and (FORCE_FLAG.search(segment) or PLUS_REFSPEC.search(segment)):
        return BLOCK_FORCE_PUSH

    if is_push and github_push_blocked(segment, cwd):
        return BLOCK_GITHUB_PUSH

    if READERS.search(segment) and SECRET_PATH.search(ENV_PLACEHOLDER.sub("", segment)):
        return BLOCK_SECRET_READ

    if PROC_DUMP.search(segment):
        return BLOCK_PROC_DUMP

    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or ""
        cwd = payload.get("cwd") or os.getcwd()
    except Exception:
        return 0  # fail open: never wedge the agent on a parse error

    if not command:
        return 0

    for segment in SEGMENT_SPLIT.split(command):
        cd = re.match(r"\s*cd\s+(\S+)\s*$", segment)
        if cd:
            cwd = os.path.join(cwd, os.path.expanduser(cd.group(1).strip("'\"")))
            continue
        message = violation(segment, cwd)
        if message:
            sys.stderr.write(message + "\n")
            return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
