"""Chunking: splitting sources into passages small enough to embed and cite.

Good chunks are the biggest lever on retrieval quality: a chunk should be one
self-contained idea, small enough that its embedding means one thing, and big
enough to make sense on its own when shown to the model.

FR-10 sets the rules for COBOL: split by division, section, and paragraph, tag
every chunk with its source and dialect, and never split a COBOL paragraph.
"""

from .models import Chunk, SourceDocument


def estimate_tokens(text: str) -> int:
    """Rough token count, used to keep chunks within the embedding model's limit.

    TODO: a cheap approximation (e.g. characters / 4) is enough to start; an
    exact count needs the embedding model's tokenizer. Err on the high side,
    since text past ``embedding_max_input_tokens`` is silently ignored by the
    model.
    """
    raise NotImplementedError


def chunk_cobol(source: SourceDocument, text: str, max_tokens: int) -> list[Chunk]:
    """Split COBOL source code along its structure (FR-10).

    Intended behaviour:
    - Respect fixed-format columns: 1-6 sequence area, 7 indicator ('*' or '/'
      marks a comment line), 8-11 Area A, 12-72 Area B. Division, section, and
      paragraph headers start in Area A.
    - IDENTIFICATION / ENVIRONMENT / DATA DIVISION: one chunk per division, or
      per section (e.g. WORKING-STORAGE SECTION) if the division is too long.
    - PROCEDURE DIVISION: one chunk per paragraph, labelled with its section
      (if any) and paragraph name. Never split a paragraph (FR-10).
    - Every chunk gets source_id, source_title, url, dialect, kind="cobol",
      division/section/paragraph, and its line range.

    Open questions (team decisions, not settled here):
    - A paragraph longer than ``max_tokens``: FR-10 forbids splitting it, but
      the model can't read past its limit. Options: embed a summary or the
      first part while storing the full text, or relax FR-10 for such cases.
    - COPY statements / copybooks: inline them, or chunk copybooks separately?
    - Reuse: the Analyzer agent on the agent-orchestrator branch already parses
      divisions and paragraphs. Once that merges, this should call it rather
      than keep a second COBOL parser.
    """
    raise NotImplementedError


def chunk_prose(source: SourceDocument, text: str, max_tokens: int) -> list[Chunk]:
    """Split documentation (IBM docs, the Open Mainframe Project course) by heading.

    Intended behaviour:
    - One chunk per section under a heading, with the heading path recorded
      (e.g. "Data division > PICTURE clause") so a chunk makes sense alone.
    - Sections longer than ``max_tokens`` split at paragraph boundaries, with a
      small overlap so a sentence cut in half still appears whole somewhere.
    - Keep code examples inside one chunk, together with the text that
      explains them.

    TODO: depends on the format the sources arrive in (Markdown, HTML, PDF),
    which isn't decided until the source list is approved.
    """
    raise NotImplementedError


def chunk_source(source: SourceDocument, text: str, max_tokens: int) -> list[Chunk]:
    """Chunk one source with the strategy for its kind."""
    if source.kind == "cobol":
        return chunk_cobol(source, text, max_tokens)
    return chunk_prose(source, text, max_tokens)
