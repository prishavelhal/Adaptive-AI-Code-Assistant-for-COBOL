# CobolTutor

A VSCode extension that tutors people on IBM COBOL. It explains the code you have
open and answers your COBOL questions, using IBM Granite 4.2 (8B) running locally
through Ollama.

```
┌──────────────────────── VSCode ─────────────────────────┐        ┌──────── Docker Compose ────────┐
│                                                         │        │                                │
│  Vue webview (chat UI)  ◄─postMessage─►  Extension host │  HTTP  │  backend (FastAPI)             │
│  webview/src/**                          src/**         │──POST─►│    builds the tutor prompt     │
│  renders Markdown,                       owns the chat, │◄─SSE───│    streams tokens as SSE       │
│  no network access                       SSE client     │        │          │  OpenAI-compatible  │
│                                                         │        │          ▼  API (/v1)          │
└─────────────────────────────────────────────────────────┘        │  ollama  (granite4.2:8b)       │
                                                                   └────────────────────────────────┘
```

## Repository layout

| Path                       | What it is                                                         |
| -------------------------- | ------------------------------------------------------------------ |
| `extension/`               | The VSCode extension (TypeScript; bundled by esbuild)              |
| `extension/webview/`       | The chat UI (Vue 3; built by Vite)                                 |
| `extension/shared/`        | Types shared by the extension, the webview, and the backend API     |
| `backend/`                 | FastAPI service that streams answers from the model (Python + uv)  |
| `docker-compose.yml`       | Runs Ollama, downloads the models, and runs the backend            |
| `.github/workflows/ci.yml` | Lint, type-check, test, and package both halves                    |

## Quick start

**Prerequisites:** Docker with the Compose plugin, Node.js 22+ with pnpm, and VSCode.
The model runs on CPU by default. With an NVIDIA GPU, uncomment the `deploy:`
block in `docker-compose.yml` for much faster answers.

1. **Start the backend stack.** The first run downloads roughly 5 GB of models.

   ```sh
   docker compose up -d
   docker compose logs -f ollama-pull   # watch the download; it exits when done
   ```

   Check it's ready: `curl http://127.0.0.1:8000/health` should show `"model_ready": true`.

2. **Run the extension.**

   ```sh
   cd extension
   pnpm install
   ```

   Open this repository folder in VSCode and press **F5**. A second VSCode window
   (the "Extension Development Host") opens with CobolTutor loaded.

3. **Try it.** Open a `.cbl` file, select some code, right-click, and choose
   **Explain Selected Code** (or press `Ctrl+Alt+E`). You can also click the
   CobolTutor icon in the activity bar and type a question.

   If something doesn't work, run **CobolTutor: Check Backend Connection** from
   the Command Palette.

To install the extension permanently instead of using F5, run `pnpm package` in
`extension/`. Then in VSCode: Extensions → `…` → **Install from VSIX…**.

## Features (milestone 1)

- **Chat sidebar** with answers streamed token by token, rendered as Markdown. Stop and New chat buttons.
- **Explain Selected Code** / **Explain This File** commands (editor right-click menu, Command Palette).
- **Attach active file**: questions you type include your current selection, or the whole
  file if nothing is selected. The 📎 chip above the input box shows what will be attached;
  click it to turn attaching off. Only the file's base name is sent, never its full path.

## Settings

| Setting                                | Default                 | Meaning                                         |
| -------------------------------------- | ----------------------- | ----------------------------------------------- |
| `coboltutor.backendUrl`                 | `http://127.0.0.1:8000` | Where the backend is running                    |
| `coboltutor.includeActiveFileByDefault` | `true`                  | Whether 📎 starts on when VSCode opens            |

Backend settings are environment variables; see `backend/README.md`.

## Development

```sh
# Backend (backend/)
uv sync && uv run pytest && uv run ruff check . && uv run mypy

# Extension (extension/)
pnpm install && pnpm typecheck && pnpm test && pnpm build
pnpm watch          # rebuild on save while debugging with F5
```

## Roadmap

1. ✅ Streaming chat panel (SSE)
2. ✅ Explain selection / file
3. ⏳ RAG: PostgreSQL + pgvector, `granite-embedding:278m`, ingestion scripts for the
   Open Mainframe Project COBOL course and IBM documentation
4. ⏳ Compile / syntax check in a GnuCOBOL (`-std=ibm`) Docker sandbox, shown as VSCode diagnostics
