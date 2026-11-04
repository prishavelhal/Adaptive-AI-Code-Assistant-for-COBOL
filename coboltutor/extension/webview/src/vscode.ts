// -----------------------------------------------------------------------------
// Typed wrapper around the VSCode webview messaging API.
//
// VSCode injects a global `acquireVsCodeApi()` function into every webview. It
// may be called only once per page load, so we call it here, once, and share
// the result.
// -----------------------------------------------------------------------------
import type { HostToWebview, WebviewToHost } from "../../shared/protocol";

interface VsCodeApi {
  postMessage(message: WebviewToHost): void;
}

declare function acquireVsCodeApi(): VsCodeApi;

const api = acquireVsCodeApi();

/** Send a message to the extension host (chatViewProvider.ts). */
export function postToHost(message: WebviewToHost): void {
  api.postMessage(message);
}

/** Subscribe to messages from the extension host. Returns an unsubscribe function. */
export function onHostMessage(handler: (message: HostToWebview) => void): () => void {
  const listener = (event: MessageEvent<HostToWebview>) => handler(event.data);
  window.addEventListener("message", listener);
  return () => window.removeEventListener("message", listener);
}
