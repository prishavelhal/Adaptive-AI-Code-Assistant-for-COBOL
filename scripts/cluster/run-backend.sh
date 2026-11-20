#!/usr/bin/env bash
# Start the CobolTutor backend against the vLLM server started by serve-vllm.sh
# (or by the serve-vllm.sbatch batch job).
#
# Run it in your Advanced Desktop session (where VS Code runs), from anywhere
# in the repo:
#   scripts/cluster/run-backend.sh
#
# It loads profiles/cluster-vllm.conf, finds the vLLM job's address in
# ~/.config/coboltutor/vllm-endpoint, waits until the model is loaded, and
# then runs the backend on http://127.0.0.1:8000 (the extension's default).
# Stop it with Ctrl+C. Stopping the backend does NOT stop the model server;
# stop that in its own terminal (or `scancel <jobid>` for a batch job).
#
# Options (environment variables):
#   VLLM_BASE_URL    use this vLLM address instead of the endpoint file
#                    (e.g. http://localhost:8001/v1 through an SSH tunnel)
#   COBOLTUTOR_PORT  backend port, if 8000 is taken by another user on the node.
#                    Also change the "coboltutor.backendUrl" setting in VS Code.
set -euo pipefail

# Find the repo from this script's location, so it works from any directory.
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BACKEND_DIR=$REPO_DIR/coboltutor/backend
CONFIG_DIR=$HOME/.config/coboltutor
ENDPOINT_FILE=$CONFIG_DIR/vllm-endpoint

# `set -a` exports everything the files set, so the backend process sees it.
set -a
# shellcheck source=SCRIPTDIR/../../coboltutor/backend/profiles/cluster-vllm.conf
source "$BACKEND_DIR/profiles/cluster-vllm.conf"
# shellcheck source=/dev/null
source "$CONFIG_DIR/vllm.env"
set +a

# --- Where is vLLM? ---------------------------------------------------------
if [ -z "${VLLM_BASE_URL:-}" ]; then
  if [ ! -f "$ENDPOINT_FILE" ]; then
    echo "error: no running vLLM server found ($ENDPOINT_FILE is missing)." >&2
    echo "Start one in another terminal with:  scripts/cluster/serve-vllm.sh" >&2
    echo "(or as a batch job: sbatch scripts/cluster/serve-vllm.sbatch)" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$ENDPOINT_FILE"
  FROM_ENDPOINT_FILE=1
  # The file can outlive its server if it was killed hard (e.g. the desktop
  # session or batch job hit its time limit). VLLM_JOB_ID is the Slurm job the
  # server ran in: your desktop session's job, or the batch job.
  if [ -n "$VLLM_JOB_ID" ] && command -v squeue >/dev/null 2>&1 &&
    [ -z "$(squeue -h -j "$VLLM_JOB_ID" 2>/dev/null)" ]; then
    echo "error: the Slurm job vLLM ran in ($VLLM_JOB_ID) has ended. Start the server again." >&2
    rm -f "$ENDPOINT_FILE"
    exit 1
  fi
fi
echo "vLLM: $VLLM_BASE_URL"

# --- Wait for the model to load -----------------------------------------------
# vLLM's /health (outside /v1, no API key needed) returns 200 once the model
# is loaded. Loading 30B takes a few minutes, longer on the first download.
HEALTH_URL=${VLLM_BASE_URL%/v1}/health
printf 'Waiting for the model to load'
for _ in $(seq 1 180); do # 180 x 5 s = 15 minutes
  if curl -sf -o /dev/null "$HEALTH_URL"; then
    echo " ready."
    break
  fi
  # serve-vllm.sh deletes the endpoint file when it exits, so if it's gone the
  # server crashed while loading (e.g. out of GPU memory): stop waiting.
  if [ -n "${FROM_ENDPOINT_FILE:-}" ] && [ ! -f "$ENDPOINT_FILE" ]; then
    echo
    echo "error: the vLLM server stopped while loading the model. Check its output." >&2
    exit 1
  fi
  printf '.'
  sleep 5
done
if ! curl -sf -o /dev/null "$HEALTH_URL"; then
  echo
  echo "error: vLLM at $HEALTH_URL didn't become ready in 15 minutes." >&2
  echo "Check the output of serve-vllm.sh (for a batch job: granite-vllm-<jobid>.log)." >&2
  exit 1
fi

# --- Start the backend ----------------------------------------------------------
export COBOLTUTOR_LLM_BASE_URL=$VLLM_BASE_URL
# The backend sends this as "Authorization: Bearer <key>". Exported, not
# passed as an argument, so it doesn't show up in `ps`.
export COBOLTUTOR_LLM_API_KEY=$VLLM_API_KEY
echo "Backend: http://127.0.0.1:${COBOLTUTOR_PORT:-8000} (model $COBOLTUTOR_LLM_MODEL)"
cd "$BACKEND_DIR"
exec uv run coboltutor-backend
