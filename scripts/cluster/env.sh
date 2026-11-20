# Shared settings for the scripts in scripts/cluster/. Sourced by them, not run.
#
# Why this exists: on the cluster your home directory (/nfs/stak/users/...) has
# a small quota, and pip, uv, vLLM, Hugging Face and Triton all cache gigabytes
# of files under ~/.cache by default. Filling the quota breaks installs with
# "No space left on device". So every cache is pointed at the HPC share instead.
#
# Override the location with:  export COBOLTUTOR_HPC_DIR=/some/other/dir
# shellcheck shell=bash

HPC_DIR=${COBOLTUTOR_HPC_DIR:-$HOME/hpc-share}

# pip, uv and vLLM keep their caches under $XDG_CACHE_HOME (default ~/.cache).
export XDG_CACHE_HOME=$HPC_DIR/.cache
# Python interpreters that uv downloads (default ~/.local/share/uv/python).
# The cluster's system Python is too old for vLLM, so uv provides 3.12.
export UV_PYTHON_INSTALL_DIR=$HPC_DIR/uv-python
# Model weights from Hugging Face (tens of GB). Later runs reuse them.
export HF_HOME=$HPC_DIR/hf-cache
# Compiled GPU kernels (default ~/.triton, which ignores XDG_CACHE_HOME).
export TRITON_CACHE_DIR=$XDG_CACHE_HOME/triton

# uv's own installer puts the uv binary in ~/.local/bin (small, ~40 MB).
# Add it here so the scripts find uv even before you open a new terminal.
export PATH=$HOME/.local/bin:$PATH
