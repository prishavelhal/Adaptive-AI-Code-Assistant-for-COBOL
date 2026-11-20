"""Tests for POST /api/agent-chat (the agent pipeline), using the existing fake LLM.

FakeLLM, parse_sse, and the client fixture come from test_api.py, so both
endpoints are exercised with exactly the same fake model.
"""

import httpx
import openai
from fastapi.testclient import TestClient

# pytest puts tests/ on sys.path, so the sibling module imports directly.
from test_api import FakeLLM, client, parse_sse, use_llm

from coboltutor_backend.llm import AnswerTruncatedError

__all__ = ["client"]  # re-exported pytest fixture

CODE = {
    "file_name": "HELLO.cbl",
    "language_id": "cobol",
    "code": "       PROCEDURE DIVISION.\n       0000-MAIN.\n           PERFORM 1000-GREET\n"
    "           STOP RUN.\n       1000-GREET.\n           DISPLAY 'HI'.",
    "start_line": 1,
    "end_line": 6,
    "is_selection": False,
}


def post(client: TestClient, body: dict[str, object]) -> list[tuple[str, dict[str, object]]]:
    res = client.post("/api/agent-chat", json=body)
    assert res.status_code == 200
    assert res.headers["content-type"].startswith("text/event-stream")
    return parse_sse(res.text)


def test_stages_then_tokens_then_done(client: TestClient) -> None:
    use_llm(FakeLLM(["Hello", " world"]))
    events = post(
        client, {"messages": [{"role": "user", "content": "Explain", "code_context": CODE}]}
    )
    assert events == [
        ("stage", {"name": "analyze"}),
        ("stage", {"name": "explain"}),
        ("token", {"text": "Hello"}),
        ("token", {"text": " world"}),
        ("done", {}),
    ]


def test_analysis_reaches_the_model(client: TestClient) -> None:
    llm = FakeLLM(["ok"])
    use_llm(llm)
    post(client, {"messages": [{"role": "user", "content": "Explain", "code_context": CODE}]})
    last = llm.received[-1]["content"]
    # The analysis note comes first, then the existing prompt's code block and question.
    assert last.index("Structural analysis") < last.index("Full file from `HELLO.cbl`")
    assert "0000-MAIN (line 2)" in last
    assert "line 3: PERFORM 1000-GREET" in last
    assert last.rstrip().endswith("Explain")


def test_same_prompt_as_api_chat_when_no_code(client: TestClient) -> None:
    # With no code attached there's nothing to analyze, so the agent endpoint
    # must send the model exactly what /api/chat sends.
    body = {"messages": [{"role": "user", "content": "What is COMP-3?"}]}
    agent_llm, chat_llm = FakeLLM(["a"]), FakeLLM(["a"])
    use_llm(agent_llm)
    post(client, body)
    use_llm(chat_llm)
    client.post("/api/chat", json=body)
    assert agent_llm.received == chat_llm.received


def test_errors_use_the_shared_messages(client: TestClient) -> None:
    use_llm(FakeLLM(["partial"], error=AnswerTruncatedError(got_answer=True)))
    events = post(client, {"messages": [{"role": "user", "content": "Explain"}]})
    assert events[-2] == ("token", {"text": "partial"})
    assert events[-1][0] == "error"
    assert "cut off" in str(events[-1][1]["message"])


def test_unexpected_error_is_reported_in_stream(client: TestClient) -> None:
    err = openai.APIConnectionError(request=httpx.Request("POST", "http://ollama"))
    use_llm(FakeLLM([], error=err))
    events = post(client, {"messages": [{"role": "user", "content": "Hi"}]})
    assert events[-1][0] == "error"
    assert "Could not reach the model server" in str(events[-1][1]["message"])


def test_invalid_body_is_rejected_like_api_chat(client: TestClient) -> None:
    use_llm(FakeLLM([]))
    res = client.post("/api/agent-chat", json={"messages": [{"role": "assistant", "content": "x"}]})
    assert res.status_code == 422
