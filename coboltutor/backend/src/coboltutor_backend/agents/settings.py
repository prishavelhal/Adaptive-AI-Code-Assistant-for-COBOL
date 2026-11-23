"""Settings for the agent pipeline only.

These live in their own class (rather than as new fields on config.Settings) so
the agent work doesn't change the shared settings object. They are read from
environment variables prefixed with ``COBOLTUTOR_AGENT_``, e.g.
``COBOLTUTOR_AGENT_LLM_REVIEW=true``, or from ``backend/.env``.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class AgentSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="COBOLTUTOR_AGENT_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Critic ----------------------------------------------------------------
    # The Critic's built-in checks (line numbers, unknown names) always run: they
    # need no model and take microseconds. The model review is a second Granite
    # call after every answer. On a laptop that adds several seconds (longer on
    # CPU) during which the extension still shows the answer as in progress, so
    # it is off by default. Turn it on for evaluation runs or on the GPU cluster.
    llm_review: bool = False
    # Most issues reported per answer, so a confused answer can't flood the UI.
    max_issues: int = 8


@lru_cache
def get_agent_settings() -> AgentSettings:
    """Cached settings; tests replace this with FastAPI's dependency_overrides."""
    return AgentSettings()
