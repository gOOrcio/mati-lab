"""Embedding client for LiteLLM's OpenAI-compatible /v1/embeddings."""

from __future__ import annotations

import os
import time
from dataclasses import dataclass

import httpx


class EmbedError(RuntimeError):
    pass


@dataclass
class Embedder:
    base_url: str
    api_key: str
    model: str = "embeddings"
    timeout: float = 60.0
    max_retries: int = 3
    retry_sleep: float = 1.0

    @classmethod
    def from_env(cls) -> "Embedder":
        return cls(
            base_url=os.environ["LITELLM_BASE_URL"].rstrip("/"),
            api_key=os.environ["LITELLM_API_KEY"],
            model=os.environ.get("LITELLM_EMBED_MODEL", "embeddings"),
        )

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        url = f"{self.base_url}/v1/embeddings"
        body = {"model": self.model, "input": texts}
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        last_err: Exception | None = None
        for attempt in range(self.max_retries + 1):
            try:
                with httpx.Client(timeout=self.timeout) as client:
                    r = client.post(url, headers=headers, json=body)
                if r.status_code >= 500:
                    last_err = EmbedError(f"{r.status_code} {r.text[:200]}")
                    if attempt < self.max_retries:
                        time.sleep(self.retry_sleep)
                        continue
                    raise last_err
                r.raise_for_status()
                data = r.json()["data"]
                data.sort(key=lambda d: d["index"])
                return [d["embedding"] for d in data]
            except httpx.HTTPError as e:
                last_err = e
                if attempt < self.max_retries:
                    time.sleep(self.retry_sleep)
                    continue
                raise EmbedError(str(e)) from e
        raise EmbedError(str(last_err))
