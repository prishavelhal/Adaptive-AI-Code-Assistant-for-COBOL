"""Critic agent: checks the Explainer's finished answer against the code.

It runs after the answer has streamed, so it can't change what the user already
read. Instead it reports possible problems, which the orchestrator sends as a
`verification` event.

Two layers:

1. Built-in checks (always on, no model call). They catch the most common
   small-model mistakes mechanically:
     * a "line N" reference outside the code that was attached;
     * a COBOL-style name (e.g. ``2000-CALC-TAX``) that appears nowhere in the
       attached code or the conversation, i.e. most likely invented.
2. Model review (optional, ``COBOLTUTOR_AGENT_LLM_REVIEW``). A second Granite
   call, through the same LLMClient, asked to list factual mistakes as JSON.
   If the model fails or replies with something that isn't the expected JSON,
   the review is skipped: the Critic must never break an answer that already
   succeeded.
"""

import json
import logging
import re
from dataclasses import asdict, dataclass
from typing import Literal

from ..config import Settings
from ..llm import LLMClient
from ..prompts import render_code_context
from ..schemas import ChatRequest, CodeContext
from .analyzer import CodeAnalysis, render_analysis
from .explainer import load_prompt

logger = logging.getLogger("coboltutor.agents")


@dataclass(frozen=True)
class Issue:
    """One possible problem in the answer."""

    source: Literal["check", "review"]  # built-in check, or the model review
    message: str
    line: int | None = None


@dataclass
class Verification:
    """What the Critic found. Sent to the client as the `verification` event."""

    issues: list[Issue]
    reviewed_by_model: bool  # True only if the model review ran and parsed

    def to_event(self) -> dict[str, object]:
        return {
            "issues": [asdict(i) for i in self.issues],
            "reviewed_by_model": self.reviewed_by_model,
        }


# --- Layer 1: built-in checks -----------------------------------------------------

# "line 42", "lines 10-20", "lines 10 to 20", "lines 10 and 12" (en dash too).
_LINE_REF = re.compile(r"\blines?\s+(\d+)(?:\s*(?:-|–|to|and|through)\s*(\d+))?", re.I)

# A COBOL-style user-defined name: upper case with at least one hyphen,
# e.g. WS-GROSS or 2000-PROCESS-EMPLOYEE. Single words (MOVE, TOTAL) are skipped:
# they are too often ordinary English or keywords to judge reliably. The
# (?=...[A-Z]) lookahead requires at least one letter, so number ranges such as
# "5-9" or dates such as "2026-11-19" are not mistaken for names.
_COBOL_NAME = re.compile(
    r"(?<![A-Za-z0-9-])(?=[A-Z0-9-]*[A-Z])[A-Z0-9]+(?:-[A-Z0-9]+)+(?![A-Za-z0-9-])"
)

