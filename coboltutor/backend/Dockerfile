# -----------------------------------------------------------------------------
# CobolTutor backend container image.
#
# Two stages:
#   1. "builder" uses uv to install the locked dependencies into a virtualenv.
#   2. The final image copies only that virtualenv and the source code, so the
#      shipped image doesn't contain uv, build caches, or dev tools.
# -----------------------------------------------------------------------------

FROM python:3.12-slim AS builder

# Copy the uv binary from its official image (pinned to the version used in development).
COPY --from=ghcr.io/astral-sh/uv:0.13.5 /uv /usr/local/bin/uv

WORKDIR /app

# UV_COMPILE_BYTECODE: precompile .py -> .pyc for faster container startup.
# UV_NO_CACHE: don't keep uv's download cache in the image layer (it would only
#   add size, since this stage is thrown away apart from the virtualenv).
#
# Note: this file intentionally avoids BuildKit-only syntax such as
# `RUN --mount=type=cache`, so it also builds with Docker's classic builder.
# Some distros (e.g. Arch) don't install the buildx plugin by default.
ENV UV_COMPILE_BYTECODE=1 \
    UV_NO_CACHE=1

# Install third-party dependencies first, using only the lockfile. Docker caches
# each layer, so this slow step re-runs only when dependencies change, not on
# every source edit.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# Now copy the source and install the project itself into the same virtualenv.
COPY README.md ./
COPY src ./src
RUN uv sync --locked --no-dev --no-editable


FROM python:3.12-slim

# Run as an unprivileged user, not root: a basic container-hardening step.
RUN useradd --create-home --uid 1000 coboltutor
WORKDIR /app
COPY --from=builder --chown=coboltutor:coboltutor /app/.venv /app/.venv

# Put the virtualenv first on PATH so `coboltutor-backend` resolves to it.
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

USER coboltutor
EXPOSE 8000

# Docker (and Compose's depends_on) can use this to tell when the server is up.
# It uses Python's standard library so we don't need curl in the image.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

CMD ["coboltutor-backend"]
