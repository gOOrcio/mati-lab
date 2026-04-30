import pytest
from pytest_httpx import HTTPXMock

from watcher.embedder import Embedder, EmbedError


def _ok_payload(n: int, dim: int = 768) -> dict:
    return {
        "object": "list",
        "data": [{"object": "embedding", "index": i, "embedding": [0.1] * dim} for i in range(n)],
        "model": "embeddings",
        "usage": {"prompt_tokens": 10, "total_tokens": 10},
    }


def test_embed_single(httpx_mock: HTTPXMock):
    httpx_mock.add_response(
        url="http://litellm.test/v1/embeddings",
        method="POST",
        json=_ok_payload(1),
    )
    e = Embedder(base_url="http://litellm.test", api_key="sk-test")
    [vec] = e.embed(["hello"])
    assert len(vec) == 768
    assert vec[0] == pytest.approx(0.1)


def test_embed_batch(httpx_mock: HTTPXMock):
    httpx_mock.add_response(
        url="http://litellm.test/v1/embeddings",
        method="POST",
        json=_ok_payload(3),
    )
    e = Embedder(base_url="http://litellm.test", api_key="sk-test")
    out = e.embed(["a", "b", "c"])
    assert len(out) == 3
    assert all(len(v) == 768 for v in out)


def test_embed_retries_on_5xx(httpx_mock: HTTPXMock):
    httpx_mock.add_response(status_code=503, url="http://litellm.test/v1/embeddings", method="POST")
    httpx_mock.add_response(status_code=503, url="http://litellm.test/v1/embeddings", method="POST")
    httpx_mock.add_response(json=_ok_payload(1), url="http://litellm.test/v1/embeddings", method="POST")
    e = Embedder(base_url="http://litellm.test", api_key="sk-test", retry_sleep=0)
    [vec] = e.embed(["x"])
    assert len(vec) == 768


def test_embed_raises_on_persistent_5xx(httpx_mock: HTTPXMock):
    for _ in range(4):
        httpx_mock.add_response(status_code=503, url="http://litellm.test/v1/embeddings", method="POST")
    e = Embedder(base_url="http://litellm.test", api_key="sk-test", retry_sleep=0)
    with pytest.raises(EmbedError):
        e.embed(["x"])


def test_embed_sets_auth_header(httpx_mock: HTTPXMock):
    httpx_mock.add_response(url="http://litellm.test/v1/embeddings", method="POST", json=_ok_payload(1))
    e = Embedder(base_url="http://litellm.test", api_key="sk-secret")
    e.embed(["x"])
    req = httpx_mock.get_request()
    assert req.headers["Authorization"] == "Bearer sk-secret"
    assert req.headers["Content-Type"] == "application/json"
