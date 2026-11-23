**Core implementation rule:** Opening the assistant may show local selection status, but code is sent to the backend only after the developer explicitly submits a question.

## **1\. Stack and responsibility split**

Keep the VS Code-specific layer small and the backend independent of VS Code. This lets the team build and demonstrate the interface with mocked responses before retrieval and generation are ready.

| Layer | Technology | Responsibilities |
| ----- | ----- | ----- |
| Extension host | VS Code Extension API \+ TypeScript | Register the assistant view and commands; read the active editor and selection locally; validate explicit submissions; call the backend; relay typed events to the webview; store local preferences. |
| Webview UI | Vue.js \+ TypeScript | Render sidebar screens; manage question entry, quiz, profile controls, conversation, citations, loading, streaming, and error states; send typed messages to the extension host. |
| Build | esbuild | Bundle the extension host and Vue webview separately; emit static assets with stable paths; run in watch mode for local extension development. |
| Backend | HTTP API \+ SSE response stream | Retrieve public COBOL material, apply the cognitive adaptation layer and prompt templates, call the LLM, and stream answer text, source references, completion, and errors. |

## **2\. Map the UI to Vue components**

Build the visible experience as reusable components inside the webview. Keep screen-specific components presentational where possible; a small set of composables should own view state and message handling.

| UI area | Suggested Vue component | Implementation notes |
| ----- | ----- | ----- |
| Assistant landing state | `AssistantPanel.vue, EmptyState.vue, CodeContextCard.vue` | Show “Understand your COBOL,” the grounded-answer explanation, a preference summary card, code context, question field, disabled Ask state without a selection, and the send-on-Ask privacy note. |
| Answer state | `ConversationView.vue, ExplanationMessage.vue, SourceList.vue` | Show selected preference chips,  question, illustrative code preview, “In short,” step-by-step explanation, optional example, sources/demo-source status, adaptation note, code context, and follow-up composer. |
| Preference settings | `ProfileSettings.vue, DimensionControl.vue` | Render the five labeled sliders and endpoint labels shown in the wireframe, plus Save, Reset, explanatory copy, and a Retake quiz action. |
| Quiz entry and question | `QuizIntro.vue, ProfileQuiz.vue, QuizProgress.vue, QuizQuestion.vue` | The intro offers Take quiz and Skip. The question state shows progress, one statement, five Likert choices, Back, Next, and Exit quiz. |
| Saved-preferences state | `PreferencesSaved.vue` | Confirm that preferences are saved and explanations will use them; allow the user to continue or adjust the sliders. |
| Adaptive-output examples | `ExplanationVariantGallery.vue, ExplanationMessage.vue` | Build ten example variants—two ends across five dimensions from one shared illustrative snippet, for design review and evaluation. |
| Request feedback states | `RequestStatus.vue, ErrorNotice.vue` | Represent retrieving, streaming, complete, canceled, and retryable error states without changing the overall sidebar layout. |

## **Wire Frame Screens**