# Hyphenated words a correct answer may use even when the code doesn't contain
# them: reserved words, intrinsic functions, and common non-COBOL terms.
_ALWAYS_KNOWN = {
    # scope terminators
    *(
        f"END-{v}"
        for v in (
            "ACCEPT ADD CALL COMPUTE DELETE DISPLAY DIVIDE EVALUATE EXEC IF MULTIPLY "
            "PERFORM READ RETURN REWRITE SEARCH START STRING SUBTRACT UNSTRING WRITE"
        ).split()
    ),
    "END-OF-FILE", "END-OF-PAGE",
    # divisions, sections, paragraphs in the IDENTIFICATION/ENVIRONMENT DIVISIONs
    "PROGRAM-ID", "CLASS-ID", "METHOD-ID", "WORKING-STORAGE", "LOCAL-STORAGE",
    "FILE-CONTROL", "INPUT-OUTPUT", "I-O", "I-O-CONTROL", "SOURCE-COMPUTER",
    "OBJECT-COMPUTER", "SPECIAL-NAMES", "DATE-WRITTEN", "DATE-COMPILED", "END-PROGRAM",
    "DECIMAL-POINT", "CODE-SET", "SEGMENT-LIMIT",
    # file organisation and record handling
    "LINE-SEQUENTIAL", "RECORD-SEQUENTIAL", "RELATIVE-KEY", "RECORD-KEY",
    "ALTERNATE-KEY", "FILE-STATUS", "SORT-MERGE",
    # data categories, usage, and figurative constants
    "NUMERIC-EDITED", "ALPHANUMERIC-EDITED", "NATIONAL-EDITED", "ALPHABETIC-LOWER",
    "ALPHABETIC-UPPER", "PROCEDURE-POINTER", "FUNCTION-POINTER",
    *(f"COMP-{n}" for n in "12345"), *(f"COMPUTATIONAL-{n}" for n in "12345"),
    "PACKED-DECIMAL", "HIGH-VALUE", "HIGH-VALUES", "LOW-VALUE", "LOW-VALUES",
    "SHIFT-IN", "SHIFT-OUT",
    # special registers
    "RETURN-CODE", "SORT-RETURN", "SORT-CONTROL", "SORT-CORE-SIZE", "SORT-FILE-SIZE",
    "SORT-MESSAGE", "SORT-MODE-SIZE", "WHEN-COMPILED", "LINAGE-COUNTER",
    "LINE-COUNTER", "PAGE-COUNTER", "DEBUG-ITEM", "XML-CODE", "XML-EVENT", "XML-TEXT",
    "XML-NTEXT", "JSON-CODE", "JSON-STATUS", "DAY-OF-WEEK", "TIME-OF-DAY",
    # common intrinsic functions
    "CURRENT-DATE", "NUMVAL-C", "NUMVAL-F", "UPPER-CASE", "LOWER-CASE",
    "INTEGER-OF-DATE", "DATE-OF-INTEGER", "INTEGER-OF-DAY", "DAY-OF-INTEGER",
    "DATE-TO-YYYYMMDD", "DAY-TO-YYYYDDD", "YEAR-TO-YYYY",
    "DISPLAY-OF", "NATIONAL-OF", "TEST-NUMVAL", "TEST-DATE-YYYYMMDD",
    # general programming terms that explanations write in capitals
    "IF-ELSE", "IF-THEN", "IF-THEN-ELSE", "DO-WHILE", "DO-UNTIL", "GO-TO",
    "TOP-DOWN", "Z-OS",
}  # fmt: skip

# Standards, encodings, and dialect names with a number: ISO-8601, IEEE-754,
# UTF-16, ANSI-85, COBOL-74, IBM-1047, CP-037, ... A user-defined name such as
# "TOTAL-2" never starts with one of these prefixes, so this can't hide it.
_STANDARD_NAME = re.compile(r"^(?:ISO|IEEE|UTF|UCS|ANSI|COBOL|IBM|CP|RFC|ECMA|X3)(?:-\d+)+$")


def _known_names(request: ChatRequest) -> set[str]:
    """Every hyphenated name the answer could legitimately mention.

    That is: anything in any code attached during the conversation (not only the
    latest, since follow-ups may refer back), anything the user typed, and the
    reserved words above. Matching against the raw text (not the Analyzer's
    lists) means keywords in the code, like WORKING-STORAGE, never get flagged.

    Earlier *assistant* answers are deliberately not trusted: if the model
    invented a name once, repeating it in a follow-up must still be flagged.
    """
    known = set(_ALWAYS_KNOWN)
    for msg in request.messages:
        if msg.role != "user":
            continue
        texts = [msg.content.upper()]
        if msg.code_context is not None:
            texts.append(msg.code_context.code.upper())
        for text in texts:
            known.update(_COBOL_NAME.findall(text))
    return known


def _code_ranges(request: ChatRequest) -> list[CodeContext]:
    return [m.code_context for m in request.messages if m.code_context is not None]


