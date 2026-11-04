// -----------------------------------------------------------------------------
// The chat sidebar: owns the conversation and connects the webview UI to the backend.
//
// Data flow for one question:
//   1. The webview posts {type: "send", text}, or an "Explain" command calls ask().
//   2. We attach code from the editor (if enabled), append the user turn plus an
//      empty assistant turn, and send the webview a full "state" snapshot.
//   3. streamChat() POSTs the whole conversation to the backend. As each SSE
//      token arrives we append it to the assistant turn and post a small
//      "token" message to the webview.
//   4. When the stream ends (done, error, or Stop) we post a final "state".
//
// The conversation lives here, in the extension host, not in the webview.
// VSCode may destroy a webview while its sidebar is hidden; when it comes back
// it sends "ready" and we just re-send the state. An answer that's streaming
// while the panel is hidden keeps going and is complete when it reappears.
// -----------------------------------------------------------------------------
import * as vscode from "vscode";
import type {
  ChatMessage,
  CodeContext,
  HostToWebview,
  UiMessage,
  WebviewToHost,
} from "../shared/protocol";
import { BackendError, streamChat } from "./backendClient";
import { baseName, buildCodeContext, describeContext, type EditorSnapshot } from "./codeContext";
import { getWebviewHtml } from "./webviewHtml";

/** One conversation turn: the data sent to the backend plus display-only extras. */
interface Turn {
  role: "user" | "assistant";
  content: string;
  codeContext?: CodeContext;
  error?: string;
  stopped?: boolean;
}

/** URI schemes of real documents. Others (e.g. "output" for the Output panel) are skipped. */
const DOCUMENT_SCHEMES = new Set(["file", "untitled", "vscode-remote", "vscode-vfs"]);

export class ChatViewProvider implements vscode.WebviewViewProvider, vscode.Disposable {
  /** Must match the view id in package.json ("contributes.views"). */
  static readonly viewId = "coboltutor.chat";

  private view?: vscode.WebviewView;
  private turns: Turn[] = [];
  /** Set while an answer is streaming; abort() cancels the HTTP request. */
  private abortController?: AbortController;
  private includeActiveFile: boolean;
  /**
   * The most recently focused text editor. Clicking into the chat sidebar can
   * leave `activeTextEditor` undefined, so we remember the last real one.
   */
  private lastEditor?: vscode.TextEditor;
  private readonly disposables: vscode.Disposable[] = [];

  constructor(private readonly extensionUri: vscode.Uri) {
    this.includeActiveFile = vscode.workspace
      .getConfiguration("coboltutor")
      .get<boolean>("includeActiveFileByDefault", true);
    this.lastEditor = vscode.window.activeTextEditor;

    // Keep the "attached file" chip in the chat up to date as the user moves
    // between editors and changes their selection.
    this.disposables.push(
      vscode.window.onDidChangeActiveTextEditor((editor) => {
        if (editor && DOCUMENT_SCHEMES.has(editor.document.uri.scheme)) this.lastEditor = editor;
        this.postActiveContext();
      }),
      vscode.window.onDidChangeTextEditorSelection(() => this.postActiveContext()),
    );
  }

  // --- WebviewViewProvider -----------------------------------------------------

