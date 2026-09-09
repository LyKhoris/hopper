#!/usr/bin/env bash
# run.sh — local runner for Hopper. No extra installs, just runs modules in order.
# Usage:
#   bash run.sh [--yes] [--dry-run] [--only bootstrap,packages,fcitx,scripts] [--list] [--tui]
# The TUI (index.ts) calls the same modules, so results are identical.
set -euo pipefail

HOPPER_ROOT="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
ONLY=""
ASSUME_YES=0
USE_TUI=0

usage() {
  echo "Usage: bash run.sh [--yes] [--dry-run] [--only a,b,c] [--list] [--tui]"
  echo "  steps: bootstrap, packages, fcitx, scripts"
  echo "  --tui needs bun + deps (bun install first), otherwise runs plain bash."
  echo "  Env: STOP_ON_FAILURE=1 (default) stops at the first failing step/script."
  echo "       STOP_ON_FAILURE=0 runs everything and reports at the end."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --list)
      echo "bootstrap -> modules/00-bootstrap.sh"
      echo "packages  -> modules/10-packages.sh"
      echo "fcitx     -> modules/20-fcitx.sh"
      echo "scripts   -> modules/30-scripts.sh"
      exit 0
      ;;
    --tui) USE_TUI=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done
export DRY_RUN

# Map step names to module files, in fixed order.
STEPS=("bootstrap:modules/00-bootstrap.sh" "packages:modules/10-packages.sh" "fcitx:modules/20-fcitx.sh" "scripts:modules/30-scripts.sh")

# Filter by --only if given (comma-separated).
SELECTED=()
for entry in "${STEPS[@]}"; do
  name="${entry%%:*}"
  file="${entry#*:}"
  if [ -z "$ONLY" ] || [[ ",$ONLY," == *",$name,"* ]]; then
    SELECTED+=("$name:$file")
  fi
done

if [ "${#SELECTED[@]}" -eq 0 ]; then
  echo "No steps selected (check --only value)." >&2
  exit 1
fi

# Optional TUI path: only needs bun (a runtime dep, not a system install).
if [ "$USE_TUI" = "1" ]; then
  if ! command -v bun >/dev/null 2>&1; then
    echo "ERROR: --tui needs bun. Install bun (https://bun.sh) then: bun install && bun index.ts" >&2
    echo "Or run without --tui to use plain bash." >&2
    exit 1
  fi
  export HOPPER_ONLY="$ONLY" HOPPER_DRY_RUN="$DRY_RUN"
  exec bun "$HOPPER_ROOT/index.ts"
fi

# Arch check (friendly, matches modules/_lib.sh).
if ! command -v pacman >/dev/null 2>&1; then
  echo "ERROR: pacman not found. Hopper only works on Arch-based distros." >&2
  exit 1
fi

# Show the plan first — package list + script list, nothing else — then ask.
# Preview always prints, even with --yes (so logs show what was approved).
LOGDIR="$HOPPER_ROOT/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/hopper-$(date +%Y%m%d-%H%M%S).log"

export HOPPER_ONLY="$ONLY"
# Preview exits 2 when the selected steps need nothing — then there is
# nothing to confirm and nothing to run. (Guarded for set -e.)
preview_code=0
bash "$HOPPER_ROOT/modules/99-preview.sh" || preview_code=$?
if [ "$preview_code" -eq 2 ]; then
  echo "Everything is already set up — nothing to do."
  exit 0
elif [ "$preview_code" -ne 0 ]; then
  exit "$preview_code"
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  # Read from the terminal, not stdin: stdin may be the piped script itself
  # when run as `curl ... | bash`.
  if ! read -rp "Install everything listed above? [Y/n] " ans < /dev/tty; then
    echo "Aborted (no terminal to confirm — re-run with --yes to skip this check)."
    exit 1
  fi
  if [[ "$ans" =~ ^[Nn]$ ]]; then
    echo "Aborted, nothing changed."
    exit 0
  fi
fi
echo ""
echo "Log: $LOGFILE"

# Run each module, tee output to the log file.
overall=0
{
  echo "=== hopper run $(date -u +%FT%TZ) dry_run=$DRY_RUN only=${ONLY:-all} ==="
  for entry in "${SELECTED[@]}"; do
    name="${entry%%:*}"
    file="${entry#*:}"
    echo ""
    echo ">>> [$name] bash $file"
    if bash "$HOPPER_ROOT/$file"; then
      echo "<<< [$name] OK"
    else
      echo "<<< [$name] FAILED" >&2
      overall=1
      if [ "${STOP_ON_FAILURE:-1}" = "1" ]; then
        echo "Stopping (first failure)." >&2
        break
      fi
    fi
  done
  echo ""
  if [ "$overall" -eq 0 ]; then
    echo "All selected steps finished OK. fcitx may need a log-out/in."
  else
    echo "Some steps FAILED. See above + $LOGFILE"
  fi
} 2>&1 | tee "$LOGFILE"

exit "$overall"
