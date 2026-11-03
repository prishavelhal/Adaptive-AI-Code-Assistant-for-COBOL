// -----------------------------------------------------------------------------
// HTTP client for the Python backend. This is the "SSE client" from the stack.
//
// It runs in the extension host (Node.js), not in the webview, because:
//   - the webview's Content Security Policy blocks network access (and should);
//   - Node's fetch isn't subject to browser CORS rules, so the backend needs no
//     CORS configuration.
// Tokens are handed to the caller through a callback; chatViewProvider.ts then
// forwards them to the webview.
// -----------------------------------------------------------------------------
import type { BackendEvent, ChatRequest, HealthResponse } from "../shared/protocol";
import { SseParser } from "./sse";

/** An error whose message is safe and useful to show to the user as-is. */
export class BackendError extends Error {}

export interface StreamHandlers {
  onToken: (text: string) => void;
}

/** Remove trailing slashes so `${base}/api/chat` never contains "//". */
function joinUrl(baseUrl: string, path: string): string {
  return baseUrl.replace(/\/+$/, "") + path;
}

/**
 * Turn a low-level fetch failure into an actionable message. Node's fetch
 * reports "connection refused" as a generic TypeError("fetch failed") with the
 * real reason in `cause`.
 */
function describeFetchError(err: unknown, baseUrl: string): BackendError {
  const cause = (err as { cause?: { code?: string } })?.cause;
  if (cause?.code === "ECONNREFUSED" || cause?.code === "ENOTFOUND") {
    return new BackendError(
      `Can't reach the CobolTutor backend at ${baseUrl}. Start it with \`docker compose up -d\` ` +
        "in the project folder, or check the `coboltutor.backendUrl` setting.",
    );
  }
  return new BackendError(`Request to the backend failed: ${(err as Error)?.message ?? err}`);
}

/**
 * POST the conversation to /api/chat and stream the answer.
 *
 * Resolves when the answer is complete. Rejects with BackendError on failure,
 * or with an AbortError if `signal` is aborted (the user pressed Stop).
 */
export async function streamChat(
  baseUrl: string,
  request: ChatRequest,
  signal: AbortSignal,
  handlers: StreamHandlers,
): Promise<void> {
  let response: Response;
  try {
    response = await fetch(joinUrl(baseUrl, "/api/chat"), {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify(request),
      signal,
    });
  } catch (err) {
    if (signal.aborted) throw err; // let the caller see the AbortError
    throw describeFetchError(err, baseUrl);
  }

  if (!response.ok || !response.body) {
    // A 422 means the request failed validation (e.g. the code was too large).
    // FastAPI explains why in a JSON "detail" field; show part of it.
    const detail = await response.text().catch(() => "");
    throw new BackendError(
      `The backend rejected the request (HTTP ${response.status}). ${detail.slice(0, 300)}`,
    );
  }

  const parser = new SseParser();
  // TextDecoder in streaming mode correctly handles multi-byte UTF-8
  // characters split across network chunks.
  const decoder = new TextDecoder();
  const reader = response.body.getReader();

  // Handle one parsed event. Returns true if the stream is finished.
  const handle = (raw: { event: string; data: string }): boolean => {
    const evt = { event: raw.event, data: JSON.parse(raw.data) } as BackendEvent;
    switch (evt.event) {
      case "token":
        handlers.onToken(evt.data.text);
        return false;
      case "done":
        return true;
      case "error":
        throw new BackendError(evt.data.message);
      default:
        return false; // ignore unknown events, for forward compatibility
    }
  };

  try {
    while (true) {
      const { value, done } = await reader.read();
      const events = done
        ? parser.feed(decoder.decode()).concat(parser.flush())
        : parser.feed(decoder.decode(value, { stream: true }));
      for (const raw of events) {
        if (handle(raw)) return;
      }
      if (done) break;
    }
  } finally {
    // Release the connection even if we stopped early (done event, error, abort).
    reader.cancel().catch(() => undefined);
  }
  // The stream closed without a `done` or `error` event, e.g. the backend
  // crashed partway through.
  throw new BackendError("The connection to the backend closed before the answer finished.");
}

/** GET /health. Used by the "Check Backend Connection" command. */
export async function checkHealth(baseUrl: string): Promise<HealthResponse> {
  let response: Response;
  try {
    response = await fetch(joinUrl(baseUrl, "/health"), { signal: AbortSignal.timeout(10_000) });
  } catch (err) {
    throw describeFetchError(err, baseUrl);
  }
  if (!response.ok) throw new BackendError(`Health check failed (HTTP ${response.status}).`);
  return (await response.json()) as HealthResponse;
}
