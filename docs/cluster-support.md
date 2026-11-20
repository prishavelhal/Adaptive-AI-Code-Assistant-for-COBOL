# GUIDE TO USING THE APPLICATION ON THE CLUSTER

**Running this application on the school's High Performance Computing (HPC) cluster will allow you to take full use of Granite's 30B model at speed. This is due to the cluster allowing access to very powerful GPUs.**

1. **Enable your HPC account and connect to the cluster via the school's VPN.** Follow [this link](https://it.engineering.oregonstate.edu/hpc) and follow the directions under **Getting started with the COE HPC cluster**. This will take you through all the steps needed to access the cluster. It is important to use the VPN so that you can connect to a virtual desktop to run VSCode.

2. **Launch an Advanced Desktop session.** 

3. **Download VSCode.** Open firefox and go to VSCode's page, and hit the **Download for Linux** button in the top right hand corner. Make sure to hit just the big part of the button, as that will download the .tar.gz version. We need to use the .tar.gz version because using the .rpm version requires sudo permissions, and we do not have sudo permission on the cluster.

Anyways, put the .tar.gz folder where you want to access vscode from (I put it in my home directory), and extract the application using `tar -xvzf ./filename.tar.gz` (just use tab to autocomplete). It should extract the whole application into a directory called `VSCode-linux-x64`. Feel free to delete the .tar.gz file now. You can now launch VSCode by typing `code` in a directory from the terminal like normal.

4. **Clone our repo into your ENGR account.** If you've already done this you can skip this step.

5. **Configure the repo to use the 30B model.** You don't edit any code. The cluster settings live in `coboltutor/backend/profiles/cluster-vllm.conf`, and three scripts in `scripts/cluster/` do the rest. Here's how the pieces fit:

   An Advanced Desktop session is already a Slurm job with a GPU, so everything runs on that one node. You don't need `sbatch` or `srun`:

   ```
   your Advanced Desktop node (one Slurm job, one GPU)
     VS Code  -->  backend (127.0.0.1:8000)  --API key-->  vLLM serving Granite 30B (127.0.0.1, random port)
   ```

   To confirm your session has a GPU and see how big it is, run `nvidia-smi` in a desktop terminal. A 30B model in bf16 needs about 60 GB of GPU memory for the weights alone (see Troubleshooting if yours is smaller).

   **a. One-time setup.** From the repo root, run:

   ```bash
   scripts/cluster/setup.sh
   ```

   This installs vLLM into a Python 3.12 virtual environment in `~/hpc-share`. The cluster's own `python3` is 3.9, which is too old for vLLM, so the script uses `uv` to download 3.12. Your home directory has a small quota, so every download cache (pip, uv, vLLM, model weights) goes to `~/hpc-share` too. `scripts/cluster/env.sh` sets those locations. The script also creates a private API key in `~/.config/coboltutor/vllm.env` and installs `uv` if you don't have it. **Never commit or share `vllm.env`.**

   **b. Set the model.** In `coboltutor/backend/profiles/cluster-vllm.conf`, set `VLLM_MODEL_ID` to the Granite 4.2 30B repo id from https://huggingface.co/ibm-granite.

   **c. Start the model** in a desktop terminal:

   ```bash
   scripts/cluster/serve-vllm.sh     # wait for "Application startup complete"
   ```

   Leave this terminal open. The first run downloads the weights (about 60 GB), so it takes a while. Later runs reuse them. Stop the model with Ctrl+C. It also stops when your desktop session ends.

   **d. Start the backend** in a second desktop terminal:

   ```bash
   scripts/cluster/run-backend.sh
   ```

   It finds the model server, waits for the model to load, and serves the backend on `http://127.0.0.1:8000`. The VS Code extension uses that address by default. If port 8000 is taken by another user on the node, run `COBOLTUTOR_PORT=8010 scripts/cluster/run-backend.sh` and change the `coboltutor.backendUrl` setting in VS Code to match.

   **e. Check it.** Run `curl http://127.0.0.1:8000/health`. It should show `"model": "granite4.2:30b"` and `"model_ready": true`. In VS Code, run **CobolTutor: Check Backend Connection** from the command palette.

6. **Troubleshooting**
   - **"No space left on device" with a path in `/nfs/stak/users/...`:** your home directory is full. Check what's using it with `du -sh ~/.cache/* ~/.local/share/*`. Delete caches the scripts no longer use, such as `~/.cache/pip`, then run the script again.
   - **`serve-vllm.sh` says there's no GPU:** your desktop session was started without one. Start a new session that requests a GPU.
   - **vLLM fails with an out-of-memory error:** the GPU is too small for 30B. Add `--quantization fp8` to `VLLM_EXTRA_ARGS` in the profile. If your session has 2 GPUs, add `--tensor-parallel-size 2` instead. If neither works, run the model as a separate batch job on a bigger GPU (below).
   - **Answers include the model's "thinking" text:** add the `--reasoning-parser` named on the model card to `VLLM_EXTRA_ARGS`.
   - **Requests fail with an error about `reasoning_effort`:** keep `COBOLTUTOR_LLM_REASONING_EFFORT=` empty in the profile. That's the default.

   **Running the model as a batch job instead.** Use this when your desktop's GPU is too small, or for long evaluation runs that shouldn't depend on the desktop staying open. `scripts/cluster/serve-vllm.sbatch` runs the same server on a separate GPU node:

   ```bash
   # First set #SBATCH --partition in the file to a GPU partition (run `sinfo` to list them).
   sbatch scripts/cluster/serve-vllm.sbatch   # from the repo root
   squeue -u $USER                            # wait for state R (running)
   tail -f granite-vllm-<jobid>.log           # wait for "Application startup complete"
   scripts/cluster/run-backend.sh             # in your desktop, same as before
   ```

   The job runs for up to 4 hours. Stop it early with `scancel <jobid>` so you don't hold a GPU you aren't using. If `run-backend.sh` waits forever, your desktop node can't reach the GPU node directly. Open an SSH tunnel with `ssh -N -L 8001:<gpu-node>:<port> <login-node>`, using the address printed at the top of the job log, then run `VLLM_BASE_URL=http://localhost:8001/v1 scripts/cluster/run-backend.sh`.

7. **Switching back to local development.** Nothing on your laptop changes. Local development still uses Granite 8B on Ollama through `install.sh` or `docker compose up`. `profiles/local-ollama.conf` has the local settings if you run the backend by hand.

**For evaluation runs:** every run should use the same model id, vLLM version, and `VLLM_EXTRA_ARGS`. Changing any of them changes the model's output, so scores from different settings can't be compared. `serve-vllm.sh` prints all three when it starts (and a batch job saves them at the top of its log), so save that output with your results.


