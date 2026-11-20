"""Retrieval: from a learner's question to the most relevant chunks.

This is the piece /api/chat (and later the agent orchestrator's `retrieve`
stage) will call. It ties the embedder and the store together and guards
against searching an index built with a different embedding model.
"""

from ..config import Settings
from .embedder import Embedder
from .models import RetrievedChunk
from .store import VectorStore


class IndexMismatchError(Exception):
    """The index was built with a different embedding model or vector size.

    Searching anyway would compare incompatible vectors and silently return
    irrelevant passages, so we refuse and say how to fix it (re-run ingestion
    with the current model, or point the embedder at the original one).
    """


class IndexNotBuiltError(Exception):
    """Nothing has been ingested yet (no index_info row)."""


def build_search_query(question: str, code: str | None, max_chars: int) -> str:
    """Decide what text to embed for the search.

    TODO: start with the question alone. Questions like "explain this" carry
    no meaning without the code, so for those include the code too: perhaps
    the COBOL keywords and constructs it uses, as the Analyzer agent finds
    them, rather than raw text. Trim to ``max_chars``. Worth measuring both
    ways with the evaluation set (FR-11).
    """
    raise NotImplementedError


class Retriever:
    """Embeds a question and returns the closest chunks from the store."""

    def __init__(self, embedder: Embedder, store: VectorStore, settings: Settings) -> None:
        self._embedder = embedder
        self._store = store
        self._settings = settings

    async def check_index(self) -> None:
        """Make sure the stored index matches the configured embedder.

        TODO: info = await store.get_index_info()
        - None -> raise IndexNotBuiltError
        - model name or dimensions differ from the embedder -> raise
          IndexMismatchError naming both models
        Call once at startup or on first use, not on every question.
        """
        raise NotImplementedError

    async def retrieve(self, question: str, code: str | None = None) -> list[RetrievedChunk]:
        """Return up to ``settings.rag_top_k`` relevant chunks, best first.

        TODO:
        1. query = build_search_query(question, code, ...)
        2. vector = await embedder.embed_query(query)
        3. results = await store.search(vector, settings.rag_top_k)
        4. optionally drop results below a minimum score, so an off-topic
           question doesn't get irrelevant "sources" attached
        """
        raise NotImplementedError
