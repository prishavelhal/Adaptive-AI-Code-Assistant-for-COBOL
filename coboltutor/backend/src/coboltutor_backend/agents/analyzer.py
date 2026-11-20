"""Analyzer agent: turns attached COBOL into a structural summary.

This agent does not call the model. Finding divisions, paragraphs, PERFORM
targets, and data items is pattern matching, which plain Python does instantly
and exactly; a small local model asked to do it tends to invent paragraphs.
The summary is handed to the Explainer as ground truth, and later to the Critic
as something to check claims against.

It handles fixed-format source (sequence area in columns 1-6, indicator in
column 7) and free-format source. It is a best-effort scanner, not a full COBOL
parser: anything it doesn't recognise is skipped rather than guessed at.
"""

import re
from dataclasses import dataclass, field

from ..schemas import CodeContext

# --- Data shapes ---------------------------------------------------------------


@dataclass(frozen=True)
class Located:
    """A name found at a 1-based line number in the user's file."""

    name: str
    line: int


@dataclass(frozen=True)
class DataItem:
    """One DATA DIVISION entry, e.g. ``05 EMP-RATE PIC 9(3)V99``."""

    level: str
    name: str
    line: int
    picture: str | None = None
    usage: str | None = None  # e.g. COMP-3
    occurs: str | None = None  # e.g. "5" from OCCURS 5 TIMES
    redefines: str | None = None


@dataclass(frozen=True)
class Reference:
    """A control-flow reference such as ``PERFORM 2000-PROCESS`` on a given line."""

    verb: str  # PERFORM, GO TO, or CALL
    target: str
    line: int


@dataclass
class CodeAnalysis:
    """Everything the Analyzer found in one piece of code."""

    file_name: str
    start_line: int
    end_line: int
    is_selection: bool
    program_id: str | None = None
    divisions: list[Located] = field(default_factory=list)
    sections: list[Located] = field(default_factory=list)
    paragraphs: list[Located] = field(default_factory=list)
    data_items: list[DataItem] = field(default_factory=list)
    references: list[Reference] = field(default_factory=list)
    files: list[Located] = field(default_factory=list)  # SELECT ... ASSIGN
    embedded: list[Located] = field(default_factory=list)  # EXEC SQL / EXEC CICS / ...

    @property
    def unresolved_targets(self) -> list[Reference]:
        """PERFORM / GO TO targets not defined as a paragraph or section in this code.

        For a selection that is expected (the target may be elsewhere in the file);
        for a whole file it usually means a typo or a missing copybook.
        """
        known = {p.name for p in self.paragraphs} | {s.name for s in self.sections}
        return [r for r in self.references if r.verb != "CALL" and r.target not in known]

    @property
    def is_empty(self) -> bool:
        return not (
            self.program_id
            or self.divisions
            or self.sections
            or self.paragraphs
            or self.data_items
            or self.references
            or self.files
            or self.embedded
        )


# --- Source normalisation --------------------------------------------------------

# A line in fixed format: 6 sequence characters (digits, spaces, or anything),
# an indicator, then the program text. We treat code as fixed format when most
# non-blank lines have a blank-or-numeric sequence area and a valid indicator.
_FIXED_INDICATORS = {" ", "*", "/", "-", "D", "d"}


def _looks_fixed_format(lines: list[str]) -> bool:
    candidates = [ln for ln in lines if ln.strip()]
    if not candidates:
        return False
    fixed = sum(
        1
        for ln in candidates
        if len(ln) >= 7
        and (ln[:6].isspace() or ln[:6].strip().isdigit())
        and ln[6] in _FIXED_INDICATORS
    )
    return fixed / len(candidates) >= 0.8


@dataclass(frozen=True)
class _SourceLine:
    number: int  # 1-based line number in the user's file
    text: str  # program text, comments removed, upper-cased
    area_a: bool  # True if the text starts in Area A (columns 8-11)


def _source_lines(code: str, start_line: int) -> list[_SourceLine]:
    raw = code.splitlines()
    fixed = _looks_fixed_format(raw)
    out: list[_SourceLine] = []
    for offset, line in enumerate(raw):
        number = start_line + offset
        if fixed:
            if len(line) < 7 or line[6] in "*/":
                continue  # blank or comment line
            body = line[7:72]
            stripped = body.lstrip()
            area_a = bool(stripped) and len(body) - len(stripped) < 4
        else:
            body = line.split("*>", 1)[0]  # free-format inline comment
            stripped = body.lstrip()
            if stripped.startswith("*"):
                continue
            area_a = bool(stripped) and len(body) - len(stripped) < 4
        # Blank out string literals so names inside them aren't picked up.
        text = re.sub(r"\"[^\"]*\"|'[^']*'", '""', stripped.rstrip()).upper()
        if text:
            out.append(_SourceLine(number, text, area_a))
    return out


