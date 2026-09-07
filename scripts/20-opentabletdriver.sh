#!/usr/bin/env bash
# 20-opentabletdriver: fix osu! tablet detection (OpenTabletDriver udev rules).
# Safe to run twice. DRY_RUN=1 supported.
#
# History: OTD moved its packaging files from eng/linux/ to eng/bash/ (2024+),
# which broke hardcoded paths. This script tries the repo first (new path, then
# old path) and falls back to built-in known-good content, so a repo move
# can't break your hop again.
# HOPPER_TITLE is the short display name shown in the pre-install preview.
HOPPER_TITLE="Fix osu! tablet detection"
# This script supports `--check`: exit 0 = already applied, exit 1 = work to do.
SUPPORTS_CHECK=1
set -euo pipefail

if [ "${1:-}" = "--check" ]; then
  # Applied = current rules + configs in place, old leftovers gone.
  # Local file reads only: no sudo, no network, instant.
  ok=1
  grep -q "OpenTabletDriver" /etc/udev/rules.d/70-opentabletdriver.rules 2>/dev/null || ok=0
  grep -q "install wacom /usr/bin/true" /etc/modprobe.d/99-opentabletdriver.conf 2>/dev/null || ok=0
  grep -qx "uinput" /etc/modules-load.d/opentabletdriver.conf 2>/dev/null || ok=0
  if [ -f /etc/udev/rules.d/90-opentabletdriver.rules ]; then ok=0; fi
  if [ -f /etc/udev/rules.d/99-opentabletdriver.rules ]; then ok=0; fi
  if [ -f /etc/modprobe.d/blacklist.conf ]; then ok=0; fi
  if [ "$ok" = "1" ]; then exit 0; else exit 1; fi
fi

DRY_RUN="${DRY_RUN:-0}"

say() { echo "[otd-fix] $*"; }
run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ $* (dry-run, skipped)"
  else
    "$@"
  fi
}

# Known-good config content (verified against OTD repo). Used only if the
# repo no longer ships these files.
MODPROBE_CONTENT='install wacom /usr/bin/true
install hid_uclogic /usr/bin/true'
MODULES_LOAD_CONTENT='uinput'

write_file() {
  # write_file <path> <content> — writes only if missing or different.
  local dest="$1" content="$2"
  if [ -f "$dest" ] && [ "$(cat "$dest")" = "$content" ]; then
    say "$(basename "$dest") already correct, skipping."
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ write $dest (dry-run, skipped)"
    return 0
  fi
  if [ -f "$dest" ]; then
    sudo cp -n "$dest" "$dest.bak" || true
  fi
  echo "$content" | sudo tee "$dest" >/dev/null
  say "Wrote $dest"
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

say "Fetching fresh OTD udev rules (shallow clone to /tmp)..."
WORKDIR="/tmp/OpenTabletDriver-hopper"
if [ "$DRY_RUN" = "1" ]; then
  echo "+ git clone --depth 1 https://github.com/OpenTabletDriver/OpenTabletDriver.git $WORKDIR (dry-run, skipped)"
  echo "+ ./generate-rules.sh | sudo tee /etc/udev/rules.d/70-opentabletdriver.rules (dry-run, skipped)"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git not found. Run modules/00-bootstrap.sh first." >&2
    exit 1
  fi
  rm -rf "$WORKDIR"
  git clone --depth 1 https://github.com/OpenTabletDriver/OpenTabletDriver.git "$WORKDIR"
  # Generate + install udev rules.
  bash "$WORKDIR/generate-rules.sh" | sudo tee /etc/udev/rules.d/70-opentabletdriver.rules >/dev/null
  say "Wrote /etc/udev/rules.d/70-opentabletdriver.rules"

  # Module configs: prefer the repo copy (new layout first, old layout
  # second), fall back to built-in content if both disappear one day.
  MODPROBE_SRC=""; MODULES_SRC=""
  for base in "$WORKDIR/eng/bash/Generic" "$WORKDIR/eng/linux/Generic"; do
    if [ -f "$base/usr/lib/modprobe.d/99-opentabletdriver.conf" ]; then
      MODPROBE_SRC="$base/usr/lib/modprobe.d/99-opentabletdriver.conf"
    fi
    if [ -f "$base/usr/lib/modules-load.d/opentabletdriver.conf" ]; then
      MODULES_SRC="$base/usr/lib/modules-load.d/opentabletdriver.conf"
    fi
  done
  if [ -n "$MODPROBE_SRC" ]; then
    say "Using repo config: ${MODPROBE_SRC#$WORKDIR/}"
    sudo cp "$MODPROBE_SRC" /etc/modprobe.d/99-opentabletdriver.conf
  else
    say "Repo layout changed again, using built-in config."
    write_file /etc/modprobe.d/99-opentabletdriver.conf "$MODPROBE_CONTENT"
  fi
  if [ -n "$MODULES_SRC" ]; then
    say "Using repo config: ${MODULES_SRC#$WORKDIR/}"
    sudo cp "$MODULES_SRC" /etc/modules-load.d/opentabletdriver.conf
  else
    say "Repo layout changed again, using built-in config."
    write_file /etc/modules-load.d/opentabletdriver.conf "$MODULES_LOAD_CONTENT"
  fi
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
