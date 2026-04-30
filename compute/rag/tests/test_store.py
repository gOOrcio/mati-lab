from unittest.mock import MagicMock

from watcher.chunker import Chunk
from watcher.store import VaultStore


def _chunks(n: int = 2) -> list[Chunk]:
    return [
        Chunk(
            chunk_id=f"id{i}",
            path="notes/foo.md",
            heading_path=["Foo", f"Sub {i}"],
            text=f"text {i}",
            tags=["t1"],
        )
        for i in range(n)
    ]


def test_upsert_chunks_calls_qdrant_with_correct_payload():
    client = MagicMock()
    store = VaultStore(client=client, collection="obsidian-vault")
    chs = _chunks(2)
    vecs = [[0.1] * 768, [0.2] * 768]

    store.upsert_chunks(chs, vecs, mtime=1700000000)

    client.upsert.assert_called_once()
    kwargs = client.upsert.call_args.kwargs
    assert kwargs["collection_name"] == "obsidian-vault"
    points = kwargs["points"]
    assert len(points) == 2
    assert points[0].id == "id0"
    assert points[0].vector == [0.1] * 768
    assert points[0].payload["path"] == "notes/foo.md"
    assert points[0].payload["heading_path"] == ["Foo", "Sub 0"]
    assert points[0].payload["text"] == "text 0"
    assert points[0].payload["tags"] == ["t1"]
    assert points[0].payload["mtime"] == 1700000000


def test_delete_by_path_uses_filter():
    client = MagicMock()
    store = VaultStore(client=client, collection="obsidian-vault")

    store.delete_by_path("notes/foo.md")

    client.delete.assert_called_once()
    kwargs = client.delete.call_args.kwargs
    assert kwargs["collection_name"] == "obsidian-vault"
    flt = kwargs["points_selector"]
    assert flt.must[0].key == "path"
    assert flt.must[0].match.value == "notes/foo.md"


def test_upsert_no_chunks_is_noop():
    client = MagicMock()
    store = VaultStore(client=client, collection="obsidian-vault")
    store.upsert_chunks([], [], mtime=0)
    client.upsert.assert_not_called()


def test_known_paths_with_mtime_paginates_and_dedupes():
    client = MagicMock()
    page1 = [
        MagicMock(payload={"path": "a.md", "mtime": 100}),
        MagicMock(payload={"path": "a.md", "mtime": 105}),
        MagicMock(payload={"path": "b.md", "mtime": 200}),
    ]
    page2 = [MagicMock(payload={"path": "c.md", "mtime": 300})]
    client.scroll.side_effect = [(page1, "cursor1"), (page2, None)]
    store = VaultStore(client=client, collection="obsidian-vault")
    out = store.known_paths_with_mtime()
    assert out == {"a.md": 105, "b.md": 200, "c.md": 300}
    assert client.scroll.call_count == 2