# --- Patterns ------------------------------------------------------------------

_NAME = r"[A-Z0-9][A-Z0-9-]*"
_DIVISION = re.compile(rf"^({_NAME})\s+DIVISION\b")
_SECTION = re.compile(rf"^({_NAME})\s+SECTION\s*\.")
_PARAGRAPH = re.compile(rf"^({_NAME})\s*\.\s*$")
_PROGRAM_ID = re.compile(rf"^PROGRAM-ID\s*\.?\s*({_NAME})")
_DATA_ITEM = re.compile(rf"^(\d{{1,2}})\s+({_NAME})\b(.*)$")
_PICTURE = re.compile(r"\bPIC(?:TURE)?\s+(?:IS\s+)?(\S+?)\.?(?=\s|$)")
_USAGE = re.compile(r"\b(COMP(?:UTATIONAL)?(?:-[1-5X])?|BINARY|PACKED-DECIMAL|DISPLAY)\b")
_OCCURS = re.compile(r"\bOCCURS\s+(\d+(?:\s+TO\s+\d+)?)")
_REDEFINES = re.compile(rf"\bREDEFINES\s+({_NAME})")
_PERFORM = re.compile(rf"\bPERFORM\s+({_NAME})(?:\s+(?:THRU|THROUGH)\s+({_NAME}))?")
_GO_TO = re.compile(rf"\bGO\s+TO\s+({_NAME})")
_CALL = re.compile(rf"\bCALL\s+(\"\"|{_NAME})")
_SELECT = re.compile(rf"^SELECT\s+(?:OPTIONAL\s+)?({_NAME})")
_EXEC = re.compile(r"\bEXEC\s+(SQL|CICS|DLI|SQLIMS)\b")

# Words that can follow PERFORM without naming a paragraph (inline PERFORMs).
_PERFORM_KEYWORDS = {"UNTIL", "VARYING", "WITH", "TEST", "FOREVER"}
# Area A words that end in a period but aren't paragraph names.
_NOT_PARAGRAPHS = {"END-PROGRAM", "EXIT", "GOBACK", "STOP", "SKIP1", "SKIP2", "SKIP3", "EJECT"}

# The only real division names. "ID" is the short form of IDENTIFICATION. Anything
# else followed by DIVISION (e.g. inside a comment that slipped through) is ignored.
_DIVISION_NAMES = {"IDENTIFICATION", "ID", "ENVIRONMENT", "DATA", "PROCEDURE"}


# --- The agent -------------------------------------------------------------------


def analyze(ctx: CodeContext) -> CodeAnalysis:
    """Scan ``ctx.code`` and return what it contains. Never raises on odd input."""
    result = CodeAnalysis(
        file_name=ctx.file_name,
        start_line=ctx.start_line,
        end_line=ctx.end_line,
        is_selection=ctx.is_selection,
    )
    # Which division we are in decides how an Area A word is read: in the
    # PROCEDURE DIVISION it's a paragraph, elsewhere it isn't. A selection may
    # start partway through, so "unknown" counts as procedure code unless the
    # line looks like a data entry.
    division: str | None = None

    for line in _source_lines(ctx.code, ctx.start_line):
        text = line.text

        if m := _DIVISION.match(text):
            if m.group(1) in _DIVISION_NAMES:
                division = "IDENTIFICATION" if m.group(1) == "ID" else m.group(1)
                result.divisions.append(Located(division, line.number))
                continue

        if m := _PROGRAM_ID.match(text):
            result.program_id = m.group(1)
            continue

        if m := _SECTION.match(text):
            result.sections.append(Located(m.group(1), line.number))
            continue

        for em in _EXEC.finditer(text):
            result.embedded.append(Located(f"EXEC {em.group(1)}", line.number))

        if m := _SELECT.match(text):
            result.files.append(Located(m.group(1), line.number))
            continue

        in_data = division == "DATA" or (division is None and _DATA_ITEM.match(text))
        if in_data:
            if m := _DATA_ITEM.match(text):
                rest = m.group(3)
                pic = _PICTURE.search(rest)
                usage = _USAGE.search(rest)
                occurs = _OCCURS.search(rest)
                redefines = _REDEFINES.search(rest)
                result.data_items.append(
                    DataItem(
                        level=m.group(1).zfill(2),
                        name=m.group(2),
                        line=line.number,
                        picture=pic.group(1) if pic else None,
                        usage=usage.group(1) if usage and usage.group(1) != "DISPLAY" else None,
                        occurs=occurs.group(1) if occurs else None,
                        redefines=redefines.group(1) if redefines else None,
                    )
                )
            continue

        if division not in (None, "PROCEDURE"):
            continue

        if line.area_a and (m := _PARAGRAPH.match(text)) and m.group(1) not in _NOT_PARAGRAPHS:
            result.paragraphs.append(Located(m.group(1), line.number))
            continue

        for pm in _PERFORM.finditer(text):
            target, thru = pm.group(1), pm.group(2)
            # "PERFORM 5 TIMES" and "PERFORM UNTIL ..." are inline loops, not calls.
            if target in _PERFORM_KEYWORDS or target.isdigit():
                continue
            result.references.append(Reference("PERFORM", target, line.number))
            if thru:
                result.references.append(Reference("PERFORM", thru, line.number))
        for gm in _GO_TO.finditer(text):
            result.references.append(Reference("GO TO", gm.group(1), line.number))
        for cm in _CALL.finditer(text):
            target = cm.group(1)
            # Literal program names were blanked out with the other strings;
            # record them as a literal call rather than dropping them.
            result.references.append(
                Reference(
                    "CALL", "(literal program name)" if target == '""' else target, line.number
                )
            )

    return result


