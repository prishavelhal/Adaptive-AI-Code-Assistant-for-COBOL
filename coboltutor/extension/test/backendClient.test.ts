// Tests streamChat against a mocked `fetch`, so no backend has to be running.
import { afterEach, describe, expect, it, vi } from "vitest";
import { AGENT_CHAT_PATH, BackendError, streamChat } from "../src/backendClient";

/** Build a fetch Response whose body streams the given chunks. */
function sseResponse(chunks: string[], status = 200): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const c of chunks) controller.enqueue(encoder.encode(c));
      controller.close();
    },
  });
  return new Response(body, { status, headers: { "Content-Type": "text/event-stream" } });
}

const REQUEST = { messages: [{ role: "user" as const, content: "hi" }] };

afterEach(() => vi.unstubAllGlobals());

describe("streamChat", () => {
  it("delivers tokens in order and resolves on done", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      sseResponse(['event: token\ndata: {"text":"Hel', 'lo"}\n\nevent: token\ndata: {"text":"!"}\n\n', "event: done\ndata: {}\n\n"]),
    );
    vi.stubGlobal("fetch", fetchMock);

    const tokens: string[] = [];
    await streamChat("http://x/", REQUEST, new AbortController().signal, { onToken: (t) => tokens.push(t) });

    expect(tokens).toEqual(["Hello", "!"]);
    // The trailing slash on the base URL is handled.
    expect(fetchMock.mock.calls[0]![0]).toBe("http://x/api/chat");
    expect(JSON.parse(fetchMock.mock.calls[0]![1].body)).toEqual(REQUEST);
  });

  it("rejects with the backend's message on an error event", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(sseResponse(['event: error\ndata: {"message":"Is Ollama running?"}\n\n'])),
    );
    await expect(
      streamChat("http://x", REQUEST, new AbortController().signal, { onToken: () => {} }),
    ).rejects.toThrow(new BackendError("Is Ollama running?"));
  });

  it("rejects if the stream ends without done", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(sseResponse(['event: token\ndata: {"text":"a"}\n\n'])));
    await expect(
      streamChat("http://x", REQUEST, new AbortController().signal, { onToken: () => {} }),
    ).rejects.toThrow(/closed before the answer finished/);
  });

  it("explains how to start the backend when the connection is refused", async () => {
    const err = Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNREFUSED" } });
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(err));
    await expect(
      streamChat("http://127.0.0.1:8000", REQUEST, new AbortController().signal, { onToken: () => {} }),
    ).rejects.toThrow(/docker compose up -d/);
  });

  it("reports HTTP errors such as validation failures", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response('{"detail":"bad"}', { status: 422 })));
    await expect(
      streamChat("http://x", REQUEST, new AbortController().signal, { onToken: () => {} }),
    ).rejects.toThrow(/HTTP 422/);
  });
});

describe("streamChat with the agent endpoint", () => {
  const VERIFICATION = {
    issues: [{ source: "check", message: "The answer mentions line 99.", line: 99 }],
    reviewed_by_model: false,
  };
  const AGENT_STREAM = [
    'event: stage\ndata: {"name":"analyze"}\n\n',
    'event: stage\ndata: {"name":"explain"}\n\n',
    'event: token\ndata: {"text":"Hi"}\n\n',
    'event: stage\ndata: {"name":"verify"}\n\n',
    `event: verification\ndata: ${JSON.stringify(VERIFICATION)}\n\n`,
    "event: done\ndata: {}\n\n",
  ];

  it("posts to the path it is given and reports stages and verification", async () => {
    const fetchMock = vi.fn().mockResolvedValue(sseResponse(AGENT_STREAM));
    vi.stubGlobal("fetch", fetchMock);

    const seen: string[] = [];
    let verification: unknown;
    await streamChat(
      "http://x",
      REQUEST,
      new AbortController().signal,
      {
        onToken: (t) => seen.push(`token:${t}`),
        onStage: (s) => seen.push(`stage:${s}`),
        onVerification: (v) => (verification = v),
      },
      AGENT_CHAT_PATH,
    );

    expect(fetchMock.mock.calls[0]![0]).toBe("http://x/api/agent-chat");
    expect(seen).toEqual(["stage:analyze", "stage:explain", "token:Hi", "stage:verify"]);
    expect(verification).toEqual(VERIFICATION);
  });

  it("still works for callers that only handle tokens (the existing /api/chat usage)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(sseResponse(AGENT_STREAM)));
    const tokens: string[] = [];
    await streamChat("http://x", REQUEST, new AbortController().signal, {
      onToken: (t) => tokens.push(t),
    });
    expect(tokens).toEqual(["Hi"]);
  });
});
