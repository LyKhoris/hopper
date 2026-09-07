#!/usr/bin/env bash
# 00-bootstrap: verify Arch, ensure base-devel+git, install yay if missing.
# Safe to run twice. Standalone: bash modules/00-bootstrap.sh
# Dry-run: DRY_RUN=1 bash modules/00-bootstrap.sh
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ensure_arch
step "Bootstrap (base-devel, git, yay)"

# yay must NEVER run as root. Refuse early with a clear message.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "ERROR: run hopper as your normal user, not root. sudo is used only where needed." >&2
  exit 1
fi

# Prompt for sudo once so later steps don't pause mid-way.
log "Checking sudo access..."
run sudo -v

# base-devel + git are required for AUR builds (yay) and for fetching repos.
log "Ensuring base-devel + git..."
run sudo pacman -Syu --needed --noconfirm base-devel git

# Install yay-bin (prebuilt, faster than building yay from source).
if command -v yay >/dev/null 2>&1; then
  log "yay already installed, skipping."
else
  log "yay not found, installing yay-bin..."
  TMPDIR_YAY="/tmp/yay-bin-hopper"
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ git clone https://aur.archlinux.org/yay-bin.git $TMPDIR_YAY (dry-run, skipped)"
    echo "+ makepkg -si --noconfirm in $TMPDIR_YAY (dry-run, skipped)"
  else
    rm -rf "$TMPDIR_YAY"
    git clone https://aur.archlinux.org/yay-bin.git "$TMPDIR_YAY"
    (cd "$TMPDIR_YAY" && makepkg -si --noconfirm)
    rm -rf "$TMPDIR_YAY"
  fi
  log "yay installed."
fi

log "Bootstrap done."
