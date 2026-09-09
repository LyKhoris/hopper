#!/usr/bin/env bash
# 30-fcitx-im-order: set fcitx5 input order to English -> Pinyin -> Mozc,
# and enable Cloud Pinyin for Chinese input.
# Writes ~/.config/fcitx5/profile + ~/.config/fcitx5/conf/pinyin.conf
# (backed up first). Safe to run twice.
# Needs the fcitx step done first (fcitx5 + chinese-addons + mozc installed).
# DRY_RUN=1 supported.
HOPPER_TITLE="Set fcitx order + cloud pinyin"
# This script supports `--check`: exit 0 = already applied, exit 1 = work to do.
SUPPORTS_CHECK=1
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
PROFILE="$HOME/.config/fcitx5/profile"
PINYIN_CONF="$HOME/.config/fcitx5/conf/pinyin.conf"

say() { echo "[fcitx-im] $*"; }

current_items() {
  # Print the Group 0 input methods in order, e.g. "keyboard-us pinyin mozc ".
  awk '/^\[Groups\/0\/Items\/[0-9]+\]/{get=1; next} get==1 && /^Name=/{print; get=0}' "$PROFILE" 2>/dev/null | cut -d= -f2 | tr '\n' ' ' || true
}

if [ "${1:-}" = "--check" ]; then
  # Applied = file exists and starts with EN -> Pinyin -> Mozc.
  # Extra input methods after those three are allowed (we don't wipe them).
  # NOTE: DefaultIM is deliberately NOT checked — fcitx itself rewrites it to
  # your last-used input method, which is normal and not worth fighting.
  [ -f "$PROFILE" ] || exit 1
  items="$(current_items)"
  [ "${items#keyboard-us pinyin mozc }" != "$items" ] || exit 1
  # Cloud Pinyin must be switched on (uncommented True, not a default comment).
  grep -q "^CloudPinyinEnabled=True" "$PINYIN_CONF" 2>/dev/null || exit 1
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
  echo "+ stop fcitx5, write $PROFILE (order: keyboard-us, pinyin, mozc), enable cloud pinyin in $PINYIN_CONF, start fcitx5 (dry-run, skipped)"
  echo "+ push env vars to this session so new apps work now (dry-run, skipped)"
  exit 0
fi

# fcitx5 saves its config on exit, so the daemon must be FULLY STOPPED before
# writing — otherwise it overwrites the new profile with the old one.
was_running=0
if systemctl --user is-active fcitx5.service >/dev/null 2>&1; then
  say "Stopping fcitx5 first (it would overwrite the new profile otherwise) ..."
  systemctl --user stop fcitx5.service 2>/dev/null || true
  was_running=1
elif [ -n "$(pgrep -x fcitx5 2>/dev/null || true)" ]; then
  say "Stopping fcitx5 first (it would overwrite the new profile otherwise) ..."
  pkill -x fcitx5 2>/dev/null || true
  was_running=1
fi
if [ "$was_running" = "1" ]; then
  for _ in $(seq 1 50); do
    if [ -z "$(pgrep -x fcitx5 2>/dev/null || true)" ]; then
      break
    fi
    sleep 0.1
  done
fi

mkdir -p "$(dirname "$PROFILE")"
if [ -f "$PROFILE" ]; then
  cp -n "$PROFILE" "$PROFILE.bak" 2>/dev/null || true
  say "Backed up existing profile to $PROFILE.bak"
fi

# Remember any extra input methods the user added (e.g. korean, chewing).
# The order we enforce is EN -> Pinyin -> Mozc first; extras are kept after
# them so a re-run never deletes someone's keyboard.
extras=()
if [ -f "$PROFILE" ]; then
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$name" != "keyboard-us" ] && [ "$name" != "pinyin" ] && [ "$name" != "mozc" ]; then
      dup=0
      for e in ${extras[@]+"${extras[@]}"}; do
        [ "$e" = "$name" ] && dup=1
      done
      [ "$dup" -eq 0 ] && extras+=("$name")
    fi
  done < <(awk '/^\[Groups\/0\/Items\/[0-9]+\]/{get=1; next} get==1 && /^Name=/{print substr($0,6); get=0}' "$PROFILE" 2>/dev/null || true)
  if grep -q '^\[Groups/[1-9]' "$PROFILE" 2>/dev/null; then
    say "WARNING: extra fcitx groups found — only Group 0 is rewritten, other groups are left in the .bak file."
  fi
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
# Re-append the extras we saved above, renumbered from 3 on.
# (Insert before the [GroupOrder] footer so the file stays valid.)
if [ "${#extras[@]}" -gt 0 ]; then
  tmp="$(mktemp)"
  grep -v '^\[GroupOrder\]' "$PROFILE" > "$tmp" || true
  idx=3
  for e in "${extras[@]}"; do
    printf '\n[Groups/0/Items/%s]\n# Name\nName=%s\n# Layout\nLayout=\n' "$idx" "$e" >> "$tmp"
    idx=$((idx + 1))
  done
  printf '\n[GroupOrder]\n0=Default\n' >> "$tmp"
  mv "$tmp" "$PROFILE"
  say "Kept your extra input methods: ${extras[*]}"
fi
say "Wrote $PROFILE"

# Cloud Pinyin lives in the same stopped window: the daemon would also
# clobber this file on exit. Flip the commented default to an active True.
mkdir -p "$(dirname "$PINYIN_CONF")"
if [ -f "$PINYIN_CONF" ]; then
  cp -n "$PINYIN_CONF" "$PINYIN_CONF.bak" 2>/dev/null || true
fi
if grep -q "^[# ]*CloudPinyinEnabled=" "$PINYIN_CONF" 2>/dev/null; then
  sed -i 's/^[# ]*CloudPinyinEnabled=.*/CloudPinyinEnabled=True/' "$PINYIN_CONF"
else
  echo "CloudPinyinEnabled=True" >> "$PINYIN_CONF"
fi
say "Enabled cloud pinyin ($PINYIN_CONF)"

# Start the daemon again if it was running; otherwise first login picks it up.
if [ "$was_running" = "1" ]; then
  if systemctl --user is-enabled fcitx5.service >/dev/null 2>&1; then
    if systemctl --user start fcitx5.service >/dev/null 2>&1; then
      say "Started fcitx5, new order is live."
    else
      say "Couldn't restart fcitx5 — log out/in to apply."
    fi
  else
    if fcitx5 -d >/dev/null 2>&1; then
      say "Started fcitx5, new order is live."
    else
      say "Couldn't restart fcitx5 — log out/in to apply."
    fi
  fi
else
  say "fcitx5 isn't running — order applies on next login."
fi

# Same session, no logout: push the env vars into dbus + the user manager so
# newly opened apps use fcitx right away. A script can't change the
# environment of already-running apps — those still need a restart.
export GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS="@im=fcitx"
dbus-update-activation-environment GTK_IM_MODULE QT_IM_MODULE XMODIFIERS >/dev/null 2>&1 || true
systemctl --user import-environment GTK_IM_MODULE QT_IM_MODULE XMODIFIERS >/dev/null 2>&1 || true
say "New apps use the new order now; restart already-open apps (or log out/in) if they ignore input."
