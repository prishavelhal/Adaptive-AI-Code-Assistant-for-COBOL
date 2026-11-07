// -----------------------------------------------------------------------------
// Types shared by every part of the frontend. There are two separate contracts:
//
//  1. Extension host  <->  Python backend   (HTTP JSON + Server-Sent Events)
//     Mirrors backend/src/coboltutor_backend/schemas.py. Field names use
//     snake_case to match Python, so the objects can be sent as-is.
//
//  2. Extension host  <->  Vue webview      (VSCode's postMessage channel)
//     The webview is sandboxed: it can't reach the network or read files, so
//     everything goes through these messages. The extension host owns the
//     conversation state; the webview only displays it and reports user actions.
//
// This file contains only types (no runtime code), so either side can import it
// without pulling in anything else.
// -----------------------------------------------------------------------------

// ===== 1. Backend API =========================================================

/** Code from the user's editor that is attached to a question. */
export interface CodeContext {
  /** Base file name only (e.g. "PAYROLL.cbl"); the full path never leaves the machine. */
  file_name: string;
  /** VSCode language id, e.g. "cobol" (depends on which COBOL extension is installed). */
  language_id: string;
  code: string;
  /** 1-based, inclusive line range of `code` within the file. */
  start_line: number;
  end_line: number;
  /** true = the user's selection, false = the whole file. */
  is_selection: boolean;
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  code_context?: CodeContext | null;
}

/** Body of POST /api/chat. */
export interface ChatRequest {
  messages: ChatMessage[];
}

/** Events the backend streams back (see backend/src/coboltutor_backend/sse.py). */
export type BackendEvent =
  | { event: "token"; data: { text: string } }
  | { event: "done"; data: Record<string, never> }
  | { event: "error"; data: { message: string } };

/** Response of GET /health. */
export interface HealthResponse {
  status: string;
  model: string;
  model_ready: boolean;
}

// ===== 2. Host <-> webview messages ==========================================

/** One chat bubble as the webview displays it. */
export interface UiMessage {
  role: "user" | "assistant";
  /** Markdown text. For the assistant message being streamed, this grows token by token. */
  content: string;
  /** Short label for attached code, e.g. "PAYROLL.cbl · lines 10-24", shown as a chip. */
  contextLabel?: string;
  /** Set when generating this answer failed; shown as an error under the message. */
  error?: string;
  /** true if the user pressed Stop before the answer finished. */
  stopped?: boolean;
}

/** Messages the extension host sends to the webview. */
export type HostToWebview =
  /** Full snapshot of the conversation; sent on load and after structural changes. */
  | {
      type: "state";
      messages: UiMessage[];
      /** true while an answer is being generated. */
      streaming: boolean;
    }
  /** Append text to the last (assistant) message. Avoids resending the whole state per token. */
  | { type: "token"; text: string }
  /** What will be attached if the user sends a question now (null = no usable editor). */
  | { type: "activeContext"; label: string | null; include: boolean };

/** Messages the webview sends to the extension host. */
export type WebviewToHost =
  /** The webview finished loading and wants the current state. */
  | { type: "ready" }
  /** The user submitted a question. */
  | { type: "send"; text: string }
  /** The user pressed Stop. */
  | { type: "cancel" }
  /** The user clicked "New chat". */
  | { type: "newChat" }
  /** The user toggled "attach active file". */
  | { type: "setIncludeActiveFile"; include: boolean };
