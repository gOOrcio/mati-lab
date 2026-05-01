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
  MCP_TRANSPORT       stdio  (or `streamable-http` for Hermes / remote)
  MCP_HTTP_HOST       0.0.0.0   (only used when MCP_TRANSPORT=streamable-http)
  MCP_HTTP_PORT       8080      (only used when MCP_TRANSPORT=streamable-http)
  MCP_BEARER_TOKEN    (optional) when set + transport=streamable-http, every
                      HTTP request must carry `Authorization: Bearer <value>`
                      or get 401. Stdio transport is unaffected (subprocess
                      auth is implicit). Unset = open access on the HTTP
                      surface — only safe on a tightly-scoped LAN.

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

# Build FastMCP with the bind host from env at construction time. If we leave
# the default ("127.0.0.1") and then mutate `mcp.settings.host` later, FastMCP
# has already auto-enabled DNS-rebinding protection with a localhost-only
# allowlist (see fastmcp/server.py: `if host in ("127.0.0.1", "localhost",
# "::1")`). Subsequent LAN requests get rejected with 421 "Invalid Host header".
# Reading the env upfront sidesteps that auto-enable for streamable-http.
_HTTP_HOST = os.environ.get("MCP_HTTP_HOST", "127.0.0.1")
_HTTP_PORT = int(os.environ.get("MCP_HTTP_PORT", "8080"))

mcp = FastMCP("vault-rag", host=_HTTP_HOST, port=_HTTP_PORT)
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
    # qdrant-client >= 1.15 removed `search()`; use `query_points()` and
    # unwrap `.points` to get the same list of ScoredPoint objects.
    response = qdrant.query_points(
        collection_name=QDRANT_COLLECTION,
        query=vec,
        limit=limit,
        with_payload=True,
    )
    out: list[dict[str, Any]] = []
    for r in response.points:
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


class _BearerAuthASGI:
    """ASGI middleware enforcing `Authorization: Bearer <token>` on HTTP requests.

    Only wraps the app when `MCP_BEARER_TOKEN` is set. Skips non-HTTP scopes
    (lifespan, websocket) and CORS preflight (OPTIONS) so the MCP transport
    layer can negotiate normally. Constant-time string compare to avoid
    timing oracles on the token.
    """

    def __init__(self, app: Any, token: str) -> None:
        self.app = app
        self._token = token

    async def __call__(self, scope: Any, receive: Any, send: Any) -> None:
        if scope["type"] != "http" or scope.get("method") == "OPTIONS":
            await self.app(scope, receive, send)
            return
        provided = ""
        for name, value in scope.get("headers", []):
            if name == b"authorization":
                provided = value.decode("latin-1", errors="replace")
                break
        expected = f"Bearer {self._token}"
        # secrets.compare_digest avoids leaking length / prefix via timing.
        import secrets

        if not provided or not secrets.compare_digest(provided, expected):
            await send(
                {
                    "type": "http.response.start",
                    "status": 401,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"www-authenticate", b'Bearer realm="vault-rag-mcp"'),
                    ],
                }
            )
            await send(
                {
                    "type": "http.response.body",
                    "body": b'{"error":"unauthorized"}',
                }
            )
            return
        await self.app(scope, receive, send)


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "stdio":
        mcp.run()
    elif transport == "streamable-http":
        # Host + port already wired in via env at FastMCP construction time
        # (see _HTTP_HOST / _HTTP_PORT above) so DNS rebinding protection
        # doesn't auto-latch to localhost-only.
        bearer = os.environ.get("MCP_BEARER_TOKEN")
        if not bearer:
            # Run the default path — no auth wrapper.
            mcp.run(transport="streamable-http")
        else:
            # Wrap the FastMCP ASGI app with bearer-auth, then run via uvicorn.
            # We bypass mcp.run() so we can inject middleware around the app.
            import uvicorn

            inner_app = mcp.streamable_http_app()
            app = _BearerAuthASGI(inner_app, bearer)
            uvicorn.run(app, host=_HTTP_HOST, port=_HTTP_PORT, log_level="info")
    else:
        raise SystemExit(f"unknown MCP_TRANSPORT={transport!r}; expected stdio or streamable-http")
