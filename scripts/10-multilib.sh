#!/usr/bin/env bash
# 10-multilib: enable the [multilib] repo in /etc/pacman.conf if disabled.
# Needed for steam, gamescope, gamemode (32-bit libs).
# Safe to run twice. DRY_RUN=1 supported.
HOPPER_TITLE="Enable multilib repo"
set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"

step_enable() { echo ""; echo "=== $* ==="; }

step_enable "multilib repo"

if [ ! -f "$PACMAN_CONF" ]; then
  echo "ERROR: $PACMAN_CONF not found. Not an Arch system?" >&2
  exit 1
fi

# Already enabled? [multilib] uncommented means active.
if grep -q "^\[multilib\]" "$PACMAN_CONF"; then
  echo "[hopper] [multilib] already enabled, skipping."
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

# Uncomment [multilib] and its Include line (only the block right after it).
sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$PACMAN_CONF"

# Verify it worked.
if grep -q "^\[multilib\]" "$PACMAN_CONF"; then
  echo "[hopper] [multilib] enabled. Refreshing package databases..."
  sudo pacman -Sy
else
  echo "ERROR: failed to enable [multilib]. Check $PACMAN_CONF manually." >&2
  exit 1
fi
