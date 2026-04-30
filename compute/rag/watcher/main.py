"""Watchdog event loop: chunk -> embed -> upsert.

Run as `python -m watcher.main`. Reads config from env:

  VAULT_PATH        : root dir to watch (default /vault)
  QDRANT_URL        : http://192.168.1.65:30017
  QDRANT_COLLECTION : obsidian-vault
  LITELLM_BASE_URL  : http://192.168.1.65:4000
  LITELLM_API_KEY   : sk-...
  DEBOUNCE_SECONDS  : seconds to coalesce bursty saves (default 5)
  EMBED_BATCH       : chunks per /v1/embeddings call (default 16)
  SKIP_RECONCILE    : 1/true/yes to skip startup reconciliation
"""

from __future__ import annotations

import logging
import os
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from .chunker import chunk_markdown
from .embedder import Embedder
from .store import VaultStore

log = logging.getLogger("rag.watcher")


@dataclass
class Debouncer:
    delay: float
    on_fire: Callable[[str], None]
    _timers: dict[str, threading.Timer] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def touch(self, key: str) -> None:
        with self._lock:
            t = self._timers.pop(key, None)
            if t is not None:
                t.cancel()
            t = threading.Timer(self.delay, self._fire, args=(key,))
            self._timers[key] = t
            t.start()

    def _fire(self, key: str) -> None:
        with self._lock:
            self._timers.pop(key, None)
        try:
            self.on_fire(key)
        except Exception:
            log.exception("on_fire failed for %s", key)


SKIP_TOP_DIRS = {".obsidian", ".trash", ".stversions", ".stfolder"}


def _should_skip(abs_path: Path, vault_root: Path) -> bool:
    """Skip Obsidian state, Syncthing artifacts, and `*.sync-conflict-*` copies."""
    rel = abs_path.relative_to(vault_root)
    first = rel.parts[0] if rel.parts else ""
    if first in SKIP_TOP_DIRS:
        return True
    if ".sync-conflict-" in abs_path.name:
        return True
    return False


class _Handler(FileSystemEventHandler):
    def __init__(self, debouncer: Debouncer, vault_root: Path):
        self.deb = debouncer
        self.vault_root = vault_root

    def on_modified(self, event: FileSystemEvent) -> None:
        self._maybe(event)

    def on_created(self, event: FileSystemEvent) -> None:
        self._maybe(event)

    def on_moved(self, event: FileSystemEvent) -> None:
        if not event.is_directory and event.src_path.endswith(".md"):
            self.deb.touch(f"DELETE::{event.src_path}")
        self._maybe(event)

    def on_deleted(self, event: FileSystemEvent) -> None:
        if not event.is_directory and event.src_path.endswith(".md"):
            self.deb.touch(f"DELETE::{event.src_path}")

    def _maybe(self, event: FileSystemEvent) -> None:
        target = getattr(event, "dest_path", "") or event.src_path
        if event.is_directory or not target.endswith(".md"):
            return
        if _should_skip(Path(target), self.vault_root):
            return
        self.deb.touch(target)


def _process(
    key: str,
    *,
    vault_root: Path,
    embedder: Embedder,
    store: VaultStore,
    batch: int,
) -> None:
    if key.startswith("DELETE::"):
        path = key[len("DELETE::") :]
        rel = Path(path).relative_to(vault_root).as_posix()
        log.info("delete %s", rel)
        store.delete_by_path(rel)
        return

    abs_path = Path(key)
    if not abs_path.exists():
        return  # raced with delete; the DELETE event will arrive
    rel = abs_path.relative_to(vault_root)
    text = abs_path.read_text(encoding="utf-8", errors="replace")
    chunks = chunk_markdown(text, path=rel)
    if not chunks:
        log.info("skip %s (no chunks)", rel)
        store.delete_by_path(rel.as_posix())
        return

    log.info("index %s -> %d chunks", rel, len(chunks))
    vectors: list[list[float]] = []
    for i in range(0, len(chunks), batch):
        sl = chunks[i : i + batch]
        vectors.extend(embedder.embed([c.text for c in sl]))

    mtime = int(abs_path.stat().st_mtime)
    store.delete_by_path(rel.as_posix())
    store.upsert_chunks(chunks, vectors, mtime=mtime)


def reconcile(
    vault_root: Path, embedder: Embedder, store: VaultStore, batch: int
) -> tuple[int, int, int]:
    """Walk vault, re-index changed files, delete points for missing files.

    Returns (re_indexed, deleted, skipped).
    """
    log.info("reconcile: starting")
    known = store.known_paths_with_mtime()
    on_disk: dict[str, int] = {}
    for p in vault_root.rglob("*.md"):
        if _should_skip(p, vault_root):
            continue
        rel = p.relative_to(vault_root).as_posix()
        on_disk[rel] = int(p.stat().st_mtime)

    re_indexed = skipped = 0
    for rel, disk_mtime in on_disk.items():
        stored_mtime = known.get(rel, -1)
        if disk_mtime > stored_mtime:
            _process(
                str(vault_root / rel),
                vault_root=vault_root,
                embedder=embedder,
                store=store,
                batch=batch,
            )
            re_indexed += 1
        else:
            skipped += 1

    missing_paths = set(known.keys()) - set(on_disk.keys())
    for rel in missing_paths:
        log.info("reconcile: deleting orphaned points for %s", rel)
        store.delete_by_path(rel)

    log.info(
        "reconcile: re_indexed=%d skipped=%d deleted=%d",
        re_indexed, skipped, len(missing_paths),
    )
    return re_indexed, len(missing_paths), skipped


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    vault_root = Path(os.environ.get("VAULT_PATH", "/vault")).resolve()
    debounce = float(os.environ.get("DEBOUNCE_SECONDS", "5"))
    batch = int(os.environ.get("EMBED_BATCH", "16"))
    skip_reconcile = os.environ.get("SKIP_RECONCILE", "").lower() in {"1", "true", "yes"}
    embedder = Embedder.from_env()
    store = VaultStore.from_env()

    if skip_reconcile:
        log.info("reconcile: skipped (SKIP_RECONCILE set)")
    else:
        reconcile(vault_root, embedder, store, batch)

    def fire(key: str) -> None:
        _process(key, vault_root=vault_root, embedder=embedder, store=store, batch=batch)

    deb = Debouncer(delay=debounce, on_fire=fire)
    handler = _Handler(deb, vault_root)
    observer = Observer()
    observer.schedule(handler, str(vault_root), recursive=True)
    observer.start()
    log.info("watching %s (debounce=%.1fs)", vault_root, debounce)
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
