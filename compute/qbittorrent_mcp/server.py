#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "mcp>=1.0",
#     "httpx>=0.27",
# ]
# ///
"""MCP server fronting the homelab qBittorrent Web UI API.

Why a custom server:
  qBittorrent's API is REST + session-cookie auth. Wrapping it in MCP gives
  Hermes (and any other MCP client) clean tool calls — `qbit_add_magnet(url,
  category)` vs the raw `POST /api/v2/torrents/add` + cookie dance + URL
  encoding it would otherwise have to remember every time. Same shape as
  vault-rag-mcp.

Why no auth dance here:
  qBittorrent's "Bypass authentication for clients in whitelisted IP subnets"
  is enabled for the LAN + docker bridges, so HTTP requests from this MCP
  container land at qBit without needing a session cookie. The MCP server
  protects ITSELF with bearer auth (MCP_BEARER_TOKEN env), so attackers on
  LAN can't talk to qBit-via-MCP without the bearer.

Configuration via env:
  QBIT_BASE_URL       http://192.168.1.65:30024
  MCP_TRANSPORT       stdio  (or `streamable-http` for Hermes / remote)
  MCP_HTTP_HOST       0.0.0.0
  MCP_HTTP_PORT       8080
  MCP_BEARER_TOKEN    (optional) when set + transport=streamable-http,
                      every HTTP request to THIS server must carry
                      `Authorization: Bearer <value>` or get 401.

Tools exposed:
  qbit_add_magnet(magnet, category?, save_path?, paused?)
  qbit_list(filter?, category?, sort?, limit?)
  qbit_get(hash)
  qbit_pause(hashes)
  qbit_resume(hashes)
  qbit_delete(hashes, delete_files?)
  qbit_categories()
"""

from __future__ import annotations

import os
import secrets
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP


def _env(key: str, default: str | None = None) -> str:
    val = os.environ.get(key, default)
    if val is None:
        raise RuntimeError(f"missing required env var: {key}")
    return val


QBIT_BASE = _env("QBIT_BASE_URL").rstrip("/")
_HTTP_HOST = os.environ.get("MCP_HTTP_HOST", "127.0.0.1")
_HTTP_PORT = int(os.environ.get("MCP_HTTP_PORT", "8080"))

mcp = FastMCP("qbittorrent", host=_HTTP_HOST, port=_HTTP_PORT)


def _client() -> httpx.Client:
    # New client per call — keeps the file simple and stateless. qBit's API
    # responses are small; no benefit from connection-keep-alive at our
    # request rate (a few per minute at most).
    return httpx.Client(timeout=15)


def _post_form(path: str, data: dict[str, Any] | None = None) -> httpx.Response:
    with _client() as c:
        r = c.post(f"{QBIT_BASE}{path}", data=data or {})
        r.raise_for_status()
        return r


def _get_json(path: str, params: dict[str, Any] | None = None) -> Any:
    with _client() as c:
        r = c.get(f"{QBIT_BASE}{path}", params=params or {})
        r.raise_for_status()
        return r.json()


@mcp.tool()
def qbit_add_magnet(
    magnet: str,
    category: str | None = None,
    save_path: str | None = None,
    paused: bool = False,
) -> dict[str, Any]:
    """Queue a magnet link for download in qBittorrent.

    Pass either a `magnet:?xt=urn:btih:...` URI or any HTTP(S) URL pointing
    at a `.torrent` file. Optionally tag with a category (e.g., "tv",
    "movies") and override the default save path. Returns a status dict
    with a hint about how to find the torrent in `qbit_list`.

    qBittorrent's `/api/v2/torrents/add` doesn't return the new torrent's
    hash directly — qBit accepts the request, then resolves the magnet
    asynchronously. Call `qbit_list` after a few seconds to confirm.

    Args:
        magnet: Magnet URI or HTTP URL of a .torrent file.
        category: Optional category. Must already exist in qBit.
        save_path: Optional override for the destination directory.
        paused: If True, add the torrent in paused state (don't auto-start).
    """
    data: dict[str, Any] = {"urls": magnet}
    if category:
        data["category"] = category
    if save_path:
        data["savepath"] = save_path
    if paused:
        data["paused"] = "true"
    r = _post_form("/api/v2/torrents/add", data)
    body = r.text.strip()
    return {
        "status": "queued" if body == "Ok." else f"unexpected: {body!r}",
        "http_status": r.status_code,
        "next": "Call qbit_list() after ~5s to see the torrent appear with its hash.",
    }


