"""Orchestrator: runs the agents in order and turns their output into SSE events.

Pipeline (each step announces itself with a `stage` event before it runs):

    1. analyze  - Analyzer agent (no model call) on the code attached to the
                  latest user message that has code
    2. explain  - Explainer agent, streamed as `token` events

Later steps (retrieve, verify) slot in as more stages. The events are the same
ones /api/chat sends (token, done, error, see sse.py), plus `stage`:

    stage  {"name": str}  - the pipeline started this step

Errors are turned into user-facing text by the same function /api/chat uses,
which main.py passes in, so both endpoints report problems identically.
"""

import logging
from collections.abc import AsyncIterator, Callable

from ..config import Settings
from ..llm import AnswerTruncatedError, EmptyAnswerError, LLMClient
from ..schemas import ChatRequest, CodeContext
from ..sse import format_sse
from .analyzer import CodeAnalysis, analyze
from .explainer import explain

logger = logging.getLogger("coboltutor.agents")

# Turns an exception into a message for the user. main.py's _friendly_error.
ErrorDescriber = Callable[[Exception, Settings], str]


def latest_code_context(request: ChatRequest) -> CodeContext | None:
    """The code the user is asking about now: the newest user message that carries code.

    This mirrors how prompts.build_messages picks which code to include in full,
    so the analysis always describes the same code the model sees.
    """
    for msg in reversed(request.messages):
        if msg.role == "user" and msg.code_context is not None:
            return msg.code_context
    return None


async def run_pipeline(
    request: ChatRequest,
    settings: Settings,
    llm: LLMClient,
    describe_error: ErrorDescriber,
) -> AsyncIterator[str]:
    """Yield the SSE-formatted events for one agent-chat request."""
    try:
        # --- 1. Analyzer -----------------------------------------------------
        yield format_sse("stage", {"name": "analyze"})
        ctx = latest_code_context(request)
        analysis: CodeAnalysis | None = analyze(ctx) if ctx is not None else None

        # --- 2. Explainer ----------------------------------------------------
        yield format_sse("stage", {"name": "explain"})
        async for text in explain(request, analysis, settings, llm):
            yield format_sse("token", {"text": text})

        yield format_sse("done", {})
    except (AnswerTruncatedError, EmptyAnswerError) as exc:
        # Expected model outcomes, not bugs: one log line, no traceback
        # (the same policy as /api/chat).
        logger.warning("agent stream ended without a complete answer: %r", exc)
        yield format_sse("error", {"message": describe_error(exc, settings)})
    except Exception as exc:
        logger.exception("agent pipeline failed")
        yield format_sse("error", {"message": describe_error(exc, settings)})
