#!/usr/bin/env bash
# =============================================================================
# CobolTutor installer for macOS and Linux.   (Windows: install.ps1 / install.cmd)
#
#   ./install.sh              # interactive install
#   ./install.sh --yes        # accept every default, no questions
#   ./install.sh --help       # all options
#
# What it does, in order:
#   1. Checks this computer: OS, CPU, RAM, disk, and GPU (NVIDIA, AMD, Apple).
#   2. Installs Docker if it's missing and makes sure it's running.
#   3. Sets up the GPU path:
#        - Linux + NVIDIA: NVIDIA Container Toolkit, Ollama in Docker on the GPU
#        - Linux + AMD:    Ollama's ROCm image in Docker
#        - macOS:          Ollama installed natively, so it can use Metal
#        - otherwise:      Ollama in Docker on the CPU
#   4. Finds VS Code (or Cursor / VSCodium / Windsurf); installs VS Code if none.
#   5. Downloads the Granite models with a live progress bar. While that runs,
#      the backend image and the VS Code extension build in the background.
#   6. Starts the stack and waits until the backend says the model is ready.
#   7. Installs the CobolTutor extension into every editor it found.
#
# It's safe to run again: finished steps are detected and skipped, and models
# that are already downloaded aren't downloaded again.
#
# Written for the bash 3.2 that ships with macOS: no associative arrays,
# no ${var,,}, no mapfile.
# =============================================================================

set -u -o pipefail

# --- Windows shells (Git Bash, MSYS2, Cygwin): hand off to the PowerShell installer.
case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*)
    here="$(cd "$(dirname "$0")" && pwd)"
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$(cygpath -w "$here/install.ps1")" "$@"
    ;;
esac

# =============================================================================
# Settings. Keep model names and versions in step with coboltutor/docker-compose.yml.
# =============================================================================
CHAT_MODEL="granite4.2:8b"                 # the tutor model
EMBED_MODEL="granite-embedding:278m"       # for the upcoming RAG milestone
NATIVE_MODEL="coboltutor-granite4.2:8b"    # native mode: CHAT_MODEL with a 16k context
OLLAMA_IMAGE="ollama/ollama:0.40.11"       # used to copy models out of the Docker volume
OLLAMA_VOLUME="ollama-models"              # the named volume in docker-compose.yml
NODE_IMAGE="node:22-slim"                  # builds the extension when Node 22+ isn't installed
BACKEND_URL="http://127.0.0.1:8000"
NATIVE_OLLAMA_URL="http://127.0.0.1:11434"
MIN_RAM_GB=8          # below this, Granite 8B won't fit in memory
GOOD_RAM_GB=16        # comfortable
MIN_DISK_GB=12        # models (~5.5 GB) + images (~3 GB) + headroom
MIN_COMPOSE="2.24.0"  # native mode's override uses `!reset`

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/coboltutor"
EXT_DIR="$APP_DIR/extension"
LOG_DIR="$ROOT_DIR/.install-logs/$(date +%Y%m%d-%H%M%S)"

# =============================================================================
# Command-line options
# =============================================================================
ASSUME_YES=0      # --yes
GPU_CHOICE=auto   # --gpu auto|nvidia|amd|metal|cpu
OLLAMA_MODE=auto  # --ollama auto|docker|native
DO_MODELS=1       # --no-models
DO_EXTENSION=1    # --no-extension
DO_EDITOR=1       # --no-editor  (don't install VS Code if no editor is found)
DRY_RUN=0         # --dry-run

usage() {
  cat <<EOF
CobolTutor installer (macOS / Linux)

Usage: ./install.sh [options]

Options:
  -y, --yes             Don't ask questions; accept the defaults.
      --gpu MODE        auto (default), nvidia, amd, metal, or cpu.
      --cpu             Same as --gpu cpu.
      --ollama MODE     Where Ollama runs: auto (default), docker, or native.
                        auto = native on macOS (uses the Apple GPU), Docker on Linux.
      --no-models       Don't download the AI models now.
      --no-extension    Don't build or install the VS Code extension.
      --no-editor       Don't install VS Code if no editor is found.
      --dry-run         Show what would happen without changing anything.
  -h, --help            Show this help.

Environment: NO_COLOR=1 turns off colors.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) ASSUME_YES=1 ;;
    --gpu) GPU_CHOICE="${2:-}"; shift ;;
    --gpu=*) GPU_CHOICE="${1#*=}" ;;
    --cpu) GPU_CHOICE=cpu ;;
    --ollama) OLLAMA_MODE="${2:-}"; shift ;;
    --ollama=*) OLLAMA_MODE="${1#*=}" ;;
    --no-models) DO_MODELS=0 ;;
    --no-extension) DO_EXTENSION=0 ;;
    --no-editor) DO_EDITOR=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

case "$GPU_CHOICE" in auto | nvidia | amd | metal | cpu) ;; *)
  echo "--gpu must be auto, nvidia, amd, metal, or cpu (got '$GPU_CHOICE')" >&2; exit 2 ;;
esac
case "$OLLAMA_MODE" in auto | docker | native) ;; *)
  echo "--ollama must be auto, docker, or native (got '$OLLAMA_MODE')" >&2; exit 2 ;;
esac

# =============================================================================
# Terminal UI: colors, symbols, step headers, spinners, prompts
# =============================================================================
IS_TTY=0
[ -t 1 ] && IS_TTY=1

if [ "$IS_TTY" = 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""
fi

# Unicode symbols only when the terminal's locale is UTF-8; ASCII otherwise.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8* | *utf8* | *UTF8* | *utf-8*)
    S_OK="✔"; S_FAIL="✖"; S_WARN="▲"; S_ARROW="›"; S_DOT="•"; S_BAR="│"
    H_LINE="─"; FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) ;;
  *)
    S_OK="OK"; S_FAIL="X"; S_WARN="!"; S_ARROW=">"; S_DOT="*"; S_BAR="|"
    H_LINE="-"; FRAMES=('|' '/' '-' '\') ;;
esac

TOTAL_STEPS=7
CURRENT_STEP=0

banner() {
  printf '%s' "$C_CYAN$C_BOLD"
  cat <<'EOF'

    ____      _           _ _____      _
   / ___|___ | |__   ___ | |_   _|   _| |_ ___  _ __
  | |   / _ \| '_ \ / _ \| | | || | | | __/ _ \| '__|
  | |__| (_) | |_) | (_) | | | || |_| | || (_) | |
   \____\___/|_.__/ \___/|_| |_| \__,_|\__\___/|_|
EOF
  printf '%s\n' "$C_RESET"
  printf '  %sYour local IBM COBOL tutor %s Granite 4.2 on Ollama %s VS Code%s\n' \
    "$C_DIM" "$S_DOT" "$S_DOT" "$C_RESET"
  [ "$DRY_RUN" = 1 ] && printf '  %s%sDRY RUN: nothing will be changed%s\n' "$C_YELLOW" "$C_BOLD" "$C_RESET"
  echo
}

