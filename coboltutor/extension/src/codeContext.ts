// -----------------------------------------------------------------------------
// Builds the CodeContext (code attached to a question) from editor state.
//
// The logic is kept free of the `vscode` module: it takes a plain snapshot of
// the editor, so unit tests can call it directly. chatViewProvider.ts takes that
// snapshot from the real editor.
// -----------------------------------------------------------------------------
import type { CodeContext } from "../shared/protocol";

/**
 * Most characters of code we'll attach. The backend refuses requests above
 * 200,000 characters and trims the prompt to its own (smaller) limit, so this
 * cap only keeps us under the hard limit and avoids sending megabytes over HTTP.
 */
export const MAX_ATTACH_CHARS = 150_000;

/** A plain-data snapshot of what we need from a VSCode TextEditor. */
export interface EditorSnapshot {
  /** Full path or URI path of the document; only its base name is used. */
  path: string;
  languageId: string;
  /** Entire document text. */
  text: string;
  /**
   * The selection, as 0-based line/character positions (same as VSCode's API).
   * Omitted or empty = nothing selected.
   */
  selection?: { startLine: number; startChar: number; endLine: number; endChar: number };
}

/** Extract "PAYROLL.cbl" from "/home/me/src/PAYROLL.cbl" (or a Windows path). */
export function baseName(path: string): string {
  return path.split(/[\\/]/).pop() || path;
}

function isEmptySelection(sel: EditorSnapshot["selection"]): boolean {
  return !sel || (sel.startLine === sel.endLine && sel.startChar === sel.endChar);
}

/**
 * Build the context to attach:
 *   - with a selection: the selected *lines*, whole, so COBOL's column-based
 *     layout stays intact even if the selection starts partway into a line;
 *   - without one: the whole file.
 * Returns undefined if there's no code (an empty file or selection).
 */
export function buildCodeContext(
  snap: EditorSnapshot,
  maxChars: number = MAX_ATTACH_CHARS,
): CodeContext | undefined {
  const ctx = buildUncapped(snap);
  return ctx && capCodeContext(ctx, maxChars);
}

/**
 * Trim a context to at most `maxChars`, cutting at a line boundary, and fix up
 * `end_line` to match. The backend's prompt notes when a file was cut short.
 */
export function capCodeContext(ctx: CodeContext, maxChars: number): CodeContext {
  if (ctx.code.length <= maxChars) return ctx;
  const cut = ctx.code.lastIndexOf("\n", maxChars);
  const code = ctx.code.slice(0, cut > 0 ? cut : maxChars);
  return { ...ctx, code, end_line: ctx.start_line + code.split("\n").length - 1 };
}

function buildUncapped(snap: EditorSnapshot): CodeContext | undefined {
  const lines = snap.text.split(/\r\n|\n/);
  const fileName = baseName(snap.path);

  if (!isEmptySelection(snap.selection)) {
    const sel = snap.selection!;
    let endLine = sel.endLine;
    // Selecting whole lines by dragging to the start of the next line puts the
    // end at character 0 of that line. That line wasn't really selected, so
    // exclude it.
    if (sel.endChar === 0 && endLine > sel.startLine) endLine -= 1;
    const code = lines.slice(sel.startLine, endLine + 1).join("\n");
    if (!code.trim()) return undefined;
    return {
      file_name: fileName,
      language_id: snap.languageId,
      code,
      start_line: sel.startLine + 1, // VSCode lines are 0-based; people count from 1
      end_line: endLine + 1,
      is_selection: true,
    };
  }

  if (!snap.text.trim()) return undefined;
  return {
    file_name: fileName,
    language_id: snap.languageId,
    code: snap.text,
    start_line: 1,
    end_line: lines.length,
    is_selection: false,
  };
}

/** Short label for the context chip in the UI, e.g. "PAYROLL.cbl · lines 10-24". */
export function describeContext(ctx: Pick<CodeContext, "file_name" | "start_line" | "end_line" | "is_selection">): string {
  if (!ctx.is_selection) return `${ctx.file_name} · whole file`;
  return ctx.start_line === ctx.end_line
    ? `${ctx.file_name} · line ${ctx.start_line}`
    : `${ctx.file_name} · lines ${ctx.start_line}-${ctx.end_line}`;
}
