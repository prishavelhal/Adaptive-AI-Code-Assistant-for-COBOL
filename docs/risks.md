# Risks

## Open risks

**R-1 · Technical · Likelihood Medium, Impact High**
(Unmeasured, and explanation accuracy is the core of the product.)
IBM has not published whether Granite 4.2 was trained on COBOL, and we have not tested it. If it explains Enterprise COBOL incorrectly, learners are taught wrong things.
Owner: Quinn. Response: build a COBOL test set and run it on the 30B model in the first cluster batch; use expert-reviewed worked examples to cover gaps. Trigger: more than 2 of the first 30 test explanations are wrong.

**R-2 · Technical · Likelihood Medium, Impact High**
(The allocation rules are unknown, and the 30B is where we judge quality.)
The 80 GB GPU on OSU's cluster has not been granted. Without it, we cannot run the 30B model at full precision, and results would come from the 8B or a hosted endpoint, which behave differently.
Owner: Taylor. Response: send the request and ask about job time limits and charges. Fallbacks: the 30B at 8-bit on a smaller GPU. Trigger: no reply 10 days after asking.


**R-3 · Technical · Likelihood Medium, Impact High**
(Adaptation is harder than explanation, and it is our research contribution.)
We have not shown that Granite adapts explanations by learning-style facet. If outputs do not differ meaningfully, the study cannot show adaptation matters.
Owner: Aditi. Response: test with no examples, random examples, and facet-matched examples; reproduce the source paper's method on Granite. Trigger: reviewers cannot tell adapted answers from default ones in the first evaluation run.

**R-4 · Team · Likelihood Medium, Impact High**
(Reviewer availability is unknown, and one wrong example repeats across learners.)
No COBOL-expert reviewer has been assigned to check the worked examples.
Owner: Jack. Response: ask IBM for a named reviewer; compile examples with GnuCOBOL as a first screen. Trigger: no reviewer by the time the first 20 examples are written.

**R-5 · Technical · Likelihood Medium, Impact Medium**
(The differences are known, but they slow us more than they stop us.)
The model will run on Ollama (8B, quantized), vLLM (30B). Their settings and output formats differ, so a prompt that works on one may not work on another.
Owner: Michael. Response: keep differences in configuration only, pin settings, and record the model and prompt version with every result. Trigger: the same prompt gives structurally different output on two backends.

**R-6 · Technical · Likelihood Medium, Impact Medium**
(Both are untested, but simple fallbacks exist.)
Retrieving worked examples and reading COBOL structure (copybooks, divisions, paragraphs) are unproven. If either fails, the tutor gets the wrong examples or raw text.
Owner: Quinn. Response: run a spike on each; filter examples by detected constructs first. Trigger: either spike is not working.

**R-7 · Team · Likelihood Medium, Impact Medium**
(Both are fixable with practice and documentation.)
VS Code extensions and LLM apps are new to at least part of the team, and until setup is documented only one person can run vLLM batches. Either could stall work in a busy week.
Owner: Sarah. Response: build one thin end-to-end slice first; script and document the cluster setup; have a second person reproduce a run. Trigger: no working slice by The end of sprint 5.

## External prerequisites

Things the project waits on from outside the team.

None yet.

## Closed risks

None yet.
