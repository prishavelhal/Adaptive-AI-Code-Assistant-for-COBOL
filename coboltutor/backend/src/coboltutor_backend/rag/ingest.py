"""The ``coboltutor-ingest`` command: build or refresh the knowledge-base index.

Run from coboltutor/backend/:

    uv run coboltutor-ingest                     # ingest every approved source
    uv run coboltutor-ingest --source omp-course # just one (repeatable)
    uv run coboltutor-ingest --dry-run           # chunk only: no model, no database

Needs COBOLTUTOR_DATABASE_URL and a reachable embedding server (see config.py),
except with --dry-run, which is meant for checking chunking (FR-10) quickly.
"""

import argparse
import asyncio
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from ..config import Settings, get_settings

# The knowledge base lives at coboltutor/knowledge-base/, one level up from
# backend/, which is where the command is normally run from.
DEFAULT_KNOWLEDGE_BASE_DIR = Path("../knowledge-base")


@dataclass
class IngestReport:
    """What an ingestion run did, printed at the end."""

    sources_ingested: int = 0
    chunks_written: int = 0
    # Source IDs skipped, each with the reason (e.g. "file missing").
    skipped: list[str] = field(default_factory=list)


async def ingest(
    knowledge_base_dir: Path,
    settings: Settings,
    *,
    only_sources: Sequence[str] | None = None,
    dry_run: bool = False,
) -> IngestReport:
    """Load, chunk, embed, and store the approved sources.

    TODO:
    1. sources = loaders.load_manifest(knowledge_base_dir); keep only
       ``only_sources`` if given (unknown IDs are an error, not a silent no-op)
    2. for each source: text = loaders.read_source_text(source), then
       chunks = chunking.chunk_source(source, text,
                                      settings.embedding_max_input_tokens)
    3. dry_run: report counts and per-source chunk sizes, then stop
    4. otherwise: embedder = OpenAICompatibleEmbedder(settings),
       store = PgVectorStore(settings)
       await store.ensure_schema(IndexInfo(embedder.model_name,
                                           embedder.dimensions))
       per source: vectors = await embedder.embed_documents([c.text ...]),
       then await store.replace_source(source.source_id, embedded_chunks)
    5. always close the store (try/finally)
    """
    raise NotImplementedError


def build_arg_parser() -> argparse.ArgumentParser:
    """Command-line options for coboltutor-ingest."""
    parser = argparse.ArgumentParser(
        prog="coboltutor-ingest",
        description="Build or refresh the CobolTutor knowledge-base index.",
    )
    parser.add_argument(
        "--knowledge-base",
        type=Path,
        default=DEFAULT_KNOWLEDGE_BASE_DIR,
        help="folder containing SOURCES.md (default: %(default)s)",
    )
    parser.add_argument(
        "--source",
        action="append",
        dest="sources",
        metavar="SOURCE_ID",
        help="ingest only this source ID; repeat for several",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="load and chunk only; don't call the embedding model or the database",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> None:
    """Entry point for the ``coboltutor-ingest`` script (see pyproject.toml)."""
    args = build_arg_parser().parse_args(argv)
    report = asyncio.run(
        ingest(
            args.knowledge_base,
            get_settings(),
            only_sources=args.sources,
            dry_run=args.dry_run,
        )
    )
    print(
        f"Ingested {report.sources_ingested} source(s), "
        f"wrote {report.chunks_written} chunk(s), skipped {len(report.skipped)}."
    )
    for reason in report.skipped:
        print(f"  skipped: {reason}")
