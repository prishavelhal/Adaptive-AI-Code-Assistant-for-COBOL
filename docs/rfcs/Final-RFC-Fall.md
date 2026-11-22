
# RFC-1: Adaptive AI Code Assistant Tool as a VS Code Extension

**Status:** Accepted  
**Author:** Prisha Velhal  
**Date:** 10/24/2026  
**Decision Owners:** Adaptive AI Code Assistant Capstone Team  
**Decision Date:** 10/25/2026  

---

## 1. Problem and Context

Our project is an adaptive AI assistant designed to help developers understand legacy COBOL code. The main UI decision is whether to build the tool as a VS Code extension or a standalone browser application. Our goal is to let developers request explanations directly within their code editor without switching applications.

Unlike a conventional LLM chat interface, our planned UI includes a learning-style assessment based on five GenderMag cognitive dimensions, adjustable cognitive preferences, and different explanation formats. While prompts or SKILL.md instructions could produce similar explanations, our interface would integrate these capabilities into the developer's workflow, allowing users to select code, configure preferences, and receive adaptive explanations without manually transferring code or repeatedly specifying instructions.

The timing of this decision matters because the team has established its technology stack and developed an initial walking skeleton, a minimal end-to-end implementation connecting the application's major components. Since the original RFC, we have created a working local VS Code extension prototype that explains COBOL code, providing initial evidence that the architecture is feasible. Our stack includes the VS Code Extension API, TypeScript, Vue.js, esbuild, and an SSE client. However, the complete adaptive interface is not yet functional, and we still need to integrate cognitive preference controls and improve model performance.

Reversing this decision would become increasingly expensive as we develop VS Code-specific functionality. Switching to a browser application would require rebuilding editor interactions, modifying code-context handling, and rewriting integration tests. Our separate backend would remain largely reusable, but the frontend would require significant rework. Confirming this architecture now allows us to identify integration problems before investing further development time.

## 2. Options

### Option 1: VS Code Extension with a Vue Webview

This creates a flexible chat that can live in the sidebar of VS Code and use the planned TypeScript/Vue frontend. Costs of this would be separate extension and webview contexts, message passing, packaging, integration tests, and added security work.

### Option 2: Standalone Browser Application

Easy to use for a demo with no need for extension packaging. Costs are that users would have to move between apps and a later extension would still need editor integrations and its own tests.

### Option 3: Hybrid

This gives users an editor entry point while keeping a browser UI. Costs of this would be that the user would still have to context switch across applications and code selection is harder to pass safely. The team would also have to account for maintenance of an extension and web app integration.

### Option 4: Do Nothing

Continue building backend and retrieval work, but this would force a late redesign and leave the user workflow untested.

### Option 5: Native VS Code Views and Commands

This option would use VS Code's built-in UI components, such as commands, menus, and tree views, rather than a custom Vue webview. This could reduce the amount of custom frontend code and make the application more consistent with VS Code's native interface. However, our planned application includes interactive cognitive preference controls, streamed explanations, and different explanation formats that would be more difficult to implement using only native views. This option would make sense if we simplified the scope of our UI to basic code explanation commands rather than a fully interactive adaptive chat interface.

## 3. Technical Tradeoff Analysis

The extension option best matched our intended workflow which is for users to ask about code where they are editing it directly in their code environment. VS Code supports custom views in a sidebar or panel, and a webview [1] communicates with the extension through message passing. This would support a customizable chat interface while introducing additional design and testing requirements. The extension host would also broker editor context and messages rather than giving the Vue view direct editor access.

A webview can render chat history, adaptive controls, and streamed text with the planned frontend. Some costs included in this would be that webviews are typically very resource-heavy, isolated, and only really make sense when native APIs are insufficient. We would need to use them sparingly, support themes and accessibility, and keep the editor focused. VS Code's security [2] also makes this part of the design important by restricting webview permissions and resources, validating messages and limiting what workspace content can be digested by the AI.

