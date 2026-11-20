# CobolTutor backend

A FastAPI service that streams IBM COBOL tutoring answers from IBM Granite 4.2
(served by Ollama) to the VSCode extension using Server-Sent Events.

## API

| Method | Path        | Purpose                                                                      |
| ------ | ----------- | ---------------------------------------------------------------------------- |
| GET    | `/health`   | `{"status": "ok", "model": "...", "model_ready": true}`                      |
| POST   | `/api/chat` | Body `{"messages": [...]}`. Response is an SSE stream of `token`, then `done` or `error` events |
| POST   | `/api/agent-chat` | Same body and stream as `/api/chat`, answered by the agent pipeline. Adds `stage` events (`{"name": "analyze"}`, `{"name": "explain"}`) before each step |

### Agent pipeline (`src/coboltutor_backend/agents/`)

`/api/agent-chat` builds on the existing code instead of replacing it; `/api/chat` is unchanged.

1. **Analyzer** (`analyzer.py`, no model call): scans the attached COBOL for divisions,
   sections, paragraphs, data items (PIC, usage, OCCURS, REDEFINES), PERFORM / GO TO / CALL
   targets, files, and embedded EXEC SQL/CICS, with real line numbers.
2. **Explainer** (`explainer.py`): the existing `prompts.build_messages()` output with the
   analysis added to the latest user message (wording in `agents/prompts/`), streamed
   through the existing `LLMClient`.

`orchestrator.py` runs the steps and reuses the same SSE events and error messages as
`/api/chat`. Planned next steps: learning profile, a Critic that checks the answer, and
retrieval once RAG ingestion exists.

Try it (backend running):

```sh
curl -N http://127.0.0.1:8000/api/agent-chat -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"What does PERFORM VARYING do?"}]}'
```

Interactive API docs are at <http://localhost:8000/docs> while the server is running.

## Local development (without Docker for the backend)

```sh
# Ollama must be running and have the model, e.g.:
#   docker compose up -d ollama ollama-pull     (from the repo root)
uv sync                       # install dependencies into .venv
uv run coboltutor-backend     # start on http://localhost:8000
```

## Checks

```sh
uv run ruff check .           # lint
uv run ruff format .          # auto-format
uv run mypy                   # type-check
uv run pytest                 # tests (no model needed; uses a fake LLM)
```

## Configuration

All settings are environment variables prefixed with `COBOLTUTOR_`; see
`src/coboltutor_backend/config.py` for the full list and their defaults. The most
useful ones are `COBOLTUTOR_LLM_BASE_URL` and `COBOLTUTOR_LLM_MODEL`.
