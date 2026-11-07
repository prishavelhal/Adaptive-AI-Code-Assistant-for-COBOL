"""Unit tests for prompt construction (coboltutor_backend.prompts)."""

from coboltutor_backend.config import Settings
from coboltutor_backend.prompts import (
    SYSTEM_PROMPT,
    _fence_for,
    _number_lines,
    _truncate_code,
    build_messages,
    render_code_context,
)
from coboltutor_backend.schemas import ChatMessage, ChatRequest, CodeContext

SAMPLE = "       IDENTIFICATION DIVISION.\n       PROGRAM-ID. HELLO.\n"


def make_ctx(code: str = SAMPLE, **kw: object) -> CodeContext:
    return CodeContext(file_name="HELLO.cbl", language_id="cobol", code=code, **kw)  # type: ignore[arg-type]


def test_number_lines_aligns_numbers_and_starts_at_offset() -> None:
    out = _number_lines("A\nB\nC", start_line=9)
    # 9, 10, 11 -> width 2, so 9 is padded with one space.
    assert out.splitlines() == [" 9| A", "10| B", "11| C"]


def test_fence_is_longer_than_backticks_in_code() -> None:
    assert _fence_for("no ticks") == "```"
    assert _fence_for("has ```` four") == "`````"


def test_truncate_cuts_on_line_boundary() -> None:
    code, truncated = _truncate_code("aaaa\nbbbb\ncccc", max_chars=11)
    assert truncated is True
    assert code == "aaaa\nbbbb"
    assert _truncate_code("short", 100) == ("short", False)


def test_render_code_context_includes_header_and_numbered_code() -> None:
    out = render_code_context(make_ctx(start_line=5, end_line=6, is_selection=True), 10_000)
    assert "Selected code from `HELLO.cbl` (lines 5-6)" in out
    assert "5|        IDENTIFICATION DIVISION." in out
    assert "```cobol" in out
    assert "cut off" not in out


def test_render_code_context_reports_truncation() -> None:
    long_code = "\n".join(f"       DISPLAY {i}." for i in range(1000))
    out = render_code_context(make_ctx(code=long_code), max_chars=200)
    assert "cut off" in out


def test_build_messages_starts_with_system_prompt() -> None:
    req = ChatRequest(messages=[ChatMessage(role="user", content="What is COBOL?")])
    msgs = build_messages(req, Settings())
    assert msgs[0] == {"role": "system", "content": SYSTEM_PROMPT}
    assert msgs[1] == {"role": "user", "content": "What is COBOL?"}


def test_only_latest_code_context_is_included_in_full() -> None:
    old = make_ctx(code="       OLD-CODE.\n")
    new = make_ctx(code="       NEW-CODE.\n")
    req = ChatRequest(
        messages=[
            ChatMessage(role="user", content="explain", code_context=old),
            ChatMessage(role="assistant", content="It is old."),
            ChatMessage(role="user", content="and this?", code_context=new),
        ]
    )
    msgs = build_messages(req, Settings())
    assert "OLD-CODE" not in msgs[1]["content"]
    assert "Earlier I attached code" in msgs[1]["content"]
    assert "NEW-CODE" in msgs[3]["content"]


def test_history_is_trimmed() -> None:
    turns = [
        ChatMessage(role="user" if i % 2 == 0 else "assistant", content=f"m{i}") for i in range(9)
    ]
    msgs = build_messages(ChatRequest(messages=turns), Settings(max_history_messages=3))
    # system prompt + the last 3 turns
    assert [m["content"] for m in msgs[1:]] == ["m6", "m7", "m8"]
