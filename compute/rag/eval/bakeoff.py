"""Phase 6 Task 4 — embedding-model bake-off.

For each candidate LiteLLM model alias:
  - create a temporary Qdrant collection
  - bulk-embed the vault into it
  - run each eval query, score recall@5 (= 1 if expected substring appears
    in any of the top-5 result paths, else 0)
  - report mean recall@5 + median latency per query

Print a sorted summary; pick the highest-recall, lowest-latency one.

Run:
  cd compute/rag
  VAULT_PATH=/path/to/vault \\
  QDRANT_URL=http://192.168.1.65:30017 \\
  LITELLM_BASE_URL=http://192.168.1.65:4000 \\
  LITELLM_API_KEY=sk-... \\
  .venv/bin/python eval/bakeoff.py

If the local box can't see the vault directly, rsync first:
  rsync -a truenas_admin@192.168.1.65:/mnt/bulk/obsidian-vault/ /tmp/vault/
  VAULT_PATH=/tmp/vault ...
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import httpx
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, PointStruct, VectorParams

from watcher.chunker import chunk_markdown

CANDIDATES = [
    ("embed-nomic", 768),
    ("embed-mxbai", 1024),
    ("embed-bge-m3", 1024),
]

VAULT = Path(os.environ["VAULT_PATH"])
QDRANT = QdrantClient(url=os.environ["QDRANT_URL"], timeout=120)
LITELLM = os.environ["LITELLM_BASE_URL"].rstrip("/")
KEY = os.environ["LITELLM_API_KEY"]
QUERIES = json.loads(Path("eval/queries.json").read_text())

SKIP_TOP = {".obsidian", ".trash", ".stversions", ".stfolder"}


def embed_one(model: str, text: str) -> tuple[list[float], float]:
    t0 = time.time()
    r = httpx.post(
        f"{LITELLM}/v1/embeddings",
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
        json={"model": model, "input": text},
        timeout=120,
    )
    r.raise_for_status()
    return r.json()["data"][0]["embedding"], time.time() - t0


def embed_batch(model: str, texts: list[str]) -> list[list[float]]:
    r = httpx.post(
        f"{LITELLM}/v1/embeddings",
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
        json={"model": model, "input": texts},
        timeout=300,
    )
    r.raise_for_status()
    data = sorted(r.json()["data"], key=lambda d: d["index"])
    return [d["embedding"] for d in data]


def index(model: str, dim: int) -> tuple[str, int]:
    coll = f"bakeoff-{model.replace('embed-', '').replace('-', '_')}"
    QDRANT.recreate_collection(
        collection_name=coll,
        vectors_config=VectorParams(size=dim, distance=Distance.COSINE),
    )
    files: list[Path] = []
    for p in VAULT.rglob("*.md"):
        rel_parts = p.relative_to(VAULT).parts
        if rel_parts and rel_parts[0] in SKIP_TOP:
            continue
        if ".sync-conflict-" in p.name:
            continue
        files.append(p)

    points: list[PointStruct] = []
    pid = 0
    for f in files:
        rel = f.relative_to(VAULT)
        chunks = chunk_markdown(f.read_text("utf-8", errors="replace"), path=rel)
        if not chunks:
            continue
        for i in range(0, len(chunks), 16):
            batch = chunks[i : i + 16]
            vecs = embed_batch(model, [c.text for c in batch])
            for c, v in zip(batch, vecs):
                points.append(
                    PointStruct(
                        id=pid,
                        vector=v,
                        payload={"path": c.path, "text": c.text[:200]},
                    )
                )
                pid += 1
    if points:
        QDRANT.upsert(collection_name=coll, points=points)
    return coll, len(points)


def evaluate(model: str, coll: str) -> dict:
    hits = 0
    latencies: list[float] = []
    per_query: list[dict] = []
    for q in QUERIES:
        vec, lat = embed_one(model, q["q"])
        latencies.append(lat)
        results = QDRANT.search(collection_name=coll, query_vector=vec, limit=5)
        paths = [r.payload["path"] for r in results]
        scores = [r.score for r in results]
        hit = any(q["expect_path_substr"] in p for p in paths)
        if hit:
            hits += 1
        per_query.append(
            {
                "q": q["q"],
                "hit": hit,
                "top_score": round(scores[0], 3) if scores else None,
                "top_path": paths[0] if paths else None,
            }
        )
    latencies.sort()
    return {
        "recall@5": hits / len(QUERIES),
        "median_query_latency_s": round(latencies[len(latencies) // 2], 3),
        "per_query": per_query,
    }


def main() -> None:
    rows = []
    for model, dim in CANDIDATES:
        print(f"=== {model} (dim={dim}) ===", flush=True)
        coll, n_points = index(model, dim)
        print(f"indexed {n_points} chunks into {coll}", flush=True)
        m = evaluate(model, coll)
        rows.append({"model": model, "dim": dim, "n_points": n_points, **m})
        print(json.dumps({k: v for k, v in m.items() if k != "per_query"}, indent=2))
        for pq in m["per_query"]:
            mark = "✓" if pq["hit"] else "✗"
            print(f"  {mark} score={pq['top_score']} path={pq['top_path']}  q={pq['q'][:60]}")
        print()

    print("\n=== summary (higher recall first, then lower latency) ===")
    rows.sort(key=lambda r: (-r["recall@5"], r["median_query_latency_s"]))
    for r in rows:
        print(
            f"  {r['model']:14s} dim={r['dim']:4d} "
            f"recall@5={r['recall@5']:.2f} "
            f"median_lat={r['median_query_latency_s']}s  "
            f"chunks={r['n_points']}"
        )


if __name__ == "__main__":
    main()