# A line of $1 copies of $H_LINE.
hrule() { local n=$1 s=""; while [ "$n" -gt 0 ]; do s="$s$H_LINE"; n=$((n - 1)); done; printf '%s' "$s"; }

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  local title="$1" pad=$((52 - ${#1}))
  [ "$pad" -lt 3 ] && pad=3
  printf '\n%s%s[%d/%d]%s %s%s%s %s%s%s\n' "$C_BOLD" "$C_MAGENTA" "$CURRENT_STEP" "$TOTAL_STEPS" \
    "$C_RESET" "$C_BOLD" "$title" "$C_RESET" "$C_DIM" "$(hrule "$pad")" "$C_RESET"
}

ok()   { printf '  %s%s%s %s\n' "$C_GREEN" "$S_OK" "$C_RESET" "$*"; }
warn() { printf '  %s%s%s %s\n' "$C_YELLOW" "$S_WARN" "$C_RESET" "$*"; }
err()  { printf '  %s%s%s %s\n' "$C_RED" "$S_FAIL" "$C_RESET" "$*" >&2; }
info() { printf '  %s%s %s%s\n' "$C_DIM" "$S_ARROW" "$*" "$C_RESET"; }
note() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

die() {
  err "$*"
  [ -d "$LOG_DIR" ] && note "Logs: $LOG_DIR"
  exit 1
}

# "Label ......... value" lines for the summary.
kv() { printf '  %s%-14s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }

# m:ss since $1 (a $SECONDS value).
elapsed() { local s=$((SECONDS - $1)); printf '%d:%02d' $((s / 60)) $((s % 60)); }

# Show the last lines of a log, indented, after a failure.
show_log_tail() {
  [ -s "$1" ] || return 0
  tail -n "${2:-15}" "$1" | while IFS= read -r line; do printf '    %s%s %s%s\n' "$C_DIM" "$S_BAR" "$line" "$C_RESET"; done
  note "Full log: $1"
}

# Wait for background process $1 while showing a spinner labelled $2.
# $3 is its log, shown if it fails. Returns the process's exit code.
spin_wait() {
  local pid=$1 label=$2 log=$3 start=$SECONDS i=0 rc
  if [ "$IS_TTY" = 1 ]; then
    printf '\033[?25l' # hide cursor
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s %s(%s)%s\033[K' "$C_CYAN" "${FRAMES[$((i % ${#FRAMES[@]}))]}" "$C_RESET" \
        "$label" "$C_DIM" "$(elapsed "$start")" "$C_RESET"
      i=$((i + 1))
      sleep 0.1
    done
    printf '\r\033[K\033[?25h'
  fi
  wait "$pid"; rc=$?
  if [ "$rc" = 0 ]; then
    ok "$label ${C_DIM}($(elapsed "$start"))${C_RESET}"
  else
    err "$label failed (exit code $rc)"
    show_log_tail "$log"
  fi
  return "$rc"
}

# run "Label" cmd args...  - run a command with a spinner; output goes to a log.
# Use only for commands that never prompt (sudo is unlocked up front).
run() {
  local label=$1; shift
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] $label: $*"; return 0; fi
  local log
  log="$LOG_DIR/$(printf %s "$label" | tr -cs 'A-Za-z0-9' '-' | tr 'A-Z' 'a-z').log"
  "$@" >"$log" 2>&1 </dev/null &
  spin_wait $! "$label" "$log"
}

# live cmd args... - run a command in the foreground, showing its own output
# (progress bars, installers that may ask for a password).
live() {
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] $*"; return 0; fi
  "$@"
}

# Poll until a command succeeds, with a spinner. wait_until "Label" seconds cmd...
wait_until() {
  local label=$1 timeout=$2; shift 2
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] wait for: $label"; return 0; fi
  local start=$SECONDS i=0
  [ "$IS_TTY" = 1 ] && printf '\033[?25l'
  while ! "$@" >/dev/null 2>&1; do
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      [ "$IS_TTY" = 1 ] && printf '\r\033[K\033[?25h'
      err "$label: gave up after ${timeout}s"
      return 1
    fi
    # Redraw the spinner every 0.1s; re-check the condition every 2s.
    local j=0
    while [ $j -lt 20 ]; do
      [ "$IS_TTY" = 1 ] && printf '\r  %s%s%s %s %s(%s)%s\033[K' "$C_CYAN" \
        "${FRAMES[$((i % ${#FRAMES[@]}))]}" "$C_RESET" "$label" "$C_DIM" "$(elapsed "$start")" "$C_RESET"
      i=$((i + 1)); j=$((j + 1)); sleep 0.1
    done
  done
  [ "$IS_TTY" = 1 ] && printf '\r\033[K\033[?25h'
  ok "$label ${C_DIM}($(elapsed "$start"))${C_RESET}"
}

# confirm "Question?" [Y|N]  - returns 0 for yes. --yes picks the default.
# Reads from /dev/tty so it still works when the script's stdin is a pipe.
confirm() {
  local q=$1 def=${2:-Y} hint ans
  [ "$def" = Y ] && hint="[Y/n]" || hint="[y/N]"
  if [ "$ASSUME_YES" = 1 ] || ! { : </dev/tty; } 2>/dev/null; then
    [ "$def" = Y ]; return
  fi
  printf '  %s?%s %s %s%s%s ' "$C_BLUE$C_BOLD" "$C_RESET" "$q" "$C_DIM" "$hint" "$C_RESET"
  read -r ans </dev/tty || ans=""
  [ -z "$ans" ] && ans=$def
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Restore the cursor and stop background jobs if the user presses Ctrl-C.
BG_PIDS=""
cleanup() {
  [ "$IS_TTY" = 1 ] && printf '\033[?25h'
  for p in $BG_PIDS; do kill "$p" 2>/dev/null; done
}
trap cleanup EXIT
trap 'echo; err "Interrupted."; exit 130' INT TERM

# =============================================================================
# Small helpers
# =============================================================================
have() { command -v "$1" >/dev/null 2>&1; }

# version_ge 2.24.1 2.24.0 -> true.  Compares dotted numbers, ignores suffixes.
version_ge() {
  local a b i x y
  IFS=. read -r -a a <<<"${1%%[-+ ]*}"
  IFS=. read -r -a b <<<"${2%%[-+ ]*}"
  for i in 0 1 2; do
    x=${a[$i]:-0}; y=${b[$i]:-0}
    x=${x//[!0-9]/}; y=${y//[!0-9]/}
    [ "${x:-0}" -gt "${y:-0}" ] && return 0
    [ "${x:-0}" -lt "${y:-0}" ] && return 1
  done
  return 0
}

# Root access: nothing when we're root, sudo otherwise.
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

# Ask for the sudo password once, in the foreground, then keep it fresh so
# commands behind a spinner never stop to prompt invisibly.
SUDO_READY=0
unlock_sudo() {
  [ "$SUDO_READY" = 1 ] && return 0
  [ "$(id -u)" = 0 ] && { SUDO_READY=1; return 0; }
  [ "$DRY_RUN" = 1 ] && { SUDO_READY=1; return 0; }
  have sudo || die "This step needs root and sudo isn't installed. Re-run as root."
  info "Administrator access is needed for the next step."
  sudo -v || die "Couldn't get administrator access."
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  BG_PIDS="$BG_PIDS $!"
  SUDO_READY=1
}

# `docker` may need sudo on Linux until the user logs in again after being
# added to the docker group, so every Docker call goes through these.
DOCKER_SUDO=0
dk() { if [ "$DOCKER_SUDO" = 1 ]; then as_root docker "$@"; else docker "$@"; fi; }
dc() { (cd "$APP_DIR" && dk compose "$@"); }

# Download a URL to a file.
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

# =============================================================================
# Step 1: detect the system
# =============================================================================
OS=""; ARCH=""; DISTRO_ID=""; DISTRO_NAME=""; PKG=""
RAM_GB=0; DISK_GB=0
GPU_KIND=none; GPU_NAME=""; GPU_NOTE=""
HAS_GUI=1

detect_os() {
  ARCH="$(uname -m)"
  case "$(uname -s)" in
    Darwin)
      OS=macos
      DISTRO_NAME="macOS $(sw_vers -productVersion 2>/dev/null)"
      # Bash under Rosetta reports x86_64 on an Apple Silicon Mac.
      [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = 1 ] && ARCH=arm64
      ;;
    Linux)
      OS=linux
      grep -qi microsoft /proc/version 2>/dev/null && OS=wsl
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        DISTRO_ID="$(. /etc/os-release && echo "${ID:-}")"
        DISTRO_NAME="$(. /etc/os-release && echo "${PRETTY_NAME:-Linux}")"
      fi
      if have apt-get; then PKG=apt
      elif have dnf; then PKG=dnf
      elif have pacman; then PKG=pacman
      elif have zypper; then PKG=zypper
      fi
      [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && HAS_GUI=0
      ;;
    *) die "Unsupported OS: $(uname -s). On Windows, run install.cmd instead." ;;
  esac
}

detect_resources() {
  local kb
  if [ "$OS" = macos ]; then
    RAM_GB=$(($(sysctl -n hw.memsize) / 1073741824))
  else
    kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    RAM_GB=$((${kb:-0} / 1048576))
  fi
  # Free space where the models will land: Docker's data dir on Linux, the
  # home folder on macOS (native Ollama keeps models in ~/.ollama).
  local where="$HOME"
  [ "$OS" != macos ] && [ -d /var/lib/docker ] && where=/var/lib/docker
  [ "$OS" != macos ] && [ ! -d /var/lib/docker ] && where=/var/lib
  kb=$(df -Pk "$where" 2>/dev/null | awk 'NR == 2 {print $4}')
  DISK_GB=$((${kb:-0} / 1048576))
}

detect_gpu() {
  if [ "$OS" = macos ]; then
    if [ "$ARCH" = arm64 ]; then
      GPU_KIND=metal
      GPU_NAME="$(sysctl -n machdep.cpu.brand_string 2>/dev/null) (Metal)"
    else
      GPU_NOTE="Intel Macs have no GPU support in Ollama; using the CPU."
    fi
    return
  fi

  # NVIDIA: nvidia-smi works only when the driver is installed and loaded.
  if have nvidia-smi && nvidia-smi -L >/dev/null 2>&1; then
    GPU_KIND=nvidia
    GPU_NAME="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -n1 | sed 's/, / - /')"
    return
  fi

  # Otherwise look at PCI vendor IDs in sysfs (works without lspci).
  local vendors="" v
  for v in /sys/class/drm/card*/device/vendor; do
    [ -r "$v" ] && vendors="$vendors $(cat "$v")"
  done
  case "$vendors" in
    *0x10de*) GPU_NOTE="An NVIDIA GPU is present but its driver isn't installed (no working nvidia-smi). Using the CPU; install the NVIDIA driver and re-run for GPU speed." ;;
  esac
  case "$vendors" in
    *0x1002*)
      if [ -e /dev/kfd ]; then
        GPU_KIND=amd
        GPU_NAME="AMD Radeon (ROCm)"
        have lspci && GPU_NAME="$(lspci 2>/dev/null | grep -iE 'vga|display|3d' | grep -iE 'amd|ati' | head -n1 | sed 's/.*: //') (ROCm)"
      else
        GPU_NOTE="An AMD GPU is present but /dev/kfd is missing (amdgpu/ROCm driver not loaded). Using the CPU."
      fi
      ;;
  esac
}

