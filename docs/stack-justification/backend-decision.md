# Backend Direction and Framework
## Backend Team Report

### Backend Language Choice  
**Language Choice:** Python 3.11+ with FastAPI

(Justification goes here)

Python is the standard language for AI and LLM development, and nearly every
component our backend depends on is Python first: model serving (vLLM, Ollama
clients), agent orchestration, retrieval (pgvector clients, embedding libraries), and evaluation. 
Choosing Python means we use these tools directly instead of through ports or wrappers that lag
behind or lack features.

FastAPI gives us async request handling and built-in support for streaming
responses (Server-Sent Events), which the VS Code extension needs to display
explanations as they generate. It also generates interactive API docs
automatically, so the frontend team can see and test every endpoint without
waiting on us.

Python 3.11+ is required for its performance improvements and better
error messages, and it is supported by all of our dependencies.

### Inspiration
1. **IBM Research's adaptive code explanation paper** (Anderson et al.), which
   this project builds on. Its generation and analysis pipeline was Python based, 
   so we can reuse its methods in our evaluation framework.
2. **IBM Granite's ecosystem.** IBM optimizes Granite 4.2 for vLLM, a Python
   serving engine, and publishes Python examples for working with Granite. Staying
   in Python keeps us aligned with how IBM itself uses the model, which matters
   for handoff.
3. **The LangChain / LangGraph ecosystem**, the most widely used tooling for
   RAG pipelines and agentic workflows, both of which are core objectives in
   our project brief.

### 3. Option 1 vs Option 2
| | Option 1: Python + FastAPI | Option 2: Node.js + TypeScript (Express/NestJS) |
|---|---|---|
| AI/ML ecosystem | First-class: vLLM, LangGraph, Ragas, embeddings, NLP libraries all native | Partial: LangChain.js exists, but most eval and NLP tooling is Python only |
| Team familiarity | Backend team is very familiar with Python and AI/LLM work in Python | TBD |
| Learning curve | Low; FastAPI is small and well-documented | Low for TS users; same language as the extension |
| Setup effort for the walking skeleton | Low: one endpoint, ~50 lines, Docker image straightforward | Low for the API, but eval and RAG tooling would need a separate Python service anyway |

**Decision:** 
Python 3.11+ with FastAPI.

**Reasoning:** 
The main advantage of a TypeScript backend is sharing one
language with the VS Code extension. However, our evaluation framework,
retrieval pipeline, and model tooling are all Python native, so a TypeScript
backend would still require Python for those parts, leaving us with two
backend languages instead of one. Python keeps the entire AI pipeline in a
single codebase, matches IBM's own Granite tooling for a cleaner handoff, and
lets us reuse methods from the IBM Research paper directly. The extension and
backend communicate over a simple HTTP + SSE API, so using different languages
on each side adds no real complexity.