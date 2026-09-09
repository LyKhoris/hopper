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
ENV_FILE="$HOME/.config/environment.d/fcitx.conf"
UNIT_FILE="$HOME/.config/systemd/user/fcitx5.service"

for pkg in $FCITX_PKGS; do
  if is_installed "$pkg"; then
    log "$pkg already installed, skipping."
  else
    log "Installing $pkg..."
    run yay -S --needed --noconfirm "$pkg"
  fi
done

# Fast path: packages installed, env vars present, autostart unit in place
# and enabled → fully set up, nothing to do (no sudo, no network, instant).
if grep -q "GTK_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
  && grep -q "QT_IM_MODULE=fcitx" "$ENV_FILE" 2>/dev/null \
  && grep -q "XMODIFIERS=@im=fcitx" "$ENV_FILE" 2>/dev/null \
  && [ -f "$UNIT_FILE" ] \
  && systemctl --user is-enabled fcitx5.service >/dev/null 2>&1; then
  log "fcitx5 already set up, skipping."
  exit 0
fi

# Env vars so apps actually use fcitx. Preferred location (no sudo needed).
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

# Autostart via a systemd user service (works on any desktop/WM, no sudo).
# fcitx5 ships no unit file, so we install our own. Never overwrites yours.
FCITX_BIN="$(command -v fcitx5 2>/dev/null || echo /usr/bin/fcitx5)"
UNIT_CONTENT="[Unit]
Description=Fcitx5 input method framework

[Service]
ExecStart=${FCITX_BIN} --replace
Restart=on-failure

[Install]
WantedBy=default.target"
log "Ensuring fcitx5 autostart ($UNIT_FILE) ..."
if [ "$DRY_RUN" = "1" ]; then
  echo "+ write $UNIT_FILE + systemctl --user enable/start fcitx5 (dry-run, skipped)"
else
  mkdir -p "$(dirname "$UNIT_FILE")"
  if [ ! -f "$UNIT_FILE" ]; then
    echo "$UNIT_CONTENT" > "$UNIT_FILE"
    log "Wrote $UNIT_FILE"
  elif [ "$(cat "$UNIT_FILE")" = "$UNIT_CONTENT" ]; then
    log "Autostart unit already correct, skipping."
  else
    log "Custom unit found, keeping yours and enabling as-is."
  fi
  if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable fcitx5.service 2>/dev/null; then
    log "fcitx5 will autostart on login."
    if systemctl --user start fcitx5.service 2>/dev/null; then
      log "fcitx5 started now (no logout needed for the daemon itself)."
    else
      log "Couldn't start fcitx5 right now — it will start on next login."
    fi
  else
    echo "WARNING: no systemd user session here, autostart NOT enabled." >&2
    echo "Add 'fcitx5 -d' to your desktop/WM autostart instead." >&2
  fi
fi

echo ""
log "fcitx5 done. Run fcitx5-configtool to add Pinyin + Mozc (log out/in first if apps ignore input)."