# Turn detection + options into the plan: where Ollama runs and on what.
ACCEL=cpu            # nvidia | amd | metal | cpu
OVERRIDE=""          # extra compose file, if any
choose_plan() {
  local want=$GPU_CHOICE
  [ "$want" = auto ] && want=$GPU_KIND
  [ "$want" = none ] && want=cpu

  case "$want" in
    metal) [ "$OS" = macos ] || die "--gpu metal only works on macOS." ;;
    nvidia | amd) [ "$OS" = macos ] && die "Docker can't use NVIDIA/AMD GPUs on macOS. Use --gpu metal or cpu." ;;
  esac
  [ "$want" = amd ] && [ "$OS" = wsl ] && die "AMD GPUs aren't supported in Docker under WSL. Run install.cmd on Windows instead."
  ACCEL=$want

  if [ "$OLLAMA_MODE" = auto ]; then
    if [ "$OS" = macos ]; then OLLAMA_MODE=native; else OLLAMA_MODE=docker; fi
  fi
  if [ "$OLLAMA_MODE" = native ] && [ "$OS" != macos ]; then
    # A native Ollama on Linux listens on 127.0.0.1 only, which containers
    # can't reach; making it listen everywhere would expose it to the network.
    die "--ollama native is supported on macOS (and Windows). On Linux, Ollama runs in Docker."
  fi
  if [ "$OLLAMA_MODE" = docker ] && [ "$ACCEL" = metal ]; then
    warn "Docker can't use the Apple GPU, so Ollama in Docker will run on the CPU."
    ACCEL=cpu
  fi

  case "$OLLAMA_MODE:$ACCEL" in
    native:*) OVERRIDE="docker-compose.native-ollama.yml" ;;
    docker:nvidia) OVERRIDE="docker-compose.gpu-nvidia.yml" ;;
    docker:amd) OVERRIDE="docker-compose.gpu-amd.yml" ;;
    *) OVERRIDE="" ;;
  esac
}

