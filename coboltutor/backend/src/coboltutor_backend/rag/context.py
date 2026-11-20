"""Turning retrieved chunks into prompt text and citations.

Two outputs per request:
- text added to the prompt: the passages, each labelled [S1], [S2], ... and
  wrapped in the instructions from prompts/retrieved_context.md
- a ``sources`` payload sent to the extension so it can show what the answer
  was based on, with links (FR-3)

The labels are the link between the two: the model cites [S2], and the
extension looks up S2 in the sources payload.
"""

from collections.abc import Sequence
from importlib.resources import files
from typing import Any

from .models import RetrievedChunk

# Prompt wording lives in its own file, not in code (AGENTS.md). The template
# contains a {passages} placeholder that render_context fills in.
_PROMPT_FILE = "retrieved_context.md"
PASSAGES_PLACEHOLDER = "{passages}"


def load_context_prompt() -> str:
    """Return the instruction template from prompts/retrieved_context.md."""
    return files(__package__).joinpath("prompts", _PROMPT_FILE).read_text(encoding="utf-8")


def render_context(chunks: Sequence[RetrievedChunk], max_chars: int) -> str:
    """Build the retrieved-passages block that goes into the prompt.

    TODO:
    - label chunks S1, S2, ... in rank order
    - format each as: label, title, location (division/paragraph or heading),
      then the text in a fenced block (```cobol for COBOL sources)
    - stop adding chunks once ``max_chars`` would be exceeded; never cut a
      chunk in half, since half a passage is worse than none
    - substitute the result for PASSAGES_PLACEHOLDER in load_context_prompt()
    - return "" when there are no chunks, so the prompt is unchanged
    """
    raise NotImplementedError


def sources_event_payload(chunks: Sequence[RetrievedChunk]) -> dict[str, Any]:
    """Build the data for a future ``sources`` SSE event.

    Proposed shape (needs a matching type in extension/shared/protocol.ts):
        {"sources": [{"label": "S1", "source_id": ..., "title": ...,
                      "url": ..., "location": ..., "score": ...}, ...]}

    The event must be sent before ``done``: the extension stops reading the
    stream at ``done``, so anything after it is lost.

    TODO: build it from the same chunks, in the same order, as render_context,
    so labels match. Include only chunks that actually made it into the prompt.
    """
    raise NotImplementedError
