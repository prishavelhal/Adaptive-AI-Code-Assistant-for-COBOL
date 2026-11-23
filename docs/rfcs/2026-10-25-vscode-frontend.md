# RFC: Using Visual Studio Code as the Frontend

| Field | Value |
| --- | --- |
| Author | Taylor Hacker |
| Date | 2026-10-25 (revised 2026-11-22 after peer and instructor review) |
| Status | Proposed |
| Decision Date | (fill when decided) |
| Deciders | Taylor, Prisha, Quinn, Sarah, Jack, Michael |
| Superseded By | (none) |

## Problem and Context

Our team is building a proof-of-concept AI assistant that explains IBM Enterprise COBOL and adapts each explanation to the user's problem-solving style. The project responds to a real shortage. The COBOL systems that run banking, insurance, and government services are increasingly maintained by developers who did not learn COBOL, and our IBM partner's brief observes that most AI code assistants give the same explanation to everyone, regardless of how they learn. IBM Research found that language models can adapt code explanations to different problem-solving styles when prompted, and that IBM Granite adapted less than other models [1]. Our assistant adds an adaptation layer on top of IBM Granite 4.2 to close that gap, and the team has already chosen Python with FastAPI for the backend.

The frontend has not yet been decided. The frontend determines where users meet the assistant, how the assistant obtains the COBOL code it explains, and what IBM would have to adopt if it continued the project after handoff. The leading candidate is an extension for Microsoft's Visual Studio Code (VS Code), an editor used by 73.6% of developers in the 2024 Stack Overflow Developer Survey [2]. IBM already ships mainframe tooling in the same editor, such as the IBM Z Open Editor extension for COBOL, PL/I, HLASM, REXX, and JCL [3].

The decision is needed now for three reasons. First, the walking skeleton, which streams an explanation from the backend to the user, cannot be demonstrated end to end until the frontend exists. Second, several requirements depend on the frontend: selecting code and requesting an explanation from the editor (FR-1), streaming answers (FR-2), a persistent style profile in a sidebar (FR-4), and follow-up questions (FR-7). Third, the planned user study measures comprehension through whichever interface we build, so that interface must be fixed before the study is designed.

This decision is moderately hard to reverse. The backend exposes a plain HTTP API and does not depend on the frontend, so changing frontends later would not require backend work. However, the frontend code, its tests, the installation instructions, and the user study materials would all need to be rebuilt, which would cost roughly a sprint. Deferring the decision costs more: the team would continue building backend features with no way to put them in front of a user, and every test of adaptation would happen without the context of a real editor.

## Options

### Option A: VS Code Extension

The assistant ships as a VS Code extension. A sidebar panel hosts the chat and the style profile, and editor commands such as "Explain Selected Code" send the current selection or file to the backend. The panel is a webview, which is an embedded web page that communicates with the extension through message passing [4].

The main benefit is that the code is already in front of the user. The extension reads the open file or selection through VS Code's API, so the user never copies code into another tool, and the extension can attach surrounding context such as the file name and line numbers. This matters for COBOL in particular, where a program's meaning often depends on copybooks and data definitions elsewhere in the file or project. A second benefit is that IBM's own COBOL tooling runs in VS Code [3], so mainframe developers would use our assistant alongside tools they may already have installed, and IBM would receive a product in a format it already distributes. A third benefit is distribution: an extension packages into a single `.vsix` file that anyone can install without the Marketplace [5].

The costs are a loss of control and some added complexity. The interface must fit VS Code's layout, such as a sidebar of limited width, and must follow the editor's color theme. The webview runs in a restricted environment, so all communication with the backend passes through the extension, and the webview must declare a Content Security Policy [4]. VS Code's own component library for webviews, the Webview UI Toolkit, was deprecated on January 1, 2025 [6], so the interface must be built with a general web framework.

**Right choice when** the target users already work in VS Code, where IBM's own COBOL tooling runs [3], and the assistant's value depends on direct access to the code being read.

### Option B: Terminal Application

The assistant runs as a command-line program, similar to terminal-based developer tools such as Claude Code. The user runs a command with a file or a range of lines, and the explanation streams to the terminal.

A terminal application works with every editor, including Vim, Emacs, and the JetBrains IDEs, and it is simpler to test, because tests can run the program and compare its output without launching an editor. Its costs are significant for this project. The program would have to read, locate, and select code without an editor's help, so the user would specify files and line ranges by hand. The style profile and follow-up conversation would need a text-based interface. Most importantly, a command-line interface asks more of users who have lower computer self-efficacy, one of the cognitive facets that the GenderMag method identifies [7]. Because our project adapts to these facets, building the one interface that disadvantages some of them would undermine the project's goal.

**Right choice when** the target users are experienced terminal users who work outside VS Code, or when the assistant must run in scripted or automated pipelines rather than interactively.

### Option C: Standalone Web Application

The assistant runs as a web application in the browser, and users paste or upload code into it.