@mcp.tool()
def qbit_list(
    filter: str | None = None,
    category: str | None = None,
    sort: str = "added_on",
    limit: int = 20,
) -> list[dict[str, Any]]:
    """List torrents in qBittorrent.

    Args:
        filter: Optional state filter — one of "all" (default), "downloading",
                "completed", "paused", "active", "inactive", "resumed",
                "stalled", "stalled_uploading", "stalled_downloading", "errored".
        category: Optional category filter.
        sort: Field to sort by. Default `added_on` (newest first).
        limit: Cap returned rows (default 20, max 200).
    """
    limit = max(1, min(200, int(limit)))
    params: dict[str, Any] = {"sort": sort, "reverse": "true", "limit": limit}
    if filter:
        params["filter"] = filter
    if category:
        params["category"] = category
    rows = _get_json("/api/v2/torrents/info", params)
    return [
        {
            "hash": t.get("hash"),
            "name": t.get("name"),
            "state": t.get("state"),
            "progress": round(float(t.get("progress", 0.0)), 4),
            "size": t.get("size"),
            "category": t.get("category"),
            "save_path": t.get("save_path"),
            "added_on": t.get("added_on"),
            "dlspeed": t.get("dlspeed"),
            "upspeed": t.get("upspeed"),
            "num_seeds": t.get("num_seeds"),
            "num_leechs": t.get("num_leechs"),
            "eta": t.get("eta"),
        }
        for t in rows
    ]


@mcp.tool()
def qbit_get(hash: str) -> dict[str, Any]:
    """Get details for a single torrent by its info-hash."""
    rows = _get_json("/api/v2/torrents/info", {"hashes": hash})
    if not rows:
        return {"error": "not_found", "hash": hash}
    return rows[0]


@mcp.tool()
def qbit_pause(hashes: str) -> dict[str, Any]:
    """Pause one or more torrents. Pass a single hash or `hash1|hash2|...`.

    Use `all` to pause every torrent.
    """
    _post_form("/api/v2/torrents/pause", {"hashes": hashes})
    return {"status": "paused", "hashes": hashes}


@mcp.tool()
def qbit_resume(hashes: str) -> dict[str, Any]:
    """Resume one or more torrents. Pass a single hash or `hash1|hash2|...`."""
    _post_form("/api/v2/torrents/resume", {"hashes": hashes})
    return {"status": "resumed", "hashes": hashes}


@mcp.tool()
def qbit_delete(hashes: str, delete_files: bool = False) -> dict[str, Any]:
    """Delete one or more torrents. Pass a single hash or `hash1|hash2|...`.

    Args:
        hashes: Single hash or pipe-separated list.
        delete_files: If True, also delete the downloaded files from disk.
                      Default False — leaves files intact (safer).
    """
    _post_form(
        "/api/v2/torrents/delete",
        {"hashes": hashes, "deleteFiles": "true" if delete_files else "false"},
    )
    return {"status": "deleted", "hashes": hashes, "files_deleted": delete_files}


@mcp.tool()
def qbit_categories() -> dict[str, Any]:
    """List all configured categories with their save paths.

    Useful for checking what `category` values are valid before calling
    `qbit_add_magnet`.
    """
    return _get_json("/api/v2/torrents/categories")


# ---------------------------------------------------------------------------
# Bearer-auth ASGI middleware — same shape as compute/rag/mcp/server.py.
# Only wraps the app when MCP_BEARER_TOKEN is set; stdio transport unaffected.
# ---------------------------------------------------------------------------
class _BearerAuthASGI:
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
        if not provided or not secrets.compare_digest(provided, expected):
            await send(
                {
                    "type": "http.response.start",
                    "status": 401,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"www-authenticate", b'Bearer realm="qbittorrent-mcp"'),
                    ],
                }
            )
            await send({"type": "http.response.body", "body": b'{"error":"unauthorized"}'})
            return
        await self.app(scope, receive, send)


if __name__ == "__main__":
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "stdio":
        mcp.run()
    elif transport == "streamable-http":
        bearer = os.environ.get("MCP_BEARER_TOKEN")
        if not bearer:
            mcp.run(transport="streamable-http")
        else:
            import uvicorn

            inner_app = mcp.streamable_http_app()
            app = _BearerAuthASGI(inner_app, bearer)
            uvicorn.run(app, host=_HTTP_HOST, port=_HTTP_PORT, log_level="info")
    else:
        raise SystemExit(f"unknown MCP_TRANSPORT={transport!r}; expected stdio or streamable-http")
