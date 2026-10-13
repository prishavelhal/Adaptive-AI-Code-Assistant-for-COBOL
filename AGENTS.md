## Project context
Agentic AI system that teaches COBOL to users, adapting to their learning
style (derived from the GenderMag method). Built for IBM's COBOL
modernization project (Project 03). Setup, review rules, and the Definition
of Done are in CONTRIBUTING.md; do not duplicate them here. The team charter
lives in the team's shared drive, not in this repo.

## Workflows
Branch from main; name branches in kebab-case. Never commit to main directly. Commits use Conventional Commits Every PR must pass unit, integration, e2e, lint, and format checks. Never skip or weaken a check to get a green build.

## Tech stack
- Backend: Python , FastAPI, LangChain
- Frontend: HTML, CSS, JavaScript
- LLM provider: Granite or Llama (still deciding)
- Vector store for RAG: still deciding

## LLMS AND RAG 
- Keep prompts and the persona/character file in their own files, not as strings buried in code.
- Only index public or partner-approved COBOL documentation in the RAG pipeline. Unit tests must mock LLM calls. No real API calls in CI.

## Conventions
- Prompts and the persona/character file live in `[prompts/]`, never as
  strings in code.
- Only index public or partner-approved COBOL documentation in the RAG pipeline.
- Unit tests must mock LLM calls. No real API calls in CI.
- Branch from main; kebab-case branch names (e.g. `fix-error-7`); never
  commit to main directly.
- Commits use Conventional Commits; reference issues by number.
- Every PR must pass unit, integration, e2e, lint, and format checks before
  merging. Never skip or weaken a check to get a green build.

## Confidentiality boundary
- Never put credentials, API keys, tokens, or .env contents in code, prompts,
  logs, or commits.
- Never include IBM proprietary code, documents, or partner meeting content
  in prompts, logs, or committed test fixtures unless the partner has cleared it.
- Never use real user data; use synthetic data in tests and examples.
- If unsure whether something is safe to include, stop and ask the AI Coordinator.

## Things you should never do
- Never write hardcoded credentials or share API keys.

## Always
- Ask before modifying large parts of the code.
- Ask before making a large structural change to the project.

## To be added once code exists
| Item | Owner | Target sprint |
|---|---|---|
| Architecture overview and module layout | [name] | [N] |
| RAG ingestion rules (sources, chunking, approval) | [name] | [N] |
| Test fixtures and mocking guidance | [name] | [N] |
| Confirmed run/test/lint commands | [name] | [N] |
