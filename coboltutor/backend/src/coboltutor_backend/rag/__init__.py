"""RAG (retrieval-augmented generation) for CobolTutor.

STATUS: skeleton. The types, interfaces, and module layout are in place; most
function bodies raise NotImplementedError. Nothing outside this package calls
it yet, and ``Settings.rag_enabled`` is False by default.

What RAG does here
------------------
Before the model answers, we look up passages from approved COBOL
documentation that are relevant to the question, add them to the prompt, and
tell the model to cite them. That grounds answers in real sources (FR-3) and
reduces made-up facts (NFR-3: at least 90% of claims supported by sources).

The pipeline has two halves:

  Ingestion (offline, run by hand: ``uv run coboltutor-ingest``)
      knowledge-base/SOURCES.md      list of approved sources (loaders.py)
        -> load each source's text   (loaders.py)
        -> split into chunks         (chunking.py; FR-10)
        -> embed each chunk          (embedder.py)
        -> store chunk + vector      (store.py, schema.sql)

  Retrieval (online, once per question)
      question (+ the learner's code)
        -> embed it                  (embedder.py)
        -> nearest chunks            (store.py)
        -> prompt text + citations   (context.py, prompts/retrieved_context.md)
      All three steps are wrapped by retriever.py.

Modules
-------
  models.py     plain data types passed between the stages
  embedder.py   Embedder interface + client for an OpenAI-compatible
                /v1/embeddings server (Ollama locally, vLLM on the cluster)
  store.py      VectorStore interface + PostgreSQL/pgvector implementation
  schema.sql    the database tables and indexes
  chunking.py   COBOL-aware and prose chunking
  loaders.py    reads the SOURCES.md manifest and source files
  retriever.py  question -> relevant chunks; checks the index was built with
                the same embedding model we are querying with
  context.py    turns retrieved chunks into prompt text and a `sources`
                payload for the extension
  ingest.py     the ``coboltutor-ingest`` command

Design notes
------------
- Each external dependency (embedding server, database) sits behind a small
  Protocol, the same pattern as ``llm.LLMClient``. Tests use in-memory fakes,
  so CI never needs Postgres or a model server (AGENTS.md: no real calls in CI).
- Plain psycopg + pgvector + the openai client, no LangChain: this matches
  the rest of the backend. If the team adopts LangGraph later, VectorStore is
  easy to wrap as a LangChain retriever.
- Not yet wired in: /api/chat, the `sources` SSE event, the extension UI, and
  a `retrieve` stage in the agent orchestrator (on the agent branches).
"""
