"""HTTP route for the agent pipeline: POST /api/agent-chat.

It accepts the same JSON body as /api/chat (``ChatRequest``) and answers with
the same SSE stream, plus `stage` events. That means the VS Code extension can
use it by changing only the URL it posts to.

Why a factory function instead of a module-level router? The route needs
main.py's ``get_llm`` dependency and error formatter. Importing them from
main.py here would create a circular import (main.py imports this module).
Passing them in also keeps FastAPI's ``dependency_overrides[get_llm]`` working,
so tests swap in a fake model for both endpoints the same way.
"""

from collections.abc import Callable
from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from ..config import Settings, get_settings
from ..llm import LLMClient
from ..schemas import ChatRequest
from .orchestrator import ErrorDescriber, run_pipeline
from .settings import AgentSettings, get_agent_settings


def create_agent_router(
    get_llm: Callable[[], LLMClient], describe_error: ErrorDescriber
) -> APIRouter:
    """Build the router; main.py mounts it with ``app.include_router``."""
    router = APIRouter()

    @router.post("/api/agent-chat")
    async def agent_chat(
        request: ChatRequest,
        settings: Annotated[Settings, Depends(get_settings)],
        llm: Annotated[LLMClient, Depends(get_llm)],
        agent_settings: Annotated[AgentSettings, Depends(get_agent_settings)],
    ) -> StreamingResponse:
        """Stream the answer from the multi-agent pipeline as Server-Sent Events."""
        return StreamingResponse(
            run_pipeline(request, settings, llm, describe_error, agent_settings),
            media_type="text/event-stream",
            # Same anti-buffering headers as /api/chat.
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    return router
