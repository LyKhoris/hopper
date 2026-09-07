#!/usr/bin/env bash
# 99-preview: package list + script list, nothing else. Installs nothing.
# Shown before every run (CLI question + TUI confirm screen). Always exits 0.
# Env: HOPPER_ONLY="bootstrap,packages,fcitx,scripts" (empty = all).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ONLY="${HOPPER_ONLY:-}"

want() {
  # want <step> — true if this step is selected.
  [ -z "$ONLY" ] || [[ ",$ONLY," == *",$1,"* ]]
}

all_pkgs=()    # every package name, in order
to_install=()  # the ones missing (will be installed)
have_pkgs=()   # the ones already installed

collect() {
  # collect <pkg> — record it, sort missing vs installed. Never fails.
  all_pkgs+=("$1")
  if pacman -Q "$1" >/dev/null 2>&1; then
    have_pkgs+=("$1")
  else
    to_install+=("$1")
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

script_needs_run() {
  # script_needs_run <file> — false (skip) if it reports already applied.
  if grep -q '^SUPPORTS_CHECK=1' "$1" 2>/dev/null && bash "$1" --check >/dev/null 2>&1; then
    return 1
  fi
  return 0
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

shown=0

if want packages || want fcitx; then
  shown=1
  all_pkgs=(); to_install=(); have_pkgs=()
  if want packages && [ -f "$HOPPER_ROOT/packages.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      pkg="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$pkg" ] || [[ "$pkg" == \#* ]]; then
        continue
      fi
      collect "$pkg"
    done < "$HOPPER_ROOT/packages.txt"
  fi
  if want fcitx; then
    for pkg in fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc; do
      collect "$pkg"
    done
  fi
  if [ "${#to_install[@]}" -gt 0 ] && [ "${#have_pkgs[@]}" -eq 0 ]; then
    echo "Packages to install (${#to_install[@]}): $(join_pretty "${to_install[@]}")"
  elif [ "${#to_install[@]}" -gt 0 ]; then
    echo "Packages to install (${#to_install[@]}): $(join_pretty "${to_install[@]}")"
    echo "Already installed (${#have_pkgs[@]}): $(join_pretty "${have_pkgs[@]}")"
  else
    echo "Packages (${#all_pkgs[@]}), all installed: $(join_pretty "${all_pkgs[@]}")"
  fi
fi

if want scripts; then
  shown=1
  titles=()
  for s in "$HOPPER_ROOT"/scripts/[0-9]*-*.sh; do
    if [ -f "$s" ] && script_needs_run "$s"; then
      titles+=("$(script_title "$s")")
    fi
  done
  if [ "${#titles[@]}" -gt 0 ]; then
    echo "Scripts (${#titles[@]}): $(join_pretty "${titles[@]}")"
  else
    echo "Scripts: (none)"
  fi
fi

if [ "$shown" -eq 0 ]; then
  echo "(preview only covers packages + scripts)"
fi
exit 0
