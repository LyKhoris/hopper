#!/usr/bin/env bash
# 99-preview: one short readable plan — only what WILL change. Installs nothing.
# Shown before every run (CLI question + TUI confirm screen). Always exits 0.
# Env: HOPPER_ONLY="bootstrap,packages,fcitx,scripts" (empty = all).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ONLY="${HOPPER_ONLY:-}"

want() {
  # want <step> — true if this step is selected.
  [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]
}

missing=() # package names that will be installed
have_n=0   # already-installed count

collect() {
  # collect <pkg> — sort into missing[] or bump have_n. Never fails.
  if pacman -Q "$1" >/dev/null 2>&1; then
    have_n=$((have_n + 1))
  else
    missing+=("$1")
  fi
}

script_title() {
  # script_title <file> — its HOPPER_TITLE="..." or a prettified filename.
  local t
  t="$(grep -m1 '^HOPPER_TITLE=' "$1" 2>/dev/null | cut -d'"' -f2 || true)"
  if [ -z "$t" ]; then
    t="$(basename "$1" | sed -e 's/^[0-9]*-//' -e 's/\.sh$//' -e 's/[-_]/ /g')"
  fi
  echo "$t"
}

join_pretty() {
  # join_pretty a b c -> "a, b, c"
  local out="$1"
  shift
  for x in "$@"; do
    out="$out, $x"
  done
  echo "$out"
}

echo "Hopper plan:"

if want bootstrap; then
  echo "  ! bootstrap first runs a FULL SYSTEM UPGRADE (pacman -Syu)"
  if ! command -v yay >/dev/null 2>&1; then
    echo "  will also build: yay-bin"
  fi
fi

if want packages; then
  missing=(); have_n=0
  if [ -f "$HOPPER_ROOT/packages.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      pkg="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$pkg" ] || [[ "$pkg" == \#* ]]; then
        continue
      fi
      collect "$pkg"
    done < "$HOPPER_ROOT/packages.txt"
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  packages to install (${#missing[@]}): $(join_pretty "${missing[@]}")"
  fi
  if [ "$have_n" -gt 0 ]; then
    echo "  packages already installed ($have_n), skipping."
  fi
fi

if want fcitx; then
  missing=(); have_n=0
  for pkg in fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc; do
    collect "$pkg"
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  keyboards to install (${#missing[@]}): $(join_pretty "${missing[@]}")"
  fi
  if [ "$have_n" -gt 0 ]; then
    echo "  keyboards already installed ($have_n), skipping."
  fi
  ENV_FILE="$HOME/.config/environment.d/fcitx.conf"
  if grep -q "GTK_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
    && grep -q "QT_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
    && grep -q "XMODIFIERS=@im=fcitx" "$ENV_FILE" 2>/dev/null; then
    : # already set, nothing to say
  else
    echo "  will also set up keyboard env vars (logout/in needed after)"
  fi
fi

if want scripts; then
  titles=()
  for s in "$HOPPER_ROOT"/scripts/[0-9]*-*.sh; do
    if [ -f "$s" ]; then
      titles+=("$(script_title "$s")")
    fi
  done
  if [ "${#titles[@]}" -gt 0 ]; then
    echo "  scripts to run (${#titles[@]}): $(join_pretty "${titles[@]}")"
  fi
fi
exit 0