A webpage would be easier for reviewers to access but would weaken the workflow we are trying to provide developers. We want a streamlined process where developers would not have to switch between multiple applications. While we could also go for a hybrid option that would allow for the streamlined workflow that we desire, it would require us to design and maintain two integrated interfaces. VS Code also offers native views and commands that could be used to reduce custom webview code, but the current frontend uses Vue and a chat view and would need deeper rendering. We have no measurements or user studies for what UI would be most effective, other than what is already in the published paper of our advisor, Andrew Anderson [3]. His paper tested adaptive AI models through local models that used a more conventional chat interface. However, outside of this we don't have any benchmark to go off of. Therefore, this recommendation reflects our own views for product fit and platform capabilities.

Since the initial RFC draft, our team has made progress that provides more concrete evidence for this architectural decision. We created a Figma specification for the VS Code extension, including the main COBOL explanation workflow, loading and streaming states, error handling, and learning profile settings. Sarah and I also designed the adaptive learning layer around five GenderMag cognitive dimensions and documented how those preferences would influence the explanations generated by the model. These designs were reviewed collaboratively and incorporated into the project's DESIGN.md documentation.

Additionally, the team developed an initial working prototype of the VS Code extension in the coboltutor directory [4]. The prototype demonstrates a basic local code explanation workflow using our agreed technology stack. We also have a Figma UI wireframe we have been working on to show the user's end-to-end workflow [5]. This is important because it shows that the extension architecture is not only a theoretical design but can support an initial end-to-end implementation. All of these changes have been pushed into our GitHub repository and pass the required CI checks that we have in place [6].

However, the prototype also revealed limitations that will need to be addressed. Our team observed that locally running the model resulted in slow responses and inconsistent explanation quality. These issues are primarily related to model inference rather than the VS Code extension itself. The AI team is working toward deploying a larger model on the university's HPC cluster and optimizing the inference pipeline.

This distinction matters when evaluating the frontend architecture. A standalone browser application would not necessarily improve model response time because both interfaces would depend on the same backend. Instead, the extension should be evaluated on how effectively it handles code selection, communicates with the backend, and displays streamed responses. While we now have initial working software, we still lack controlled performance comparisons and user studies demonstrating whether the extension is more effective than a browser interface.

## 4. Recommendation and Verification Plan

### Decision

We propose a VS Code extension with a sidebar/panel view. The extension host owns commands and editor access while the webview owns the presentation and sends typed messages to the host. The host calls the backend to relay response events. This tool will not be made through a parallel website for the walking skeleton. We will keep the backend independent of VS Code to allow for flexibility in case another UI were to be added so that it would not require too much remediation of retrieval or model orchestration.

### Consequences

This supports the code understanding workflow and the current plan we have for the frontend. It would commit the team to an extension and would limit the first demo to VS Code users. We would also have to factor the responsibility for workspace-data security. We can't assume any performance advantage at this time, but as we are deeper in development we can verify this. Reversal is possible if early enough, but editor features and UI backend could make a later switch laborious and costly.

### Verification Plan

Now that we have a working local extension prototype, we can begin evaluating whether the chosen architecture meets our functional requirements. The current prototype demonstrates that a basic COBOL explanation workflow is possible, but it does not yet validate the full adaptive interface. We propose the following acceptance criteria to evaluate the architecture as development progresses.

| Test | Acceptance Criteria |
|---|---|
| Extension activation | The extension launches successfully in VS Code and displays the intended sidebar interface without errors. |
| Code selection | A user can select COBOL code in the editor and send the correct selection to the backend. |
| Backend communication | The extension successfully sends a request and displays the corresponding model response. |
| Streaming | The interface progressively displays incoming response text without missing or duplicating content. |
| Cognitive preferences | Users can configure all five cognitive dimensions, and the correct values are included in the backend request. |
| Adaptive explanations | Changes to cognitive preferences produce the intended changes in the explanation configuration and output format. |
| Error handling | The interface displays a meaningful error when the backend is unavailable or a request fails. |
| Security | No workspace code is sent to the backend without an explicit user action. |
| UI responsiveness | The interface displays a loading indicator within 500 milliseconds of submitting a request under controlled local test conditions. |

