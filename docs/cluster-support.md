# GUIDE TO USING THE APPLICATION ON THE CLUSTER

**Running this application on the school's High Performance Computing (HPC) cluster will allow you to take full use of Granite's 30B model at speed. This is due to the cluster allowing access to very powerful GPUs.**

1. **Enable your HPC account and connect to the cluster via the school's VPN.** Follow [this link](https://it.engineering.oregonstate.edu/hpc) and follow the directions under **Getting started with the COE HPC cluster**. This will take you through all the steps needed to access the cluster. It is important to use the VPN so that you can connect to a virtual desktop to run VSCode.

2. **Launch an Advanced Desktop session.** Follow [this link](https://submit-b.hpc.engr.oregonstate.edu/), this will take you to the web GUI for the cluster. Sign in and click on `My Interactive Sessions` in the orange top bar. There, underneath the `Interactive Tabs` box you will see an option for `Advanced Desktop`, which is a way to run a desktop environment on a cluster node. Click on it, and it'll take you to a screen where you can configure the desktop. Under the `Queue/Partition` section, select `dgxh`. This node has access to the best GPUs on the cluster.

In the menu for configuring the desktop, go to **Queue/Partition** and select `dgxh`. This is the most powerful partition of the cluster, and has the GPUs that AI team will be building the application around. 

3. **Download VSCode.** Open firefox and go to VSCode's page, and hit the **Download for Linux** button in the top right hand corner. Make sure to hit just the big part of the button, as that will download the .tar.gz version. We need to use the .tar.gz version because using the .rpm version requires sudo permissions, and we do not have sudo permission on the cluster.

Anyways, put the .tar.gz folder where you want to access vscode from (I put it in my home directory), and extract the application using `tar -xvzf ./filename.tar.gz` (just use tab to autocomplete). It should extract the whole application into a directory called `VSCode-linux-x64`. Feel free to delete the .tar.gz file now. You can now launch VSCode by typing `code` in a directory from the terminal like normal.

4. **Clone our repo into your ENGR account in the ~/hpc-share folder.** The hpc-share folder (it gets created the first time you access the cluster) has tons of space on it where we can download the large models for our project. The normal ENGR accounts are only given 25GB of space, this directory has over 100.

5. **Run the installer.** In a terminal in your Advanced Desktop session, from the repo root:

   ```bash
   ./install.sh
   ```

   It notices it's on the cluster and asks **"Set up the cluster version?"**. Answer yes (or run `./install.sh --cluster` to skip the question). On your laptop the same script does the normal Docker install instead; `--no-cluster` forces that here too.

   The cluster install has four steps, needs no Docker and no sudo, and is safe to run again (finished steps are skipped):

   1. **Checks the node:** GPU, free space in `~/hpc-share`, and the model id. It warns if your session has no GPU or there's less than ~100 GB free.
   2. **Finds VS Code,** including the `.tar.gz` copy in your home folder from step 3. It never tries to install VS Code here.
   3. **Sets up vLLM** by running `scripts/cluster/setup.sh`: a Python 3.12 virtual environment with vLLM in `~/hpc-share`, plus a private API key in `~/.config/coboltutor/vllm.env`. **Never commit or share `vllm.env`.** Meanwhile the VS Code extension builds in the background, using the cluster's Node module (`module load nodejs`; the system Node is too old).
   4. **Installs the extension** into VS Code and prints how to start everything.

   The first run downloads several GB for vLLM, so it takes a while. Every download cache (pip, uv, npm, pnpm, model weights) goes to `~/hpc-share`, not your small home folder; `scripts/cluster/env.sh` sets those locations.

   **Run `./install.sh` again after you pull new code.** It skips what's already set up and rebuilds the extension, so VS Code gets the latest version. Then run **Developer: Reload Window** in VS Code.

6. **Start CobolTutor.** Do this every time you start a new desktop session. Here's how the pieces fit:

   ```
   your Advanced Desktop node (one Slurm job, one GPU)
     VS Code  -->  backend (127.0.0.1:8000)  --API key-->  vLLM serving Granite 30B (127.0.0.1, random port)
   ```

   An Advanced Desktop session is already a Slurm job with a GPU, so everything runs on that one node. You don't need `sbatch` or `srun`.

   **a. Start the model** in a desktop terminal:

   ```bash
   scripts/cluster/serve-vllm.sh     # wait for "Application startup complete"
   ```

   Leave this terminal open. The first start downloads the model weights (about 60 GB) and takes a while; later starts reuse them and take about 4-5 minutes. Stop the model with Ctrl+C. It also stops when your desktop session ends.

   **b. Start the backend** in a second desktop terminal:

   ```bash
   scripts/cluster/run-backend.sh
   ```

   It finds the model server, waits for the model to load, and serves the backend on `http://127.0.0.1:8000`, the address the VS Code extension uses by default. If port 8000 is taken by another user on the node, run `COBOLTUTOR_PORT=8010 scripts/cluster/run-backend.sh` and change the `coboltutor.backendUrl` setting in VS Code to match.

   **c. Check it.** Run `curl http://127.0.0.1:8000/health`. It should show `"model": "granite4.2:30b"` and `"model_ready": true`. In VS Code, run **CobolTutor: Check Backend Connection** from the command palette, then try it: open `coboltutor/examples/PAYROLL.cbl`, right-click, and choose **Explain This File**.

7. **Turn on the agent pipeline (optional).** By default the extension uses the plain chat endpoint (`/api/chat`). To use the multi-agent pipeline (`/api/agent-chat`) instead, open VS Code's Settings, search for `coboltutor.useAgents`, and turn it on. Each answer then goes through three stages:

   - **analyze:** the Analyzer agent reads the attached COBOL's structure (plain Python, no model call);
   - **explain:** the Explainer agent streams the answer from Granite 30B;
   - **verify:** the Critic agent checks the answer against the code. On the cluster it also asks the model to review the answer (`COBOLTUTOR_AGENT_LLM_REVIEW=true` in the profile), which adds roughly 25 seconds after the answer finishes.

   The Critic's model review can be wrong too: in testing it once flagged a correct statement as a mistake. Treat its findings as hints, not verdicts.

8. **Settings.** You don't edit any code. All cluster settings live in `coboltutor/backend/profiles/cluster-vllm.conf`, which `serve-vllm.sh` and `run-backend.sh` both read. The defaults are tuned for an 80 GB H100 or the 141 GB H200:

   | Setting | Value | Why |
   |---|---|---|
   | `VLLM_MODEL_ID` | `ibm-granite/granite-4.2-30b` | The model vLLM downloads and serves |
   | `VLLM_EXTRA_ARGS` | `--reasoning-parser nemotron_v3` | Full precision (bf16), no quantization: the weights take ~55 GB, which an 80 GB+ GPU holds easily. The parser keeps Granite's "thinking" text out of answers |
   | `VLLM_MAX_MODEL_LEN` | `32768` | Room for the Critic's review prompt (code + analysis + the whole answer). At 16k, long files made the review silently skip |
   | `COBOLTUTOR_LLM_REASONING_EFFORT` | `low` | Limits how long Granite thinks. **Don't leave it empty**: then the 30B model can spend its whole token budget thinking and never answer |
   | `COBOLTUTOR_AGENT_LLM_REVIEW` | `true` | The Critic's model review (step 7) |

   The comments in the profile explain each setting, including timings for the other reasoning-effort levels. Restart `serve-vllm.sh` after changing a `VLLM_*` setting, and `run-backend.sh` after changing a `COBOLTUTOR_*` one.

9. **Troubleshooting**
   - **Nothing shows up in VS Code:** the extension isn't installed or VS Code hasn't loaded it. Run `./install.sh` again, then **Developer: Reload Window**. A CobolTutor icon should appear in the activity bar.
   - **"No space left on device" with a path in `/nfs/stak/users/...`:** your home directory is full. Check what's using it with `du -sh ~/.cache/* ~/.local/share/*`. Delete caches the scripts no longer use, such as `~/.cache/pip`, then run the script again.
   - **`serve-vllm.sh` says there's no GPU:** your desktop session was started without one. Start a new session that requests a GPU (step 2).
   - **vLLM fails with an out-of-memory error:** the GPU is too small for 30B in full precision (check with `nvidia-smi`). Add `--quantization fp8_per_tensor --kv-cache-dtype fp8` to `VLLM_EXTRA_ARGS` in the profile, which halves the memory the model needs at a small cost in answer quality. If your session has 2 GPUs, add `--tensor-parallel-size 2` instead. If neither works, run the model as a batch job on a bigger GPU (below).
   - **"The model used its whole length budget reasoning and never started an answer":** `COBOLTUTOR_LLM_REASONING_EFFORT` is empty or too high. Set it to `low` and restart `run-backend.sh`.
   - **Answers include the model's "thinking" text:** `VLLM_EXTRA_ARGS` is missing `--reasoning-parser nemotron_v3`.

   **Running the model as a batch job instead.** Use this when your desktop session has no GPU, or for long evaluation runs that shouldn't depend on the desktop staying open. `scripts/cluster/serve-vllm.sbatch` runs the same server on a separate GPU node. By default it asks for the H200 (`--partition=dgxh --constraint=h200`); change the constraint to `vram80g` to accept any 80 GB+ GPU and usually start sooner. Submit it from the repo root:

   ```bash
   sbatch scripts/cluster/serve-vllm.sbatch   # from the repo root
   squeue -u $USER                            # wait for state R (running)
   tail -f granite-vllm-<jobid>.log           # wait for "Application startup complete"
   scripts/cluster/run-backend.sh             # in your desktop, same as before
   ```

   The job runs for up to 4 hours. Stop it early with `scancel <jobid>` so you don't hold a GPU you aren't using. If `run-backend.sh` waits forever, your desktop node can't reach the GPU node directly. Open an SSH tunnel with `ssh -N -L 8001:<gpu-node>:<port> <login-node>`, using the address printed at the top of the job log, then run `VLLM_BASE_URL=http://localhost:8001/v1 scripts/cluster/run-backend.sh`.

10. **Switching back to local development.** Nothing on your laptop changes. Local development still uses Granite 8B on Ollama through `install.sh` (which skips the cluster setup off the cluster) or `docker compose up`. `profiles/local-ollama.conf` has the local settings if you run the backend by hand.

**For evaluation runs:** every run should use the same model id, vLLM version, and `VLLM_EXTRA_ARGS`. Changing any of them changes the model's output, so scores from different settings can't be compared. `serve-vllm.sh` prints all three when it starts (and a batch job saves them at the top of its log), so save that output with your results.
