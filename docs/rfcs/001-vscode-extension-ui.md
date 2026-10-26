<!-- docs/rfcs/YYYY-MM-DD-short-title.md (or docs/adr/, whichever your repo uses) -->

# RFC: Adaptive AI Code Assistant Tool as a VS Code extension

<!--Proposed-->

| Field | Value |
| --- | --- |
| Author | Prisha Velhal|
| Date | 2026-10-25|
| Status | Proposed / Accepted|
| Decision Date | 10/25/2026 |
| Deciders | Capstone Team |
| Superseded By | (link, if applicable) |

## Problem and Context

Our project is an adaptive AI assistant to help developers understand legacy COBOL code. The user interface decision is whether we should create this tool to live inside the code editor as a visual studio code (Vs code) extension or in a separate browser application. We want users to be able to comprehend and interact with the AI tool in a way that is convenient for them and without having to leave the code editor. The team has expressed a preference for an extension, and Sarah and I have both decided to move forward with designing for an extension tool. This RFC asks the team to confirm that direction before it becomes expensive to change.
The timing of this decision matters because during this sprint we established the stack and data architecture and planned the walking skeleton accordingly, however no application software works end to end yet. This gives us flexibility for the time being to make our decisions. The CI checks in github currently show that the configured job succeeds, however it does not prove that the extension launches, or demonstrates any other functionality otherwise. The tools and frameworks we will be using in this project include the VS Code Extension API, TypeScript, Vue.js, esbuild, and an SSE client. Therefore, it is essential that we are certain about this direction for the UI to avoid an expensive switch later.
If we put off this decision, we could build the backend without testing the intended frontend workflow or later find that the editor integration does not work or fit as intended. The decision in this RFC is the first deployment decision, whether to build an in-editor VS Code extension or a separate browser application.

## Options

At least three options, **including "do nothing"**. Give each option a short name, an account of its real costs, and the condition under which it would be the right choice. An option with no such condition is a strawman, and a strawman weakens the whole document.

### Option A: VS Code extension with a  Vue webview

This creates a flexible chat that can live in the sidebar of VS Code and use the planned TypeScript/Vue frontend. Costs of this would be separate extension and webview contexts, message passing, packaging, integration tests, and added security work.

### Option B: Standalone browser application:

Easy to use for a demo with no need for extension packaging. Costs are that users would have to move between apps and a later extension would still need editor integrations and its own tests.
### Option C: Hybrid
This gives users an editor entry point while keeping a browser UI. Costs of this would be that the user would still have to context switch across applications and code selection is harder to pass safely. The team would also have to account for maintenance of an extension and web app integration.


### Option D: Do Nothing

Continue building backend and retrieval work, but this would force a late redesign and leave the user workflow untested.

## Analysis

The extension option best matched our intended workflow which is for users to ask about code where they are editing it directly in their code environment. VS code supports custom views in a sidebar or panel, and a webview [1] communicates with the extension through message passing. This would allow for a chat view but also created a method to design and test. The extension host would also broker editor context and messages rather than giving the Vue view direct editor access.
A webview can render chat history, adaptive controls, and streamed text with the planned frontend. Some costs included in this would be that webviews are typically very resource-heavy, isolated, and only really make sense when native APIs are insufficient. We would need to use them sparingly, support themes and accessibility, and keep the editor focused. VS code’s security [2] also makes this part of the design important by restricting webview permissions and resources, validating messages and limiting what workspace content can be digested by the AI.
A webpage would be easier for reviewers to access but would weaken the workflow we are trying to provide developers. We want a streamlined process where developers would not have to switch between multiple applications. While we could also go for a hybrid option that would allow for the streamlined workflow that we desire, it would require us designing two UI integrated faces. VS Code also offers native views and commands that could be used to reduce custom webview code, but the current frontend uses Vue and a chat view and would need deeper rendering. We have no measurements or user studies for what UI would be most effective, other than what is already in the published paper of our advisor, Andrew Anderson [3]. His paper tested adaptive AI models through local models that used a more conventional chat interface. However, outside of this we don’t have any benchmark to go off of. Therefore, this recommendation reflects our own views for product fit and platform capabilities.


## Recommendation and Verification Plan

Decision:
We propose a VS Code extension with a sidebar/panel view. The extension host owns commands and editor access while the webview owns the presentation and sends typed messages to the host. The host calls the backend to relay response events. These are out planned checks and are subject to change throughout development. This tool will not be made through a parallel website for the walking skeleton. We will keep the backend independent of VS Code to allow for flexibility in case another UI were to be added so that it would not require too much remediation of retrieval or model orchestration.


Consequences:
This supports the code understanding workflow and the current plan we have for the frontend. It would commit the team to an extension and would limit the first demo to VS Code users. We would also have to factor the responsibility for workspace-data security. We can’t assume any performance advantage at this time, but as we are deeper in development we can verify this. Reversal is possible if early enough, but editor features and UI backend could make a later switch laborious and costly.

## Constraints

The project plan is to use external publicly available COBOL documentation. We will not be using any proprietary IBM software, applications, or data.
We will send code only after explicit user action and confirm our data flow and model endpoint with our IBM advisors. We will also check licenses for any dependencies, sample COBOL inputs, and assets. The project does not establish a project license, so the RFC assumes none. Documented VS Code APIs will be used with a team-authored UI unless a suitable template is found, in which case we will thoroughly check licensing privileges.

## Delegation and Validation

I used an AI assistant to organize some sections of this RFC, to compare various options, and to locate VS Code documentation. I have not treated the CI run as proof of extension functionality or results of performance. Before acceptance, I will compare this recommendation with Sarah’s current UI notes and confirm that the team unanimously agrees with this decision as well as confirm with our IBM mentors that the code-context flow respects the partner boundary. We don’t have any integration tests yet as the extension has not been built yet, however we will also require code review and extension tests before accepting the walking skeleton. 

## Decision

Proposed, until your team decides. Then accepted, rejected, or superseded, with the date and who chaired the decision. If superseded, link the RFC that replaces this one.

