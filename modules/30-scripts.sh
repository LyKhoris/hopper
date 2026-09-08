#!/usr/bin/env bash
# 30-scripts: run every scripts/NN-*.sh in sorted order.
# Safe to run twice IF each script is idempotent (they all are).
# Standalone: bash modules/30-scripts.sh
# Dry-run: DRY_RUN=1 bash modules/30-scripts.sh
# Env: STOP_ON_FAILURE=1 (default) stops at first failing script.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ensure_arch
step "Personal scripts"

STOP_ON_FAILURE="${STOP_ON_FAILURE:-1}"
SCRIPT_DIR="$HOPPER_ROOT/scripts"

if [ ! -d "$SCRIPT_DIR" ]; then
  echo "ERROR: $SCRIPT_DIR not found." >&2
  exit 1
fi

# Find numbered scripts, sorted. Ignores README and dotfiles.
# Same discovery as 99-preview.sh (glob + sort, no `ls` parsing).
shopt -s nullglob
_unsorted=("$SCRIPT_DIR"/[0-9]*-*.sh)
shopt -u nullglob
SCRIPTS=()
if [ "${_unsorted[@]+set}" = "set" ] && [ "${#_unsorted[@]}" -gt 0 ]; then
  mapfile -t SCRIPTS < <(printf '%s\n' "${_unsorted[@]}" | sort)
fi

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  log "No scripts found in $SCRIPT_DIR, nothing to do."
  exit 0
fi

log "Found ${#SCRIPTS[@]} script(s)."
ok=0
fail=0
failed_list=""

for s in "${SCRIPTS[@]}"; do
  # Fast path: scripts advertising SUPPORTS_CHECK=1 can report "already
  # applied" without doing any work (no clone, no sudo, no network).
  if grep -q '^[[:space:]]*SUPPORTS_CHECK=1' "$s" 2>/dev/null && bash "$s" --check >/dev/null 2>&1; then
    log "$(basename "$s") already applied, skipping."
    ok=$((ok + 1))
    continue
  fi
  log "Running $(basename "$s")..."
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ bash $s (dry-run, skipped)"
    ok=$((ok + 1))
  else
    if bash "$s"; then
      log "$(basename "$s") OK."
      ok=$((ok + 1))
    else
      echo "$(basename "$s") FAILED." >&2
      fail=$((fail + 1))
      failed_list="$failed_list $(basename "$s")"
      if [ "$STOP_ON_FAILURE" = "1" ]; then
        echo "Stopping (STOP_ON_FAILURE=1)." >&2
        break
      fi
    fi
  fi
done

echo ""
log "Scripts summary: $ok ok, $fail failed."
if [ "$fail" -gt 0 ]; then
  echo "Failed:$failed_list" >&2
  exit 1
fi