accel_label() {
  case "$OLLAMA_MODE:$ACCEL" in
    native:metal) echo "Apple GPU (Metal) ${C_DIM}via Ollama on macOS${C_RESET}" ;;
    native:*) echo "CPU ${C_DIM}via Ollama on macOS${C_RESET}" ;;
    docker:nvidia) echo "NVIDIA GPU ${C_DIM}via Ollama in Docker${C_RESET}" ;;
    docker:amd) echo "AMD GPU (ROCm) ${C_DIM}via Ollama in Docker${C_RESET}" ;;
    *) echo "CPU ${C_DIM}via Ollama in Docker (answers will be slower)${C_RESET}" ;;
  esac
}

step_system() {
  step "Checking your system"
  [ -f "$APP_DIR/docker-compose.yml" ] || die "Can't find coboltutor/docker-compose.yml next to this script. Run it from a clone of the repository."
  detect_os
  detect_resources
  detect_gpu
  choose_plan

  kv "System" "$DISTRO_NAME ($ARCH)"
  kv "Memory" "${RAM_GB} GB"
  kv "Free disk" "${DISK_GB} GB"
  if [ -n "$GPU_NAME" ]; then kv "GPU" "$GPU_NAME"; else kv "GPU" "none usable"; fi
  kv "Granite runs" "$(accel_label)"
  [ -n "$GPU_NOTE" ] && warn "$GPU_NOTE"

  [ "$RAM_GB" -lt "$MIN_RAM_GB" ] && warn "Only ${RAM_GB} GB of RAM: Granite 8B needs about ${MIN_RAM_GB} GB and may not load."
  [ "$RAM_GB" -ge "$MIN_RAM_GB" ] && [ "$RAM_GB" -lt "$GOOD_RAM_GB" ] && note "${RAM_GB} GB of RAM works, but ${GOOD_RAM_GB} GB+ is more comfortable."
  if [ "$DISK_GB" -lt "$MIN_DISK_GB" ]; then
    warn "Only ${DISK_GB} GB free; about ${MIN_DISK_GB} GB is needed for the models and images."
    confirm "Continue anyway?" N || die "Stopped. Free up some disk space and run again."
  fi

  have curl || {
    [ "$OS" = macos ] && die "curl is missing, which shouldn't happen on macOS."
    unlock_sudo
    case "$PKG" in
      apt) run "Installing curl" as_root sh -c 'apt-get update && apt-get install -y curl ca-certificates' ;;
      dnf) run "Installing curl" as_root dnf install -y curl ;;
      pacman) run "Installing curl" as_root pacman -S --needed --noconfirm curl ;;
      zypper) run "Installing curl" as_root zypper --non-interactive install curl ;;
      *) die "Please install curl, then run this again." ;;
    esac || die "Couldn't install curl."
  }

  echo
  confirm "Install CobolTutor with these settings?" Y || { info "Nothing changed. Options: ./install.sh --help"; exit 0; }
}

# =============================================================================
# Step 2: Docker
# =============================================================================
ensure_brew() {
  have brew && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { eval "$("$b" shellenv)"; return 0; }
  done
  info "Homebrew (the macOS package manager) is needed to install the missing software."
  confirm "Install Homebrew from brew.sh?" Y || die "Install Docker Desktop and Ollama yourself, then run this again."
  [ "$DRY_RUN" = 1 ] && { info "[dry-run] install Homebrew"; return 0; }
  # Runs in the foreground because it asks for your password. Homebrew treats
  # any value of NONINTERACTIVE (even 0) as "don't ask", so set it only for --yes.
  local script
  script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
    die "Couldn't download the Homebrew installer."
  if [ "$ASSUME_YES" = 1 ]; then NONINTERACTIVE=1 /bin/bash -c "$script"; else /bin/bash -c "$script"; fi ||
    die "Homebrew didn't install."
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)"
  done
  have brew || die "Homebrew installed, but 'brew' isn't on PATH. Open a new terminal and run this again."
}

docker_ready() { dk info >/dev/null 2>&1; }

install_docker_linux() {
  [ "$OS" = wsl ] && die "Docker isn't available in this WSL distro. Install Docker Desktop on Windows (turn on WSL integration for this distro), or run install.cmd from Windows."
  unlock_sudo
  case "$DISTRO_ID" in
    ubuntu | debian | raspbian | fedora | centos | rhel | sles)
      # Docker's official convenience script: adds Docker's repo and installs
      # Docker Engine plus the compose and buildx plugins.
      run "Downloading Docker's install script" fetch https://get.docker.com "$LOG_DIR/get-docker.sh" &&
        run "Installing Docker Engine" as_root sh "$LOG_DIR/get-docker.sh" && return 0
      warn "Docker's script didn't work here; trying the distro packages."
      ;;
  esac
  case "$PKG" in
    apt)
      run "Installing Docker (apt)" as_root sh -c 'apt-get update && apt-get install -y docker.io &&
        (apt-get install -y docker-compose-v2 || apt-get install -y docker-compose-plugin)' ;;
    dnf)
      run "Adding Docker's package repository" as_root sh -c \
        'curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo' &&
        run "Installing Docker (dnf)" as_root dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin ;;
    pacman)
      run "Installing Docker (pacman)" as_root pacman -S --needed --noconfirm docker docker-compose docker-buildx ;;
    zypper)
      run "Installing Docker (zypper)" as_root zypper --non-interactive install docker docker-compose ;;
    *) die "Don't know how to install Docker on $DISTRO_NAME. Install it (https://docs.docker.com/engine/install/) and run this again." ;;
  esac || die "Docker didn't install."
}

