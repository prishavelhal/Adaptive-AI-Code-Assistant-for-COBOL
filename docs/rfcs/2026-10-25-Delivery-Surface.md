# RFC: Delivery Surface for the Adaptive COBOL Assistant (VS Code Extension vs. Web App)

| Field | Value |
| --- | --- |
| Author | Sarah Pilon |
| Date | 2026-10-24 |
| Status | Proposed |
| Decision Date | (fill when decided) |
| Deciders | Aditi Thakur, Jack Davison, Michael Taylor, Prisha Velhal, Quinn Mcnamee, Sarah Pilon |
| Superseded By | (link, if applicable) |


## Problem and Context
Our team is building an adaptive AI assistant that explains COBOL code to match different developers' problem-solving/coding styles.


The decision is on what delivery surface we will use, to present and receive code to/from the user. Our options are a VSCode extension with a chat panel, or command line based extension, standalone web app, a hybrid of the two or keeping it as no frontend project. The frontend report is leaning towards a VSCode chat panel beside the COBOL file. Despite that, no frontend code exists and the implementation won't fully begin until at least the end of fall or the beginning of winter. This means that as of right now, changing direction only costs planning time.
Once we begin coding the project, the choice becomes hard to undo, as we would have to reevaluate how we connect to the backend, how we capture data, and which API and constraints we are following. None of us have built a VSCode extension before so making the wrong choice is even more impactful.
If we defer the decision, the backend team continues without a UI, and the surface might get decided late and be less polished. This leaves less time to build a usable UI and weakens the demo and our ability to run a realistic user evaluation.


## Options
### Option A: VSCode Extension GUI
Description: VSCode extension opens a chat panel on the side of the selected file the user is reading, similar to the Copilot chat built into VSCode. The panel is built with Vue and TypeScript. Users adjust their style profile with the five sliders.


Benefits: Users can intuitively understand how to navigate the UI, and the assistant doesn't need to copy and paste the code, as it works with the file structure. There are also a multitude of inspirations of the interface that can be found. Also, IBM supports COBOL development in VS Code through its own extension. This also fits the proof of concept the most of working with the developer and their environment.


Costs: Requires learning VS Code extension and webview APIs, which no one in our frontend team, nonetheless any team on our project, has done before. We also must adhere to the restraints VSCode webview offers and changes as they update (which could be during our project timeline). If a new restraint releases that impacts our project, we would have to accommodate that.


Right choice when: The file context matters more than easy access, and the team understands and is willing to adapt to the extension learning curve.


### Option B: VSCode Extension CLI


Description: This extension requires working in the terminal and typing commands to read a certain COBOL file and both prompting and receiving responses from the command line.


Benefits: This approach would require much less frontend work, and still allows the editor content and file access.


Costs: Similar to the GUI of VSCode extension, must adhere to the restraints VSCode offers and changes as they update and understand if a new restraint releases that impacts our project, we would have to accommodate that. We also still have no team experience on VSCode extensions. Moving on, the user might be confused on how to interact with the app, and would be far less intuitive.
It would also be hard to plan the quizzing feature, and a weaker demo.


Right choice when: Frontend time is too short, or demo needs to be stable while showing backend works.


### Option C: Standalone web app
Description: A browser app where the user copy and pastes, or uploads, the COBOL code file and chats with the assistant similar to AI chats on websites. It would use the same Vue frontend, just hosted separately.


Benefits: Requires no installation so evaluation participants just need a link to the chat. It is also not tied to any IDE and not restricted by any of their constraints.


Costs: No direct file access meaning it could be missing some context files, and the user could copy and paste incorrectly leading to missing information. This also would require hosting and would require more care with data handling. This is also different than how COBOL developers normal working environment.


Right choice when: We need participants to easily be able to access the web, or if our team cannot fully implement the code as an extension.


### Option D: Hybrid (work as web app while it can also be an extension)
Description: Build the Vue chat UI as a webapp, while following the guidelines to release it as an extension.


Benefits: Keeps both options open and allows for a pivot as the UI would also be reused rather than needing a full redesign.  


Costs: Would gain the costs of the previous options as well, such as requiring us to follow and adhere to VSCode restrictions, and data security. However, we would have to carry both of those risks. Also brings in new risks of possibility not completing the project within the projected timeline and not excelling in the frontend and leaving both as partially complete.


Right choice when: The team is on the fence on which application to stick to, or wants to reach a wider audience.


### Option E: Do Nothing  (Defer the decision)
Description: No Frontend service, use only API Docs built from the backend and AI team.


Benefits: Due to not having a stable backend and agreed upon coding structure, avoiding doing the frontend service means any unstable elements or scrapped evaluation choices don't involve wasted frontend work.


