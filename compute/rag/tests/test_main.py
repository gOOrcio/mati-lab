import time
from pathlib import Path

from watcher.main import Debouncer, _should_skip


def test_debouncer_collapses_burst():
    fires: list[str] = []
    d = Debouncer(delay=0.05, on_fire=fires.append)
    d.touch("a.md")
    d.touch("a.md")
    d.touch("a.md")
    time.sleep(0.15)
    assert fires == ["a.md"]


def test_debouncer_separates_distinct_paths():
    fires: list[str] = []
    d = Debouncer(delay=0.05, on_fire=fires.append)
    d.touch("a.md")
    d.touch("b.md")
    time.sleep(0.15)
    assert sorted(fires) == ["a.md", "b.md"]


def test_debouncer_resets_window_on_touch():
    fires: list[str] = []
    d = Debouncer(delay=0.10, on_fire=fires.append)
    d.touch("a.md")
    time.sleep(0.05)
    d.touch("a.md")
    time.sleep(0.07)
    assert fires == []
    time.sleep(0.08)
    assert fires == ["a.md"]


def test_should_skip():
    root = Path("/vault")
    assert _should_skip(root / ".obsidian/workspace.json", root)
    assert _should_skip(root / ".trash/old.md", root)
    assert _should_skip(root / ".stversions/foo.md", root)
    assert _should_skip(root / "notes/foo.sync-conflict-20260429-1234-ABCD.md", root)
    assert not _should_skip(root / "notes/foo.md", root)
    assert not _should_skip(root / "deep/nested/note.md", root)


def test_reconcile_re_indexes_changed_and_deletes_missing(tmp_path):
    """Integration-ish: real filesystem, mocked store + embedder."""
    from unittest.mock import MagicMock

    from watcher.main import reconcile

    (tmp_path / "kept.md").write_text("# Kept\n\nbody")
    (tmp_path / "changed.md").write_text("# Changed\n\nnew body")
    (tmp_path / "new.md").write_text("# New\n\nbody")
    import os as _os
    _os.utime(tmp_path / "kept.md", (1000, 1000))
    _os.utime(tmp_path / "changed.md", (2000, 2000))
    _os.utime(tmp_path / "new.md", (3000, 3000))

    store = MagicMock()
    store.known_paths_with_mtime.return_value = {
        "kept.md": 1000, "changed.md": 1500, "gone.md": 500,
    }
    embedder = MagicMock()
    embedder.embed.return_value = [[0.1] * 768]

    re_indexed, deleted, skipped = reconcile(tmp_path, embedder, store, batch=16)

    assert re_indexed == 2
    assert skipped == 1
    assert deleted == 1
    deleted_paths = {call.args[0] for call in store.delete_by_path.call_args_list}
    assert "gone.md" in deleted_paths