ensure_docker() {
  step "Docker"

  # 2a. Install it if it's missing.
  if ! have docker; then
    if [ "$OS" = macos ]; then
      info "Docker isn't installed. Installing Docker Desktop with Homebrew."
      ensure_brew
      # The cask was called "docker" before 2025 and "docker-desktop" since.
      live brew install --cask docker-desktop || live brew install --cask docker || die "Docker Desktop didn't install."
    else
      info "Docker isn't installed."
      install_docker_linux
    fi
    [ "$DRY_RUN" = 0 ] && ! have docker && die "Docker installed, but the 'docker' command isn't on PATH. Open a new terminal and run this again."
    ok "Docker installed"
  else
    ok "Docker is installed ${C_DIM}($(docker --version 2>/dev/null | sed 's/Docker version //; s/,.*//'))${C_RESET}"
  fi

  # 2b. Make sure the engine is running and we can talk to it.
  if ! docker_ready && [ "$DRY_RUN" = 0 ]; then
    if [ "$OS" = macos ]; then
      if [ -d /Applications/OrbStack.app ]; then open -ga OrbStack
      elif have colima && ! [ -d /Applications/Docker.app ]; then run "Starting Colima" colima start
      else
        open -ga Docker
        note "If Docker Desktop shows its welcome window, accept it so the engine can start."
      fi
      wait_until "Waiting for Docker to start" 300 docker_ready ||
        die "Docker didn't start. Open Docker Desktop, wait for it to say it's running, then run this again."
    else
      # Linux: is the daemon down, or are we just not allowed to use it?
      unlock_sudo
      if [ "$(id -u)" != 0 ] && sudo docker info >/dev/null 2>&1; then
        DOCKER_SUDO=1 # running, but this user isn't in the docker group yet
      else
        have systemctl && run "Starting the Docker service" as_root systemctl enable --now docker
        if docker_ready; then :
        elif [ "$(id -u)" != 0 ] && sudo docker info >/dev/null 2>&1; then DOCKER_SUDO=1
        else die "The Docker service won't start. Check: sudo systemctl status docker"; fi
      fi
      if [ "$DOCKER_SUDO" = 1 ] && [ "$(id -u)" != 0 ]; then
        info "Your user can't use Docker without sudo yet."
        if confirm "Add $USER to the 'docker' group? (lets you run docker without sudo; gives root-level access)" Y; then
          as_root usermod -aG docker "$USER" && ok "Added $USER to the docker group ${C_DIM}(takes effect next time you log in)${C_RESET}"
        fi
        note "This run will use sudo for Docker."
      fi
    fi
  fi
  [ "$DRY_RUN" = 0 ] && ok "Docker engine is running"

  # 2c. Docker Compose v2 (the `docker compose` plugin).
  if ! dk compose version >/dev/null 2>&1; then
    [ "$OS" = macos ] && die "Docker Compose is missing. Update Docker Desktop, then run this again."
    unlock_sudo
    case "$PKG" in
      apt) run "Installing Docker Compose" as_root sh -c 'apt-get update && (apt-get install -y docker-compose-plugin || apt-get install -y docker-compose-v2)' ;;
      dnf) run "Installing Docker Compose" as_root dnf install -y docker-compose-plugin ;;
      pacman) run "Installing Docker Compose" as_root pacman -S --needed --noconfirm docker-compose ;;
      zypper) run "Installing Docker Compose" as_root zypper --non-interactive install docker-compose ;;
      *) false ;;
    esac || die "Couldn't install Docker Compose. See https://docs.docker.com/compose/install/linux/"
  fi
  local cv
  cv="$(dk compose version --short 2>/dev/null | sed 's/^v//')"
  ok "Docker Compose ${C_DIM}(${cv:-unknown})${C_RESET}"
  if [ "$OLLAMA_MODE" = native ] && [ -n "$cv" ] && ! version_ge "$cv" "$MIN_COMPOSE"; then
    die "Docker Compose $cv is too old (need $MIN_COMPOSE+). Update Docker Desktop and run this again."
  fi
}

# =============================================================================
# Step 3: GPU runtime (Linux + NVIDIA) or native Ollama (macOS)
# =============================================================================
nvidia_runtime_ready() { dk info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia; }

install_nvidia_toolkit() {
  unlock_sudo
  case "$PKG" in
    apt)
      run "Adding NVIDIA's package repository" as_root sh -c '
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
          gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
          sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
          > /etc/apt/sources.list.d/nvidia-container-toolkit.list &&
        apt-get update' &&
        run "Installing the NVIDIA Container Toolkit" as_root apt-get install -y nvidia-container-toolkit ;;
    dnf)
      run "Adding NVIDIA's package repository" as_root sh -c \
        'curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo -o /etc/yum.repos.d/nvidia-container-toolkit.repo' &&
        run "Installing the NVIDIA Container Toolkit" as_root dnf install -y nvidia-container-toolkit ;;
    zypper)
      run "Adding NVIDIA's package repository" as_root zypper --non-interactive ar -f \
        https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo &&
        run "Installing the NVIDIA Container Toolkit" as_root zypper --non-interactive --gpg-auto-import-keys install nvidia-container-toolkit ;;
    pacman)
      run "Installing the NVIDIA Container Toolkit" as_root pacman -S --needed --noconfirm nvidia-container-toolkit ;;
    *) return 1 ;;
  esac || return 1
  run "Connecting the toolkit to Docker" as_root nvidia-ctk runtime configure --runtime=docker &&
    run "Restarting Docker" as_root systemctl restart docker
}

# Fall back to CPU when the GPU path can't be set up.
use_cpu_instead() {
  warn "$1"
  warn "Falling back to the CPU. Fix the GPU setup and re-run to switch."
  ACCEL=cpu; OVERRIDE=""
}

OLLAMA_BIN=""
native_ollama_up() { curl -fsS "$NATIVE_OLLAMA_URL/api/version" >/dev/null 2>&1; }

find_ollama_bin() {
  if have ollama; then OLLAMA_BIN="$(command -v ollama)"
  elif [ -x /Applications/Ollama.app/Contents/Resources/ollama ]; then OLLAMA_BIN=/Applications/Ollama.app/Contents/Resources/ollama
  elif [ -x "$HOME/Applications/Ollama.app/Contents/Resources/ollama" ]; then OLLAMA_BIN="$HOME/Applications/Ollama.app/Contents/Resources/ollama"
  else OLLAMA_BIN=""; fi
  [ -n "$OLLAMA_BIN" ]
}

