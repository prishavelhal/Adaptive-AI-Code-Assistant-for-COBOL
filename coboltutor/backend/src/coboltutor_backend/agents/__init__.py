"""Multi-agent pipeline for CobolTutor.

The agents build on the existing backend rather than replacing it:

    analyzer.py     - Analyzer agent: parses attached COBOL into a structure summary
                      (plain Python, no model call: fast, exact, testable)
    explainer.py    - Explainer agent: the existing prompt (prompts.build_messages) plus
                      the analysis, streamed through the existing LLMClient
    orchestrator.py - runs the agents in order and emits the existing SSE events
                      (token / done / error) plus a new `stage` event
    routes.py       - POST /api/agent-chat, mounted next to the existing /api/chat

The existing /api/chat route is unchanged. Clients that don't know the `stage`
event ignore it (see extension/src/backendClient.ts), so the agent endpoint
speaks the same protocol as /api/chat.
"""
