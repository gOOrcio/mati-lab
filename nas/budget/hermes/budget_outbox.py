#!/usr/bin/env python3
"""Deliver budget guard messages to Telegram.

Runs as a Hermes cron job in script-only mode (`--no-agent`): whatever this
prints is sent verbatim, and printing nothing sends nothing. budget-worker
writes one text file per message into pending/; delivered files move to sent/
and are pruned after 30 days. No model sees any of it.
"""
import os
import time
from pathlib import Path

base = Path(os.environ.get("HERMES_HOME", "/opt/data")) / "budget"
pending, sent = base / "pending", base / "sent"
sent.mkdir(parents=True, exist_ok=True)

messages = []
for f in sorted(pending.glob("*.md")):
    text = f.read_text(encoding="utf-8").strip()
    f.rename(sent / f.name)
    if text:
        messages.append(text)

cutoff = time.time() - 30 * 86400
for f in sent.glob("*.md"):
    if f.stat().st_mtime < cutoff:
        f.unlink()

if messages:
    print("\n\n".join(messages))
