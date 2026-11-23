**Success Metrics: COBOL Learning Assistant (VSCode Extension)**

Rules for ourselves: we don’t change these metrics, thresholds, or the eval set once this file is committed. If one has to change, we add a dated change and say why.

Committed: 11/20/2026

**Metric 1: Answer Quality**

**What:** Accuracy on a frozen COBOL eval set. We compare our full system, Granite 4.2 30B plus retrieval over Redbooks/COBOL book set in knowledge base against the baseline (same Granite 4.2 30B with no retrieval and plain system prompt).

**Why:** Retrieval and prompt engineering are the main engineering work for backend. The only real test for that is comparing against the model we could already get for free. We need to know if the knowledge base did anything.

**Eval set:** Committed to an eval/ folder

- Chunk of conceptual questions (we need divisions, PIC, COMP-3, CICS/DB2 basics, file handling, PERFORM variants)  
- Coding tasks (write, fix, explain) with test inputs and expected outputs

**How to score and collect:**

- Coding: Graded automatically. Create and run an eval/run\_eval.py  
- Conceptual: two team members grade each answer against the key without knowing which system writes it. Scores are 0, 0.5, or 1\. Disagreements go to a third grader.   
- Used on the HPC vLLM deployment 

**Decision Rule:**

- If successful with a greater margin, ship retrieval as the default.  
- If only a partial difference, ship it but spend the remaining time on failure analysis. Report honestly and as a small gain.  
- If failure, retrieval is not helping. Tell the advisor and decide together whether to cut the KB onto a curated subset, or drop retrieval and focus on prompts and UX.

**Things to Observe:**

- **Hallucination Rate:** % of answers that cite a COBOL feature, compiler option, or Redbook/Source section that doesn’t exist  
- Coding and conceptual scored separately, so a good combined number doesn’t hide anything


  
**Metric 2: Answer Speed**

**What:** Time taken for the COBOL Learning Assistant to generate an answer after a user submits a question in the VS Code extension. We measure both time to first time (TTFT) and total response generation time.

**Why**: Developers need explanations quickly enough to avoid interrupting their workflow. Even if our answers are accurate, the assistant won’t be useful if users spend too much time waiting for responses. Since our system uses Granite 4.2 30B with retrieval over the COBOL knowledge base, we need to understand whether retrieval introduces noticeable latency.

**Eval Set**: Use the same COBOL evaluation set from Metric 1, including conceptual questions and coding tasks.

**How to Score and Collect:**

- Instrument the VS Code extensions and backend to record when a request is submitted, when the first token is received, and when the response finishes.  
- Calculate median (p50) and 95th-percentile (p95) response times.  
- Compare response times between the full system (Granite 4.2 30B \+ retrieval) and the baseline (Granite 4.2 30B without retrieval).  
- Run evaluations on the HPC vLLM deployment under comparable conditions.

**Decision Rule:**

- If successful, median time to first token is under 3 seconds, and 95% of responses within 15 seconds.  
- IF partially successful median time to first token is between 3-5 seconds, or p95 total response time is between 15-25 seconds. Ship with documented latency limitations and prioritize optimization.  
- If failure, median time to first token exceeds 5 seconds or p95 total response time exceeds 25 seconds. Investigate retrieval overhead, model inference performance, and streaming behavior before shipping.

**Things to Observe:**

- Retrieval Overhead: Additional latency introduced by knowledge base retrieval compared with the baseline.  
- Response Length: Whether longer explanations significantly increase generation time  
- Streaming Performance: Whether users receive the first token quickly even when the full response takes longer.


**Metric 3: Follow-up rate**

**What:** The amount of times a user follows up with the model and tries to receive clarification from the model. It also gauges on if the prompt is not a clarifying follow up, like asking for an example or a question relating to the prompt is a success, while a “I don’t understand” is a failure. 

**Why:** The idea is that due to our model being able to adhere to the users learning style, receiving a follow up that says “what do you mean?” or “can you explain it better?” suggests it did not land.

**Eval Method:** Use the analyzer agent to flag if the user’s prompt is asking for clarification on info the model gave earlier. Store query and count in /docs.

**How to score and collect:**

- For each conversation with the model, keep a counter that starts at 0 that collects the amount of requested clarifications in the session. When a user asks for clarification, the program updates a section of the database with the counter’s new value and adds an entry with the prompt, so that eval can be done later on areas needing clarification. Additional metadata such as conversation length will be added to the db as well.  
- The standard for scoring will be determined based on testing of the application to provide a reasonable default.

**Decision Rule:**

- If successful with a greater margin, ship the adaptive layer as the default.  
- If there is only a partial difference, ship it but spend the remaining time on failure analysis of the snippets that still drew follow ups.  
- If failure (Clarification is not clear and the user keeps on asking questions), the adaptation is not helping. Change the prompts file and retune the explanations to be more descriptive.

**Things to Observe:**

- **Context window length**: It is important to note how much of the context window has filled up at the time of the clarification request. This is because once the context window overflows, it starts getting rid of early context, and could cause response quality degradation.  
- **User’s** **Learning Style:** The learning style of the user could be a major factor in determining if the user asks for clarification or not, and should be noted in the db along with other metadata from the conversation.