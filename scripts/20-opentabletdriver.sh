#!/usr/bin/env bash
# 20-opentabletdriver: fix osu! tablet detection (OpenTabletDriver udev rules).
# Cleaned up from the owner's original script: removed duplicate blocks,
# shallow-clones to /tmp, backs up files before deleting, supports DRY_RUN=1.
# Safe to run twice.
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"

say() { echo "[otd-fix] $*"; }
run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ $* (dry-run, skipped)"
  else
    "$@"
  fi
}

say "Cleaning old OpenTabletDriver udev rules..."
for c in /etc/udev/rules.d/90-opentabletdriver.rules /etc/udev/rules.d/99-opentabletdriver.rules; do
  if [ -f "$c" ]; then
    say "Removing $c (backed up to $c.bak first)"
    if [ "$DRY_RUN" = "1" ]; then
      echo "+ sudo cp -n $c $c.bak && sudo rm $c (dry-run, skipped)"
    else
      sudo cp -n "$c" "$c.bak" || true
      sudo rm "$c"
    fi
  fi
done

say "Cleaning old kernel-module blacklist (only OTD leftovers)..."
if [ -f /etc/modprobe.d/blacklist.conf ]; then
  say "Backing up + removing /etc/modprobe.d/blacklist.conf"
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ sudo cp -n /etc/modprobe.d/blacklist.conf /etc/modprobe.d/blacklist.conf.bak (dry-run, skipped)"
    echo "+ sudo rm /etc/modprobe.d/blacklist.conf (dry-run, skipped)"
  else
    sudo cp -n /etc/modprobe.d/blacklist.conf /etc/modprobe.d/blacklist.conf.bak || true
    sudo rm /etc/modprobe.d/blacklist.conf
  fi
fi

say "Loading uinput, unloading conflicting tablet drivers..."
run sudo modprobe uinput
# These two may fail if modules aren't loaded — that's fine.
run sudo rmmod wacom hid_uclogic 2>/dev/null || true

say "Fetching fresh OTD rules (shallow clone to /tmp)..."
WORKDIR="/tmp/OpenTabletDriver-hopper"
if [ "$DRY_RUN" = "1" ]; then
  echo "+ git clone --depth 1 https://github.com/OpenTabletDriver/OpenTabletDriver.git $WORKDIR (dry-run, skipped)"
  echo "+ ./generate-rules.sh | sudo tee /etc/udev/rules.d/70-opentabletdriver.rules (dry-run, skipped)"
  echo "+ sudo cp modprobe + modules-load configs (dry-run, skipped)"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git not found. Run modules/00-bootstrap.sh first." >&2
    exit 1
  fi
  rm -rf "$WORKDIR"
  git clone --depth 1 https://github.com/OpenTabletDriver/OpenTabletDriver.git "$WORKDIR"
  # Generate + install udev rules.
  bash "$WORKDIR/generate-rules.sh" | sudo tee /etc/udev/rules.d/70-opentabletdriver.rules >/dev/null
  sudo cp "$WORKDIR/eng/linux/Generic/usr/lib/modprobe.d/99-opentabletdriver.conf" /etc/modprobe.d/99-opentabletdriver.conf
  sudo cp "$WORKDIR/eng/linux/Generic/usr/lib/modules-load.d/opentabletdriver.conf" /etc/modules-load.d/opentabletdriver.conf
  rm -rf "$WORKDIR"
fi

say "Reloading udev + rebuilding initramfs..."
run sudo modprobe uinput
run sudo rmmod wacom hid_uclogic 2>/dev/null || true
run sudo udevadm control --reload-rules
# Trigger may return non-zero on some systems; don't fail the whole run.
if [ "$DRY_RUN" = "1" ]; then
  echo "+ sudo udevadm trigger (dry-run, skipped)"
  echo "+ sudo mkinitcpio -P (dry-run, skipped)"
else
  sudo udevadm trigger || true
  if command -v mkinitcpio >/dev/null 2>&1; then
    sudo mkinitcpio -P
  else
    say "mkinitcpio not found, skipping initramfs rebuild (fine on some Arch variants)."
  fi
fi

say "Done. Replug your tablet if osu! still doesn't see it."
