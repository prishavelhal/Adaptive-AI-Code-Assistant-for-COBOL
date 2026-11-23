"""Orchestrator: runs the agents in order and turns their output into SSE events.

Pipeline (each step announces itself with a `stage` event before it runs):

    1. analyze  - Analyzer agent (no model call) on the code attached to the
                  latest user message that has code
    2. explain  - Explainer agent, streamed as `token` events
    3. verify   - Critic agent checks the finished answer (only when code was
                  attached, since there is nothing to check it against otherwise)

Later steps (retrieve) slot in as more stages. The events are the same ones
/api/chat sends (token, done, error, see sse.py), plus:

    stage         {"name": str}                  - the pipeline started this step
    verification  {"issues": [...],              - the Critic's findings; each issue
                   "reviewed_by_model": bool}      is {source, message, line}

`verification` is always sent *before* `done`: the extension stops reading the
stream as soon as it sees `done` (extension/src/backendClient.ts), so anything
after it would be lost.

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
from .critic import verify
from .explainer import explain
from .settings import AgentSettings

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
    agent_settings: AgentSettings | None = None,
) -> AsyncIterator[str]:
    """Yield the SSE-formatted events for one agent-chat request."""
    agent_settings = agent_settings or AgentSettings()
    try:
        # --- 1. Analyzer -----------------------------------------------------
        yield format_sse("stage", {"name": "analyze"})
        ctx = latest_code_context(request)
        analysis: CodeAnalysis | None = analyze(ctx) if ctx is not None else None

        # --- 2. Explainer ----------------------------------------------------
        yield format_sse("stage", {"name": "explain"})
        # Keep the full answer: the Critic needs it once streaming is finished.
        answer_parts: list[str] = []
        async for text in explain(request, analysis, settings, llm):
            answer_parts.append(text)
            yield format_sse("token", {"text": text})

        # --- 3. Critic -------------------------------------------------------
        # Only when there is code to check against. A general question
        # ("what is COMP-3?") has no code, so there is nothing to verify.
        if ctx is not None and analysis is not None:
            yield format_sse("stage", {"name": "verify"})
            result = await verify(
                "".join(answer_parts),
                request,
                ctx,
                analysis,
                settings,
                llm,
                use_model=agent_settings.llm_review,
                max_issues=agent_settings.max_issues,
            )
            yield format_sse("verification", result.to_event())

        yield format_sse("done", {})
    except (AnswerTruncatedError, EmptyAnswerError) as exc:
        # Expected model outcomes, not bugs: one log line, no traceback
        # (the same policy as /api/chat). The Critic doesn't run on a
        # truncated answer, since half an answer can't be checked fairly.
        logger.warning("agent stream ended without a complete answer: %r", exc)
        yield format_sse("error", {"message": describe_error(exc, settings)})
    except Exception as exc:
        logger.exception("agent pipeline failed")
        yield format_sse("error", {"message": describe_error(exc, settings)})
