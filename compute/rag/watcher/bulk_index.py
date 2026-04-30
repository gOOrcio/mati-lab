"""One-shot bulk index of the entire vault. Force re-embed regardless of mtime.

Run as `python -m watcher.bulk_index`. Use cases: switching embedding model,
schema migration, suspect-corruption recovery. Sequential — fine for current
vault sizes.
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path

from .embedder import Embedder
from .main import _process
from .store import VaultStore

log = logging.getLogger("rag.bulk")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    vault_root = Path(os.environ.get("VAULT_PATH", "/vault")).resolve()
    batch = int(os.environ.get("EMBED_BATCH", "16"))
    embedder = Embedder.from_env()
    store = VaultStore.from_env()

    skip_top = {".obsidian", ".trash", ".stversions", ".stfolder"}
    files: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(vault_root):
        rel = Path(dirpath).relative_to(vault_root)
        first = rel.parts[0] if rel.parts else ""
        if first in skip_top:
            dirnames[:] = []
            continue
        for name in filenames:
            if name.endswith(".md") and ".sync-conflict-" not in name:
                files.append(Path(dirpath) / name)

    log.info("bulk index: %d files under %s", len(files), vault_root)
    started = time.time()
    for i, p in enumerate(files, 1):
        try:
            _process(
                str(p),
                vault_root=vault_root,
                embedder=embedder,
                store=store,
                batch=batch,
            )
        except Exception:
            log.exception("failed: %s", p)
        if i % 25 == 0:
            elapsed = time.time() - started
            log.info("progress: %d/%d (%.1fs elapsed)", i, len(files), elapsed)
    log.info("bulk index done: %d files in %.1fs", len(files), time.time() - started)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
