#!/usr/bin/env bash
# 20-fcitx: install fcitx5 with Chinese Pinyin + Japanese Mozc.
# Safe to run twice (won't overwrite your existing config).
# Standalone: bash modules/20-fcitx.sh
# Dry-run: DRY_RUN=1 bash modules/20-fcitx.sh
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

ensure_arch
step "fcitx5 (Chinese Pinyin + Japanese Mozc)"

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "ERROR: run as normal user, not root." >&2
  exit 1
fi

if ! command -v yay >/dev/null 2>&1; then
  echo "ERROR: yay not found. Run modules/00-bootstrap.sh first." >&2
  exit 1
fi

# Fixed package list (locked per PLAN.md).
FCITX_PKGS="fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc"

for pkg in $FCITX_PKGS; do
  if is_installed "$pkg"; then
    log "$pkg already installed, skipping."
  else
    log "Installing $pkg..."
    run yay -S --needed --noconfirm "$pkg"
  fi
done

# Env vars so apps actually use fcitx. Preferred location (no sudo needed).
ENV_FILE="$HOME/.config/environment.d/fcitx.conf"
log "Ensuring $ENV_FILE ..."
if [ "$DRY_RUN" = "1" ]; then
  echo "+ write GTK_IM_MODULE=fcitx, QT_IM_MODULE=fcitx, XMODIFIERS=@im=fcitx to $ENV_FILE (dry-run, skipped)"
else
  mkdir -p "$(dirname "$ENV_FILE")"
  # Back up once, never overwrite blindly.
  if [ -f "$ENV_FILE" ]; then
    cp -n "$ENV_FILE" "$ENV_FILE.bak" 2>/dev/null || true
  fi
  touch "$ENV_FILE"
  grep -q "GTK_IM_MODULE=fcitx" "$ENV_FILE" || echo "GTK_IM_MODULE=fcitx" >> "$ENV_FILE"
  grep -q "QT_IM_MODULE=fcitx" "$ENV_FILE" || echo "QT_IM_MODULE=fcitx" >> "$ENV_FILE"
  grep -q "XMODIFIERS=@im=fcitx" "$ENV_FILE" || echo "XMODIFIERS=@im=fcitx" >> "$ENV_FILE"
  log "Wrote env vars to $ENV_FILE"
fi

echo ""
log "fcitx5 done. Log out and back in, then run fcitx5-configtool to add Pinyin + Mozc."
log "Tip: fcitx5 should autostart on most desktops. If not, add fcitx5 -d to your WM autostart."
