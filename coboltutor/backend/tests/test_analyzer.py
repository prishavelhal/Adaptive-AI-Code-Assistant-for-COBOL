"""Unit tests for the Analyzer agent (agents/analyzer.py). No model involved."""

from pathlib import Path

from coboltutor_backend.agents.analyzer import analyze, render_analysis
from coboltutor_backend.schemas import CodeContext

# The sample program shipped with the repo (synthetic data, safe to use in tests).
PAYROLL = Path(__file__).resolve().parents[2] / "examples" / "PAYROLL.cbl"


def ctx(code: str, start_line: int = 1, is_selection: bool = False) -> CodeContext:
    lines = max(len(code.splitlines()), 1)
    return CodeContext(
        file_name="TEST.cbl",
        language_id="cobol",
        code=code,
        start_line=start_line,
        end_line=start_line + lines - 1,
        is_selection=is_selection,
    )


def test_payroll_structure() -> None:
    a = analyze(ctx(PAYROLL.read_text()))
    assert a.program_id == "PAYROLL"
    assert [d.name for d in a.divisions] == ["IDENTIFICATION", "ENVIRONMENT", "DATA", "PROCEDURE"]
    assert [s.name for s in a.sections] == ["WORKING-STORAGE"]
    assert [p.name for p in a.paragraphs] == [
        "0000-MAIN",
        "1000-PRINT-HEADER",
        "2000-PROCESS-EMPLOYEE",
        "3000-PRINT-TOTALS",
    ]
    # Every PERFORM in the sample points at a paragraph that exists.
    assert {r.target for r in a.references} == {
        "1000-PRINT-HEADER",
        "2000-PROCESS-EMPLOYEE",
        "3000-PRINT-TOTALS",
    }
    assert a.unresolved_targets == []


def test_payroll_data_items() -> None:
    a = analyze(ctx(PAYROLL.read_text()))
    items = {d.name: d for d in a.data_items}
    assert items["EMP-RATE"].picture == "9(3)V99"
    assert items["WS-GROSS"].usage == "COMP-3"
    assert items["EMPLOYEE"].occurs == "5"
    assert items["EMPLOYEE-TABLE"].redefines == "EMPLOYEE-DATA"
    # Line numbers are the real ones in the file, so the model can cite them.
    source = PAYROLL.read_text().splitlines()
    assert "EMP-RATE" in source[items["EMP-RATE"].line - 1]


def test_comments_and_strings_are_ignored() -> None:
    code = "\n".join(
        [
            "       PROCEDURE DIVISION.",
            "      * PERFORM NOT-A-REAL-CALL",
            "       MAIN-PARA.",
            '           DISPLAY "PERFORM ALSO-NOT-A-CALL"',
            "           STOP RUN.",
        ]
    )
    a = analyze(ctx(code))
    assert a.references == []
    assert [p.name for p in a.paragraphs] == ["MAIN-PARA"]


def test_inline_perform_is_not_a_call() -> None:
    code = "\n".join(
        [
            "       PROCEDURE DIVISION.",
            "       MAIN-PARA.",
            "           PERFORM UNTIL WS-DONE = 'Y'",
            "               PERFORM READ-NEXT THRU READ-EXIT",
            "           END-PERFORM",
            "           PERFORM 3 TIMES",
            "               DISPLAY 'HI'",
            "           END-PERFORM.",
        ]
    )
    a = analyze(ctx(code))
    assert [(r.verb, r.target) for r in a.references] == [
        ("PERFORM", "READ-NEXT"),
        ("PERFORM", "READ-EXIT"),
    ]


def test_selection_line_numbers_and_unresolved_targets() -> None:
    # A selection from the middle of a file: line numbers are offset, and the
    # PERFORM target being elsewhere is reported as outside the selection.
    code = "       0000-MAIN.\n           PERFORM 1000-INIT\n           STOP RUN."
    a = analyze(ctx(code, start_line=120, is_selection=True))
    assert a.paragraphs[0].line == 120
    assert a.references[0].line == 121
    assert [r.target for r in a.unresolved_targets] == ["1000-INIT"]
    assert "outside the selected lines: 1000-INIT" in render_analysis(a)


def test_call_go_to_files_and_embedded_sql() -> None:
    code = "\n".join(
        [
            "       ENVIRONMENT DIVISION.",
            "       FILE-CONTROL.",
            "           SELECT CUSTOMER-FILE ASSIGN TO CUSTIN.",
            "       PROCEDURE DIVISION.",
            "       MAIN-PARA.",
            "           CALL 'SUBPGM' USING WS-AREA",
            "           EXEC SQL SELECT 1 INTO :WS-X FROM SYSIBM.SYSDUMMY1 END-EXEC",
            "           GO TO MAIN-PARA.",
        ]
    )
    a = analyze(ctx(code))
    assert [f.name for f in a.files] == ["CUSTOMER-FILE"]
    assert [e.name for e in a.embedded] == ["EXEC SQL"]
    assert ("CALL", "(literal program name)") in [(r.verb, r.target) for r in a.references]
    assert ("GO TO", "MAIN-PARA") in [(r.verb, r.target) for r in a.references]
    assert a.unresolved_targets == []  # CALLs are other programs, never "unresolved"


def test_free_format_and_garbage_input() -> None:
    free = "IDENTIFICATION DIVISION.\nPROGRAM-ID. HELLO.\nPROCEDURE DIVISION.\nMAIN.\n  STOP RUN."
    a = analyze(ctx(free))
    assert a.program_id == "HELLO"
    assert [p.name for p in a.paragraphs] == ["MAIN"]

    # Not COBOL at all: no crash, nothing found, nothing added to the prompt.
    junk = analyze(ctx("hello world\n{}\n\t\t"))
    assert junk.is_empty
    assert render_analysis(junk) == ""
