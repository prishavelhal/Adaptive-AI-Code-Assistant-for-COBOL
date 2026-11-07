"""Helpers for writing Server-Sent Events (SSE).

SSE is a simple, text-based streaming format defined by the HTML spec. The server
keeps an HTTP response open and writes "events" to it, each one shaped like this:

    event: token
    data: {"text": "Hello"}
    <blank line>

The blank line marks the end of an event. We always put JSON in ``data`` so that
newlines and other special characters in the model's output are escaped safely
(a raw newline inside ``data:`` would split the event).

Events this backend sends (the extension's parser in extension/src/sse.ts expects
exactly these):
    token  {"text": str}     - the next piece of the assistant's answer
    done   {}                - the answer finished normally
    error  {"message": str}  - something went wrong; no more events follow
"""

import json
from typing import Any


def format_sse(event: str, data: dict[str, Any]) -> str:
    """Serialise one SSE event. The trailing blank line ends the event."""
    # ensure_ascii=False keeps non-ASCII characters readable on the wire; JSON
    # still escapes newlines, so the payload always stays on one line.
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata: {payload}\n\n"