  /** Called by VSCode each time the sidebar view's webview is (re)created. */
  resolveWebviewView(view: vscode.WebviewView): void {
    this.view = view;
    view.webview.options = {
      enableScripts: true,
      // The webview may only load files from our built webview folder.
      localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, "dist", "webview")],
    };
    view.webview.html = getWebviewHtml(view.webview, this.extensionUri);

    view.webview.onDidReceiveMessage(
      (msg: WebviewToHost) => this.onWebviewMessage(msg),
      undefined,
      this.disposables,
    );
    view.onDidDispose(() => {
      if (this.view === view) this.view = undefined;
    });
  }

  private onWebviewMessage(msg: WebviewToHost): void {
    switch (msg.type) {
      case "ready":
        this.postState();
        this.postActiveContext();
        break;
      case "send": {
        const text = msg.text.trim();
        if (!text) return;
        const ctx = this.includeActiveFile ? this.activeCodeContext() : undefined;
        void this.ask(text, ctx);
        break;
      }
      case "cancel":
        this.abortController?.abort();
        break;
      case "newChat":
        this.newChat();
        break;
      case "setIncludeActiveFile":
        this.includeActiveFile = msg.include;
        this.postActiveContext();
        break;
    }
  }

  // --- Public actions (also used by commands in extension.ts) -----------------

  /** Clear the conversation, cancelling any answer in progress. */
  newChat(): void {
    this.abortController?.abort();
    this.turns = [];
    this.postState();
  }

  /**
   * "Explain" commands: open the chat and ask for an explanation of the editor's
   * selection (`selectionOnly`) or, otherwise, of the whole file.
   */
  async explain(editor: vscode.TextEditor | undefined, selectionOnly: boolean): Promise<void> {
    editor ??= this.currentEditor();
    if (!editor) {
      void vscode.window.showInformationMessage("CobolTutor: open a COBOL file first.");
      return;
    }
    const snap = snapshot(editor);
    if (!selectionOnly) delete snap.selection; // whole file even if something is selected
    const ctx = buildCodeContext(snap);
    if (!ctx) {
      void vscode.window.showInformationMessage(
        selectionOnly ? "CobolTutor: select some code first." : "CobolTutor: this file is empty.",
      );
      return;
    }
    // Reveal the sidebar. "<viewId>.focus" is a command VSCode creates for every view.
    await vscode.commands.executeCommand(`${ChatViewProvider.viewId}.focus`);
    const prompt = ctx.is_selection
      ? "Explain what this selected code does."
      : "Explain what this program does, section by section.";
    await this.ask(prompt, ctx);
  }

  /** Add a user question to the conversation and stream the tutor's answer. */
  async ask(text: string, codeContext: CodeContext | undefined): Promise<void> {
    // One answer at a time: asking again (e.g. via Explain) cancels the current one.
    this.abortController?.abort();
    const controller = new AbortController();
    this.abortController = controller;

    this.turns.push({ role: "user", content: text, codeContext });
    // Build the request *before* adding the empty assistant turn we'll stream into.
    const request = { messages: this.toBackendMessages() };
    const answer: Turn = { role: "assistant", content: "" };
    this.turns.push(answer);
    this.postState();

    const baseUrl = vscode.workspace
      .getConfiguration("coboltutor")
      .get<string>("backendUrl", "http://127.0.0.1:8000");

    try {
      await streamChat(baseUrl, request, controller.signal, {
        onToken: (t) => {
          answer.content += t;
          // Only forward tokens if this is still the current answer (it may
          // have been replaced by a newer question since).
          if (this.abortController === controller) this.post({ type: "token", text: t });
        },
      });
      // Safety net: the backend reports empty answers as errors itself, but
      // never show a "successful" blank bubble if one slips through anyway.
      if (!answer.content.trim()) {
        answer.error = "The model returned an empty answer. Please try again.";
      }
    } catch (err) {
      if (controller.signal.aborted) {
        answer.stopped = true;
      } else {
        answer.error =
          err instanceof BackendError ? err.message : `Unexpected error: ${String(err)}`;
      }
    } finally {
      // Only the request that's still current may clear the controller and
      // send the final state; a superseded one must not clobber the new one.
      if (this.abortController === controller) {
        this.abortController = undefined;
      }
      this.postState();
    }
  }

  dispose(): void {
    this.abortController?.abort();
    for (const d of this.disposables) d.dispose();
  }

  // --- Helpers -------------------------------------------------------------------

  /**
   * Convert turns to the backend format. Assistant turns that failed or are
   * empty are left out, so the model never sees an error as its own reply.
   */
  private toBackendMessages(): ChatMessage[] {
    return this.turns
      .filter((t) => t.role === "user" || (t.content.trim() && !t.error))
      .map((t) => ({ role: t.role, content: t.content, code_context: t.codeContext ?? null }));
  }

  /** The editor the user is working in, if it's still open. */
  private currentEditor(): vscode.TextEditor | undefined {
    const active = vscode.window.activeTextEditor;
    if (active && DOCUMENT_SCHEMES.has(active.document.uri.scheme)) return active;
    if (this.lastEditor && !this.lastEditor.document.isClosed) return this.lastEditor;
    return undefined;
  }

  private activeCodeContext(): CodeContext | undefined {
    const editor = this.currentEditor();
    return editor ? buildCodeContext(snapshot(editor)) : undefined;
  }

  private post(msg: HostToWebview): void {
    // postMessage to a hidden or destroyed webview is just dropped; that's fine,
    // because the webview asks for the full state again when it's recreated.
    void this.view?.webview.postMessage(msg);
  }

  private postState(): void {
    const messages: UiMessage[] = this.turns.map((t) => ({
      role: t.role,
      content: t.content,
      contextLabel: t.codeContext ? describeContext(t.codeContext) : undefined,
      error: t.error,
      stopped: t.stopped,
    }));
    this.post({ type: "state", messages, streaming: this.abortController !== undefined });
  }

  private postActiveContext(): void {
    if (!this.view) return;
    // Build only the label, not the full context, since this runs on every
    // selection change and copying large files each time would be wasteful.
    const editor = this.currentEditor();
    let label: string | null = null;
    if (editor) {
      const sel = editor.selection;
      const name = editor.document.fileName;
      if (sel.isEmpty) {
        label = describeContext({ file_name: baseName(name), start_line: 1, end_line: 1, is_selection: false });
      } else {
        // Match buildCodeContext: a selection ending at column 0 excludes that line.
        const end = sel.end.character === 0 && sel.end.line > sel.start.line ? sel.end.line - 1 : sel.end.line;
        label = describeContext({
          file_name: baseName(name),
          start_line: sel.start.line + 1,
          end_line: end + 1,
          is_selection: true,
        });
      }
    }
    this.post({ type: "activeContext", label, include: this.includeActiveFile });
  }
}

/** Copy what buildCodeContext needs out of a live editor. */
function snapshot(editor: vscode.TextEditor): EditorSnapshot {
  const { document, selection } = editor;
  return {
    path: document.fileName,
    languageId: document.languageId,
    text: document.getText(),
    selection: {
      startLine: selection.start.line,
      startChar: selection.start.character,
      endLine: selection.end.line,
      endChar: selection.end.character,
    },
  };
}
