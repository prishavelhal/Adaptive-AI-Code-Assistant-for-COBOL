// -----------------------------------------------------------------------------
// Extension entry point. VSCode calls `activate` the first time one of our
// contributions (the sidebar view or a command) is used, and `deactivate` on
// shutdown.
//
// This file only wires things together. The logic lives in:
//   chatViewProvider.ts - conversation state + webview <-> backend plumbing
//   backendClient.ts    - HTTP/SSE calls to the Python backend
//   codeContext.ts      - turns editor contents into code attached to a question
// -----------------------------------------------------------------------------
import * as vscode from "vscode";
import { BackendError, checkHealth } from "./backendClient";
import { ChatViewProvider } from "./chatViewProvider";

export function activate(context: vscode.ExtensionContext): void {
  const chat = new ChatViewProvider(context.extensionUri);

  // Anything pushed onto context.subscriptions is disposed automatically
  // when the extension is deactivated.
  context.subscriptions.push(
    chat,
    vscode.window.registerWebviewViewProvider(ChatViewProvider.viewId, chat),

    // Editor commands receive the editor they were invoked on. Commands run
    // from the Command Palette receive nothing, so fall back to the active one.
    vscode.commands.registerCommand("coboltutor.explainSelection", () =>
      chat.explain(vscode.window.activeTextEditor, true),
    ),
    vscode.commands.registerCommand("coboltutor.explainFile", () =>
      chat.explain(vscode.window.activeTextEditor, false),
    ),
    vscode.commands.registerCommand("coboltutor.newChat", () => chat.newChat()),
    vscode.commands.registerCommand("coboltutor.checkBackend", checkBackendCommand),
  );
}

export function deactivate(): void {
  // Nothing extra: everything is cleaned up through context.subscriptions.
}

/** "CobolTutor: Check Backend Connection": reports whether the backend and model are ready. */
async function checkBackendCommand(): Promise<void> {
  const baseUrl = vscode.workspace
    .getConfiguration("coboltutor")
    .get<string>("backendUrl", "http://127.0.0.1:8000");
  try {
    const health = await checkHealth(baseUrl);
    if (health.model_ready) {
      void vscode.window.showInformationMessage(
        `CobolTutor: backend is up and model "${health.model}" is ready.`,
      );
    } else {
      void vscode.window.showWarningMessage(
        `CobolTutor: backend is up, but model "${health.model}" isn't ready yet. ` +
          "It may still be downloading; check `docker compose logs -f ollama-pull`.",
      );
    }
  } catch (err) {
    const message = err instanceof BackendError ? err.message : String(err);
    void vscode.window.showErrorMessage(`CobolTutor: ${message}`);
  }
}
