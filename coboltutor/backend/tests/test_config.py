"""Tests for settings loaded from environment variables."""

import pytest

from coboltutor_backend.config import Settings


def test_empty_reasoning_effort_means_omit(monkeypatch: pytest.MonkeyPatch) -> None:
    # The cluster profile (profiles/cluster-vllm.conf) relies on this.
    monkeypatch.setenv("COBOLTUTOR_LLM_REASONING_EFFORT", "")
    assert Settings(_env_file=None).llm_reasoning_effort is None


def test_reasoning_effort_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("COBOLTUTOR_LLM_REASONING_EFFORT", "none")
    assert Settings(_env_file=None).llm_reasoning_effort == "none"


def test_reasoning_effort_default_is_low(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("COBOLTUTOR_LLM_REASONING_EFFORT", raising=False)
    assert Settings(_env_file=None).llm_reasoning_effort == "low"