ensure_native_ollama() {
  if find_ollama_bin; then
    ok "Ollama is installed ${C_DIM}($OLLAMA_BIN)${C_RESET}"
  else
    info "Ollama isn't installed. Installing it with Homebrew."
    ensure_brew
    run "Installing Ollama" brew install ollama || die "Ollama didn't install."
    [ "$DRY_RUN" = 1 ] && OLLAMA_BIN=ollama || find_ollama_bin || die "Ollama installed, but the 'ollama' command isn't on PATH."
  fi

  if ! native_ollama_up && [ "$DRY_RUN" = 0 ]; then
    # Prefer the Ollama app if it's there; otherwise run the Homebrew service,
    # which also starts Ollama again after a reboot.
    if [ -d /Applications/Ollama.app ] || [ -d "$HOME/Applications/Ollama.app" ]; then
      open -ga Ollama
    elif have brew && brew list --formula ollama >/dev/null 2>&1; then
      run "Starting the Ollama service" brew services start ollama
    else
      nohup "$OLLAMA_BIN" serve >"$LOG_DIR/ollama-serve.log" 2>&1 &
      note "Started 'ollama serve' for now; start Ollama yourself after a reboot."
    fi
    wait_until "Waiting for Ollama to start" 60 native_ollama_up || die "Ollama didn't start. Try running 'ollama serve' in another terminal."
  fi

  if [ "$DRY_RUN" = 0 ]; then
    local v
    v="$(curl -fsS "$NATIVE_OLLAMA_URL/api/version" | sed 's/.*"version":"\([^"]*\)".*/\1/')"
    if ! version_ge "$v" "${OLLAMA_IMAGE##*:}"; then
      warn "Ollama $v is older than the tested version (${OLLAMA_IMAGE##*:}); Granite 4.2 may not load."
      if have brew && brew list --formula ollama >/dev/null 2>&1 && confirm "Upgrade Ollama with Homebrew?" Y; then
        run "Upgrading Ollama" brew upgrade ollama && run "Restarting the Ollama service" brew services restart ollama
        wait_until "Waiting for Ollama to restart" 60 native_ollama_up
      else
        note "Update it from https://ollama.com/download if the model fails to load."
      fi
    else
      ok "Ollama is running ${C_DIM}(version $v)${C_RESET}"
    fi
  fi
}

step_accel() {
  step "AI runtime"
  if [ "$OLLAMA_MODE" = native ]; then
    ensure_native_ollama
  elif [ "$ACCEL" = nvidia ]; then
    if [ "$OS" = wsl ]; then
      ok "Using Docker Desktop's built-in GPU support (WSL 2)"
    elif [ "$DRY_RUN" = 0 ] && nvidia_runtime_ready; then
      ok "NVIDIA Container Toolkit is set up"
    else
      info "Docker needs the NVIDIA Container Toolkit to use the GPU."
      install_nvidia_toolkit || use_cpu_instead "Couldn't install the NVIDIA Container Toolkit on $DISTRO_NAME."
      [ "$DRY_RUN" = 0 ] && [ "$ACCEL" = nvidia ] && ! nvidia_runtime_ready &&
        use_cpu_instead "Docker still doesn't list the NVIDIA runtime."
      [ "$ACCEL" = nvidia ] && ok "NVIDIA Container Toolkit is set up"
    fi
  elif [ "$ACCEL" = amd ]; then
    ok "Using Ollama's ROCm image ${C_DIM}(passes /dev/kfd and /dev/dri through)${C_RESET}"
  else
    ok "Nothing extra needed for the CPU"
  fi
  write_compose_env
}

# Record the chosen compose files in coboltutor/.env, so a plain
# `docker compose up -d` later uses the same setup. Other lines are kept.
write_compose_env() {
  local env="$APP_DIR/.env" files="docker-compose.yml"
  [ -n "$OVERRIDE" ] && files="$files:$OVERRIDE"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] write COMPOSE_FILE=$files to coboltutor/.env"; return 0; fi
  local tmp="$env.tmp.$$"
  { [ -f "$env" ] && grep -vE '^(COMPOSE_FILE|COMPOSE_PATH_SEPARATOR)=|^# Set by install\.(sh|ps1)' "$env"
    echo "# Set by install.sh: which compose files make up this machine's stack."
    echo "COMPOSE_PATH_SEPARATOR=:"
    echo "COMPOSE_FILE=$files"
  } >"$tmp" && mv "$tmp" "$env"
  ok "Saved the setup to coboltutor/.env ${C_DIM}(COMPOSE_FILE=$files)${C_RESET}"
}

# =============================================================================
# Step 4: code editor
# =============================================================================
EDITOR_NAMES=()   # display names, e.g. "VS Code"
EDITOR_CLIS=()    # matching CLI paths

add_editor() {
  local name=$1 cli=$2 n
  for n in ${EDITOR_NAMES[@]+"${EDITOR_NAMES[@]}"}; do [ "$n" = "$name" ] && return 0; done
  [ -x "$cli" ] || return 0
  EDITOR_NAMES+=("$name"); EDITOR_CLIS+=("$cli")
}

find_editors() {
  EDITOR_NAMES=(); EDITOR_CLIS=()
  local c
  have code && add_editor "VS Code" "$(command -v code)"
  have code-insiders && add_editor "VS Code Insiders" "$(command -v code-insiders)"
  have cursor && add_editor "Cursor" "$(command -v cursor)"
  have codium && add_editor "VSCodium" "$(command -v codium)"
  have windsurf && add_editor "Windsurf" "$(command -v windsurf)"
  if [ "$OS" = macos ]; then
    # Apps whose CLI isn't on PATH ("Install 'code' command" never run).
    for c in /Applications "$HOME/Applications"; do
      add_editor "VS Code" "$c/Visual Studio Code.app/Contents/Resources/app/bin/code"
      add_editor "VS Code Insiders" "$c/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code"
      add_editor "Cursor" "$c/Cursor.app/Contents/Resources/app/bin/cursor"
      add_editor "VSCodium" "$c/VSCodium.app/Contents/Resources/app/bin/codium"
      add_editor "Windsurf" "$c/Windsurf.app/Contents/Resources/app/bin/windsurf"
    done
  fi
}

install_vscode() {
  if [ "$OS" = macos ]; then
    ensure_brew
    live brew install --cask visual-studio-code
    return
  fi
  unlock_sudo
  local arch=x64
  case "$ARCH" in aarch64 | arm64) arch=arm64 ;; armv7l) arch=armhf ;; esac
  case "$PKG" in
    apt)
      run "Downloading VS Code" fetch "https://update.code.visualstudio.com/latest/linux-deb-$arch/stable" "$LOG_DIR/code.deb" &&
        run "Installing VS Code" as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$LOG_DIR/code.deb" ;;
    dnf | zypper)
      run "Trusting Microsoft's signing key" as_root rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
        run "Downloading VS Code" fetch "https://update.code.visualstudio.com/latest/linux-rpm-$arch/stable" "$LOG_DIR/code.rpm" &&
        if [ "$PKG" = dnf ]; then run "Installing VS Code" as_root dnf install -y "$LOG_DIR/code.rpm"
        else run "Installing VS Code" as_root zypper --non-interactive install "$LOG_DIR/code.rpm"; fi ;;
    pacman) run "Installing Code - OSS" as_root pacman -S --needed --noconfirm code ;;
    *)
      if have snap; then run "Installing VS Code (snap)" as_root snap install code --classic
      else return 1; fi ;;
  esac
}