# --- Rendering for the model -------------------------------------------------------


def _fmt_located(items: list[Located], limit: int) -> str:
    shown = ", ".join(f"{i.name} (line {i.line})" for i in items[:limit])
    more = len(items) - limit
    return shown + (f", and {more} more" if more > 0 else "")


def render_analysis(analysis: CodeAnalysis, max_items: int = 40) -> str:
    """Plain-text summary of the analysis, for inclusion in the Explainer's prompt.

    ``max_items`` caps each list so a huge file can't crowd out the code itself.
    """
    lines: list[str] = []
    if analysis.program_id:
        lines.append(f"- Program: {analysis.program_id}")
    if analysis.divisions:
        lines.append(f"- Divisions: {_fmt_located(analysis.divisions, max_items)}")
    if analysis.sections:
        lines.append(f"- Sections: {_fmt_located(analysis.sections, max_items)}")
    if analysis.paragraphs:
        lines.append(f"- Paragraphs: {_fmt_located(analysis.paragraphs, max_items)}")
    # FILLER entries are unnamed padding/constant areas. Listing them wastes the
    # item budget on lines the model can already see in the code, so only named
    # items are listed (the count still says how many FILLERs were skipped).
    named = [d for d in analysis.data_items if d.name != "FILLER"]
    fillers = len(analysis.data_items) - len(named)
    if named:
        skipped = f", plus {fillers} FILLER" if fillers else ""
        lines.append(f"- Data items ({len(named)} named{skipped}):")
        for d in named[:max_items]:
            details = [
                f"PIC {d.picture}" if d.picture else "",
                d.usage or "",
                f"OCCURS {d.occurs}" if d.occurs else "",
                f"REDEFINES {d.redefines}" if d.redefines else "",
            ]
            extra = ", ".join(x for x in details if x)
            lines.append(
                f"  - {d.level} {d.name} (line {d.line})" + (f": {extra}" if extra else "")
            )
        if len(named) > max_items:
            lines.append(f"  - and {len(named) - max_items} more")
    if analysis.references:
        lines.append("- Control flow:")
        for r in analysis.references[:max_items]:
            lines.append(f"  - line {r.line}: {r.verb} {r.target}")
        if len(analysis.references) > max_items:
            lines.append(f"  - and {len(analysis.references) - max_items} more")
    unresolved = analysis.unresolved_targets
    if unresolved:
        where = (
            "outside the selected lines"
            if analysis.is_selection
            else "not defined in this file (typo or copybook?)"
        )
        names = sorted({r.target for r in unresolved})
        lines.append(f"- Targets {where}: {', '.join(names[:max_items])}")
    if analysis.files:
        lines.append(f"- Files (SELECT): {_fmt_located(analysis.files, max_items)}")
    if analysis.embedded:
        lines.append(f"- Embedded statements: {_fmt_located(analysis.embedded, max_items)}")
    return "\n".join(lines)
