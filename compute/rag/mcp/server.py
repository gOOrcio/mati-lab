#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "mcp>=1.0",
#     "httpx>=0.27",
#     "qdrant-client>=1.13",
# ]
# ///
"""Read-only MCP server for the homelab Obsidian-vault Qdrant collection.

Why a custom server instead of `mcp-server-qdrant`:
  The official server only supports the `fastembed` provider (local, in-process).
  Our corpus is embedded by `rag-watcher` via LiteLLM → Ollama nomic-embed-text.
  Mixing query-time fastembed with index-time Ollama-nomic puts queries and
  documents in different vector spaces — recall would suffer. This server uses
  the *same* LiteLLM `embeddings` alias the watcher uses, so query and document
  embeddings are produced by the same underlying model and live in the same
  cosine space.

Why a self-contained PEP 723 script:
  Claude Code, OpenCode, OpenClaw all invoke this via `uv run` with deps
  resolved on-the-fly. No package install, no venv setup on the calling side,
  and version pins live next to the code. The `~/.claude/mcp.json` invocation
  is just `uv run /abs/path/to/server.py`.

Configuration via env (caller sets these in `~/.claude/mcp.json`):
  QDRANT_URL          http://192.168.1.65:30017
  QDRANT_COLLECTION   obsidian-vault
  LITELLM_BASE_URL    http://192.168.1.65:4000
  LITELLM_API_KEY     <from password manager>
  LITELLM_EMBED_MODEL embeddings   (LiteLLM alias name; default ok)
  QDRANT_SEARCH_LIMIT 5            (default top-k)

Tools exposed (read-only by design — no `store`/`upsert`/`delete`):
  vault_search(query, limit?)  Vector search over the Obsidian-vault collection.
"""

from __future__ import annotations

import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP
from qdrant_client import QdrantClient


def _env(key: str, default: str | None = None) -> str:
    val = os.environ.get(key, default)
    if val is None:
        raise RuntimeError(f"missing required env var: {key}")
    return val


QDRANT_URL = _env("QDRANT_URL")
QDRANT_COLLECTION = _env("QDRANT_COLLECTION", "obsidian-vault")
LITELLM_BASE_URL = _env("LITELLM_BASE_URL").rstrip("/")
LITELLM_API_KEY = _env("LITELLM_API_KEY")
LITELLM_EMBED_MODEL = _env("LITELLM_EMBED_MODEL", "embeddings")
DEFAULT_LIMIT = int(_env("QDRANT_SEARCH_LIMIT", "5"))

mcp = FastMCP("vault-rag")
qdrant = QdrantClient(url=QDRANT_URL, timeout=30)


def _embed(text: str) -> list[float]:
    r = httpx.post(
        f"{LITELLM_BASE_URL}/v1/embeddings",
        headers={
            "Authorization": f"Bearer {LITELLM_API_KEY}",
            "Content-Type": "application/json",
        },
        json={"model": LITELLM_EMBED_MODEL, "input": text},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["data"][0]["embedding"]


@mcp.tool()
def vault_search(query: str, limit: int = DEFAULT_LIMIT) -> list[dict[str, Any]]:
    """Search the Obsidian vault by semantic similarity.

    Returns the top-N matching chunks with their source path, heading
    breadcrumb, full text, similarity score, and any frontmatter tags.
    Use this whenever the user asks about something that might be in
    their notes — homelab config, project decisions, lessons-learned
    entries, research notes, etc. — before falling back to web search.

    Args:
        query: Natural-language question or phrase. Embedded with the same
               model used to index the corpus (LiteLLM `embeddings` alias →
               Ollama nomic-embed-text by default).
        limit: Max number of results (default 5; clamp 1..50).
    """
    limit = max(1, min(50, int(limit)))
    vec = _embed(query)
    results = qdrant.search(
        collection_name=QDRANT_COLLECTION,
        query_vector=vec,
        limit=limit,
        with_payload=True,
    )
    out: list[dict[str, Any]] = []
    for r in results:
        p = r.payload or {}
        out.append(
            {
                "score": round(float(r.score), 4),
                "path": p.get("path"),
                "heading_path": p.get("heading_path", []),
                "tags": p.get("tags", []),
                "text": p.get("text", ""),
            }
        )
    return out


if __name__ == "__main__":
    mcp.run()
