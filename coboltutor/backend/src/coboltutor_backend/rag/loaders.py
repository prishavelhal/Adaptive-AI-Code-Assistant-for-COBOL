"""Loading sources: the approved-source manifest and the files it points to.

``knowledge-base/SOURCES.md`` is the single list of what may be ingested. A
source that isn't in it, or has no recorded license/permission, is never
loaded. That enforces requirement C-2 and the AGENTS.md rule ("only index
public or partner-approved COBOL documentation") in code, not just by habit.
"""

from pathlib import Path

from .models import SourceDocument


class ManifestError(Exception):
    """SOURCES.md is malformed, or a listed source is missing or unapproved."""


def parse_manifest(markdown: str, knowledge_base_dir: Path) -> list[SourceDocument]:
    """Parse the "Approved sources" table in SOURCES.md into SourceDocuments.

    TODO:
    - find the Markdown table under the "Approved sources" heading; its
      columns are documented in SOURCES.md itself
    - one SourceDocument per row; paths are relative to ``knowledge_base_dir``
    - raise ManifestError for: duplicate source IDs, an empty license or
      approval column, an unknown kind, or a path that escapes
      ``knowledge_base_dir`` (e.g. "../../etc/passwd")
    """
    raise NotImplementedError


def load_manifest(knowledge_base_dir: Path) -> list[SourceDocument]:
    """Read ``knowledge_base_dir / "SOURCES.md"`` and parse it.

    TODO: read the file (UTF-8), call parse_manifest, raise ManifestError with
    the path if SOURCES.md is missing.
    """
    raise NotImplementedError


def read_source_text(source: SourceDocument) -> str:
    """Return a source's text, ready for chunking.

    TODO: read source.path. If sources arrive as HTML or PDF, convert them to
    text here so the chunkers only ever see plain text or Markdown.
    """
    raise NotImplementedError
