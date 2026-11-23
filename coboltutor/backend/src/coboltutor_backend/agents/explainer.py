"""Explainer agent: the existing tutor prompt, enriched with the Analyzer's findings.

This agent reuses the existing pieces instead of copying them:
  * ``prompts.build_messages`` builds the message list exactly as /api/chat does
    (system prompt, history trimming, line-numbered code);
  * ``LLMClient.stream_chat`` streams the answer through the same client.

The only thing it adds is a short note containing the structural analysis,
placed in front of the user's latest message. Improvements to the shared
prompt or client therefore reach the agent pipeline automatically.
"""

from collections.abc import AsyncIterator
from functools import cache
from importlib import resources

from ..config import Settings
from ..llm import LLMClient
from ..prompts import build_messages
from ..schemas import ChatRequest
from .analyzer import CodeAnalysis, render_analysis

# Placeholder in the prompt file that is replaced with the rendered analysis.
_ANALYSIS_PLACEHOLDER = "{analysis}"


@cache
def load_prompt(name: str) -> str:
    """Read a prompt template that ships inside this package (agents/prompts/).

    Prompts live in their own files, as AGENTS.md asks, so wording changes don't
    touch code. importlib.resources finds them both in a source checkout and in
    the installed package inside the Docker image.
    """
    return resources.files(__package__).joinpath("prompts", name).read_text(encoding="utf-8")


def build_explainer_messages(
    request: ChatRequest, analysis: CodeAnalysis | None, settings: Settings
) -> list[dict[str, str]]:
    """The existing /api/chat messages, with the analysis note added to the last user turn."""
    messages = build_messages(request, settings)
    if analysis is None or analysis.is_empty:
        return messages  # nothing useful found: behave exactly like /api/chat

    note = load_prompt("explainer_analysis.md").replace(
        _ANALYSIS_PLACEHOLDER, render_analysis(analysis)
    )
    # The request schema guarantees the last message is the user's question.
    # We put the note in that turn (rather than adding a second system message)
    # because chat templates differ in how they handle several system messages.
    last = messages[-1]
    messages[-1] = {"role": last["role"], "content": f"{note.strip()}\n\n{last['content']}"}
    return messages


async def explain(
    request: ChatRequest,
    analysis: CodeAnalysis | None,
    settings: Settings,
    llm: LLMClient,
) -> AsyncIterator[str]:
    """Stream the explanation, token by token, through the shared LLM client."""
    async for text in llm.stream_chat(build_explainer_messages(request, analysis, settings)):
        yield text
