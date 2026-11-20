# Knowledge-base sources

This file is the single list of documents the RAG pipeline may ingest. The
ingestion command (`uv run coboltutor-ingest`, see
`backend/src/coboltutor_backend/rag/`) reads the **Approved sources** table
below and ingests nothing else.

Rules (from `docs/requirements.md` C-2 and `AGENTS.md`):

- Only public or partner-approved COBOL documentation. No IBM proprietary or
  internal material unless the partner has cleared it in writing.
- Every row must name the license or permission that allows our use, and who
  approved adding it. Rows with either column empty are rejected.
- Citations shown to learners link to the URL in this table (FR-3).

## Columns

| Column | Meaning |
|---|---|
| ID | Short, stable, lowercase ID used in citations, e.g. `omp-cobol-course`. Never reuse one. |
| Title | Name shown to the learner next to a citation. |
| Kind | `cobol` (COBOL source code, chunked by division/section/paragraph) or `prose` (documentation, chunked by heading). |
| Dialect | COBOL dialect the source describes, e.g. `ibm-enterprise`. Tagged on every chunk (FR-10). |
| Path | File or folder under this `knowledge-base/` folder. |
| URL | Public link to the original, used in citations. |
| License / permission | The license (e.g. `Apache-2.0`) or the written permission that allows our use. |
| Approved by | Who approved adding it, and when (e.g. `advisor, 2026-11-20`). |

## Approved sources

<!-- Add one row per approved source. Leave the table empty until a source is approved. -->

| ID | Title | Kind | Dialect | Path | URL | License / permission | Approved by |
|---|---|---|---|---|---|---|---|

## Candidates (not approved, not ingested)

Named in the project docs; each needs its license checked and approval
recorded before it moves to the table above.

- Open Mainframe Project COBOL Programming Course
- IBM Enterprise COBOL documentation (which documents are allowed is an open
  question for the advisor; see `docs/requirements.md`)
- Public COBOL sample programs
