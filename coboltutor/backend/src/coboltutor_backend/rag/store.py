"""Vector store: where chunks and their embeddings are kept and searched.

The real implementation uses PostgreSQL with the pgvector extension. Postgres
stores each chunk's text and metadata in ordinary columns and its embedding in
a ``vector`` column; pgvector's ``<=>`` operator measures cosine distance, and
an HNSW index (see schema.sql) makes "find the nearest chunks" fast.
"""

from collections.abc import Sequence
from importlib.resources import files
from typing import TYPE_CHECKING, Any, Protocol, runtime_checkable

from ..config import Settings
from .models import EmbeddedChunk, IndexInfo, RetrievedChunk, SourceKind

if TYPE_CHECKING:
    # Only imported for type hints, so importing this module doesn't need a
    # database driver at runtime until a connection is actually made.
    from psycopg import AsyncConnection

# schema.sql sits next to this file inside the package. Reading it through
# importlib.resources works the same in a source checkout and in the
# installed package inside the Docker image.
_SCHEMA_FILE = "schema.sql"
_DIMENSIONS_PLACEHOLDER = "{dimensions}"


def load_schema_sql(dimensions: int) -> str:
    """Return schema.sql with the vector size filled in.

    ``str.replace`` rather than ``str.format`` so a stray brace elsewhere in
    the SQL can never break it.
    """
    if dimensions <= 0:
        raise ValueError(f"embedding dimensions must be positive, got {dimensions}")
    sql = files(__package__).joinpath(_SCHEMA_FILE).read_text(encoding="utf-8")
    return sql.replace(_DIMENSIONS_PLACEHOLDER, str(dimensions))


@runtime_checkable
class VectorStore(Protocol):
    """What the rest of the RAG code needs from storage.

    A Protocol so tests can use an in-memory fake instead of a real database.
    """

    async def ensure_schema(self, info: IndexInfo) -> None:
        """Create the tables and indexes if missing, and record ``info``."""
        ...

    async def get_index_info(self) -> IndexInfo | None:
        """Which embedding model built the index, or None if nothing is ingested."""
        ...

    async def replace_source(self, source_id: str, chunks: Sequence[EmbeddedChunk]) -> None:
        """Replace every stored chunk of one source with ``chunks``.

        Delete-then-insert in a single transaction: re-ingesting a source that
        changed upstream leaves no stale chunks behind, and a failure halfway
        leaves the previous version intact.
        """
        ...

    async def search(
        self,
        query_embedding: Sequence[float],
        top_k: int,
        *,
        dialect: str | None = None,
        kinds: Sequence[SourceKind] | None = None,
    ) -> list[RetrievedChunk]:
        """Return the ``top_k`` chunks closest to ``query_embedding``, best first.

        ``dialect`` and ``kinds`` optionally restrict the search, e.g. to IBM
        Enterprise COBOL documentation only.
        """
        ...

    async def close(self) -> None:
        """Release the database connection."""
        ...


class PgVectorStore:
    """VectorStore backed by PostgreSQL + pgvector."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        # Opened lazily on first use, so constructing the store (e.g. at app
        # startup) never fails just because the database isn't up yet.
        self._conn: AsyncConnection[tuple[Any, ...]] | None = None

    async def _connection(self) -> "AsyncConnection[tuple[Any, ...]]":
        """TODO:
        - fail with a clear message if settings.database_url is None
        - psycopg.AsyncConnection.connect(settings.database_url.get_secret_value())
        - pgvector.psycopg.register_vector_async(conn) so Python lists go in
          and come out of `vector` columns without manual string formatting
        - cache the connection in self._conn
        """
        raise NotImplementedError

    async def ensure_schema(self, info: IndexInfo) -> None:
        """TODO: execute load_schema_sql(info.dimensions); upsert the index_info
        row. Refuse if an existing index_info row names a different model or
        size (that needs a deliberate rebuild, not a silent overwrite)."""
        raise NotImplementedError

    async def get_index_info(self) -> IndexInfo | None:
        """TODO: SELECT embedding_model, dimensions FROM index_info."""
        raise NotImplementedError

    async def replace_source(self, source_id: str, chunks: Sequence[EmbeddedChunk]) -> None:
        """TODO: in one transaction, DELETE FROM chunks WHERE source_id = %s,
        then insert every chunk (executemany or COPY)."""
        raise NotImplementedError

    async def search(
        self,
        query_embedding: Sequence[float],
        top_k: int,
        *,
        dialect: str | None = None,
        kinds: Sequence[SourceKind] | None = None,
    ) -> list[RetrievedChunk]:
        """TODO: SELECT ..., 1 - (embedding <=> %s) AS score FROM chunks
        [WHERE dialect = %s AND kind = ANY(%s)]
        ORDER BY embedding <=> %s LIMIT %s
        (``<=>`` is cosine *distance*, so 1 - distance = similarity.)
        Always pass values as query parameters, never by string formatting."""
        raise NotImplementedError

    async def close(self) -> None:
        """TODO: close self._conn if open."""
        raise NotImplementedError
