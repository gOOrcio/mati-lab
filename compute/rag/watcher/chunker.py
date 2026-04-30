"""Markdown heading-based chunker for the Obsidian vault.

Splits a markdown file into logical sections by ATX heading (#, ##, ###).
Each section becomes a Chunk with deterministic id (sha1 of path + heading
path + chunk index). Long sections split further on paragraph boundaries
with character overlap.

Pure function: no I/O, no clock.
"""

from __future__ import annotations

import hashlib
import re
import uuid
from dataclasses import dataclass, field
from pathlib import Path

import frontmatter

HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*$", re.MULTILINE)


@dataclass
class Chunk:
    chunk_id: str
    path: str
    heading_path: list[str]
    text: str
    tags: list[str] = field(default_factory=list)


def _split_long(text: str, max_chars: int, overlap: int) -> list[str]:
    if len(text) <= max_chars:
        return [text]
    paragraphs = text.split("\n\n")
    out: list[str] = []
    buf = ""
    for p in paragraphs:
        if len(buf) + len(p) + 2 > max_chars and buf:
            out.append(buf)
            buf = (buf[-overlap:] + "\n\n" + p) if overlap > 0 else p
        else:
            buf = (buf + "\n\n" + p) if buf else p
    if buf:
        out.append(buf)
    # Hard char-split any chunk still over budget (e.g. a single huge paragraph
    # with no \n\n boundaries). Preserves overlap.
    final: list[str] = []
    for chunk in out:
        if len(chunk) <= max_chars:
            final.append(chunk)
            continue
        step = max(1, max_chars - overlap)
        i = 0
        while i < len(chunk):
            final.append(chunk[i : i + max_chars])
            if i + max_chars >= len(chunk):
                break
            i += step
    return final


def chunk_markdown(
    source: str, *, path: Path, max_chars: int = 1000, overlap: int = 150
) -> list[Chunk]:
    parsed = frontmatter.loads(source)
    body = parsed.content
    tags = parsed.metadata.get("tags") or []
    if isinstance(tags, str):
        tags = [tags]

    sections: list[tuple[list[str], str]] = []
    heading_stack: list[tuple[int, str]] = []
    headings = list(HEADING_RE.finditer(body))

    if not headings:
        stripped = body.strip()
        if stripped:
            sections.append(([], stripped))
    else:
        for i, m in enumerate(headings):
            level = len(m.group(1))
            title = m.group(2).strip()
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            heading_stack.append((level, title))
            start = m.end()
            end = headings[i + 1].start() if i + 1 < len(headings) else len(body)
            text = body[start:end].strip()
            if text:
                sections.append(([h[1] for h in heading_stack], text))

    chunks: list[Chunk] = []
    for hp, text in sections:
        for sub_idx, sub_text in enumerate(_split_long(text, max_chars, overlap)):
            id_seed = f"{path.as_posix()}::{'>'.join(hp)}::{sub_idx}"
            # Qdrant point IDs must be unsigned int or UUID. Take the first
            # 16 bytes of the sha1 digest and format as a UUID — deterministic,
            # collision-equivalent to a 128-bit truncation, valid for Qdrant.
            chunk_id = str(uuid.UUID(bytes=hashlib.sha1(id_seed.encode()).digest()[:16]))
            chunks.append(
                Chunk(
                    chunk_id=chunk_id,
                    path=path.as_posix(),
                    heading_path=hp,
                    text=sub_text,
                    tags=list(tags),
                )
            )
    return chunks
