from pathlib import Path
from watcher.chunker import Chunk, chunk_markdown

VAULT_NOTE = """---
tags: [project, homelab]
aliases: [Lab Note]
---

# Top heading

Some intro text under the top heading.

## Subsection A

A short paragraph.

Another paragraph in subsection A.

## Subsection B

Yet more text.
"""


def test_chunk_markdown_splits_by_heading():
    chunks = chunk_markdown(VAULT_NOTE, path=Path("notes/lab.md"))
    assert len(chunks) == 3
    assert chunks[0].heading_path == ["Top heading"]
    assert "Some intro text" in chunks[0].text
    assert chunks[1].heading_path == ["Top heading", "Subsection A"]
    assert chunks[2].heading_path == ["Top heading", "Subsection B"]


def test_chunk_extracts_frontmatter_tags():
    chunks = chunk_markdown(VAULT_NOTE, path=Path("notes/lab.md"))
    for c in chunks:
        assert "project" in c.tags
        assert "homelab" in c.tags


def test_chunk_id_is_deterministic():
    chunks_a = chunk_markdown(VAULT_NOTE, path=Path("notes/lab.md"))
    chunks_b = chunk_markdown(VAULT_NOTE, path=Path("notes/lab.md"))
    assert [c.chunk_id for c in chunks_a] == [c.chunk_id for c in chunks_b]


def test_chunk_id_is_uuid_format():
    """Qdrant point IDs must be UUID or unsigned int — sha1 hex is rejected."""
    import uuid as _uuid

    chunks = chunk_markdown(VAULT_NOTE, path=Path("notes/lab.md"))
    for c in chunks:
        # Will raise if not a valid UUID string
        _uuid.UUID(c.chunk_id)


def test_chunk_long_section_splits_with_overlap():
    long_section = "# Heading\n\n" + ("This is a sentence. " * 200)
    chunks = chunk_markdown(long_section, path=Path("notes/long.md"), max_chars=800, overlap=150)
    assert len(chunks) >= 3
    for i in range(len(chunks) - 1):
        tail = chunks[i].text[-100:]
        assert tail[:50] in chunks[i + 1].text


def test_chunk_skips_empty_sections():
    src = "# Only heading\n\n## Empty subsection\n\n## Real content\n\nSome text."
    chunks = chunk_markdown(src, path=Path("notes/x.md"))
    assert len(chunks) == 1
    assert chunks[0].heading_path == ["Only heading", "Real content"]
