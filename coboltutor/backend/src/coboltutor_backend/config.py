"""Application settings.

Every setting can be overridden with an environment variable of the same name
prefixed with ``COBOLTUTOR_`` (case-insensitive), e.g. ``COBOLTUTOR_LLM_MODEL``.
Docker Compose sets these in docker-compose.yml; for local development you can
also put them in ``backend/.env``.
"""

from functools import lru_cache
from typing import Literal

from pydantic import SecretStr
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

    # --- RAG: retrieval-augmented generation ----------------------------------
    # RAG = before answering, look up relevant passages in our knowledge base
    # (coboltutor/knowledge-base/) and give them to the model, so answers are
    # grounded in real documentation and can cite their sources (FR-3).
    # See coboltutor_backend/rag/__init__.py for how the pieces fit together.
    #
    # Off by default: the RAG package is a skeleton and nothing calls it yet.
    # Turning this on before retrieval is implemented will not change behaviour.
    rag_enabled: bool = False

    # Connection string for PostgreSQL with the pgvector extension, e.g.
    #   postgresql://USER:PASSWORD@HOST:5432/DBNAME
    # No default on purpose: credentials must come from the environment
    # (COBOLTUTOR_DATABASE_URL in .env), never from code (see AGENTS.md).
    # SecretStr keeps the password out of logs and error messages; call
    # .get_secret_value() only at the point of connecting.
    database_url: SecretStr | None = None

    # The embedding model turns text into a vector (a list of numbers) so that
    # passages with similar meaning end up close together. It is a separate
    # model from the chat model above, served separately, because:
    #   - on the HPC cluster, vLLM serves only the 30B chat model, and
    #   - the SAME embedding model must be used to build the index (ingestion)
    #     and to search it (every question), on every machine. Vectors from
    #     different models, or even differently quantized copies of one model,
    #     are not comparable. rag/retriever.py checks this before searching.
    #
    # Default: IBM granite-embedding-english-r2 (149M parameters, 768-dim
    # vectors, reads up to 8192 tokens, Apache 2.0). Chosen provisionally over
    # granite-embedding:278m, which reads only 512 tokens and so cannot embed a
    # long COBOL paragraph whole. Not final: compare candidates on real COBOL
    # questions before committing to one.
    # TODO: decide how r2 is served locally. Ollama's official library only has
    # the older granite-embedding sizes, so this model name and URL are
    # placeholders until that is settled.
    embedding_base_url: str = "http://localhost:11434/v1"
    embedding_model: str = "granite-embedding-english-r2"
    # Only needed if the embedding server requires one (e.g. vLLM started with
    # --api-key). Like database_url, it comes from the environment only.
    embedding_api_key: SecretStr | None = None
    # Length of each vector. MUST match the model (768 for granite-embedding-
    # english-r2) and the vector column in rag/schema.sql. pgvector can only
    # index up to 2000 dimensions for the `vector` type.
    embedding_dimensions: int = 768
    # Most tokens the embedding model reads; text beyond this is silently cut
    # off by the model. The chunker uses it to decide when a chunk is too long.
    embedding_max_input_tokens: int = 8192
    # How many passages to send to the embedding server per request during
    # ingestion. Batching is much faster than one request per chunk.
    embedding_batch_size: int = 32

    # How many passages to retrieve per question.
    rag_top_k: int = 5
    # Max characters of retrieved passages added to one prompt (~2k tokens).
    # Retrieved text shares the context window with the user's code, the chat
    # history, and the answer (see "Prompt size limits" above), so it gets its
    # own budget. Raise it together with the context window, e.g. on the cluster.
    rag_max_context_chars: int = 8_000


@lru_cache
def get_settings() -> Settings:
    """Return the (cached) settings object.

    Using a function instead of a module-level global lets tests swap in custom
    settings through FastAPI's dependency overrides.
    """
    return Settings()
