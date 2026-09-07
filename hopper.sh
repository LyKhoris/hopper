#!/usr/bin/env bash
# hopper.sh — remote entrypoint. Pipe it straight from GitHub, no manual install.
#
#   curl -fsSL https://lykhoris.github.io/hopper | bash -s -- --yes
#   (fallback) bash <(curl -fsSL https://raw.githubusercontent.com/LyKhoris/hopper/main/hopper.sh) --yes
#
# What it installs: NOTHING extra, except the bare minimum to fetch + run hopper:
#   - git (via pacman, only if missing — needed to clone the repo)
# Everything else (packages, fcitx, tablet fix, multilib) is done by the repo's
# own modules, which you can review on GitHub before running.
#
# Env overrides:
#   HOPPER_REPO=...  git URL (default below — CHANGE to your repo)
#   HOPPER_DIR=...   where to clone (default ~/.local/share/hopper)
#   HOPPER_BRANCH=.. branch (default main)
set -euo pipefail

# Your repo URL (change the username if you fork/rename).
HOPPER_REPO="${HOPPER_REPO:-https://github.com/LyKhoris/hopper.git}"
HOPPER_DIR="${HOPPER_DIR:-$HOME/.local/share/hopper}"
HOPPER_BRANCH="${HOPPER_BRANCH:-main}"

say() { echo "[hopper-remote] $*"; }

# 1. If we already sit inside a hopper checkout (local dev), just run it.
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"
if [ -f "$SELF_DIR/run.sh" ] && [ -d "$SELF_DIR/modules" ]; then
  say "Local checkout detected, running ./run.sh ..."
  exec bash "$SELF_DIR/run.sh" "$@"
fi

# 2. Arch check — fail fast with a clear message.
if ! command -v pacman >/dev/null 2>&1; then
  echo "ERROR: pacman not found. Hopper only supports Arch-based distros." >&2
  exit 1
fi

# 3. Minimal dep: git, only if missing. This is the ONLY install hopper.sh does itself.
if ! command -v git >/dev/null 2>&1; then
  say "git missing, installing git (only extra package)..."
  sudo pacman -S --needed --noconfirm git
else
  say "git found."
fi

# 4. Clone or update the repo (no build, no bun, no node needed for bash mode).
# HOPPER_DIR is a disposable cache, never a workspace, so a cache that can't
# fast-forward (diverged, shallow-clone quirks) is reset to the remote instead
# of silently running stale code. Run logs (untracked) survive the reset.
if [ -d "$HOPPER_DIR/.git" ]; then
  say "Updating $HOPPER_DIR ($HOPPER_BRANCH)..."
  if git -C "$HOPPER_DIR" fetch --depth 1 origin "$HOPPER_BRANCH" >/dev/null 2>&1; then
    if git -C "$HOPPER_DIR" checkout -q -B "$HOPPER_BRANCH" FETCH_HEAD >/dev/null 2>&1; then
      say "Now at $(git -C "$HOPPER_DIR" rev-parse --short HEAD)."
    else
      echo "WARNING: downloaded the update but couldn't apply it. Running the local copy — may be outdated." >&2
    fi
  else
    echo "WARNING: can't reach GitHub (offline?). Running the local copy from $(git -C "$HOPPER_DIR" log -1 --format=%cs 2>/dev/null || echo an unknown date) — may be outdated." >&2
  fi
else
  say "Cloning $HOPPER_REPO -> $HOPPER_DIR ..."
  rm -rf "$HOPPER_DIR"
  git clone --depth 1 --branch "$HOPPER_BRANCH" "$HOPPER_REPO" "$HOPPER_DIR"
fi

say "Running hopper from $HOPPER_DIR ..."
exec bash "$HOPPER_DIR/run.sh" "$@"
