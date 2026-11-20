# CobolTutor backend

A FastAPI service that streams IBM COBOL tutoring answers from IBM Granite 4.2
(served by Ollama) to the VSCode extension using Server-Sent Events.

## API

| Method | Path        | Purpose                                                                      |
| ------ | ----------- | ---------------------------------------------------------------------------- |
| GET    | `/health`   | `{"status": "ok", "model": "...", "model_ready": true}`                      |
| POST   | `/api/chat` | Body `{"messages": [...]}`. Response is an SSE stream of `token`, then `done` or `error` events |

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

Ready-made sets of these settings live in `profiles/`:

| Profile             | Model                     | Used by                                                     |
| ------------------- | ------------------------- | ----------------------------------------------------------- |
| `local-ollama.conf` | Granite 4.2 8B on Ollama  | local development (same values as the defaults)             |
| `cluster-vllm.conf` | Granite 4.2 30B on vLLM   | `scripts/cluster/` on the HPC cluster; see `docs/cluster-support.md` |

To use a profile by hand: `set -a; source profiles/<name>.conf; set +a`, then
`uv run coboltutor-backend`. Profiles are committed, so they never hold secrets.