A web application gives the team full control over the interface, works on any device with a browser, and avoids every editor-specific restriction. Its costs fall on the user and on the partner. Users must leave their editor and paste code into a separate tool for every question. Pasting a single file also loses the related files that COBOL programs depend on. A web application would also need hosting, and because enterprise code must not leave the company's systems (NFR-5), IBM would need to deploy and secure that hosting itself rather than install an extension.

**Right choice when** the users are learners who are not yet working in a real codebase, such as students practicing on sample programs, or when the assistant must be available without installing software.

### Option D: Do Nothing (Defer the Frontend)

The team keeps building the backend and defers the frontend decision. Until a frontend exists, the only interfaces are the backend's automatically generated API documentation page and `curl` commands.

This path costs nothing in the short term and keeps every option open. Its cost arrives at the first milestone that needs a user: the walking skeleton demonstration, the IBM partner demo, and the comprehension study all require an interface that non-developers can use. Deferring also hides integration problems, such as streaming, cancellation, and how code is attached to a question, until late in the project, when they are most expensive to fix.

**Right choice when** the backend's design is still changing so quickly that any frontend would be rebuilt anyway, which is no longer true now that the backend API is stable.

## Analysis

This section compares the options on performance, complexity, maintainability, security, and cost. It draws on the VS Code documentation and on a working prototype of Option A that the team built in `coboltutor/extension/`, which already implements code selection, streaming, cancellation from the Stop button, and the sidebar chat.

**Performance.** The frontend runs no model inference in any option, so the user's wait is dominated by the backend and the model. The frontend's job is to show the first words of the answer quickly (FR-2, NFR-1) and to stop generating when the user no longer wants the answer. The prototype streams the answer through the extension to the webview. It cancels the request when the user presses Stop, starts a new chat, or asks a new question, which stops the model from spending compute on an unwanted answer. It does not yet cancel when the user closes the panel, a gap that check V4 below is designed to catch. A terminal application could stream just as quickly. A web application would add a hop through its hosting server.

**Complexity.** For Option A, most of the complexity sits in the webview. The webview cannot call the backend directly, so the extension relays each request and each streamed token through message passing [4]. Webview content can also be discarded when the panel is hidden, so conversation state must either be stored in the extension or preserved with VS Code's state API [4]. The prototype stores the conversation in the extension and redraws it whenever the panel is recreated. Its unit tests cover the stream parser, the backend client, and how code from the editor is attached to a question. Option B moves the complexity into file and line selection and into a text interface. Option C moves it into hosting, authentication, and file upload.

**Maintainability.** VS Code's extension API is stable and versioned, and the extension declares the minimum VS Code version it supports. The Webview UI Toolkit's deprecation [6] removes the official component library, so the prototype uses Vue, a general web framework that does not depend on VS Code and that the team could reuse if it later built Option C. Because the backend is a plain HTTP API, the frontend can be replaced without backend changes, which limits the risk of this decision.

**Security.** VS Code's documentation states that the extension host, where our extension runs, has the same permissions as VS Code itself [8]. Users must therefore trust our extension as they would trust the editor, and the extension should do no more than it needs to. The prototype restricts the webview with a Content Security Policy, as VS Code recommends [4], so the webview only runs our own bundled script and only loads files from the extension's own folder. The extension sends code only to the backend address the user configures, which defaults to the local machine, consistent with the requirement that enterprise code stay on the company's systems (NFR-5).

**Cost.** VS Code is free, the core editor source code is MIT-licensed [9], and an extension can be distributed as a `.vsix` file without any hosting [5]. Options A, B, and D have no hosting cost. Option C requires a server.

**Uncertainties.** We have not yet measured how long the extension takes to activate or what the editor adds to first-token latency, and we have not tested the interface with users. The verification plan below addresses each of these.

## Recommendation and Verification Plan

We recommend **Option A, the VS Code extension**. It is the only option that gives the assistant direct access to the user's code without extra steps, which matters most for COBOL, where meaning is spread across files. It matches the tools IBM already distributes, which makes handoff realistic. It avoids the self-efficacy barrier of a terminal interface. A working prototype already exists, so the remaining risk is measurable. Option C remains the fallback if user testing shows the editor integration is not worth its constraints, and the frontend-independent backend keeps that fallback inexpensive.

The decision succeeds if the following checks pass. Each check names the failure it would detect and when it runs. The thresholds marked "team target" are our proposals and will be confirmed with our IBM advisor.

