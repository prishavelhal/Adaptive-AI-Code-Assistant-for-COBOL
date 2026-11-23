#!/bin/bash
# Slurm batch job that serves Granite 4.2 30B with vLLM on a separate GPU node.
#
# You usually DON'T need this: in an Advanced Desktop session with a GPU, run
# scripts/cluster/serve-vllm.sh directly (see docs/cluster-support.md). Use this
# batch job instead when:
#   - your desktop session has no GPU, or one too small for 30B, or
#   - you want a long evaluation run that doesn't depend on the desktop staying open.
#
# Submit it FROM THE REPO ROOT (the job finds the repo via the directory you
# submit from):
#   sbatch scripts/cluster/serve-vllm.sbatch
#
# Then watch it start (the first run also downloads the weights):
#   squeue -u $USER                    # is it running yet, and on which node?
#   tail -f granite-vllm-<jobid>.log   # wait for "Application startup complete"
#
# scripts/cluster/run-backend.sh finds the job automatically. The job stops at
# the --time limit below, or when you run:  scancel <jobid>
#
# --- Slurm resource request -------------------------------------------------
# These #SBATCH lines are read by sbatch, not bash. You can also override any
# of them on the command line, e.g.:  sbatch --time=8:00:00 scripts/cluster/serve-vllm.sbatch
#
# GPU choice: on this cluster GPUs have no Slurm type names (--gres=gpu:h200:1
# is rejected), so the GPU model is picked with a node feature (--constraint).
# The default asks for the H200 in the dgxh partition. For a shorter wait,
# accept any GPU with 80 GB or more (H100 80GB or H200) instead:
#   sbatch --constraint=vram80g scripts/cluster/serve-vllm.sbatch
# See all partitions and features with:  sinfo -o "%P %N %G %f"
#SBATCH --partition=dgxh --constraint=h200
#SBATCH --job-name=granite-vllm
# GPUs. A dense 30B model in bf16 needs ~60 GB for the weights alone, so one
# 80 GB GPU, or 2 GPUs plus --tensor-parallel-size 2 in VLLM_EXTRA_ARGS.
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=%x-%j.log

set -euo pipefail

# Slurm runs a copy of this file from its own spool directory, so locate the
# repo through the directory sbatch was run from.
export COBOLTUTOR_REPO=${COBOLTUTOR_REPO:-$SLURM_SUBMIT_DIR}
if [ ! -x "$COBOLTUTOR_REPO/scripts/cluster/serve-vllm.sh" ]; then
  echo "error: repo not found at $COBOLTUTOR_REPO. Submit this job from the repo root." >&2
  exit 1
fi

# Same server as the desktop setup, but listening on all interfaces, because
# the backend runs on a different node (your desktop). The API key is what
# keeps other cluster users out.
export VLLM_HOST=0.0.0.0
exec "$COBOLTUTOR_REPO/scripts/cluster/serve-vllm.sh"
