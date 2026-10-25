# RFC: Where to Host Granite for Shared Development, Evaluation, and Demos


| Field | Value |
| --- | --- |
| Author | Jack Davison |
| Date | 2026-10-23 |
| Status | Proposed |
| Decision Date | (fill when decided) |
| Deciders | Taylor, Jack, Aditi, Michael, Quinn |
| Superseded By | — |


## Problem and Context
 
Our team is building a proof of concept VS Code extension that explains IBM Enterprise COBOL and adapts its explanations to a user's problem solving style. The team has already chosen IBM Granite 4.2 as the base model and Python + FastAPI as the backend. What we have not finalized is **where the model runs** once we move past individual laptops.
 
The walking skeleton plan runs Granite 4.2 8B locally through Ollama on each developer's machine. That works for wiring the system together, but three upcoming needs require a shared, consistent model endpoint: (1) the evaluation framework, which must produce comparable scores across runs and teammates and (2) prompt engineering for the adaptation layer, which should be tuned on the model we will actually evaluate and (3) the 30B model, which IBM reports outperforms 8B on tool calling and software engineering benchmarks [1] and needs more memory than most laptops have [7].
 
This decision is hard to reverse because it commits us to an infrastructure path. It determines accounts and access, where our evaluation numbers come from, the deployment instructions in our handoff document, and which model our prompts are tuned against. Switching hosts during the term would invalidate earlier evaluation results and cost a full sprint of re-setup. If we do nothing, each teammate keeps running a different local setup, and our results will not be comparable or reproducible by IBM.


## Options
 
### Option A: Granite 4.2 30B on the OSU College of Engineering HPC cluster via vLLM, plus 8B locally via Ollama
 
Run Granite 4.2 30B under vLLM on a GPU node of the CoE HPC cluster for prompt engineering and evaluation. The cluster provides GPU systems for research and class use and schedules jobs through Slurm [2]. IBM optimizes Granite 4.2 for vLLM and documents an OpenAI compatible serving path [1][3]. Daily local development stays on 8B through Ollama.
 
- **Benefits:** no cost to the team. Weights and prompts stay on university hardware  mirrors how an enterprise would run the model on premises. Data center GPUs can serve 30B without the heavy quantization a laptop needs.
- **Costs:** requires faculty sponsorship for HPC accounts [2]. Access requires the OSU VPN [2], someone must own the cluster setup. Prompts are tuned on 30B but developed against 8B, so behavior may differ between the two.
- **Right choice when:** The team can get HPC access and the cluster allows jobs long enough for interactive prompt work and full eval runs.
### Option B: IBM watsonx.ai (hosted by our partner's platform)
 
Use IBM's hosted platform to serve Granite. IBM documents watsonx.ai as a supported way to run Granite 4.2 [1].
 
- **Benefits:** no infrastructure to maintain, always available for demos. IBM could take over the same setup at handoff. IBM states it does not use content uploaded to watsonx, or model outputs, to train or improve IBM models [4].
- **Costs:** watsonx.ai is a paid service with usage based pricing [1], so it depends on our partner providing credits. 
- **Right choice when:** cluster access is denied or cannot support long running jobs, and our partner provides credits.
### Option C: Do Nothing (8B on each laptop via Ollama)
 
Keep the walking skeleton setup: every developer runs Granite 4.2 8B through Ollama, which exposes an OpenAI compatible API on `localhost:11434` [5].
 
- **Benefits:** free, private, already planned, works offline. Granite 4.2 8B at Q4 quantization needs roughly 6 GB of VRAM [6], so most teammates can run it.
- **Costs:** the cost arrives when evaluation starts: teammates run different hardware and quantizations, so the same eval set can produce different scores. The 30B model needs about 18 GB of VRAM even at Q4 [7], which most of our laptops cannot provide. Demos depend on one person's machine.
- **Right choice when:** the project only needs 8B and evaluation is run by one person on one machine.


## Analysis
 
**Performance.** Options A and B run on data center GPUs and can serve 30B. Option C limits most of us to quantized 8B, and CPU only machines run far slower [6]. We do not yet have measured latency.
 
**Complexity.** Option C is simplest. Option B adds account setup but no servers. Option A adds the most: HPC accounts, VPN, Slurm job scripts, and starting vLLM inside a job. 
 
**Dev/eval model mismatch.** Option A deliberately uses two models: 8B locally and 30B on the cluster. This is the main technical risk of the plan. A prompt that produces good changes on 30B may produce weaker ones on 8B, and the IBM paper this project builds on found that models differ substantially in how often they adapt [8]. We accept this because prompt engineering and evaluation, where the numbers matter, both run on 30B. Local 8B is for building and wiring features, not for judging quality.
 
