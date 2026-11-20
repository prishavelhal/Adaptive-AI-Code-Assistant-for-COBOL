#!/usr/bin/env bash
# One-time setup for running CobolTutor on the OSU CoE HPC cluster.
#
# Run it on a login node (or in your Advanced Desktop terminal) from the repo root:
#   scripts/cluster/setup.sh
#
# What it does (each step is skipped if it's already done, so re-running is safe):
#   1. Creates a Python virtual environment for vLLM in your HPC share directory
#      and installs vLLM into it. The share has far more space than $HOME,
#      which matters because vLLM and the model weights are tens of GB.
#   2. Generates a random API key for vLLM and saves it, readable only by you,
#      in ~/.config/coboltutor/vllm.env. Other cluster users can reach the
#      port vLLM listens on, so the key keeps them from using your GPU job.
#   3. Installs uv (the tool that runs the backend) into ~/.local/bin if it's missing.
#
# Settings you can override with environment variables:
#   COBOLTUTOR_HPC_DIR  where the venv and model cache go (default ~/hpc-share;
#                       keep in step with the default in serve-vllm.sh)
#   VLLM_VERSION        a vLLM version to install, e.g. 0.11.0 (default: latest).
#                       Pin one before running evaluations, so every teammate
#                       serves the model the same way.
set -euo pipefail

HPC_DIR=${COBOLTUTOR_HPC_DIR:-$HOME/hpc-share}
VENV=$HPC_DIR/vllm-venv
CONFIG_DIR=$HOME/.config/coboltutor
KEY_FILE=$CONFIG_DIR/vllm.env

if [ ! -d "$HPC_DIR" ]; then
  echo "error: $HPC_DIR doesn't exist." >&2
  echo "Set COBOLTUTOR_HPC_DIR to a directory with ~100 GB free (see the HPC docs)." >&2
  exit 1
fi

# --- 1. vLLM virtual environment -------------------------------------------
if [ -x "$VENV/bin/vllm" ]; then
  echo "vLLM is already installed in $VENV"
else
  echo "Creating $VENV and installing vLLM (this downloads several GB)..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --upgrade pip
  if [ -n "${VLLM_VERSION:-}" ]; then
    "$VENV/bin/pip" install "vllm==$VLLM_VERSION"
  else
    "$VENV/bin/pip" install vllm
  fi
fi

# --- 2. API key ------------------------------------------------------------
# umask 077 makes the new directory and file private (owner-only) from the
# moment they're created, instead of fixing permissions afterwards.
if [ -f "$KEY_FILE" ]; then
  echo "API key already exists in $KEY_FILE"
else
  (
    umask 077
    mkdir -p "$CONFIG_DIR"
    # 32 random bytes as hex. Written straight to the file, never printed.
    echo "VLLM_API_KEY=$(openssl rand -hex 32)" >"$KEY_FILE"
  )
  echo "Created a new API key in $KEY_FILE (never commit or share this file)"
fi

# --- 3. uv -------------------------------------------------------------------
if command -v uv >/dev/null 2>&1; then
  echo "uv is already installed"
else
  echo "Installing uv into ~/.local/bin..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  echo "Open a new terminal (or run: source ~/.local/bin/env) so uv is on your PATH."
fi

echo
echo "Done. Next: set VLLM_MODEL_ID in coboltutor/backend/profiles/cluster-vllm.conf,"
echo "then start the model with:  sbatch scripts/cluster/serve-vllm.sbatch"