| # | Check | Pass condition (minimum goal) | Detects | When |
| --- | --- | --- | --- | --- |
| V1 | Automated checks: type-checking, unit tests (`vitest`), and a production build | All pass on every pull request | Regressions in streaming, cancellation, or code attachment | Every pull request (already in CI) |
| V2 | Editor integration tests run inside VS Code with `@vscode/test-electron` [10] | With a `.cbl` file and a selection, "Explain Selected Code" is available and sends the selection; with no selection, it is hidden (FR-1) | Commands that break inside the real editor but pass unit tests | Added before the walking skeleton demo, then every pull request |
| V3 | First-token latency, measured from the extension | Median of 20 requests on a 50-line selection is 5 seconds or less on the 30B model (NFR-1) | An extension or relay design that makes answers feel slow | At the walking skeleton demo, then at the end of each sprint |
| V4 | Cancellation | Closing the panel or pressing Stop ends the backend's generation within 2 seconds, as shown in the backend log (team target) | Wasted cluster compute and answers that keep generating after the user has left | At the walking skeleton demo |
| V5 | Fresh install | A teammate who did not write the extension installs it from a `.vsix` file on a fresh clone and receives an answer within 30 minutes (NFR-6) | Setup steps that only work on the author's machine | Once per sprint, rotating the tester |
| V6 | GenderMag cognitive walkthrough of the "explain code" and "set profile" flows [7] | No step at which the walkthrough finds that a persona would likely give up or fail | Interface barriers for users with lower self-efficacy or a process-oriented learning style | Before the comprehension study is designed |
| V7 | Partner review | Our IBM advisor confirms that a VS Code extension is an acceptable format for handoff | A format that IBM cannot adopt | At the next partner meeting |

If V3, V6, or V7 fails and the cause cannot be fixed within one sprint, the team will reopen this RFC and evaluate Option C.

## Constraints

**Licensing.** The VS Code editor source code is MIT-licensed [9], and our extension and its libraries use permissive open-source licenses. Distributing the extension as a `.vsix` file [5] avoids depending on any marketplace's terms.

**Data use.** The extension reads code only when the user asks a question and sends it only to the configured backend, which runs on the user's machine or on the OSU cluster (NFR-5). The extension does not collect usage data.

**Intellectual property.** The extension's code is the team's work. Ownership after handoff follows the project agreement with IBM, which this decision does not change.

**Partner confidentiality.** We develop and test only with public sample COBOL programs, as the brief requires (C-1). No IBM confidential code or documents appear in the extension, its tests, or its examples.

**Project scope.** The extension explains code and does not provide syntax highlighting, parsing, or other language features. Users install an existing COBOL extension for those, which keeps our scope small. Modifying or migrating COBOL code is also out of scope.

**Time.** The proof of concept must be finished within the capstone's academic year (C-6). Building on a working prototype, rather than starting a new frontend, protects the time that remains for adaptation and evaluation, which are the project's research goals. Team members who have not used TypeScript or Vue will need time to learn them, which we will reduce by pairing them with teammates who have.

**Cost.** The team has no budget for hosting. VS Code, the extension, and its distribution are free, and the backend runs locally or on university hardware, so this option adds no cost.

## Delegation and Validation

- **Handed to AI (Claude):** guiding my initial research. For this revision, Claude drafted the revised text from the peer and instructor feedback, checked the cited sources against their web pages, and described the existing prototype from the repository's code.
- **Checks that exist in our repo:** pull requests require review before merging, per CONTRIBUTING.md. GitHub Actions runs type-checking, unit tests, and a production build of the extension on every pull request (V1).
- **Where I validated myself:** *[Taylor: describe what you personally checked, for example that you reread each cited source and confirmed that the prototype behaves as described, and why you chose those points.]*

## Decision

Proposed. The team's requirements already assume a VS Code extension (constraint C-5), and a prototype exists. The decision will be recorded here, with the date and who chaired it, after the team reviews this revision and the IBM advisor confirms the format (V7).

## References

1. Anderson, Piorkowski, Weisz, Burnett, and Varshney, "Can LLM Code Explanations Adapt to Diverse Problem-Solvers' Needs?" (2026).
2. Stack Overflow, "2024 Developer Survey: Technology," Integrated development environment. https://survey.stackoverflow.co/2024/technology
3. IBM, "IBM Z Open Editor," Visual Studio Marketplace. https://marketplace.visualstudio.com/items?itemName=IBM.zopeneditor
4. Microsoft, "Webview API," Visual Studio Code Extension API. https://code.visualstudio.com/api/extension-guides/webview
5. Microsoft, "Extension Marketplace: Install from a VSIX," Visual Studio Code documentation. https://code.visualstudio.com/docs/configure/extensions/extension-marketplace
6. Microsoft, "vscode-webview-ui-toolkit" repository (deprecated January 1, 2025; archived January 6, 2025). https://github.com/microsoft/vscode-webview-ui-toolkit
7. M. Burnett, S. Stumpf, J. Macbeth, S. Makri, L. Beckwith, I. Kwan, A. Peters, and W. Jernigan, "GenderMag: A Method for Evaluating Software's Gender Inclusiveness," *Interacting with Computers*, vol. 28, no. 6, pp. 760–787, 2016. https://doi.org/10.1093/iwc/iwv046
8. Microsoft, "Extension runtime security," Visual Studio Code documentation. https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security
9. Microsoft, "vscode/LICENSE.txt" (MIT License). https://github.com/microsoft/vscode/blob/main/LICENSE.txt
10. Microsoft, "Testing Extensions," Visual Studio Code Extension API. https://code.visualstudio.com/api/working-with-extensions/testing-extension
