import { describe, expect, it } from "vitest";
import { SseParser } from "../src/sse";

describe("SseParser", () => {
  it("parses a complete event", () => {
    const p = new SseParser();
    expect(p.feed('event: token\ndata: {"text":"hi"}\n\n')).toEqual([
      { event: "token", data: '{"text":"hi"}' },
    ]);
  });

  it("handles events split across arbitrary chunk boundaries", () => {
    const stream = 'event: token\ndata: {"text":"a"}\n\nevent: done\ndata: {}\n\n';
    // Feed one character at a time, the worst case for buffering.
    const p = new SseParser();
    const events = [...stream].flatMap((ch) => p.feed(ch));
    expect(events).toEqual([
      { event: "token", data: '{"text":"a"}' },
      { event: "done", data: "{}" },
    ]);
  });

  it("handles CRLF line endings, including a CR/LF pair split across chunks", () => {
    const p = new SseParser();
    const events = [...p.feed("event: done\r"), ...p.feed("\ndata: {}\r\n\r"), ...p.feed("\n")];
    expect(events).toEqual([{ event: "done", data: "{}" }]);
  });

  it("joins multiple data lines, defaults the event name, and ignores comments", () => {
    const p = new SseParser();
    expect(p.feed(": keep-alive\ndata: one\ndata: two\n\n")).toEqual([
      { event: "message", data: "one\ntwo" },
    ]);
  });

  it("dispatches a final unterminated event on flush", () => {
    const p = new SseParser();
    expect(p.feed("event: done\ndata: {}")).toEqual([]);
    expect(p.flush()).toEqual([{ event: "done", data: "{}" }]);
  });
});
