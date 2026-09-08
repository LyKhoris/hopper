#!/usr/bin/env bash
# 10-packages: install everything in packages.txt via yay.
# Uses --needed so already-installed packages are skipped.
# Safe to run twice. Standalone: bash modules/10-packages.sh
# Dry-run: DRY_RUN=1 bash modules/10-packages.sh
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ensure_arch
step "Packages from packages.txt"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "ERROR: do not run yay as root. Run as your normal user." >&2
  exit 1
fi

if ! command -v yay >/dev/null 2>&1; then
  echo "ERROR: yay not found. Run modules/00-bootstrap.sh first." >&2
  exit 1
fi

# steam/gamescope/gamemode live in [multilib]. Enable it here too (not just
# in bootstrap) so this step works standalone with no manual pre-step.
# Same script the scripts step uses — safe to run twice, supports DRY_RUN.
log "Ensuring [multilib] repo (needed for steam/games)..."
DRY_RUN="$DRY_RUN" bash "$HOPPER_ROOT/scripts/10-multilib.sh"

PKG_FILE="$HOPPER_ROOT/packages.txt"
if [ ! -f "$PKG_FILE" ]; then
  echo "ERROR: $PKG_FILE not found." >&2
  exit 1
fi

installed=0
skipped=0
failed=0
failed_list=""

# Read packages.txt, ignore blank lines and # comments (full-line or trailing).
while IFS= read -r line || [ -n "$line" ]; do
  # Strip trailing "# comment", then trim leading/trailing whitespace.
  pkg="$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # Skip empty lines (was blank or comment-only).
  if [ -z "$pkg" ]; then
    continue
  fi
  if is_installed "$pkg"; then
    log "$pkg already installed, skipping."
    skipped=$((skipped + 1))
  else
    log "Installing $pkg..."
    if [ "$DRY_RUN" = "1" ]; then
      echo "+ yay -S --needed --noconfirm $pkg (dry-run, skipped)"
      installed=$((installed + 1))
    else
      if yay -S --needed --noconfirm "$pkg"; then
        installed=$((installed + 1))
      else
        echo "FAILED: $pkg" >&2
        failed=$((failed + 1))
        failed_list="$failed_list $pkg"
      fi
    fi
  fi
done < "$PKG_FILE"

echo ""
log "Packages summary: $installed installed, $skipped skipped, $failed failed."
if [ "$failed" -gt 0 ]; then
  echo "Failed packages:$failed_list" >&2
  exit 1
fi
