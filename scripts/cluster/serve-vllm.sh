#!/usr/bin/env bash
# Serve Granite 4.2 30B with vLLM on THIS node's GPU.
#
# Normal use: in an Advanced Desktop session that has a GPU. The desktop is
# already a Slurm job holding the GPU, so there's no need for sbatch or srun:
# vLLM runs right here, next to VS Code and the backend. In one terminal:
#   scripts/cluster/serve-vllm.sh        # wait for "Application startup complete"
# and in a second terminal:
#   scripts/cluster/run-backend.sh
# Stop the model with Ctrl+C. It also stops when the desktop session ends.
#
# scripts/cluster/serve-vllm.sbatch runs this same script as a separate batch
# job on another GPU node, for when your desktop has no (or too small a) GPU,
# or for long evaluation runs.
#
# Prerequisites: scripts/cluster/setup.sh, and VLLM_MODEL_ID set in
# coboltutor/backend/profiles/cluster-vllm.conf.
#
# Options (environment variables):
#   VLLM_HOST           address to listen on. Default 127.0.0.1: only programs
#                       on this node can connect, which is all the backend needs.
#                       serve-vllm.sbatch sets 0.0.0.0 so other nodes can connect.
#   COBOLTUTOR_HPC_DIR  where setup.sh put the venv and model cache.
set -euo pipefail

VLLM_HOST=${VLLM_HOST:-127.0.0.1}
CONFIG_DIR=$HOME/.config/coboltutor
ENDPOINT_FILE=$CONFIG_DIR/vllm-endpoint
# Find the repo from this script's location. serve-vllm.sbatch passes
# COBOLTUTOR_REPO instead, because Slurm runs batch scripts from a copy in its
# own spool directory.
REPO_DIR=${COBOLTUTOR_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
PROFILE=$REPO_DIR/coboltutor/backend/profiles/cluster-vllm.conf

# Shared settings: HPC_DIR, and every cache (including the Hugging Face model
# weights, HF_HOME) pointed at the HPC share instead of your small $HOME.
# shellcheck source=SCRIPTDIR/env.sh
source "$REPO_DIR/scripts/cluster/env.sh"

# --- Checks before loading anything big ---------------------------------------
# Is there a GPU we're allowed to use? Inside a Slurm job, nvidia-smi only
# lists the GPUs allocated to that job.
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
  echo "error: no GPU available here. Start an Advanced Desktop session with a GPU," >&2
  echo "or run the model as a batch job:  sbatch scripts/cluster/serve-vllm.sbatch" >&2
  exit 1
fi

# Only one model server at a time: run-backend.sh reads a single endpoint file,
# and a second 30B copy wouldn't fit on the GPU anyway.
if [ -f "$ENDPOINT_FILE" ]; then
  # shellcheck source=/dev/null
  OLD_URL=$(source "$ENDPOINT_FILE" && echo "$VLLM_BASE_URL")
  if curl -sf -o /dev/null "${OLD_URL%/v1}/health"; then
    echo "error: a vLLM server is already running at $OLD_URL." >&2
    echo "Stop it first (Ctrl+C in its terminal, or scancel if it's a batch job)." >&2
    exit 1
  fi
  rm -f "$ENDPOINT_FILE" # left over from a server that didn't shut down cleanly
fi

# --- Load settings ------------------------------------------------------------
# The profile has the VLLM_* settings and COBOLTUTOR_LLM_MODEL.
# shellcheck source=SCRIPTDIR/../../coboltutor/backend/profiles/cluster-vllm.conf
source "$PROFILE"
if [[ $VLLM_MODEL_ID == *CHANGE-ME* ]]; then
  echo "error: set VLLM_MODEL_ID in $PROFILE to the Granite 4.2 30B repo id." >&2
  exit 1
fi

# Load the API key. `set -a` exports it, and vLLM reads VLLM_API_KEY from its
# environment. We deliberately don't pass it as --api-key: command-line
# arguments are visible to every user on the node through `ps`. Nodes are
# shared, so even on 127.0.0.1 other users' programs could otherwise connect.
set -a
# shellcheck source=/dev/null
source "$CONFIG_DIR/vllm.env"
set +a

# shellcheck source=/dev/null
source "$HPC_DIR/vllm-venv/bin/activate"

# Pick a free port. Nodes are shared, so a fixed port like 8001 may already be
# taken by someone else. Binding to port 0 makes the OS choose a free one.
PORT=$(python -c 'import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1])')
# The address the backend should use: localhost when we only listen locally,
# otherwise this node's name, so the backend can be on another node.
if [ "$VLLM_HOST" = "127.0.0.1" ]; then CONNECT_HOST=127.0.0.1; else CONNECT_HOST=$(hostname); fi

# Print what's being served, so a saved log records how results were produced.
echo "slurm job: ${SLURM_JOB_ID:-none} on $(hostname)"
echo "model:     $VLLM_MODEL_ID (served as $COBOLTUTOR_LLM_MODEL)"
echo "vllm:      $(vllm --version 2>/dev/null || echo unknown)"
echo "gpus:      $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | paste -sd ';')"
echo "extra:     ${VLLM_EXTRA_ARGS:-none}"
echo "address:   http://$CONNECT_HOST:$PORT/v1"

# Tell run-backend.sh where to find us. The file holds no secrets, but keep it
# private anyway. Delete it when we stop, so the backend doesn't try a dead
# address. The INT/TERM traps make bash exit normally (running the EXIT trap)
# on Ctrl+C and when Slurm ends the job, instead of dying without cleaning up.
(umask 077 && printf 'VLLM_BASE_URL=http://%s:%s/v1\nVLLM_JOB_ID=%s\n' \
  "$CONNECT_HOST" "$PORT" "${SLURM_JOB_ID:-}" >"$ENDPOINT_FILE")
trap 'rm -f "$ENDPOINT_FILE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --served-model-name: the name /v1/models reports, which the backend's health
# check compares against COBOLTUTOR_LLM_MODEL.
# VLLM_EXTRA_ARGS is intentionally unquoted so it splits into separate flags.
# shellcheck disable=SC2086
vllm serve "$VLLM_MODEL_ID" \
  --served-model-name "$COBOLTUTOR_LLM_MODEL" \
  --host "$VLLM_HOST" \
  --port "$PORT" \
  --max-model-len "$VLLM_MAX_MODEL_LEN" \
  --gpu-memory-utilization "$VLLM_GPU_MEMORY_UTILIZATION" \
  $VLLM_EXTRA_ARGS
