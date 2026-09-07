# Shared helpers for all hopper modules.
# Each module sources this file:
#   source "$(dirname "$0")/_lib.sh"
# Keeps things simple + consistent. Safe to run twice (idempotent).

# NOTE: don't call `set -euo pipefail` here — each module sets it.

# Repo root = parent of modules/ dir.
HOPPER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dry-run mode: DRY_RUN=1 just prints commands instead of running them.
DRY_RUN="${DRY_RUN:-0}"

log() {
  # Simple timestamped log line.
  echo "[hopper] $*"
}

step() {
  echo ""
  echo "=== $* ==="
}

run() {
  # Run a command, or just echo it in dry-run mode.
  # Usage: run sudo pacman -S foo
  if [ "$DRY_RUN" = "1" ]; then
    echo "+ $* (dry-run, skipped)"
  else
    "$@"
  fi
}

ensure_arch() {
  # Exit with a friendly message if this is not an Arch-based system.
  if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: pacman not found. Hopper only works on Arch-based distros." >&2
    exit 1
  fi
  if [ -f /etc/os-release ]; then
    # ID_LIKE contains "arch" on EndeavourOS, CachyOS, Garuda, Manjaro, etc.
    if ! grep -qi "arch" /etc/os-release; then
      echo "WARNING: /etc/os-release doesn't mention arch. Continuing anyway since pacman exists." >&2
    fi
  fi
}

is_installed() {
  # Check if a pacman/yay package is already installed.
  # Usage: is_installed foo && echo "already there"
  pacman -Q "$1" >/dev/null 2>&1
}
