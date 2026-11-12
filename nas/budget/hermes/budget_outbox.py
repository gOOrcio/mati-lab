#!/usr/bin/env python3
"""Deliver budget guard messages to Telegram.

Runs as a Hermes cron job in script-only mode (`--no-agent`): whatever this
prints is sent verbatim, and printing nothing sends nothing. budget-worker
writes one text file per message into pending/; delivered files move to sent/
and are pruned after 30 days. No model sees any of it.

The folder is shared with another container, so nothing here follows a
symlink: the directories must be real, and only small regular files are read.
"""
import os
import stat
import sys
import time
from pathlib import Path

MAX_BYTES = 16 * 1024
base = Path(os.environ.get("HERMES_HOME", "/opt/data")) / "budget"
pending, sent = base / "pending", base / "sent"

for d in (base, pending, sent):
    st = os.lstat(d)  # raises if missing: install-guard creates all three
    if not stat.S_ISDIR(st.st_mode):
        sys.exit(f"budget outbox: {d} is not a real directory")


def read_regular(path: Path) -> str | None:
    """Text of a small regular file, or None for anything else."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    with os.fdopen(fd, "rb") as fh:
        st = os.fstat(fh.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_BYTES:
            return None
        return fh.read().decode("utf-8", errors="replace").strip()


messages = []
for name in sorted(os.listdir(pending)):
    if not name.endswith(".md"):
        continue
    src = pending / name
    text = read_regular(src)
    if text is None:
        continue
    os.rename(src, sent / name)
    if text:
        messages.append(text)

cutoff = time.time() - 30 * 86400
for name in os.listdir(sent):
    f = sent / name
    st = os.lstat(f)
    if name.endswith(".md") and stat.S_ISREG(st.st_mode) and st.st_mtime < cutoff:
        os.unlink(f)

if messages:
    print("\n\n".join(messages))
