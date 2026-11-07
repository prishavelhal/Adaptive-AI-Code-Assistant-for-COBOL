"""Tests for OpenAICompatibleLLM against canned Ollama-style streams.

The streams below copy what Ollama sends for Granite 4.2: "thinking" arrives in
a separate `reasoning` field with empty `content`, and the final chunk carries
`finish_reason`. httpx.MockTransport stands in for the network, so no model runs.
"""

import json
from typing import Any

import httpx
import pytest
from openai import AsyncOpenAI

from coboltutor_backend.config import Settings
from coboltutor_backend.llm import AnswerTruncatedError, EmptyAnswerError, OpenAICompatibleLLM


def chunk(content: str = "", reasoning: str = "", finish: str | None = None) -> dict[str, Any]:
    """One chat.completion.chunk as Ollama formats it."""
    delta: dict[str, Any] = {"role": "assistant", "content": content}
    if reasoning:
        delta["reasoning"] = reasoning
    return {
        "id": "chatcmpl-1",
        "object": "chat.completion.chunk",
        "created": 0,
        "model": "granite4.2:8b",
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }


def make_llm(
    chunks: list[dict[str, Any]], **settings: Any
) -> tuple[OpenAICompatibleLLM, list[dict[str, Any]]]:
    """Build an LLM client whose HTTP calls return `chunks` as an SSE stream.

    Also returns a list that collects the JSON bodies of requests sent, so tests
    can check what parameters reached the "server".
    """
    sent: list[dict[str, Any]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        sent.append(json.loads(request.content))
        body = "".join(f"data: {json.dumps(c)}\n\n" for c in chunks) + "data: [DONE]\n\n"
        return httpx.Response(200, text=body, headers={"content-type": "text/event-stream"})

    llm = OpenAICompatibleLLM(Settings(**settings))
    # Swap in an SDK client that talks to the mock transport instead of the network.
    llm._client = AsyncOpenAI(
        base_url="http://ollama.test/v1",
        api_key="x",
        http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    return llm, sent


async def collect(llm: OpenAICompatibleLLM) -> list[str]:
    return [t async for t in llm.stream_chat([{"role": "user", "content": "hi"}])]


async def test_reasoning_is_skipped_and_content_streamed() -> None:
    llm, _ = make_llm(
        [
            chunk(reasoning="Let me think"),
            chunk(content="COMP-3 is "),
            chunk(content="packed."),
            chunk(finish="stop"),
        ]
    )
    assert await collect(llm) == ["COMP-3 is ", "packed."]


async def test_reasoning_that_uses_whole_budget_raises_instead_of_empty_success() -> None:
    # This is the "explain whole file" bug: every token was reasoning, then the
    # length limit hit. Previously this ended as a silent, empty "done".
    llm, _ = make_llm([chunk(reasoning="thinking..."), chunk(reasoning="more", finish="length")])
    with pytest.raises(AnswerTruncatedError) as info:
        await collect(llm)
    assert info.value.got_answer is False


async def test_partial_answer_is_kept_then_truncation_reported() -> None:
    llm, _ = make_llm([chunk(content="Part one"), chunk(finish="length")])
    received: list[str] = []
    with pytest.raises(AnswerTruncatedError) as info:
        async for t in llm.stream_chat([{"role": "user", "content": "hi"}]):
            received.append(t)
    assert received == ["Part one"]
    assert info.value.got_answer is True


async def test_empty_answer_raises() -> None:
    llm, _ = make_llm([chunk(finish="stop")])
    with pytest.raises(EmptyAnswerError):
        await collect(llm)


async def test_reasoning_effort_is_sent_and_can_be_omitted() -> None:
    llm, sent = make_llm([chunk(content="ok", finish="stop")], llm_reasoning_effort="low")
    await collect(llm)
    assert sent[0]["reasoning_effort"] == "low"

    llm, sent = make_llm([chunk(content="ok", finish="stop")], llm_reasoning_effort=None)
    await collect(llm)
    assert "reasoning_effort" not in sent[0]
