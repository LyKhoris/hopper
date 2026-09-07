#!/usr/bin/env bash
# 99-preview: show the FULL plan — everything hopper is about to install or
# change — in plain readable form. Installs nothing, changes nothing.
# Used by run.sh and the TUI before asking for confirmation.
# Env: HOPPER_ONLY="bootstrap,packages,fcitx,scripts" (empty = all).
# Always exits 0.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ONLY="${HOPPER_ONLY:-}"
WILL=0
SKIP=0

want() {
  # want <step> — true if this step is selected.
  [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]
}

check_pkg() {
  # check_pkg <name> — prints status line, bumps WILL/SKIP. Never fails.
  if pacman -Q "$1" >/dev/null 2>&1; then
    SKIP=$((SKIP + 1))
    return 1
  else
    WILL=$((WILL + 1))
    return 0
  fi
}

echo "============ Hopper plan (nothing installed yet) ============"

if want bootstrap; then
  echo "[1/4 bootstrap] system prep"
  echo "  ! includes FULL SYSTEM UPGRADE: sudo pacman -Syu base-devel git"
  if ! command -v git >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
    echo "  WILL INSTALL: base-devel + git (via the upgrade above)"
    WILL=$((WILL + 1))
  else
    echo "  base-devel + git already present, upgrade still refreshes system."
    SKIP=$((SKIP + 1))
  fi
  if command -v yay >/dev/null 2>&1; then
    echo "  yay already installed, skipping."
    SKIP=$((SKIP + 1))
  else
    echo "  WILL BUILD: yay-bin from AUR (makepkg, as normal user)"
    WILL=$((WILL + 1))
  fi
fi

if want packages; then
  echo "[2/4 packages] from packages.txt"
  PKG_FILE="$HOPPER_ROOT/packages.txt"
  will_list=""
  skip_n=0
  if [ -f "$PKG_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      pkg="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$pkg" ] || [[ "$pkg" == \#* ]]; then
        continue
      fi
      if check_pkg "$pkg"; then
        will_list="$will_list $pkg"
      else
        skip_n=$((skip_n + 1))
      fi
    done < "$PKG_FILE"
  else
    echo "  packages.txt not found!"
  fi
  if [ -n "$will_list" ]; then
    echo "  WILL INSTALL:$will_list"
  else
    echo "  WILL INSTALL: (none — everything already installed)"
  fi
  echo "  already installed ($skip_n), skipping."
fi

if want fcitx; then
  echo "[3/4 fcitx] Chinese Pinyin + Japanese Mozc"
  will_list=""
  skip_n=0
  # shellcheck disable=SC2086
  for pkg in fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc; do
    if check_pkg $pkg; then
      will_list="$will_list $pkg"
    else
      skip_n=$((skip_n + 1))
    fi
  done
  if [ -n "$will_list" ]; then
    echo "  WILL INSTALL:$will_list"
  else
    echo "  WILL INSTALL: (none — fcitx already installed)"
  fi
  echo "  already installed ($skip_n), skipping."
  ENV_FILE="$HOME/.config/environment.d/fcitx.conf"
  if [ -f "$ENV_FILE" ] && grep -q "GTK_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
    && grep -q "QT_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
    && grep -q "XMODIFIERS=@im=fcitx" "$ENV_FILE" 2>/dev/null; then
    echo "  keyboard env vars already set, skipping."
    SKIP=$((SKIP + 1))
  else
    echo "  WILL WRITE: keyboard env vars to $ENV_FILE (logout/in needed after)"
    WILL=$((WILL + 1))
  fi
fi

if want scripts; then
  echo "[4/4 scripts] run in order, stop on first failure"
  SCRIPT_DIR="$HOPPER_ROOT/scripts"
  n=0
  for s in "$SCRIPT_DIR"/[0-9]*-*.sh; do
    [ -f "$s" ] || continue
    n=$((n + 1))
    base="$(basename "$s")"
    case "$base" in
      10-multilib.sh)
        if grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
          echo "  - $base: [multilib] already enabled, will just verify."
          SKIP=$((SKIP + 1))
        else
          echo "  - $base: WILL ENABLE [multilib] repo + refresh databases."
          WILL=$((WILL + 1))
        fi
        ;;
      20-opentabletdriver.sh)
        echo "  - $base: WILL refresh tablet udev rules + rebuild initramfs."
        WILL=$((WILL + 1))
        ;;
      *)
        echo "  - $base: will run."
        WILL=$((WILL + 1))
        ;;
    esac
  done
  [ "$n" -gt 0 ] || echo "  (no scripts found)"
fi

echo "------------------------------------------------------------"
echo "TOTAL: $WILL will be installed/changed, $SKIP already done."
echo "============================================================"
exit 0
