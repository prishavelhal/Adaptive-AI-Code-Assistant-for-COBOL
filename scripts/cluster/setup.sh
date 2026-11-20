#!/usr/bin/env bash
# One-time setup for running CobolTutor on the OSU CoE HPC cluster.
#
# Run it on a login node (or in your Advanced Desktop terminal) from the repo root:
#   scripts/cluster/setup.sh
#
# What it does (each step is skipped if it's already done, so re-running is safe):
#   1. Installs uv into ~/.local/bin if it's missing. uv installs Python
#      packages and can download its own Python, which we need: the cluster's
#      system python3 is 3.9, and current vLLM requires 3.10 or newer.
#   2. Creates a Python 3.12 virtual environment for vLLM in your HPC share and
#      installs vLLM into it. The share has far more space than $HOME, which
#      matters because vLLM and its dependencies (PyTorch, CUDA libraries) are
#      many GB. All caches go to the share too (see env.sh).
#   3. Generates a random API key for vLLM and saves it, readable only by you,
#      in ~/.config/coboltutor/vllm.env. Other users on the node could otherwise
#      connect to vLLM and use your GPU.
#
# Settings you can override with environment variables:
#   COBOLTUTOR_HPC_DIR  where the venv and caches go (default ~/hpc-share; see env.sh)
#   VLLM_VERSION        a vLLM version to install, e.g. 0.11.0 (default: latest).
#                       Pin one before running evaluations, so every teammate
#                       serves the model the same way.
set -euo pipefail

# Shared settings: HPC_DIR and the cache locations.
# shellcheck source=SCRIPTDIR/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

VENV=$HPC_DIR/vllm-venv
PYTHON_VERSION=3.12
CONFIG_DIR=$HOME/.config/coboltutor
KEY_FILE=$CONFIG_DIR/vllm.env

if [ ! -d "$HPC_DIR" ]; then
  echo "error: $HPC_DIR doesn't exist." >&2
  echo "Set COBOLTUTOR_HPC_DIR to a directory with ~100 GB free (see the HPC docs)." >&2
  exit 1
fi

# --- 1. uv -------------------------------------------------------------------
if command -v uv >/dev/null 2>&1; then
  echo "uv is already installed ($(uv --version))"
else
  echo "Installing uv into ~/.local/bin..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- 2. vLLM virtual environment -------------------------------------------
if [ -x "$VENV/bin/vllm" ]; then
  echo "vLLM is already installed in $VENV"
else
  # A venv without vLLM is left over from a failed install (for example one
  # made with the system Python 3.9). Start fresh rather than reuse it.
  if [ -f "$VENV/pyvenv.cfg" ]; then
    echo "Removing the incomplete environment in $VENV..."
    rm -rf "$VENV"
  fi
  echo "Creating $VENV with Python $PYTHON_VERSION..."
  # uv downloads Python $PYTHON_VERSION into UV_PYTHON_INSTALL_DIR if needed.
  uv venv --python "$PYTHON_VERSION" "$VENV"
  echo "Installing vLLM (this downloads several GB)..."
  # --torch-backend=auto picks the PyTorch build that matches this node's
  # CUDA driver, as vLLM's install docs recommend.
  uv pip install --python "$VENV/bin/python" --torch-backend=auto \
    "vllm${VLLM_VERSION:+==$VLLM_VERSION}"
fi
echo "vLLM version: $("$VENV/bin/vllm" --version 2>/dev/null || echo unknown)"

# --- 3. API key ------------------------------------------------------------
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

echo
echo "Done. Next: set VLLM_MODEL_ID in coboltutor/backend/profiles/cluster-vllm.conf,"
echo "then start the model with:  scripts/cluster/serve-vllm.sh"
