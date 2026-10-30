# Requirements

**Status key:** Not started · In progress · Done (test name) — a requirement is Done only when a test named after it runs in CI.
**Confirmation key:** **Confirmed (brief)** = stated in the IBM partner's project brief · **Confirmed (advisor)** = confirmed by our IBM advisor in a meeting (date noted) · **Assumed** = the team's proposal, not yet confirmed; the note says who must confirm it.

Many numbers in this MD are ASSUMED. Our percentage error and evaluation percentage are subject to change as we write more of the codebase.

## Problem Statement
 
Developers who need to understand or maintain enterprise COBOL are increasingly scarce, and the systems they maintain run banking, insurance, and government services. Our IBM partner's brief states that COBOL supports nearly 90% of major banking institutions and about 70% of global business transaction processing, and that most AI code assistants give the same explanation to everyone regardless of how they learn or approach problems. IBM Research's study of LLM code explanations (Anderson et al., 2026) found that models can adapt explanations to different problem-solving styles when prompted, but did not measure whether the adapted explanations were correct, and found that IBM Granite adapted less than other models. We are building a VS Code extension that explains unfamiliar IBM Enterprise COBOL to developers, grounds its answers in public COBOL documentation, adapts the explanation to the user's problem-solving style, and measures whether that helps them understand the code.
 
## Functional Requirements
 
| ID | Requirement | Rank | Status | Confirmation |
|---|---|---|---|---|
| FR-1 | A user can select COBOL code in VS Code and request an explanation from the editor's right-click menu. | Must - every other feature builds on this path | Not started | Confirmed (brief) |
| FR-2 | Explanations stream into VS Code as they are generated. | Should - 30B responses take long enough that a blank wait reads as a hang | Not started | Assumed (team) |
| FR-3 | Each explanation is grounded in the knowledge base and lists the sources it used. | Must - the brief's anti-hallucination objective depends on it | Not started | Confirmed (brief) |
| FR-4 | A user can set a problem-solving style profile in the sidebar, and it persists across VS Code sessions. | Must - no adaptation without a profile | Not started | Confirmed (brief); profile dimensions Assumed - advisor to confirm |
| FR-5 | The explanation's structure, detail, and format change according to the user's profile. | Must - the project's core research question | Not started | Confirmed (brief) |
| FR-6 | The assistant can syntax-check selected code in an isolated GnuCOBOL sandbox and report the result. | Should - catches some hallucinations cheaply | Not started | Assumed (team) |
| FR-7 | A user can ask follow-up questions about the same code in the sidebar chat. | Should - single-shot explanations rarely answer everything | Not started | Assumed (team) |
| FR-8 | The backend exposes a health check reporting its status and configured model. | Must - needed by Docker and CI | In progress - `GET /health` implemented, no CI test yet | Confirmed (team) |
| FR-9 | The model name and model host are configured through environment variables, not code. | Must - dev uses local 8B, evaluation uses 30B on the cluster | In progress - read by `/health`, not yet used to call a model | Confirmed (team) |
| FR-10 | An ingestion script loads knowledge-base sources, chunks them by COBOL division, section, and paragraph, and tags each chunk with its source and dialect. | Must - FR-3 has nothing to retrieve without it | Not started | Confirmed (brief) |
| FR-11 | An evaluation script runs a fixed question set against the assistant and reports accuracy, faithfulness, and adaptation scores. | Must - the brief requires an evaluation framework | Not started | Confirmed (brief) |
 
### Acceptance Criteria
 
- **FR-1:** Given a `.cbl` file is open and text is selected, when the user right-clicks, then "COBOL: Explain Selection" appears; when chosen, an explanation of the selection appears in VS Code. When nothing is selected, the command does not appear.
- **FR-2:** The first words of the explanation appear before the full response is finished.
- **FR-3:** Every explanation shows at least one source, and each source links to a document listed in `knowledge-base/SOURCES.md`.
- **FR-4:** After the user changes the profile and restarts VS Code, the same profile values are shown and sent with the next request.
- **FR-5:** For the same code, explanations generated for two profiles at opposite ends of a dimension differ in at least one adaptation category the evaluation detects (FR-11).
- **FR-6:** Code that compiles with `cobc -std=ibm` reports success; code with a syntax error reports the error line. Code containing `EXEC CICS` or `EXEC SQL` is reported as "not checkable" rather than passed.
- **FR-7:** A follow-up question receives an answer that refers to the previously selected code without the user reselecting it.
- **FR-8:** `GET /health` returns HTTP 200 with `"status": "ok"` and the configured model name.
- **FR-9:** Changing `LLM_MODEL` or `LLM_BASE_URL` in `.env` and restarting changes which model answers, with no code change.
- **FR-10:** Running the ingestion script on a source produces chunks that each carry a source name and dialect tag, and no chunk splits a COBOL paragraph.
- **FR-11:** One command runs the question set and writes a dated results file to `eval/results/`.