Costs: Nobody can open a real COBOL file with context, and we can’t run realistic user evaluation making the demo weak. This would mean the cost lands when running a demo, and a time constraint is put on making a UI so the user understands what is going on.


Right choice when: The backend design is too unstable to build a UI for, good for early stages of the project.


## Analysis

**Complexity** matters most here, because nobody on the team has built a VS
Code extension. A webview works like an iframe the extension controls, so our
Vue chat panel, sliders, and quiz can live inside it, and the two sides
exchange data through message passing (VS Code docs). Option A is the most
complex, B removes the UI work but not the extension APIs, D adds keeping the
UI independent of VS Code, C is simplest, and E has none.

**Fit** is the main argument for A. The VS Code docs advise using webviews
sparingly, only when native APIs fall short. Sliders, streamed output, and a
quiz go beyond that, and webviews can sit in the sidebar, matching our
side-by-side layout.

**Maintainability** is a moderate concern. The VS Code docs say the Extension
API updates weekly, so A, B, and D carry that risk and C and E do not. We have
not verified how breaking changes are handled, so the risk's size is
uncertain.

**Performance** is less important and unmeasured. All options use the same
FastAPI + SSE backend, so we make no performance claim; the walking skeleton
will test it.

**Security and data use** differ little. Every option sends code to our
backend on the cluster, but C needs a paste warning because users choose what
to send.

**Cost** is zero in money for all options. The real cost is student time:
learning the extension APIs for A, B, and D, and hosting for C and D.

**Overall,** C wins on complexity and cost, and A wins on fit with VS Code being an established environment for COBOL as IBM supports COBOL development in VSCode through its own extension [1]. We recommend A because fit matters more for a proof of concept, and we accept the complexity
risk, which the walking skeleton is designed to test.

[1] https://www.ibm.com/docs/en/developer-for-zos/17.0.x?topic=editing-experimental-formatting-cobol-source-code

## Recommendation and Verification Plan

I propose option A with a VSCode Extension GUI. I believe it offers the best medium for programmers and our proof-of-concept goal. The main risk behind this option is a lack of experience, so this plan accommodates this issue by having fall back points throughout the plan. 

**Figma Design - Due by end of Fall:** a design chart of the chat panel and learning style quiz format. *Pass: The team agrees that the code seems feasible to make via VS Code extensions.*

**Walking Skeleton - Due by Winter Week 5:** A minimal extension that opens up a chat panel based off of the selected COBOL file, and is able to send the file data to a backend endpoint and receive a response. This does NOT have to run on a working backend, it could be a stub backend endpoint depending on the progress made on the backend at that point. *FAIL: If the team can't get a working skeleton by this date, the learning curve cost will be deemed too high and we will switch to Option C of a web so the Vue UI is not completely lost.*

**GenderMag review - Due by Winter Week 10:** A walkthrough of the core tasks (open desired file, understand explanation, do the quiz) using the project's personas. *FAIL: If any blocking issue shows no sign of being fixed by this deadline*

**Spring week 4: demo as user test.** Participants complete same tasks from GenderMag with the extension while we record task completion and confusing moments.
Fail: User gets confused or gives up. We then have about five weeks to fix problems before
the end of the school year.


**Acceptance criteria throughout:** the panel reads the open file without
copy and paste, and failing backend responses are displayed in full with a clear error message instead of freezing or showing a partial answer.

## Constraints
Licensing: The project brief is build on independently nonproprietary tools, public documentation and sample COBOL applications. Every open is open-source tools so there is no overlap with IBM-internal software. We will confirm with our mentor that VSCode fits the brief, and install the extension locally for the proof of concept.


Data Use: Every option has COBOL code sent to our backend for analysis. Our models run on the cluster or locally so the code stays within our infrastructure. Our knowledge base and test material stems from public documentation and sample COBOL applications. A web app would also need a visible warning against pasting confidential code just in case.


IP and the partner confidentiality: This RFC uses only public information and the project description, and our team's own planning documents. It contains no material IBM shared with us.


## Delegation and Validation


- **What you handed to AI tools:** I used AI to help format some of my thoughts, but every word was written by me.
- **What checks made that reasonable**: No tests or CI apply to this document, but all options were discussed as a team during meetings.
- **Where you stopped and validated the result yourself, and why those points.** I checked the project description, corrected any wrong assumptions made due to incorrect context.


What is assessed is in the [AI policy](https://capstone.alexulbrich.com/assignments/introduction/#ai-policy-applies-to-every-assignment).


## Decision

Proposed, leaning towards Option A but awaiting teams final decision.







