"""Qdrant upsert/delete operations scoped to a single collection.

Idempotent by chunk_id (sha1). Re-indexing the same file with the same
content yields the same point IDs and overwrites in place. If heading
structure changes, callers must `delete_by_path` first to prune stale IDs.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from qdrant_client import QdrantClient
from qdrant_client.models import (
    FieldCondition,
    Filter,
    MatchValue,
    PointStruct,
)

from .chunker import Chunk


@dataclass
class VaultStore:
    client: QdrantClient
    collection: str

    @classmethod
    def from_env(cls) -> "VaultStore":
        client = QdrantClient(
            url=os.environ["QDRANT_URL"],
            timeout=60,
        )
        return cls(client=client, collection=os.environ.get("QDRANT_COLLECTION", "obsidian-vault"))

    def upsert_chunks(self, chunks: list[Chunk], vectors: list[list[float]], *, mtime: int) -> None:
        if not chunks:
            return
        assert len(chunks) == len(vectors), "chunks and vectors must align"
        points = [
            PointStruct(
                id=c.chunk_id,
                vector=v,
                payload={
                    "path": c.path,
                    "heading_path": c.heading_path,
                    "text": c.text,
                    "tags": c.tags,
                    "mtime": mtime,
                },
            )
            for c, v in zip(chunks, vectors)
        ]
        self.client.upsert(collection_name=self.collection, points=points)

    def delete_by_path(self, path: str) -> None:
        flt = Filter(must=[FieldCondition(key="path", match=MatchValue(value=path))])
        self.client.delete(collection_name=self.collection, points_selector=flt)

    def known_paths_with_mtime(self) -> dict[str, int]:
        """Return {path: max(mtime) over all points with that path}."""
        result: dict[str, int] = {}
        next_offset = None
        while True:
            points, next_offset = self.client.scroll(
                collection_name=self.collection,
                limit=512,
                with_payload=["path", "mtime"],
                with_vectors=False,
                offset=next_offset,
            )
            for p in points:
                payload = p.payload or {}
                path = payload.get("path")
                mtime = int(payload.get("mtime") or 0)
                if path is None:
                    continue
                if mtime > result.get(path, -1):
                    result[path] = mtime
            if next_offset is None:
                break
        return result
