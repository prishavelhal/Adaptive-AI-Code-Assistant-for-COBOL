// -----------------------------------------------------------------------------
// Incremental Server-Sent Events (SSE) parser.
//
// Why not the browser's built-in `EventSource`? It only supports GET requests,
// and we need to POST the conversation as a JSON body. So we read the raw
// response stream with `fetch` and parse the SSE text format ourselves.
//
// The format (https://html.spec.whatwg.org/multipage/server-sent-events.html):
//   - Text arrives in arbitrary chunks. A chunk can end in the middle of a line,
//     or even in the middle of a "\r\n" pair, so we buffer the leftovers.
//   - Each line is "field: value". The fields we care about are `event` and `data`.
//   - Several `data:` lines in one event are joined with "\n".
//   - Lines starting with ":" are comments (often used as keep-alives).
//   - A blank line ends the event and "dispatches" it.
//
// This module has no VSCode or network dependencies, so it is fully unit tested
// (see test/sse.test.ts).
// -----------------------------------------------------------------------------

/** One parsed event. `event` defaults to "message", per the spec. */
export interface SseEvent {
  event: string;
  data: string;
}

export class SseParser {
  /** Text received but not yet ending in a newline (an incomplete line). */
  private buffer = "";
  /** Fields of the event currently being built. */
  private eventName = "";
  private dataLines: string[] = [];
  /** True if the previous chunk ended in "\r", whose "\n" may arrive next. */
  private pendingCR = false;

  /** Feed a chunk of decoded text; returns any events that are now complete. */
  feed(chunk: string): SseEvent[] {
    // A "\r\n" split across two chunks: drop the "\n" so we don't see an extra
    // (blank) line, which would dispatch the event too early.
    if (this.pendingCR && chunk.startsWith("\n")) {
      chunk = chunk.slice(1);
    }
    this.pendingCR = chunk.endsWith("\r");
    this.buffer += chunk;

    const events: SseEvent[] = [];
    // Split on any of the three line endings the spec allows: \r\n, \n, or \r.
    const lines = this.buffer.split(/\r\n|\n|\r/);
    // The last element is an incomplete line (or "" if the chunk ended with a
    // newline); keep it in the buffer for the next chunk.
    this.buffer = lines.pop() ?? "";

    for (const line of lines) {
      const event = this.processLine(line);
      if (event) events.push(event);
    }
    return events;
  }

  /**
   * Call when the stream ends. Dispatches a final event if the server closed the
   * connection without the trailing blank line.
   */
  flush(): SseEvent[] {
    const events: SseEvent[] = [];
    if (this.buffer) {
      const event = this.processLine(this.buffer);
      if (event) events.push(event);
      this.buffer = "";
    }
    const last = this.processLine(""); // treat end-of-stream as a blank line
    if (last) events.push(last);
    return events;
  }

  /** Handle one complete line; returns an event if the line was blank and ended one. */
  private processLine(line: string): SseEvent | undefined {
    if (line === "") {
      // Blank line: dispatch the event. Per spec, an event with no data lines
      // is not dispatched at all.
      if (this.dataLines.length === 0) {
        this.eventName = "";
        return undefined;
      }
      const event = { event: this.eventName || "message", data: this.dataLines.join("\n") };
      this.eventName = "";
      this.dataLines = [];
      return event;
    }
    if (line.startsWith(":")) return undefined; // comment

    // "field: value": split on the first colon and drop one optional space.
    const colon = line.indexOf(":");
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? "" : line.slice(colon + 1);
    if (value.startsWith(" ")) value = value.slice(1);

    if (field === "event") this.eventName = value;
    else if (field === "data") this.dataLines.push(value);
    // `id` and `retry` are part of the spec but unused here, so they're ignored.
    return undefined;
  }
}