**Maintainability.** Every option is reached through our `llm/` module. Could make it easy and set environment variables for the model names and versions. The real switching cost is keeping evaluation similar. Scores from different hosts or sizes are not directly comparable. This is why the decision should be made before evaluation work begins.
 
**Security and data use.** Our knowledge base and test code are public (Open Mainframe Project course, public IBM documentation, public sample programs). Even so, the product's premise is that enterprise COBOL should not be sent to an outside service. Options A and C demonstrate a self hosted path. Option B relies on an external platform.
 
**Cost.** Options A and C are free to the team. Option B depends entirely on our partner.


## Recommendation and Verification Plan
 
**Recommendation: Option A.** Serve Granite 4.2 30B on the CoE HPC cluster via vLLM for prompt engineering and evaluation, and Granite 4.2 8B via Ollama for local development. It is free, keeps code on university hardware, demonstrates the self hosted deployment an enterprise would use, and gives every evaluation run the same model and hardware. Option B is the fallback if the cluster cannot support our workload.
 
**Verification:**
 
1. **Access check:** HPC accounts approved for the team members running evals, with faculty sponsorship. If not approved by [date], escalate to the Option B fallback with our partner.
2. **Spike (1–2 days):** start vLLM with Granite 4.2 30B inside a Slurm job and call it through our `llm/` module. Pass: a streamed response reaches the VS Code extension end to end over the VPN.
3. **Job length check:** confirm the maximum job time on the GPU partition covers a full eval run as well as prompt tuning.
4. **Consistency test:** run the same 20 question eval set three times on 30B. Pass: scores don't vary by a set threshold (TBD).
5. **Mismatch check:** run the same eval set on local 8B and record the gap in `eval/results/`, so the team knows how far local behavior is from evaluated behavior.
## Constraints
 
- **Licensing:** Granite 4.2 is Apache 2.0 [1][6], so self hosting on the cluster and commercial use after handoff are both allowed.
- **Data use:** only public COBOL and public documentation are sent to the model. The cluster is a shared university resource, so we will not store credentials or private data in job scripts or shared directories.
- **IP:** prompts, adaptation templates, and evaluation data are our team's work. Hosting does not change ownership.
- **Partner confidentiality:** no partner confidential code is used, per the brief's requirement to use public documentation and sample applications. If that changes, the partner must approve running that code on university hardware.


## Delegation and Validation
 
- **Handed to AI (Claude):** finding sources on Granite 4.2 hosting, VRAM requirements, the OSU HPC cluster, watsonx.ai data policy, and Ollama's API. I worked with Claude to write this draft.
- **Checks that exist in our repo:** pull requests require review before merging, per CONTRIBUTING.md. Node CI runs on GitHub Actions. There is no Python CI yet, so the spike will be validated manually.
- **Where I validated myself:** I opened every cited source and confirmed each claim, I confirmed with Taylor, who talked with CoE IT about which GPUs and job limits are available. Because this is hard to reverse, approved HPC access and a passing spike are the checkpoints before the team commits.


## Decision
 
Proposed. The team is leaning toward Option A, to be decided after peer review and confirmation of HPC access.




## References
 
1. IntuitionLabs, "IBM Granite 4.2 model guide." https://intuitionlabs.ai/articles/ibm-granite-4-2-model-guide
2. Oregon State University College of Engineering IT, "HPC." https://it.engineering.oregonstate.edu/hpc
3. AICybr, "IBM Granite 4.2 Local Deployment Guide." https://aicybr.com/blog/ibm-granite-4-2-local-deployment-guide
4. IBM, "Security and privacy for foundation models" (watsonx documentation). https://eu-gb.dataplatform.cloud.ibm.com/docs/content/wsj/analyze-data/fm-security.html?context=wx
5. Ollama, "OpenAI compatibility." https://docs.ollama.com/api/openai-compatibility
6. llmrun.dev, "Granite 4.2 8B — Hardware Requirements." https://llmrun.dev/model/ibm-granite-granite-4-2-8b
7. llmrun.dev, "Granite 4.2 30B — Hardware Requirements." https://llmrun.dev/model/ibm-granite-granite-4-2-30b
8. Anderson, Piorkowski, Weisz, Burnett, and Varshney, "Can LLM Code Explanations Adapt to Diverse Problem-Solvers' Needs?" (2026).