def check_answer(answer: str, request: ChatRequest, analysis: CodeAnalysis) -> list[Issue]:
    """Layer 1: mechanical checks. Pure function, no I/O."""
    issues: list[Issue] = []

    # --- line references outside every attached range -------------------------
    contexts = _code_ranges(request)
    first = min(c.start_line for c in contexts) if contexts else analysis.start_line
    last = max(c.end_line for c in contexts) if contexts else analysis.end_line

    def in_range(n: int) -> bool:
        return any(c.start_line <= n <= c.end_line for c in contexts)

    reported_lines: set[int] = set()
    for m in _LINE_REF.finditer(answer):
        for group in (m.group(1), m.group(2)):
            if group is None:
                continue
            n = int(group)
            if not in_range(n) and n not in reported_lines:
                reported_lines.add(n)
                issues.append(
                    Issue(
                        "check",
                        f"The answer mentions line {n}, but the attached code covers "
                        f"lines {first}-{last}.",
                        n,
                    )
                )

    # --- names that appear nowhere in the code or conversation -----------------
    known = _known_names(request)
    # Names defined in a copybook aren't in the attached code, so soften the
    # message when the code COPYs anything: the name may be real, just unseen.
    hint = (
        " It may come from a copybook (COPY), which wasn't attached." if analysis.copybooks else ""
    )
    reported_names: set[str] = set()
    for name in _COBOL_NAME.findall(answer):
        if name in known or name in reported_names or _STANDARD_NAME.match(name):
            continue
        reported_names.add(name)
        issues.append(
            Issue(
                "check",
                f"The answer mentions `{name}`, which doesn't appear in the attached code.{hint}",
            )
        )
    return issues


# --- Layer 2: model review ------------------------------------------------------------


def build_review_messages(
    answer: str, ctx: CodeContext, analysis: CodeAnalysis, settings: Settings
) -> list[dict[str, str]]:
    """The review prompt. Code is rendered by the existing prompts.render_code_context."""
    user = "\n\n".join(
        [
            render_code_context(ctx, settings.max_code_chars),
            "Structural analysis:\n" + render_analysis(analysis),
            "Tutor's answer to review:\n<answer>\n" + answer + "\n</answer>",
        ]
    )
    return [
        {"role": "system", "content": load_prompt("critic.md")},
        {"role": "user", "content": user},
    ]


def parse_review(text: str) -> list[Issue] | None:
    """Pull the issues out of the model's reply. None if it isn't usable JSON.

    Small models often wrap JSON in prose or a ```json fence, so we parse the
    outermost {...} block rather than the whole reply.
    """
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        data = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    raw = data.get("issues") if isinstance(data, dict) else None
    if not isinstance(raw, list):
        return None
    issues: list[Issue] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        problem = item.get("problem")
        if not isinstance(problem, str) or not problem.strip():
            continue
        line = item.get("line")
        issues.append(Issue("review", problem.strip(), line if isinstance(line, int) else None))
    return issues


async def review_answer(
    answer: str,
    ctx: CodeContext,
    analysis: CodeAnalysis,
    settings: Settings,
    llm: LLMClient,
) -> list[Issue] | None:
    """Layer 2: ask the model. Returns None (review skipped) on any failure."""
    try:
        reply = "".join(
            [
                t
                async for t in llm.stream_chat(
                    build_review_messages(answer, ctx, analysis, settings)
                )
            ]
        )
    except Exception:
        # The answer itself already succeeded; a failed review must not turn it
        # into an error. Log it and carry on without the review.
        logger.warning("critic model review failed; skipping it", exc_info=True)
        return None
    issues = parse_review(reply)
    if issues is None:
        logger.warning("critic model review returned unusable output; skipping it")
    return issues


# --- The agent ------------------------------------------------------------------------


async def verify(
    answer: str,
    request: ChatRequest,
    ctx: CodeContext,
    analysis: CodeAnalysis,
    settings: Settings,
    llm: LLMClient,
    *,
    use_model: bool,
    max_issues: int,
) -> Verification:
    """Run the built-in checks and, if enabled, the model review."""
    issues = check_answer(answer, request, analysis)
    reviewed = False
    if use_model:
        review = await review_answer(answer, ctx, analysis, settings, llm)
        if review is not None:
            reviewed = True
            issues.extend(review)
    return Verification(issues=issues[:max_issues], reviewed_by_model=reviewed)
