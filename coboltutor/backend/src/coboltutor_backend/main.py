"""FastAPI application: HTTP routes for the CobolTutor backend.

Routes:
    GET  /health    - is the backend up, and is the model ready?
    POST /api/chat  - send the conversation, get the answer back as an SSE stream

Run it with ``uv run coboltutor-backend`` (or via Docker Compose; see the repo README).
"""

import logging
from collections.abc import AsyncIterator
from functools import lru_cache
from typing import Annotated

import openai
from fastapi import Depends, FastAPI
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from .config import Settings, get_settings
from .llm import AnswerTruncatedError, EmptyAnswerError, LLMClient, OpenAICompatibleLLM
from .prompts import build_messages
from .schemas import ChatRequest
from .sse import format_sse

logger = logging.getLogger("coboltutor")

app = FastAPI(
    title="CobolTutor backend",
    description="Streams IBM COBOL tutoring answers from IBM Granite over Server-Sent Events.",
    version="0.1.0",
)


# --- Dependencies ------------------------------------------------------------
# FastAPI's dependency injection passes these into route functions. Tests use
# `app.dependency_overrides` to replace them, e.g. with a fake LLM.


@lru_cache
def get_llm() -> LLMClient:
    """Create the LLM client once and reuse it, so HTTP connections to Ollama are reused."""
    return OpenAICompatibleLLM(get_settings())


SettingsDep = Annotated[Settings, Depends(get_settings)]
LLMDep = Annotated[LLMClient, Depends(get_llm)]


# --- Routes ------------------------------------------------------------------


class HealthResponse(BaseModel):
    status: str  # always "ok" if you got a response at all
    model: str  # the model name the backend is configured to use
    model_ready: bool  # True once Ollama is reachable and the model is downloaded


@app.get("/health")
async def health(settings: SettingsDep, llm: LLMDep) -> HealthResponse:
    """Liveness + readiness check.

    Always returns 200 while the backend runs, with ``model_ready`` reporting
    whether the model can be used. This lets the extension tell the user
    "backend is up but the model is still downloading" instead of just "error".
    """
    return HealthResponse(
        status="ok",
        model=settings.llm_model,
        model_ready=await llm.check_health(),
    )


def _friendly_error(exc: Exception, settings: Settings) -> str:
    """Turn an exception into a message that tells the user what to do about it."""
    if isinstance(exc, AnswerTruncatedError):
        if exc.got_answer:
            return (
                "The answer was cut off because it reached the length limit "
                f"({settings.llm_max_tokens} tokens). Try asking about a smaller part of the code."
            )
        return (
            "The model used its whole length budget "
            f"({settings.llm_max_tokens} tokens) reasoning and never started an answer. "
            "Try again, ask about a smaller part of the code, or lower "
            "COBOLTUTOR_LLM_REASONING_EFFORT."
        )
    if isinstance(exc, EmptyAnswerError):
        return "The model finished without producing an answer. Please try again."
    if isinstance(exc, openai.APIConnectionError):
        return (
            f"Could not reach the model server at {settings.llm_base_url}. "
            "Is Ollama running? Try `docker compose up -d` in the project folder."
        )
    if isinstance(exc, openai.NotFoundError):
        return (
            f"The model '{settings.llm_model}' is not available in Ollama. It may still be "
            f"downloading; check with `docker compose logs -f ollama-pull`."
        )
    if isinstance(exc, openai.APITimeoutError):
        return (
            "The model took too long to respond. Try again, or ask about a smaller piece of code."
        )
    if isinstance(exc, openai.APIStatusError):
        return f"The model server returned an error (HTTP {exc.status_code})."
    return "Unexpected error while generating the answer. See the backend logs for details."


@app.post("/api/chat")
async def chat(request: ChatRequest, settings: SettingsDep, llm: LLMDep) -> StreamingResponse:
    """Stream the tutor's answer to the latest user message as Server-Sent Events.

    By the time this function runs, FastAPI has already validated ``request``
    against ``ChatRequest``; invalid bodies get a 422 response automatically.
    """
    messages = build_messages(request, settings)

    async def event_stream() -> AsyncIterator[str]:
        # Errors are reported *inside* the stream, as an `error` event. Once
        # streaming starts the HTTP status (200) has already been sent, so we
        # can't change it.
        try:
            async for text in llm.stream_chat(messages):
                yield format_sse("token", {"text": text})
            yield format_sse("done", {})
        except (AnswerTruncatedError, EmptyAnswerError) as exc:
            # Expected model outcomes, not bugs: log one line, no traceback.
            logger.warning("chat stream ended without a complete answer: %r", exc)
            yield format_sse("error", {"message": _friendly_error(exc, settings)})
        except Exception as exc:
            # logger.exception records the full traceback in the server log;
            # the user only sees the friendly message.
            logger.exception("chat stream failed")
            yield format_sse("error", {"message": _friendly_error(exc, settings)})

    # If the client disconnects mid-stream (the user pressed Stop), Starlette
    # cancels `event_stream`. That closes the Ollama stream in llm.py, which
    # stops generation.
    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            # Stop caches and proxies from holding events back.
            "Cache-Control": "no-cache",
            # Tell nginx-style proxies not to buffer the stream (harmless otherwise).
            "X-Accel-Buffering": "no",
        },
    )
