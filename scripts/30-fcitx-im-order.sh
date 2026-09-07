#!/usr/bin/env bash
# 30-fcitx-im-order: set fcitx5 input order to English -> Pinyin -> Mozc.
# Writes ~/.config/fcitx5/profile (backed up first). Safe to run twice.
# Needs the fcitx step done first (fcitx5 + chinese-addons + mozc installed).
# DRY_RUN=1 supported.
HOPPER_TITLE="Set fcitx order: English, Pinyin, Mozc"
# This script supports `--check`: exit 0 = already applied, exit 1 = work to do.
SUPPORTS_CHECK=1
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
PROFILE="$HOME/.config/fcitx5/profile"

say() { echo "[fcitx-im] $*"; }

current_items() {
  # Print the Group 0 input methods in order, e.g. "keyboard-us pinyin mozc ".
  awk '/^\[Groups\/0\/Items\/[0-9]+\]/{get=1; next} get==1 && /^Name=/{print; get=0}' "$PROFILE" 2>/dev/null | cut -d= -f2 | tr '\n' ' ' || true
}

if [ "${1:-}" = "--check" ]; then
  # Applied = file exists, starts with EN -> Pinyin -> Mozc, English default.
  # Extra input methods after those three are allowed (we don't wipe them).
  [ -f "$PROFILE" ] || exit 1
  items="$(current_items)"
  [ "${items#keyboard-us pinyin mozc }" != "$items" ] || exit 1
  grep -q "^DefaultIM=keyboard-us" "$PROFILE" 2>/dev/null || exit 1
  exit 0
fi

say "Setting fcitx input order: English -> Pinyin -> Mozc ..."

for p in fcitx5 fcitx5-chinese-addons fcitx5-mozc; do
  if ! pacman -Q "$p" >/dev/null 2>&1; then
    echo "ERROR: $p not installed. Run the fcitx step first." >&2
    exit 1
  fi
done

if [ "$DRY_RUN" = "1" ]; then
  echo "+ write $PROFILE (order: keyboard-us, pinyin, mozc) (dry-run, skipped)"
  echo "+ restart fcitx5 if running (dry-run, skipped)"
  exit 0
fi

mkdir -p "$(dirname "$PROFILE")"
if [ -f "$PROFILE" ]; then
  cp -n "$PROFILE" "$PROFILE.bak" 2>/dev/null || true
  say "Backed up existing profile to $PROFILE.bak"
fi

cat > "$PROFILE" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=keyboard-us

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=pinyin
# Layout
Layout=

[Groups/0/Items/2]
# Name
Name=mozc
# Layout
Layout=

[GroupOrder]
0=Default
EOF
say "Wrote $PROFILE"

# Apply now if fcitx is already running; otherwise first login picks it up.
if systemctl --user is-active fcitx5.service >/dev/null 2>&1; then
  systemctl --user restart fcitx5.service 2>/dev/null || true
  say "Restarted fcitx5, new order is live."
elif [ -n "$(pgrep -x fcitx5 2>/dev/null || true)" ]; then
  say "fcitx5 is running outside systemd — restart it (or log out/in) to apply."
else
  say "fcitx5 isn't running — order applies on next login."
fi
