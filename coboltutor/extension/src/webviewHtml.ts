// -----------------------------------------------------------------------------
// Generates the HTML document loaded into the chat webview.
//
// Webviews are sandboxed iframes. We lock them down with a strict Content
// Security Policy (CSP):
//   - default-src 'none'  -> block everything not explicitly allowed below
//                            (including all network requests from the webview);
//   - script-src 'nonce-…'-> only run the one script tag carrying this random
//                            nonce (our bundled Vue app);
//   - style-src / font-src / img-src -> only files shipped inside the extension.
// This matters because the webview displays model output: even if the model
// produced malicious markup, the CSP stops it from running scripts or loading
// remote content.
// -----------------------------------------------------------------------------
import { randomBytes } from "node:crypto";
import * as vscode from "vscode";

export function getWebviewHtml(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  // Webviews can't load file:// URLs directly; asWebviewUri converts a path in
  // the extension folder into a URL the webview is allowed to fetch.
  const asset = (file: string) =>
    webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "dist", "webview", "assets", file));

  // A fresh random nonce each time the HTML is generated.
  const nonce = randomBytes(16).toString("base64");

  const csp = [
    "default-src 'none'",
    `style-src ${webview.cspSource}`,
    `font-src ${webview.cspSource}`,
    `img-src ${webview.cspSource} data:`,
    `script-src 'nonce-${nonce}'`,
  ].join("; ");

  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link rel="stylesheet" href="${asset("index.css")}" />
  <title>CobolTutor</title>
</head>
<body>
  <div id="app"></div>
  <script type="module" nonce="${nonce}" src="${asset("index.js")}"></script>
</body>
</html>`;
}