| Wireframe state | What the developer sees | Build behavior |
| ----- | ----- | ----- |
| Assistant landing | Dark VS Code-style panel; “Understand your COBOL”; short explanation of grounded answers; “Presentation, not a fixed profile” card; Code context says no code selected; question field; Ask; privacy note. | Keep Ask disabled until supported code is selected. Selection status and file/line preview remain local. If there is no supported selection, explain the next step. |
| Answer example | Detail: Concise and Guidance: Step by step chips; question; sample.cbl lines 120–125; “In short”; numbered steps with clickable line ranges; optional numeric example; Sources; adaptation note; code context and follow-up. | Render answer sections as structured content, not one opaque string. Keep line references clickable when they map to the active editor. Label sample content as illustrative. Show whether sources were retrieved or the answer uses demo references only. |
| Preference settings | Intro says neither end is better and preferences affect presentation, not facts/sources; five sliders; Save and Reset; “change any time” note; Retake quiz card. | Use the same five numeric values in settings, quiz results, and backend requests. Save persists locally. Reset restores the agreed defaults; Retake starts a new quiz. |
| Quiz introduction | “Want to personalize your explanations?” with a short description, Take quiz and Skip. | Take quiz opens the first question. Skip returns to the assistant without blocking use; show a sensible default profile until the user sets preferences. |
| Quiz question | One statement at a time; progress such as “Question 3 of 23”; sample statement “I avoid using new apps or technology before they are well-tested”; five choices from Strongly agree to Strongly disagree; Back, Next, and Exit quiz. | Store question definitions and scoring in data/config, not in the view component. Keep navigation state separate from answer values. Don’t hardcode the sample question as the only quiz item. |
| Saved preferences | Confirmation that preferences are saved and explanations will be adjusted; compact slider controls remain available. | Display after quiz completion/save. Let the developer edit preferences immediately; don’t treat the saved profile as permanent. |
| Dimension comparison board | Ten sidebar-sized answer cards: process/tinkering, more guidance/independent, cautious/exploratory, task/technology, comprehensive/selective. | Use the same question and illustrative account-balance snippet for every variant. Change explanation structure and guidance while keeping factual claims constant. |

## **Suggested source layout**

src/  
  extension.ts                    \# activate, commands, view registration  
  views/AssistantViewProvider.ts  \# create webview, initialize, relay messages  
  services/BackendClient.ts       \# POST requests and SSE parsing in host  
  services/ProfileStore.ts        \# local preference persistence  
  shared/messages.ts              \# host \<-\> webview message types  
  webview/  
    main.ts                       \# Vue bootstrap  
    App.vue                       \# route/state shell  
    components/                   \# panel, composer, answer, profile, quiz  
    composables/useAssistant.ts   \# request and stream state  
    composables/useProfile.ts     \# profile and quiz state  
    styles/theme.css              \# VS Code theme-aware variables  
esbuild.config.mjs                \# host and webview build entries

## **3\. VS Code-specific constraints**

The Vue components run in a sandboxed webview, not a normal browser tab. Treat the extension host as the only trusted layer, and design every screen around that split.

| Concern | Webview or host rule | Implementation notes |
| ----- | ----- | ----- |
| Access and isolation | The webview cannot read the editor, files, or network. Only the extension host can. | The host reads the active editor and selection, and sends the webview status only (“12 lines selected,” file name). Code text leaves the host only on explicit Ask. |
| Messaging | Webview and host communicate only through typed postMessage messages. | Share one Message type across both bundles. Include a requestId so replies, cancel, and retry can be matched. The host validates every incoming message. Composables own messaging, so components never call acquireVsCodeApi(). |
| Backend calls | The webview never calls the backend directly. | The host calls the HTTP API, then relays SSE events (streamChunk, streamDone, error) to the webview as typed messages. This avoids CORS and CSP problems and keeps the privacy rule intact. |
| Layout | The sidebar is narrow (about 300-400px) and user-resizable. | Use single-column layouts with wrapping text. Code previews scroll inside their own container. Test at the narrowest width, not just the 384px frames. |
| Theme | The webview inherits VS Code theme colors and fonts. | Map design tokens to \--vscode-\* variables (foreground, background, button, font family) so the UI works in light, dark, and high-contrast themes. |
| Security and loading | Webviews enforce a strict Content Security Policy and local resource roots. | Set a CSP with a nonce, and use no inline handlers. Load esbuild assets through asWebviewUri(). Escape or sanitize LLM output and code snippets before rendering. |
| State and lifecycle | Webviews are destroyed when hidden unless retainContextWhenHidden is on, which is memory-heavy. | Keep preferences and quiz progress in the host (globalState), and send them on load. Use getState()/setState() for the draft question. Re-send selection status and in-progress request state when the view reappears. |
| Editor edge cases | Selection and file changes come from editor events. | Define empty or error states for no editor, a non-COBOL file, and a very large selection. |
| Testing | CSP, theming, and resource loading only behave realistically inside VS Code. | Build with a mocked host harness that replays streamChunk events, then verify in the Extension Development Host. |

