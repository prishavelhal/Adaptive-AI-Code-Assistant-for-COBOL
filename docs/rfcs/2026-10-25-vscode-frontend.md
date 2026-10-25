<!-- docs/rfcs/YYYY-MM-DD-short-title.md (or docs/adr/, whichever your repo uses) -->

# RFC: [Using Visual Studio Code as a Frontend]

Proposed <!-- Decision record header. Leave Status as "Proposed" until your team decides,
     before or after the reviews. Then fill in the outcome and the decision date.
     The document stays where it is; this header is what makes it a record. -->

| Field | Value |
| --- | --- |
| Author | Taylor Hacker |
| Date | 2026-10-25 |
| Status | Proposed |
| Decision Date | (fill when decided) |
| Deciders | Taylor, Prisha, Quinn, Sarah, Jack, Michael |
| Superseded By | (link, if applicable) |

## Problem and Context

What decision is needed, why now, and what happens if the team does nothing. Write this so a newcomer to the project understands the stakes. 2 to 4 paragraphs.

Our team is building a proof of concept AI agent that explains IBM Enterprise COBOL and adapts its explanations to a user's problem solving style. The team has already chosen IBM Granite 4.2 as the base model and Python + FastAPI as the backend. 

What needs to be set in stone is the frontend. Our team has been heavily weighing shipping our product as an extension to Microsoft's IDE Visual Studio Code (VSCode, for short). This comes with certain benefits and drawbacks, as will be described below.


## Options

At least three options, **including "do nothing"**. Give each option a short name, an account of its real costs, and the condition under which it would be the right choice. An option with no such condition is a strawman, and a strawman weakens the whole document.

### Option A: [Use VSCode as our Frontend]

Description, benefits, costs.

VSCode is by far the most popular IDE used by developers today. As such, it is worth considering it to be the frontend of our project.

Pros:
- Because it's an editor, the code that it will be working with is already there, and is easily accessible from the extension (our product) using VSCode's APIs. If the product was an independent webapp, users would have to load in code, which actually has multiple problems that I'll cover below.
- IBM mainframe tools also run in VSCode. Tools like IBM Z Open Editor and WCA 4z run inside VSCode, so devs would have all their tools in one place.
- We can use language parsers from VSCode, which will make parsing input and building prompts with them much easier.

Cons: 
- Limited Control over UI: We would have to design our frontend so it complies with VSCode's extension rules, meaning we have to work within constraints like being in a sidebar.
- Limited Control Over Backend: Because we would be operating inside VSCode, we would have to work with managing external states like themes and adhering to security policies.

### Option B: [Make it Terminal-Based]

Description, benefits, costs.

Powerful dev tools like Claude Code are terminal-based, and are very popular in the industry. Therefore, it is worth considering if it is worth it to make this application terminal-based.

Pros:
- **No reliance on VSCode**: Some developers don't use VSCode and instead opt for editors such as Vim/Neovim, Emacs, or something from the JetBrains suite. Many Vim users specifically love to build their workflow around the terminal, and if this product were a terminal application it would most likely please them.
- **Easier Testing**: Because we don't have to rely on as many external sources, setting up a testing environment would be much simpler than using an external host.

Cons:
- **Works Certain Learning Styles**: Some people (even devs) with low self-efficacy could be intimidated by a tool like this if it were a CLI tool. 
- **More Work Wiring Everything Together**: VSCode gives us some APIs we could work with to read and parse code. Building a CLI tool means doing all of that from scratch.

### Option C: Do Nothing

What staying on the current path actually costs, and when that cost arrives.

The current path means building a webapp.

Cons:
**IBM Integration Difficulty**: It would be much harder for IBM to integrate a webapp into their products than a VSCode extension.
**User Workflow Integration Difficulty**: Users would likely be annoyed with having to paste their code into a webapp to get tutored on it every time. This would be especially difficult with COBOL, as many files reference specific details of other files.

## Analysis

The technical tradeoffs that matter for this decision: performance, complexity, maintainability, security, cost. Argue from evidence (benchmarks, prototypes, documentation, prior art) and cite what you relied on so a reviewer can check it. Acknowledge what you are uncertain about.

**Performance**: We will need to optimize for speed in VSCode's extension instance and low compute power, which will force us to build our pipeline with compute being distributed in a certain way.

**Complexity**: Our main source of complexity will come from the webview. We will need to create a pipeline to ensure that both sides (VSCode and the HPC/Cloud) can communicate with each other while adhering to VSCode's rules of use. We will also need to account for cancelling streaming when a user does something like close a panel.

**Maintainability**: The VSCode API is stable, so we most likely won't have issues with the frontend if we use VSCode. However, due to Microsoft's Webview UI being deprecated in 2025, we will most likely code the frontend in a Javascript framework like Vue.

**Security**: VSCode is very secure in terms of a serving platform (Because they're served by Microsoft), but we will need to make sure to tweak the model's permissions from their defaults because models aren't sandboxed as an extension.

**Cost**: The frontend inference is free.

## Recommendation and Verification Plan

Which option you propose and why it wins the analysis above. Then, concretely: how will the team know it worked? List the tests, metrics, or acceptance criteria that would detect failure, and when they will be checked.

I propose we use a VSCode extension as our frontend. It would be as reliable as Microsoft, and provide a helpful interface.

## Constraints

Licensing, data use, IP, and the partner confidentiality boundary as they bear on this decision. If none apply, say so explicitly and briefly explain why.

None apply, as VSCode is free and official IBM software lives in VSCode extensions already.

## Delegation and Validation

- **What you handed to AI tools** on this decision, whether that was the analysis, the prototype, the tests, or the writing.
I wrote and coded everything by hand, and used Claude for guiding my research.
- **What checks made that reasonable**: tests, CI, review gates, a staging environment, a rollback path. Name the ones that actually exist in your repo, not the ones you intend to build.
- **Where you stopped and validated the result yourself, and why those points.** If this decision is hard to reverse, say what you personally checked before committing to it.

What is assessed is in the [AI policy](https://capstone.alexulbrich.com/assignments/introduction/#ai-policy-applies-to-every-assignment).

## Decision

Proposed, until your team decides. Then accepted, rejected, or superseded, with the date and who chaired the decision. If superseded, link the RFC that replaces this one.

Proposed.
