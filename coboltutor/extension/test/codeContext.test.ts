import { describe, expect, it } from "vitest";
import { baseName, buildCodeContext, capCodeContext, describeContext } from "../src/codeContext";

const TEXT = [
  "       IDENTIFICATION DIVISION.",
  "       PROGRAM-ID. HELLO.",
  "       PROCEDURE DIVISION.",
  '           DISPLAY "HELLO".',
  "           STOP RUN.",
].join("\n");

const snap = (selection?: { startLine: number; startChar: number; endLine: number; endChar: number }) => ({
  path: "/home/me/cobol/HELLO.cbl",
  languageId: "cobol",
  text: TEXT,
  selection,
});

describe("buildCodeContext", () => {
  it("uses the whole file when nothing is selected", () => {
    const ctx = buildCodeContext(snap({ startLine: 2, startChar: 4, endLine: 2, endChar: 4 }));
    expect(ctx).toMatchObject({
      file_name: "HELLO.cbl",
      start_line: 1,
      end_line: 5,
      is_selection: false,
      code: TEXT,
    });
  });

  it("expands a partial selection to whole lines, using 1-based line numbers", () => {
    const ctx = buildCodeContext(snap({ startLine: 2, startChar: 10, endLine: 3, endChar: 5 }));
    expect(ctx).toMatchObject({ start_line: 3, end_line: 4, is_selection: true });
    expect(ctx?.code).toBe('       PROCEDURE DIVISION.\n           DISPLAY "HELLO".');
  });

  it("excludes the final line when the selection ends at its first column", () => {
    const ctx = buildCodeContext(snap({ startLine: 0, startChar: 0, endLine: 2, endChar: 0 }));
    expect(ctx).toMatchObject({ start_line: 1, end_line: 2 });
  });

  it("returns undefined for an empty file", () => {
    expect(buildCodeContext({ path: "x.cbl", languageId: "cobol", text: "  \n" })).toBeUndefined();
  });

  it("caps very large code at a line boundary and fixes end_line", () => {
    const ctx = buildCodeContext(snap(), 60);
    expect(ctx?.code).toBe("       IDENTIFICATION DIVISION.\n       PROGRAM-ID. HELLO.");
    expect(ctx?.end_line).toBe(2);
  });
});

describe("helpers", () => {
  it("baseName handles POSIX and Windows paths", () => {
    expect(baseName("/a/b/PAY.cbl")).toBe("PAY.cbl");
    expect(baseName("C:\\src\\PAY.cbl")).toBe("PAY.cbl");
    expect(baseName("Untitled-1")).toBe("Untitled-1");
  });

  it("capCodeContext leaves small contexts untouched", () => {
    const ctx = buildCodeContext(snap())!;
    expect(capCodeContext(ctx, 10_000)).toBe(ctx);
  });

  it("describeContext produces readable labels", () => {
    const base = { file_name: "A.cbl", start_line: 3, end_line: 3, is_selection: true };
    expect(describeContext(base)).toBe("A.cbl · line 3");
    expect(describeContext({ ...base, end_line: 9 })).toBe("A.cbl · lines 3-9");
    expect(describeContext({ ...base, is_selection: false })).toBe("A.cbl · whole file");
  });
});
