// -----------------------------------------------------------------------------
// Bundles the *extension host* code (src/**) into a single dist/extension.js.
//
// VSCode runs this file in a Node.js process (the "extension host"). Bundling
// means the shipped extension doesn't need a node_modules folder, and it loads
// faster. The Vue webview UI is built separately by Vite (see vite.config.ts),
// because it runs in a browser-like sandbox, not Node.
//
//   node esbuild.mjs           # one-off build
//   node esbuild.mjs --watch   # rebuild on every save (used while debugging)
// -----------------------------------------------------------------------------
import * as esbuild from "esbuild";

const watch = process.argv.includes("--watch");

/** @type {import("esbuild").BuildOptions} */
const options = {
  entryPoints: ["src/extension.ts"],
  outfile: "dist/extension.js",
  bundle: true,
  // The extension host is Node, and VSCode loads extensions as CommonJS.
  platform: "node",
  format: "cjs",
  target: "node20",
  // The `vscode` module is supplied by VSCode at runtime and can't be bundled.
  external: ["vscode"],
  sourcemap: true,
  minify: !watch,
  logLevel: "info",
};

if (watch) {
  const ctx = await esbuild.context(options);
  await ctx.watch();
} else {
  await esbuild.build(options);
}
