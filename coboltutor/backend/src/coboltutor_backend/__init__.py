"""CobolTutor backend package.

This package is a small FastAPI service that sits between the VSCode extension
and the language model:

    VSCode extension  --(HTTP POST, JSON)-->  this backend  --(OpenAI API)-->  Ollama (Granite)
    VSCode extension  <--(SSE token stream)--  this backend  <--(token stream)--  Ollama (Granite)

Module overview:
    config.py   - settings read from environment variables
    schemas.py  - the shape of the JSON the extension sends us (validated by Pydantic)
    prompts.py  - turns a chat request into the exact message list sent to the model
    llm.py      - thin streaming client for any OpenAI-compatible server (Ollama here)
    sse.py      - helpers for writing Server-Sent Events
    main.py     - the FastAPI app and its HTTP routes
"""


def main() -> None:
    """Entry point for `uv run coboltutor-backend`.

    We import inside the function so that simply importing the package (e.g. in
    tests) doesn't pull in uvicorn or read settings as a side effect.
    """
    import uvicorn

    from .config import get_settings

    settings = get_settings()
    # "coboltutor_backend.main:app" is an import string rather than the app object
    # itself; uvicorn needs it in that form to support --reload style workers.
    uvicorn.run(
        "coboltutor_backend.main:app",
        host=settings.host,
        port=settings.port,
    )
