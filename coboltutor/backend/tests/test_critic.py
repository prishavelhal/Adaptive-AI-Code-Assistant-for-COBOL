"""Tests for the Critic agent (agents/critic.py) and its place in /api/agent-chat."""

from collections.abc import AsyncIterator

from fastapi.testclient import TestClient

# pytest puts tests/ on sys.path, so the sibling module imports directly.
from test_api import client, parse_sse

from coboltutor_backend.agents.analyzer import analyze
from coboltutor_backend.agents.critic import check_answer, parse_review
from coboltutor_backend.agents.settings import AgentSettings, get_agent_settings
from coboltutor_backend.main import app, get_llm
from coboltutor_backend.schemas import ChatRequest, CodeContext

__all__ = ["client"]  # re-exported pytest fixture

CODE = (
    "       PROCEDURE DIVISION.\n"
    "       0000-MAIN.\n"
    "           PERFORM 1000-GREET\n"
    "           STOP RUN.\n"
    "       1000-GREET.\n"
    "           DISPLAY WS-MESSAGE."
)


def make_request(code: str = CODE, start_line: int = 1, question: str = "Explain") -> ChatRequest:
    ctx = CodeContext(
        file_name="HELLO.cbl",
        language_id="cobol",
        code=code,
        start_line=start_line,
        end_line=start_line + len(code.splitlines()) - 1,
    )
    return ChatRequest.model_validate(
        {"messages": [{"role": "user", "content": question, "code_context": ctx.model_dump()}]}
    )


def check(answer: str, request: ChatRequest | None = None) -> list[str]:
    request = request or make_request()
    ctx = request.messages[-1].code_context
    assert ctx is not None
    return [i.message for i in check_answer(answer, request, analyze(ctx))]


# --- Built-in checks ------------------------------------------------------------


def test_correct_answer_has_no_issues() -> None:
    answer = (
        "On line 3, `0000-MAIN` performs `1000-GREET` (lines 5-6), which displays "
        "WS-MESSAGE. STOP RUN on line 4 ends the program. WORKING-STORAGE would "
        "normally define WS-MESSAGE."
    )
    assert check(answer) == []


def test_flags_line_outside_attached_code() -> None:
    issues = check("The loop on line 42 repeats until done.")
    assert issues == ["The answer mentions line 42, but the attached code covers lines 1-6."]


def test_line_range_end_is_checked_and_reported_once() -> None:
    issues = check("Lines 5-9 print the greeting. Line 9 is the last.")
    assert issues == ["The answer mentions line 9, but the attached code covers lines 1-6."]


def test_selection_offsets_are_respected() -> None:
    request = make_request(start_line=100)
    assert check("Line 102 performs 1000-GREET.", request) == []
    assert len(check("Line 3 performs 1000-GREET.", request)) == 1


def test_flags_invented_names() -> None:
    issues = check("Then 2000-CALC-TAX computes WS-TAX-RATE.")
    assert issues == [
        "The answer mentions `2000-CALC-TAX`, which doesn't appear in the attached code.",
        "The answer mentions `WS-TAX-RATE`, which doesn't appear in the attached code.",
    ]


def test_names_the_user_typed_are_not_flagged() -> None:
    request = make_request(question="Would WS-COUNTER work here?")
    assert check("Yes, WS-COUNTER would work.", request) == []


def test_reserved_words_and_lowercase_text_are_not_flagged() -> None:
    answer = "Use COMP-3 or PACKED-DECIMAL; END-IF closes it; this is well-known and UTF-8 safe."
    assert check(answer) == []


# --- Model review parsing -----------------------------------------------------------


def test_parse_review_accepts_fenced_json() -> None:
    issues = parse_review('Sure!\n```json\n{"issues": [{"line": 3, "problem": "Wrong"}]}\n```')
    assert issues is not None
    assert [(i.source, i.line, i.message) for i in issues] == [("review", 3, "Wrong")]


def test_parse_review_rejects_garbage_and_skips_bad_items() -> None:
    assert parse_review("no json here") is None
    assert parse_review('{"issues": "nope"}') is None
    issues = parse_review('{"issues": [{"problem": ""}, "x", {"line": "4", "problem": "Bad"}]}')
    assert issues is not None
    assert [(i.line, i.message) for i in issues] == [(None, "Bad")]


# --- In the pipeline -----------------------------------------------------------------


class ScriptedLLM:
    """Returns a different reply per call: first the answer, then the review."""

    def __init__(self, *replies: list[str] | Exception) -> None:
        self.replies = list(replies)
        self.calls: list[list[dict[str, str]]] = []

    async def stream_chat(self, messages: list[dict[str, str]]) -> AsyncIterator[str]:
        self.calls.append(messages)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        for t in reply:
            yield t

    async def check_health(self) -> bool:
        return True


def run(
    client: TestClient, llm: ScriptedLLM, llm_review: bool
) -> list[tuple[str, dict[str, object]]]:
    app.dependency_overrides[get_llm] = lambda: llm
    app.dependency_overrides[get_agent_settings] = lambda: AgentSettings(llm_review=llm_review)
    body = make_request().model_dump()
    res = client.post("/api/agent-chat", json=body)
    assert res.status_code == 200
    return parse_sse(res.text)


def test_issues_are_sent_before_done(client: TestClient) -> None:
    events = run(client, ScriptedLLM(["See line 99."]), llm_review=False)
    assert [e for e, _ in events][-3:] == ["stage", "verification", "done"]
    verification = events[-2][1]
    assert verification["reviewed_by_model"] is False
    assert verification["issues"] == [
        {
            "source": "check",
            "message": "The answer mentions line 99, but the attached code covers lines 1-6.",
            "line": 99,
        }
    ]


def test_model_review_runs_when_enabled(client: TestClient) -> None:
    review = '{"issues": [{"line": 6, "problem": "WS-MESSAGE is displayed, not computed."}]}'
    llm = ScriptedLLM(["It computes WS-MESSAGE."], [review])
    events = run(client, llm, llm_review=True)
    verification = events[-2][1]
    assert verification["reviewed_by_model"] is True
    assert verification["issues"] == [
        {"source": "review", "message": "WS-MESSAGE is displayed, not computed.", "line": 6}
    ]
    # The reviewer saw the code (line-numbered by the shared renderer) and the answer.
    review_prompt = llm.calls[1][-1]["content"]
    assert "6| " in review_prompt and "It computes WS-MESSAGE." in review_prompt


def test_failed_model_review_never_breaks_the_answer(client: TestClient) -> None:
    llm = ScriptedLLM(["Fine answer."], RuntimeError("model crashed"))
    events = run(client, llm, llm_review=True)
    assert events[-1] == ("done", {})
    assert events[-2] == ("verification", {"issues": [], "reviewed_by_model": False})
