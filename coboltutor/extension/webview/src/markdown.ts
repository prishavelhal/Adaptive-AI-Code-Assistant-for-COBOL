// -----------------------------------------------------------------------------
// Converts the model's Markdown answers to HTML safe to display.
//
// There are two layers of protection, because model output is untrusted text:
//   1. markdown-it runs with `html: false`, so raw HTML in the answer is shown
//      as text, not interpreted as markup;
//   2. DOMPurify then sanitises the generated HTML, removing anything that
//      could run script (e.g. `javascript:` links), in case of a renderer bug.
// The webview's Content Security Policy (src/webviewHtml.ts) is a third layer.
// -----------------------------------------------------------------------------
import DOMPurify from "dompurify";
import MarkdownIt from "markdown-it";

const md = new MarkdownIt({
  html: false, // never pass through raw HTML from the model
  linkify: true, // turn bare URLs into links
  breaks: false, // standard Markdown line-break rules
});

export function renderMarkdown(source: string): string {
  return DOMPurify.sanitize(md.render(source));
}