step_editor() {
  step "Code editor"
  if [ "$DO_EXTENSION" = 0 ]; then info "Skipped (--no-extension)"; return; fi
  find_editors
  if [ ${#EDITOR_NAMES[@]} -eq 0 ]; then
    if [ "$DO_EDITOR" = 0 ]; then
      warn "No VS Code-compatible editor found; skipping (--no-editor)."
    elif [ "$OS" = linux ] && [ "$HAS_GUI" = 0 ]; then
      warn "No editor found, and this looks like a machine without a desktop, so VS Code won't be installed."
      note "Using VS Code Remote-SSH? Install the extension from the .vsix this script builds."
    elif [ "$OS" = wsl ]; then
      warn "No editor found. Install VS Code on Windows (it works with WSL), then re-run."
    elif confirm "No VS Code-compatible editor found. Install VS Code?" Y; then
      install_vscode || warn "Couldn't install VS Code automatically. Get it from https://code.visualstudio.com"
      find_editors
    fi
  fi
  local i
  for ((i = 0; i < ${#EDITOR_NAMES[@]}; i++)); do
    ok "${EDITOR_NAMES[$i]} ${C_DIM}(${EDITOR_CLIS[$i]})${C_RESET}"
  done
  [ ${#EDITOR_NAMES[@]} -eq 0 ] && [ "$DRY_RUN" = 0 ] && note "The extension will still be built so you can install it later."
}

# =============================================================================
# Step 5: models (foreground, with progress) + builds (background)
# =============================================================================
VSIX=""
EXT_VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$EXT_DIR/package.json" 2>/dev/null | head -n1)"
PNPM_VERSION="$(sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p' "$EXT_DIR/package.json" 2>/dev/null | head -n1)"

host_node_ok() {
  have node && have npx || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)"
  [ "${major:-0}" -ge 22 ]
}

# Builds coboltutor/extension/coboltutor-<version>.vsix. Uses Node on this
# machine if it's new enough; otherwise builds inside a Node container, so
# nobody has to install Node just to get the extension.
build_extension() {
  if host_node_ok; then
    echo ">>> Building with Node $(node -v) on this machine"
    (cd "$EXT_DIR" && npx --yes "pnpm@$PNPM_VERSION" install --frozen-lockfile &&
      npx --yes "pnpm@$PNPM_VERSION" run package) && return 0
    echo ">>> Local build failed; trying again in a container"
  fi
  echo ">>> Building in $NODE_IMAGE"
  # Copy the sources (minus any node_modules from this OS) into the container,
  # build there, and copy only the finished .vsix back out.
  dk run --rm -v "$EXT_DIR:/src" -e PNPM_VERSION="$PNPM_VERSION" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" "$NODE_IMAGE" sh -euc '
      mkdir /build
      tar -C /src --exclude=./node_modules --exclude=./dist --exclude="./*.vsix" -cf - . | tar -C /build -xf -
      cd /build
      npx --yes "pnpm@$PNPM_VERSION" install --frozen-lockfile
      npx --yes "pnpm@$PNPM_VERSION" run package
      cp ./*.vsix /src/
      chown "$HOST_UID:$HOST_GID" /src/*.vsix'
}

BACKEND_PID=""; EXTENSION_PID=""
start_background_builds() {
  if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] background: docker compose build backend"
    [ "$DO_EXTENSION" = 1 ] && info "[dry-run] background: build coboltutor-$EXT_VERSION.vsix"
    return
  fi
  dc build backend >"$LOG_DIR/backend-build.log" 2>&1 </dev/null &
  BACKEND_PID=$!; BG_PIDS="$BG_PIDS $BACKEND_PID"
  info "Building the backend image in the background"
  if [ "$DO_EXTENSION" = 1 ]; then
    build_extension >"$LOG_DIR/extension-build.log" 2>&1 </dev/null &
    EXTENSION_PID=$!; BG_PIDS="$BG_PIDS $EXTENSION_PID"
    info "Building the VS Code extension in the background"
  fi
}

# Run `ollama pull` with its own progress bar; retry, since big downloads
# fail now and then and Ollama resumes where it stopped.
pull_model() {
  local model=$1 try
  printf '\n  %s%s%s %sDownloading %s%s\n' "$C_CYAN" "$S_ARROW" "$C_RESET" "$C_BOLD" "$model" "$C_RESET"
  for try in 1 2 3; do
    if [ "$OLLAMA_MODE" = native ]; then
      live "$OLLAMA_BIN" pull "$model" && return 0
    else
      local tty_flag=""
      [ -t 0 ] && [ -t 1 ] || tty_flag="-T"
      live dc exec $tty_flag ollama ollama pull "$model" && return 0
    fi
    [ "$try" -lt 3 ] && warn "Download interrupted; retrying ($try/3)..." && sleep 3
  done
  return 1
}

# Native mode on a machine that ran the Docker setup before: the models are
# already in the ollama-models volume, so copy them instead of downloading
# ~5 GB again. Ollama's model store is the same format in both places.
reuse_docker_models() {
  [ "$DRY_RUN" = 1 ] && return 0
  local dest="${OLLAMA_MODELS:-$HOME/.ollama/models}"
  local manifest="manifests/registry.ollama.ai/library/${CHAT_MODEL%%:*}/${CHAT_MODEL##*:}"
  [ -f "$dest/$manifest" ] && return 0
  dk volume inspect "$OLLAMA_VOLUME" >/dev/null 2>&1 || return 0
  dk image inspect "$OLLAMA_IMAGE" >/dev/null 2>&1 || return 0
  dk run --rm --entrypoint test -v "$OLLAMA_VOLUME:/src:ro" "$OLLAMA_IMAGE" -f "/src/models/$manifest" 2>/dev/null || return 0
  mkdir -p "$dest"
  run "Copying models you already downloaded for Docker" \
    dk run --rm --entrypoint cp -v "$OLLAMA_VOLUME:/src:ro" -v "$dest:/dst" "$OLLAMA_IMAGE" -a /src/models/. /dst/ ||
    warn "Couldn't copy them; downloading instead."
}

ollama_container_up() { dc exec -T ollama ollama list; }

start_docker_ollama() {
  live dc pull ollama || die "Couldn't download the Ollama image. Check your internet connection."
  if ! run "Starting Ollama" dc up -d --wait ollama; then
    if [ "$ACCEL" != cpu ]; then
      use_cpu_instead "Ollama didn't start with the $(echo "$ACCEL" | tr a-z A-Z) GPU."
      write_compose_env
      run "Starting Ollama on the CPU" dc up -d --wait ollama || die "Ollama didn't start. See: docker compose logs ollama"
    else
      die "Ollama didn't start. See: cd coboltutor && docker compose logs ollama"
    fi
  fi
  # Ollama logs which compute it found at startup; tell the user if the GPU
  # wasn't picked up even though the container started.
  if [ "$ACCEL" != cpu ] && [ "$DRY_RUN" = 0 ]; then
    sleep 2
    if dc logs ollama 2>/dev/null | grep -i 'inference compute' | grep -qiE 'library=(cuda|rocm)'; then
      ok "Ollama is using the GPU"
    else
      warn "Ollama started, but its log doesn't show the GPU. Check: docker compose logs ollama | grep -i compute"
    fi
  fi
}

step_models() {
  step "AI models + builds"
  [ "$DRY_RUN" = 0 ] && mkdir -p "$LOG_DIR"

  # Docker mode: Ollama has to be running before models can be pulled.
  [ "$OLLAMA_MODE" = docker ] && [ "$DO_MODELS" = 1 ] && start_docker_ollama

  # Kick off the slow builds now, so they run while the models download.
  start_background_builds

  if [ "$DO_MODELS" = 0 ]; then
    info "Skipping model downloads (--no-models). They'll download on the first 'docker compose up'."
    return
  fi
  [ "$OLLAMA_MODE" = native ] && reuse_docker_models

  note "Granite 4.2 8B is about 5 GB, so this can take a while. Safe to stop and re-run: downloads resume."
  pull_model "$CHAT_MODEL" || die "Couldn't download $CHAT_MODEL. Check your connection and run this again; it resumes."
  pull_model "$EMBED_MODEL" || warn "Couldn't download $EMBED_MODEL (not used yet; it'll be retried next time)."
  echo

  if [ "$OLLAMA_MODE" = native ]; then
    # A copy of the model with a 16k context window; see coboltutor/ollama/Modelfile.
    run "Setting Granite's context window to 16k" \
      sh -c "cd '$APP_DIR' && '$OLLAMA_BIN' create '$NATIVE_MODEL' -f ollama/Modelfile" ||
      die "Couldn't create $NATIVE_MODEL."
  fi
  ok "Models are ready"
}

# =============================================================================
# Step 6: start the stack
# =============================================================================
backend_ready() { curl -fsS "$BACKEND_URL/health" 2>/dev/null | grep -q '"model_ready": *true'; }

step_start() {
  step "Starting CobolTutor"
  if [ -n "$BACKEND_PID" ]; then
    spin_wait "$BACKEND_PID" "Building the backend image" "$LOG_DIR/backend-build.log" || die "The backend image didn't build."
  fi

  if [ "$OLLAMA_MODE" = native ] && [ "$DRY_RUN" = 0 ]; then
    # Switching from the Docker setup: stop its Ollama so it isn't using memory
    # (its downloaded models stay in the ollama-models volume).
    # Found by label: compose itself ignores services its profiles turned off.
    local ids
    ids="$(dk ps -aq --filter label=com.docker.compose.project=coboltutor \
      --filter label=com.docker.compose.service=ollama 2>/dev/null)
$(dk ps -aq --filter label=com.docker.compose.project=coboltutor \
      --filter label=com.docker.compose.service=ollama-pull 2>/dev/null)"
    ids="$(echo "$ids" | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
    if [ -n "$ids" ]; then
      # shellcheck disable=SC2086 # word-splitting the id list is intended
      run "Removing the Ollama container (this Mac uses native Ollama)" dk rm -f $ids
    fi
  fi

  # --remove-orphans tidies containers left from older versions of the stack.
  run "Starting the services" dc up -d --remove-orphans || die "The stack didn't start. See: cd coboltutor && docker compose logs"

  if [ "$DO_MODELS" = 1 ]; then
    wait_until "Waiting for the tutor to be ready" 180 backend_ready ||
      die "The backend is up but the model isn't ready. Check: curl $BACKEND_URL/health"
  else
    wait_until "Waiting for the backend" 60 curl -fsS "$BACKEND_URL/health" || warn "The backend isn't answering yet."
  fi
}

# =============================================================================
# Step 7: the VS Code extension
# =============================================================================
step_extension() {
  step "VS Code extension"
  if [ "$DO_EXTENSION" = 0 ]; then info "Skipped (--no-extension)"; return; fi
  if [ -n "$EXTENSION_PID" ]; then
    spin_wait "$EXTENSION_PID" "Building the extension" "$LOG_DIR/extension-build.log" ||
      die "The extension didn't build."
  fi
  VSIX="$EXT_DIR/coboltutor-$EXT_VERSION.vsix"
  if [ "$DRY_RUN" = 1 ]; then info "[dry-run] install $VSIX into: ${EDITOR_NAMES[*]:-no editors found}"; return; fi
  [ -f "$VSIX" ] || die "The build finished but $VSIX is missing."
  ok "Built ${VSIX#"$ROOT_DIR"/}"

  local i failed=0
  for ((i = 0; i < ${#EDITOR_NAMES[@]}; i++)); do
    run "Installing into ${EDITOR_NAMES[$i]}" "${EDITOR_CLIS[$i]}" --install-extension "$VSIX" --force || failed=1
  done
  [ "$failed" = 1 ] && note "To install by hand: Extensions view $S_ARROW ... menu $S_ARROW Install from VSIX $S_ARROW $VSIX"
}

# =============================================================================
# Done
# =============================================================================
finish() {
  local mod="Ctrl"
  [ "$OS" = macos ] && mod="Cmd"
  echo
  printf '  %s%s%s\n' "$C_GREEN" "$(hrule 58)" "$C_RESET"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s%s Dry run finished: nothing was changed.%s\n' "$C_BOLD" "$S_OK" "$C_RESET"
  else
    printf '  %s%s%s CobolTutor is installed!%s\n' "$C_GREEN" "$C_BOLD" "$S_OK" "$C_RESET"
  fi
  printf '  %s%s%s\n\n' "$C_GREEN" "$(hrule 58)" "$C_RESET"
  kv "Running on" "$(accel_label)"
  kv "Backend" "$BACKEND_URL"
  [ ${#EDITOR_NAMES[@]} -gt 0 ] && kv "Extension in" "$(printf '%s, ' "${EDITOR_NAMES[@]}" | sed 's/, $//')"
  echo
  printf '  %sTry it%s\n' "$C_BOLD" "$C_RESET"
  echo "    1. Open a COBOL file in VS Code (try coboltutor/examples/PAYROLL.cbl)."
  echo "    2. Select some code and press $mod+Alt+E, or right-click $S_ARROW Explain Selected Code."
  echo "    3. Or click the CobolTutor icon in the activity bar and ask a question."
  echo
  printf '  %sManage it%s %s(from the coboltutor/ folder)%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  echo "    docker compose up -d      start (it also restarts by itself after a reboot)"
  echo "    docker compose down       stop (models are kept)"
  echo "    docker compose logs -f    see what it's doing"
  [ "$OLLAMA_MODE" = native ] && note "Ollama runs on this Mac outside Docker; keep it running (menu bar app or 'brew services')."
  [ -d "$LOG_DIR" ] && note "Install logs: ${LOG_DIR#"$ROOT_DIR"/}"
  [ "$DOCKER_SUDO" = 1 ] && note "Log out and back in to use docker without sudo. Until then: sudo docker compose ..."
  echo
}

main() {
  banner
  [ "$DRY_RUN" = 0 ] && mkdir -p "$LOG_DIR"
  step_system
  ensure_docker
  step_accel
  step_editor
  step_models
  step_start
  step_extension
  finish
}

main
