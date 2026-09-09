#!/usr/bin/env bash
# 99-preview: package list + script list, nothing else. Installs nothing.
# Shown before every run (CLI question + TUI confirm screen).
# Exits 0 when there is work to do, 2 when the selected steps need nothing
# (callers skip confirmation entirely then).
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
  if grep -q '^[[:space:]]*SUPPORTS_CHECK=1' "$1" 2>/dev/null && bash "$1" --check >/dev/null 2>&1; then
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
skipped=() # installed package names + applied script titles (shown below)
titles_run=() # script titles that still need running (empty = none)
pkgs_missing=0 # packages.txt wanted but not found (10-packages.sh would fail)

if want packages || want fcitx; then
  shown=1
  all_pkgs=(); to_install=(); have_pkgs=()
  if want packages && [ ! -f "$HOPPER_ROOT/packages.txt" ]; then
    pkgs_missing=1
  fi
  if want packages && [ -f "$HOPPER_ROOT/packages.txt" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      # Same parsing as 10-packages.sh: strip trailing "# comment", then trim.
      pkg="$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      if [ -z "$pkg" ]; then
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
  if [ "${#to_install[@]}" -gt 0 ]; then
    echo "Packages to install (${#to_install[@]}): $(join_pretty "${to_install[@]}")"
  fi
  for p in "${have_pkgs[@]}"; do
    skipped+=("$p")
  done
fi

if want scripts; then
  shown=1
  titles_run=()
  # Same discovery as 30-scripts.sh (glob + sort).
  shopt -s nullglob
  _scripts=("$HOPPER_ROOT"/scripts/[0-9]*-*.sh)
  shopt -u nullglob
  _sorted=()
  if [ "${#_scripts[@]}" -gt 0 ]; then
    mapfile -t _sorted < <(printf '%s\n' "${_scripts[@]}" | sort)
  fi
  for s in ${_sorted[@]+"${_sorted[@]}"}; do
    if [ ! -f "$s" ]; then
      continue
    fi
    t="$(script_title "$s")"
    if script_needs_run "$s"; then
      titles_run+=("$t")
    else
      skipped+=("$t (script)")
    fi
  done
  if [ "${#titles_run[@]}" -gt 0 ]; then
    echo "Scripts to run (${#titles_run[@]}): $(join_pretty "${titles_run[@]}")"
  fi
fi

if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Skipped (${#skipped[@]}): $(join_pretty "${skipped[@]}")"
fi

if [ "$shown" -eq 0 ]; then
  echo "(preview only covers packages + scripts)"
fi

# Nothing selected needs work (and no missing input file): tell callers to
# skip confirmation entirely. Bootstrap-only selections always proceed
# (shown == 0) since bootstrap has no cheap done-check.
if [ "$shown" -eq 1 ] && [ "${#to_install[@]}" -eq 0 ] && [ "${#titles_run[@]}" -eq 0 ] && [ "$pkgs_missing" -eq 0 ]; then
  exit 2
fi
exit 0