## Non-Functional Requirements
 
| ID | Requirement | Measure | Rank | Confirmation |
|---|---|---|---|---|
| NFR-1 | Responsiveness | First token appears within **5 s** for a 50-line COBOL selection, using 30B on the cluster; measured by script over 20 requests (median). | Should — a slow first token feels broken | Assumed — team to confirm after first measurement |
| NFR-2 | Accuracy | At least **85%** of eval-set answers judged correct against reference answers. | Must — a tutor that teaches wrong COBOL does harm | Assumed — advisor to confirm the bar |
| NFR-3 | Faithfulness | At least **90%** of factual claims in sampled answers are supported by the retrieved sources (faithfulness metric in the eval harness). | Must — the brief names hallucination reduction | Assumed — advisor to confirm the bar |
| NFR-4 | Consistency | Running the eval set 3 times on 30B gives accuracy scores within **5 percentage points** of each other. | Should — otherwise score changes are noise | Assumed (team) |
| NFR-5 | Data stays local | No user code is sent to a host other than the local machine or the OSU cluster; checked by reviewing `LLM_BASE_URL` values in config and CI. | Must — enterprise code must not leave the company's systems | Assumed — advisor to confirm |
| NFR-6 | Reproducible setup | A teammate on a fresh clone reaches a working `/health` by following the README in under **30 minutes**. | Should — 7 people on different machines | Assumed (team) |
| NFR-7 | Sandbox isolation | Sandbox runs with no network access and a **10 s** time limit per compile. | Must — it compiles code we did not write | Assumed (team) |
 
## Constraints
 
- **C-1:** Only nonproprietary tools, public documentation, and public sample COBOL applications may be used. (Partner brief)
- **C-2:** Every knowledge-base source must have a license or permission that allows our use, recorded in `knowledge-base/SOURCES.md`.
- **C-3:** The target dialect is IBM Enterprise COBOL, but the team has no Enterprise COBOL compiler; GnuCOBOL with `-std=ibm` is an approximation, so FR-6 cannot confirm code will run on z/OS.
- **C-4:** Team laptops can run only the 8B model; the 30B model must run on the OSU College of Engineering HPC cluster, which requires sponsored accounts, the OSU VPN, and Slurm jobs with time limits.
- **C-5:** The product must run as a VS Code extension, within what the VS Code extension API allows.
- **C-6:** The proof of concept must be complete within the capstone's academic year.

## Success Metrics
 
Each is set before any data is collected.
 
1. **Comprehension:** In a user study, participants answer comprehension questions about unfamiliar COBOL using adapted explanations and using non-adapted explanations. **Decision rule:** adaptation succeeds if adapted explanations produce higher mean comprehension scores. **Collection:** study with [N] participants, questions written in `eval/datasets/comprehension/`. (Assumed — advisor to confirm participant source)
2. **Accuracy:** NFR-2's bar, measured on the eval set at the end of each sprint and recorded in `eval/results/`. **Decision rule:** below 85% blocks adding new features until fixed.
3. **Adaptation rate:** Number of adaptation categories detected per explanation for Granite 4.2 30B with our adaptation layer. **Decision rule:** we report it against the Granite results in Anderson et al.; the layer succeeds if our rate is higher. **Collection:** eval harness adaptation metric.

## Non-Goals
 
- Modifying, refactoring, or migrating COBOL code, the assistant explains only.
- Syntax highlighting, parsing, or language-server features (users install an existing COBOL extension).
- Fine-tuning the model.
- Running COBOL on a mainframe or emulating z/OS.
- User accounts, authentication, or a production deployment.
- Languages other than COBOL.

## Open Questions
 
| Question | Owner | Needed by |
|---|---|---|
| Should the assistant cover JCL, CICS, and DB2, or COBOL only? | Jack (ask advisor) | Before knowledge-base ingestion starts |
| Which IBM documents may we include in the knowledge base? | [owner] (ask advisor) | Before knowledge-base ingestion starts |
| Does the CoE cluster allow a long-running vLLM endpoint, and what is the job time limit? | Taylor (CoE IT) | Before evaluation runs on 30B |
| Who are the user-study participants, and can IBM help recruit? | [owner] (ask advisor) | Before the comprehension study is designed |
| Are the NFR-2 and NFR-3 thresholds the right bar for IBM? | [owner] (ask advisor) | Before the first eval run |
| Which style dimensions should the profile use: the paper's five, or a reduced set? | [owner] | Before FR-4 is built |