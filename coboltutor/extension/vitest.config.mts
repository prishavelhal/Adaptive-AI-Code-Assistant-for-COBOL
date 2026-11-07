// Unit-test configuration. Tests cover the pure modules (SSE parsing, code
// context, backend client with a mocked fetch) and run in plain Node; no
// VSCode instance is needed.
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