We will test these requirements using a consistent set of publicly available COBOL examples and record whether each test passes or fails. For performance, we will distinguish between the time required for the interface to acknowledge a request, the time until the first response content appears, and the total time required for the model to generate an explanation. This is important because our current performance limitations are primarily related to model inference, and we do not want to attribute backend delays to the frontend architecture.

### Reconsideration Criteria

We will revisit this architectural decision after the adaptive learning controls have been integrated into the working extension. If the extension cannot reliably capture code context, preserve cognitive preferences, communicate with the backend, or render streamed responses, we will determine whether these issues can be resolved within the existing architecture. If VS Code-specific limitations prevent us from implementing essential features or require disproportionate development effort, we will reconsider the native VS Code UI or standalone browser alternatives. This review will occur before we invest significant additional effort in polishing the complete frontend.

## 5. Constraints

The project plan is to use external publicly available COBOL documentation. We will not be using any proprietary IBM software, applications, or data.

We will send code only after explicit user action and confirm our data flow and model endpoint with our IBM advisors. We will also check licenses for any dependencies, sample COBOL inputs, and assets. The project does not establish a project license, so the RFC assumes none. Documented VS Code APIs will be used with a team-authored UI unless a suitable template is found, in which case we will thoroughly check licensing privileges.

Because our application runs inside VS Code, we also need to consider how workspace code is accessed and transmitted. The extension host will be responsible for accessing selected code, while the webview will manage the user interface. We should avoid giving the webview unrestricted access to workspace files and validate messages exchanged between the two components. We also need to ensure that any code submitted to the model is sent only to an approved backend endpoint. These constraints directly influence our architectural choice because they require us to maintain a clear separation between editor access, UI presentation, and backend processing.

## 6. Delegation and Validation

I used an AI assistant to organize and draft some sections of this RFC, to compare various options, and to locate VS Code documentation. I have not treated the CI run as proof of extension functionality or results of performance. I reviewed the recommendation against the Figma designs and learning-layer documentation developed with Sarah. The team has since proceeded with the extension architecture, although the full adaptive interface still requires validation. We will also confirm with our IBM mentors that the code-context flow respects the project's confidentiality boundaries. Since the initial RFC draft, the team has implemented a local VS Code extension prototype and updated our CI workflow to support the new backend and extension structure.

This provides initial evidence that the architecture can support an end-to-end explanation workflow, although it does not validate all planned adaptive functionality. For my part of the project, I worked with Sarah to design and review the Figma interface and learning-layer controls before incorporating them into our design documentation. I used these artifacts to check whether the recommended architecture could accommodate the interactions we had planned. The next important validation points will be verifying that selected COBOL code is transferred correctly, that cognitive preference values are preserved in backend requests, and that streamed explanations are rendered reliably. These checks matter because failures in code-context handling or preference configuration would directly undermine the purpose of our adaptive assistant.

## 7. Decision

**Status: Accepted**

The team has chosen to proceed with a VS Code extension using a Vue-based webview as the primary interface for the Adaptive AI COBOL Assistant. This direction is supported by the existing UI designs, the team's selected technology stack, and the development of an initial working local prototype.

The backend will remain independent of the extension to preserve flexibility for future model and infrastructure changes. The team will continue validating the architecture as the adaptive learning controls and full explanation workflow are implemented. The decision may be reconsidered if integration testing reveals significant limitations that prevent the extension from meeting its core requirements.

## 8. References

[1] [VS Code Webview API](https://code.visualstudio.com/api/extension-guides/webview)

[2] [VS Code Extension Runtime Security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security)

[3] [AAAI AIES Research Paper](https://ojs.aaai.org/index.php/AIES/article/view/43133)

[4] [COBOL Tutor Extension Prototype](https://github.com/prishavelhal/Adaptive-AI-Code-Assistant-for-COBOL/tree/main/coboltutor)

[5] [Adaptive AI VS Code Extension Figma Wireframe](https://www.figma.com/design/OznfpeNIOKC6WR8yrVS21j/Adaptive-AI-VS-Code-Extension?node-id=0-1)

[6] [GitHub Actions CI](https://github.com/prishavelhal/Adaptive-AI-Code-Assistant-for-COBOL/actions)
