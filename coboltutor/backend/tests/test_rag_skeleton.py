"""Tests for the RAG skeleton (coboltutor_backend.rag).

The package is mostly stubs, so these tests pin down what already exists: the
interfaces, the settings defaults, the packaged schema and prompt files, and
the CLI options. The in-memory fakes below are the ones later tests will use
to exercise retrieval without Postgres or a model server (AGENTS.md: no real
calls in CI).
"""

import math
from collections.abc import Sequence
from pathlib import Path

import pytest

from coboltutor_backend.config import Settings
from coboltutor_backend.rag.context import PASSAGES_PLACEHOLDER, load_context_prompt
from coboltutor_backend.rag.embedder import Embedder, OpenAICompatibleEmbedder
from coboltutor_backend.rag.ingest import DEFAULT_KNOWLEDGE_BASE_DIR, build_arg_parser
from coboltutor_backend.rag.models import EmbeddedChunk, IndexInfo, RetrievedChunk, SourceKind
from coboltutor_backend.rag.store import PgVectorStore, VectorStore, load_schema_sql

# --- Fakes -------------------------------------------------------------------


class FakeEmbedder:
    """Deterministic stand-in for an embedding model.

    Each text becomes a tiny vector derived from its letters, so identical
    texts get identical vectors and the same input always gives the same output.
    """

    def __init__(self, dimensions: int = 4, model_name: str = "fake-embedder") -> None:
        self._dimensions = dimensions
        self._model_name = model_name

    @property
    def model_name(self) -> str:
        return self._model_name

    @property
    def dimensions(self) -> int:
        return self._dimensions

    def _vector(self, text: str) -> list[float]:
        v = [0.0] * self._dimensions
        for i, ch in enumerate(text.lower()):
            v[i % self._dimensions] += ord(ch) / 1000
        return v

    async def embed_documents(self, texts: Sequence[str]) -> list[list[float]]:
        return [self._vector(t) for t in texts]

    async def embed_query(self, text: str) -> list[float]:
        return self._vector(text)


class FakeVectorStore:
    """In-memory stand-in for PgVectorStore, using exact cosine similarity."""

    def __init__(self) -> None:
        self.info: IndexInfo | None = None
        self.chunks: dict[str, list[EmbeddedChunk]] = {}
        self.closed = False

    async def ensure_schema(self, info: IndexInfo) -> None:
        self.info = info

    async def get_index_info(self) -> IndexInfo | None:
        return self.info

    async def replace_source(self, source_id: str, chunks: Sequence[EmbeddedChunk]) -> None:
        self.chunks[source_id] = list(chunks)

    async def search(
        self,
        query_embedding: Sequence[float],
        top_k: int,
        *,
        dialect: str | None = None,
        kinds: Sequence[SourceKind] | None = None,
    ) -> list[RetrievedChunk]:
        def cosine(a: Sequence[float], b: Sequence[float]) -> float:
            norm = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))
            return sum(x * y for x, y in zip(a, b, strict=True)) / norm if norm else 0.0

        candidates = [
            ec
            for group in self.chunks.values()
            for ec in group
            if (dialect is None or ec.chunk.dialect == dialect)
            and (kinds is None or ec.chunk.kind in kinds)
        ]
        scored = [
            RetrievedChunk(ec.chunk, cosine(query_embedding, ec.embedding)) for ec in candidates
        ]
        return sorted(scored, key=lambda r: r.score, reverse=True)[:top_k]

    async def close(self) -> None:
        self.closed = True


# --- Interfaces ----------------------------------------------------------------


def test_fakes_and_real_classes_satisfy_the_interfaces() -> None:
    settings = Settings()
    assert isinstance(FakeEmbedder(), Embedder)
    assert isinstance(OpenAICompatibleEmbedder(settings), Embedder)
    assert isinstance(FakeVectorStore(), VectorStore)
    assert isinstance(PgVectorStore(settings), VectorStore)


def test_real_embedder_reports_configured_model() -> None:
    settings = Settings(embedding_model="some-model", embedding_dimensions=384)
    embedder = OpenAICompatibleEmbedder(settings)
    assert embedder.model_name == "some-model"
    assert embedder.dimensions == 384


# --- Settings --------------------------------------------------------------------


def test_rag_settings_defaults() -> None:
    settings = Settings(_env_file=None)  # ignore any developer .env
    assert settings.rag_enabled is False  # skeleton: off until implemented
    assert settings.database_url is None  # credentials only from the environment
    assert settings.embedding_model == "granite-embedding-english-r2"
    assert settings.embedding_dimensions == 768
    assert settings.embedding_max_input_tokens == 8192


def test_database_url_is_hidden_when_printed() -> None:
    settings = Settings(database_url="postgresql://user:hunter2@db:5432/kb")
    assert "hunter2" not in repr(settings)
    assert settings.database_url is not None
    assert "hunter2" in settings.database_url.get_secret_value()


# --- Packaged files -----------------------------------------------------------------


def test_schema_sql_is_packaged_and_fills_in_dimensions() -> None:
    sql = load_schema_sql(768)
    assert "CREATE EXTENSION IF NOT EXISTS vector" in sql
    assert "vector(768)" in sql
    assert "{dimensions}" not in sql


def test_schema_sql_rejects_nonpositive_dimensions() -> None:
    with pytest.raises(ValueError):
        load_schema_sql(0)


def test_context_prompt_is_packaged_with_placeholder() -> None:
    prompt = load_context_prompt()
    assert PASSAGES_PLACEHOLDER in prompt


# --- CLI ------------------------------------------------------------------------------


def test_ingest_cli_options() -> None:
    parser = build_arg_parser()

    defaults = parser.parse_args([])
    assert defaults.knowledge_base == DEFAULT_KNOWLEDGE_BASE_DIR
    assert defaults.sources is None
    assert defaults.dry_run is False

    args = parser.parse_args(
        ["--knowledge-base", "/kb", "--source", "a", "--source", "b", "--dry-run"]
    )
    assert args.knowledge_base == Path("/kb")
    assert args.sources == ["a", "b"]
    assert args.dry_run is True
