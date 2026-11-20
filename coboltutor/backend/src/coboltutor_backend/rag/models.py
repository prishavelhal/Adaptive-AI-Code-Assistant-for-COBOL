"""Plain data types passed between the stages of the RAG pipeline.

These are frozen dataclasses (immutable records) rather than Pydantic models:
they never cross the HTTP boundary directly, so they need no validation, and
immutability means a chunk can't be changed by accident after it is embedded.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Literal

# What kind of text a source contains. It decides how the source is chunked:
#   "cobol" - COBOL source code (sample programs), split by COBOL structure
#   "prose" - documentation (IBM docs, the Open Mainframe Project course),
#             split by headings
SourceKind = Literal["cobol", "prose"]


@dataclass(frozen=True)
class SourceDocument:
    """One approved source, as listed in ``knowledge-base/SOURCES.md``.

    Only sources in that manifest are ever ingested. The manifest records the
    license or permission for each one (requirement C-2), so nothing
    unapproved can end up in the index.
    """

    source_id: str  # short stable ID, e.g. "omp-cobol-course"; used in citations
    title: str  # human-readable name shown to the learner
    url: str  # public link the citation points to (FR-3)
    license: str  # license or permission that allows our use (C-2)
    dialect: str  # e.g. "ibm-enterprise"; FR-10 requires a dialect tag per chunk
    kind: SourceKind
    path: Path  # where the source's text lives, under knowledge-base/


@dataclass(frozen=True)
class Chunk:
    """A passage cut from a source: the unit we embed, store, and retrieve.

    Every chunk carries its source and dialect (FR-10) so it can be cited and
    filtered. The structural fields say where in the source it came from; which
    ones are set depends on the source kind.
    """

    text: str
    source_id: str
    source_title: str
    url: str
    dialect: str
    kind: SourceKind
    # COBOL sources: where in the program this chunk sits.
    division: str | None = None  # e.g. "PROCEDURE"
    section: str | None = None  # e.g. "MAIN-LOGIC" (COBOL sections are optional)
    paragraph: str | None = None  # e.g. "CALCULATE-PAY"
    # Prose sources: the heading path, e.g. "Data types > COMP-3".
    heading: str | None = None
    # 1-based line range in the source file, when known.
    start_line: int | None = None
    end_line: int | None = None

    def content_hash(self) -> str:
        """Stable fingerprint of this chunk's source and text.

        Lets re-ingestion recognise chunks that haven't changed (the database
        has a UNIQUE constraint on source_id + content_hash).

        TODO: sha256 of source_id and text, as a hex string.
        """
        raise NotImplementedError


@dataclass(frozen=True)
class EmbeddedChunk:
    """A chunk together with its embedding vector, ready to store."""

    chunk: Chunk
    embedding: list[float]


@dataclass(frozen=True)
class RetrievedChunk:
    """A chunk returned by a search, with how closely it matched."""

    chunk: Chunk
    # Cosine similarity between the question and the chunk: 1.0 = same
    # direction, 0.0 = unrelated. Higher is better.
    score: float


@dataclass(frozen=True)
class IndexInfo:
    """Which embedding model built the index.

    Stored in the database at ingestion time and compared against the
    configured embedder before every search: vectors from different models
    (or differently quantized copies of the same model) can't be compared, and
    a mismatch would silently return irrelevant passages.
    """

    embedding_model: str
    dimensions: int
