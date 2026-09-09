#!/usr/bin/env bash
# 10-multilib: enable the [multilib] repo in /etc/pacman.conf if disabled.
# Needed for steam, gamescope, gamemode (32-bit libs).
# Safe to run twice. DRY_RUN=1 supported.
HOPPER_TITLE="Enable multilib repo"
# This script supports `--check`: exit 0 = already applied, exit 1 = work to do.
SUPPORTS_CHECK=1
set -euo pipefail

if [ "${1:-}" = "--check" ]; then
  if grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null \
    && grep -q "^Include" /etc/pacman.conf 2>/dev/null; then
    exit 0
  else
    exit 1
  fi
fi

PACMAN_CONF="/etc/pacman.conf"

step_enable() { echo ""; echo "=== $* ==="; }

step_enable "multilib repo"

if [ ! -f "$PACMAN_CONF" ]; then
  echo "ERROR: $PACMAN_CONF not found. Not an Arch system?" >&2
  exit 1
fi

# Already enabled? [multilib] header + an active Include line means active.
if grep -q "^\[multilib\]" "$PACMAN_CONF" && grep -q "^Include" "$PACMAN_CONF"; then
  # Quiet unless HOPPER_VERBOSE=1 (the preview already listed this skip).
  if [ "${HOPPER_VERBOSE:-0}" = "1" ]; then
    echo "[hopper] [multilib] already enabled, skipping."
  fi
  exit 0
fi

# Only commented version found -> enable it.
if ! grep -q "^#\[multilib\]" "$PACMAN_CONF"; then
  echo "[hopper] No [multilib] section found in $PACMAN_CONF, nothing to do."
  exit 0
fi

echo "[hopper] Enabling [multilib] in $PACMAN_CONF ..."
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "+ sudo cp -n $PACMAN_CONF ${PACMAN_CONF}.bak (dry-run, skipped)"
  echo "+ sudo sed -i multilib uncomment (dry-run, skipped)"
  echo "+ sudo pacman -Sy (dry-run, skipped)"
  exit 0
fi

# Back up once (never overwrite existing backup).
sudo cp -n "$PACMAN_CONF" "${PACMAN_CONF}.bak" || true

# Uncomment only the [multilib] header and its Include line (not the whole
# range, and not Include lines in other sections).
sudo sed -i -e '/^#\[multilib\]/,/^#Include/ s/^#\(\[multilib\]\|Include.*mirrorlist\)/\1/' "$PACMAN_CONF"

# Verify it worked.
if grep -q "^\[multilib\]" "$PACMAN_CONF"; then
  echo "[hopper] [multilib] enabled. Refreshing package databases..."
  sudo pacman -Sy
else
  echo "ERROR: failed to enable [multilib]. Check $PACMAN_CONF manually." >&2
  exit 1
fi
