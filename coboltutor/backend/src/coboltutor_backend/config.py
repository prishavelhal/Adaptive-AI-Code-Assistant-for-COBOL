"""Application settings.

Every setting can be overridden with an environment variable of the same name
prefixed with ``COBOLTUTOR_`` (case-insensitive), e.g. ``COBOLTUTOR_LLM_MODEL``.
Docker Compose sets these in docker-compose.yml; for local development you can
also put them in ``backend/.env``.
"""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Tell pydantic-settings where to look for values and how they're named.
    model_config = SettingsConfigDict(
        env_prefix="COBOLTUTOR_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",  # ignore unrelated COBOLTUTOR_* vars instead of crashing
    )

    # --- HTTP server ---------------------------------------------------------
    # 0.0.0.0 so the server is reachable from outside its Docker container.
    # (docker-compose.yml only publishes the port on 127.0.0.1, so it is still
    # not exposed to your network.)
    host: str = "0.0.0.0"
    port: int = 8000

    # --- Language model ------------------------------------------------------
    # Ollama serves an OpenAI-compatible API under /v1. Inside Docker Compose the
    # Ollama container is reachable by its service name, "ollama"; when running
    # the backend directly on your machine it's localhost.
    llm_base_url: str = "http://localhost:11434/v1"
    # Ollama's tag for IBM Granite 4.2, 8-billion-parameter variant.
    llm_model: str = "granite4.2:8b"
    # Ollama ignores the API key, but the OpenAI SDK refuses to start without one.
    llm_api_key: str = "ollama"
    # Low temperature = more deterministic, factual answers, which suits a tutor.
    llm_temperature: float = 0.2
    # Upper bound on the length of a single answer (in tokens). For a reasoning
    # model like Granite 4.2 this budget covers the hidden "thinking" tokens AND
    # the visible answer, so it needs headroom beyond the answer itself.
    llm_max_tokens: int = 6144
    # How much Granite 4.2 "thinks" before answering. Ollama's OpenAI-compatible
    # API maps this to the model's thinking mode:
    #   "none"  - no thinking: fastest
    #   "low"   - a brief plan before answering (default): fast, rarely runs long
    #   "medium"/"high" - long reasoning: slower, and can use up llm_max_tokens
    #                     before any answer appears
    # Measured on a short question: default ~12s, "low" ~1.3s, "none" ~1.0s.
    # Set to None to leave the parameter out entirely (for servers that reject it).
    llm_reasoning_effort: Literal["none", "low", "medium", "high"] | None = "low"
    # How long to wait for the model before giving up (seconds). Generous because
    # the first request after startup may need to load the model into memory.
    llm_timeout_seconds: float = 300.0

    # --- Prompt size limits --------------------------------------------------
    # Granite 4.2 has a large context window, but local hardware is the real
    # limit: long prompts are slow on CPU. These caps keep requests reasonable.
    #
    # IMPORTANT: the prompt plus llm_max_tokens must fit in the model's context
    # window, which Ollama sets with OLLAMA_CONTEXT_LENGTH in docker-compose.yml
    # (16384 there). If it doesn't fit, Ollama silently drops half the context,
    # system prompt and code included, partway through the answer.
    # Budget: ~8k tokens of code + ~1k system prompt/history + 6k answer < 16k.
    # (A section-by-section explanation of the 170-line PAYROLL.cbl sample was
    # ~3.7k tokens, so 4k would have been cutting it close.)
    # Max characters of user code included in one prompt (~8k tokens with line numbers).
    max_code_chars: int = 24_000
    # Max number of past chat messages sent to the model (oldest dropped first).
    max_history_messages: int = 20


@lru_cache
def get_settings() -> Settings:
    """Return the (cached) settings object.

    Using a function instead of a module-level global lets tests swap in custom
    settings through FastAPI's dependency overrides.
    """
    return Settings()
