"""Streaming client for an OpenAI-compatible chat completion server (Ollama by default).

The rest of the app depends on the small ``LLMClient`` protocol below rather than
on the OpenAI SDK directly. That gives us two things:
  * tests can plug in a fake client that yields canned tokens, with no model running;
  * moving to vLLM (or anything else that speaks the OpenAI API) is a config
    change, not a code change.
"""

from collections.abc import AsyncIterator
from typing import Any, Protocol, cast

import openai
from openai import AsyncOpenAI

from .config import Settings


class AnswerTruncatedError(Exception):
    """The model hit ``llm_max_tokens`` before finishing its answer.

    Raised *after* any partial answer has been yielded, so the user keeps what
    was generated and also sees why it stopped.
    """

    def __init__(self, got_answer: bool) -> None:
        super().__init__("answer truncated by max_tokens")
        # False = the whole budget went to hidden reasoning; no answer text was produced.
        self.got_answer = got_answer


class EmptyAnswerError(Exception):
    """The model finished normally but produced no answer text."""


class LLMClient(Protocol):
    """Anything that can stream a chat completion and report whether it's healthy."""

    def stream_chat(self, messages: list[dict[str, str]]) -> AsyncIterator[str]:
        """Yield the assistant's reply piece by piece as the model generates it."""
        ...

    async def check_health(self) -> bool:
        """Return True if the model server is reachable and has our model available."""
        ...


class OpenAICompatibleLLM:
    """LLMClient implementation backed by the official ``openai`` Python SDK."""

    def __init__(self, settings: Settings) -> None:
        self._model = settings.llm_model
        self._temperature = settings.llm_temperature
        self._max_tokens = settings.llm_max_tokens
        self._reasoning_effort = settings.llm_reasoning_effort
        # AsyncOpenAI is the asyncio flavour of the SDK. Pointing base_url at
        # Ollama's /v1 endpoint makes every call go to Ollama instead of OpenAI.
        # max_retries=0: a retry partway through a stream would repeat tokens
        # the user already saw, so we report the failure instead.
        self._client = AsyncOpenAI(
            base_url=settings.llm_base_url,
            api_key=settings.llm_api_key,
            timeout=settings.llm_timeout_seconds,
            max_retries=0,
        )

    async def stream_chat(self, messages: list[dict[str, str]]) -> AsyncIterator[str]:
        # stream=True makes the server send the reply in many small "chunks"
        # as it's generated, instead of one response at the end.
        stream = await self._client.chat.completions.create(
            model=self._model,
            # The SDK's message type is a big union of TypedDicts. Our plain
            # {"role", "content"} dicts match it at runtime; the cast just
            # tells the type checker that.
            messages=cast(Any, messages),
            temperature=self._temperature,
            max_tokens=self._max_tokens,
            # Limits Granite's hidden "thinking" (see config.py). Passing
            # openai.omit instead of None leaves the field out of the request.
            reasoning_effort=self._reasoning_effort or openai.omit,
            stream=True,
        )
        got_answer = False
        finish_reason: str | None = None
        # `async with` closes the HTTP connection to Ollama even if we stop
        # early, e.g. because the user pressed Stop. Closing it makes Ollama
        # stop generating instead of wasting compute on an unwanted answer.
        async with stream:
            async for chunk in stream:
                # Each chunk has a list of "choices" (we only ever ask for one).
                if not chunk.choices:
                    continue
                choice = chunk.choices[0]
                # The last chunk says why generation ended: "stop" (finished
                # normally) or "length" (hit max_tokens).
                finish_reason = choice.finish_reason or finish_reason
                # `delta.content` is the visible answer. Reasoning models also
                # stream their thinking, which Ollama puts in a separate
                # `delta.reasoning` field; we don't show that, so it's ignored
                # here. `content` is None or "" on thinking-only chunks.
                text = choice.delta.content
                if text:
                    got_answer = True
                    yield text

        # Report outcomes that would otherwise look like a silent, empty "success".
        if finish_reason == "length":
            raise AnswerTruncatedError(got_answer)
        if not got_answer:
            raise EmptyAnswerError()

    async def check_health(self) -> bool:
        try:
            # GET /v1/models lists the models Ollama has downloaded. If ours is
            # in the list, chat requests should work.
            models = await self._client.models.list()
        except Exception:
            return False
        return any(m.id == self._model for m in models.data)
