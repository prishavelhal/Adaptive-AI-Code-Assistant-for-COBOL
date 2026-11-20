"""Embedding: turning text into vectors.

An embedding model maps a piece of text to a fixed-length list of numbers (a
vector) such that texts with similar meaning get vectors that point in similar
directions. We embed every chunk once at ingestion time, then embed each
question at retrieval time and look for the chunks whose vectors are closest.

The embedding server speaks the OpenAI-compatible ``POST /v1/embeddings`` API,
which both Ollama (local) and vLLM (HPC cluster) provide, so we reuse the
``openai`` client the chat code already uses. No requests go to OpenAI itself.
"""

from collections.abc import Sequence
from typing import Protocol, runtime_checkable

from ..config import Settings


@runtime_checkable
class Embedder(Protocol):
    """What the rest of the RAG code needs from an embedding model.

    A Protocol (structural interface) so tests can pass in a fake with the same
    methods, exactly like ``llm.LLMClient``.
    """

    @property
    def model_name(self) -> str:
        """The embedding model's name, recorded in the index (see IndexInfo)."""
        ...

    @property
    def dimensions(self) -> int:
        """Length of every vector this model returns."""
        ...

    async def embed_documents(self, texts: Sequence[str]) -> list[list[float]]:
        """Embed passages for storage. Returns one vector per text, in order."""
        ...

    async def embed_query(self, text: str) -> list[float]:
        """Embed a search query.

        Separate from embed_documents because some embedding models expect
        queries and passages to be formatted differently (for example, an
        instruction prefix on queries). granite-embedding-english-r2 doesn't,
        but keeping the split means switching models only touches this class.
        """
        ...


class OpenAICompatibleEmbedder:
    """Embedder backed by an OpenAI-compatible /v1/embeddings server."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        # TODO: create an openai.AsyncOpenAI client here, as llm.py does:
        #   base_url = settings.embedding_base_url
        #   api_key  = settings.embedding_api_key.get_secret_value() if set,
        #              else a placeholder (Ollama ignores it, but the SDK
        #              refuses to start without one)

    @property
    def model_name(self) -> str:
        return self._settings.embedding_model

    @property
    def dimensions(self) -> int:
        return self._settings.embedding_dimensions

    async def embed_documents(self, texts: Sequence[str]) -> list[list[float]]:
        """TODO:
        - send ``texts`` in batches of settings.embedding_batch_size via
          client.embeddings.create(model=..., input=batch)
        - put results back in input order (each result carries an index)
        - check every vector has ``self.dimensions`` numbers; a mismatch means
          the configured model or dimensions are wrong, so fail loudly
        """
        raise NotImplementedError

    async def embed_query(self, text: str) -> list[float]:
        """TODO: a single-item embed_documents call (no query prefix for r2)."""
        raise NotImplementedError
