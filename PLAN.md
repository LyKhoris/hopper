# Hopper — Arch Distro-Hop Setup Script (with OpenTUI)

## Goal
One command to go from fresh Arch-based install -> fully working system.
Reduces distro-hop friction. Built for someone with zero coding experience (vibe-coded),
so everything must be simple to edit, safe to re-run, and obvious in the TUI.

## Interview results (locked decisions)
- **Packages:** user will provide list via yay/pacman history. Store as plain text file (`packages.txt`).
- **Dotfiles:** SKIP for v1. Add in v2.
- **Keyboards:** `fcitx5` with Chinese Pinyin (`fcitx5-chinese-addons`) + Japanese Mozc (`fcitx5-mozc`). Defaults accepted.
- **Personal scripts:** user has scripts, will share later. Support a `scripts/` drop-in folder run in order.
- **TUI:** OpenTUI, "Checklist and Go" style. Checklist of modules + Run button + live log.
- **Distro scope:** keep it general — any Arch-based (vanilla Arch, EndeavourOS, CachyOS, Garuda, Manjaro). Must detect Arch, refuse safely on non-Arch.
- **Safety:** idempotent (safe to run twice, skips what's done). No destructive wipes. Show what will run before it runs.

## Tech stack (chosen for zero-coding maintenance)
- **Runtime:** Bun 1.3+ (OpenTUI's primary runtime, built-in TS support)
- **TUI:** `@opentui/core` (imperative API first — simpler than React/Solid for v1)
- **Workhorses:** Bash modules in `modules/` called from Bun via `Bun.$`. Keeps each step testable without the TUI.
- **Package manager logic:** `pacman` for repos + `yay` for AUR. Bootstrap `yay` if missing (clone `yay-bin` from AUR, `makepkg -si`).
- **Config:** plain files, no JSON editing required:
  - `packages.txt` — one package per line, `#` comments allowed
  - `scripts/` — numbered `*.sh` files, e.g. `10-fonts.sh`, `20-git.sh`
  - `modules/fcitx.sh` — fixed list for Chinese/Japanese

Why this split: TUI = pretty checklist, Bash = actual work. If TUI breaks, user can still run `bash modules/<thing>.sh` manually.

## Repo structure (v1)
```
hopper/
  PLAN.md            # this file
  AGENTS.md          # instructions for AI agents / contributors
  package.json       # bun project, deps: @opentui/core
  tsconfig.json
  index.ts           # TUI entry: checklist + runner
  packages.txt       # user package list (one per line)
  modules/
    _lib.sh            # shared helpers (log/step/run/ensure_arch/is_installed, DRY_RUN)
    00-bootstrap.sh  # verify Arch, sudo, install base-devel+git, install yay if missing
    10-packages.sh   # install all entries in packages.txt via yay (idempotent, skips installed)
    20-fcitx.sh      # install fcitx5 + chinese-addons + mozc + config + env vars + autostart unit
    30-scripts.sh    # run scripts/*.sh in sorted order, stop-on-error optional
    99-preview.sh     # print the plan (packages to install + scripts to run + skipped), installs nothing
  hopper.sh          # remote entrypoint for the curl one-liner (fetches git + repo only)
  run.sh             # local runner, same steps as the TUI (--yes/--dry-run/--only/--list/--tui)
  scripts/
    README.md        # "drop your .sh files here, numbered"
    .keep
  logs/              # auto-created run logs (gitignored)
```

## Modules — what each does

### 00-bootstrap
1. Check `/etc/os-release` + `pacman` exists, else exit with friendly message.
2. Ensure `sudo` works (prompt once).
3. `sudo pacman -Syu --needed --noconfirm base-devel git`
4. Enable `[multilib]` via `scripts/10-multilib.sh` (steam/gamescope/gamemode live there — must happen before the packages step).
5. If `yay` missing: `git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && makepkg -si --noconfirm`.
6. Idempotent: exits 0 quickly if everything already present.

### 10-packages
- Reads `../packages.txt`, strips comments/blank lines.
- Enables `[multilib]` first via `scripts/10-multilib.sh` (steam/games live there) — no manual pre-step, works standalone.
- For each pkg: `pacman -Q <pkg>` → skip if installed, else `yay -S --needed --noconfirm <pkg>`.
- Log summary: installed / already-present / failed.
- NEVER run `yay` as root with sudo (yay refuses). Run as normal user.

### 20-fcitx (Chinese Pinyin + Japanese Mozc)
- Install: `fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc`
- Write `~/.config/fcitx5/profile`-safe defaults only if missing (don't overwrite existing).
- Ensure env vars in `/etc/environment` or `~/.config/environment.d/fcitx.conf`:
  ```
  GTK_IM_MODULE=fcitx
  QT_IM_MODULE=fcitx
  XMODIFIERS=@im=fcitx
  ```
- Print "log out + log back in, then run fcitx5-configtool" notice. Autostart hint for DE/WM.

### 30-scripts
- Runs `scripts/*.sh` sorted alphabetically.
- Each script must be executable + idempotent. Runner logs stdout/stderr per script to `logs/`.
- Checkbox in TUI: "Stop on first failure" (default ON).

## TUI — "Checklist and Go" (index.ts)
Screens (single screen, no wizard):
```
 [x] 1. Bootstrap system (base-devel, git, yay)
 [x] 2. Install packages from packages.txt (N packages found)
 [x] 3. Setup fcitx5 (Chinese Pinyin + Japanese Mozc)
 [x] 4. Run personal scripts (M scripts found)
 [ ] [--] Dry run (print commands only)
 [ ] [x] Stop on first failure
       [ Run selected ]   [ Quit ]
 Log pane (scrollable, last 200 lines)
 Status bar: Arch? yay? counts
```
- Keyboard: `Space` toggle, `↑/↓` move, `Enter` review plan, `Enter` again confirm / `Esc` back, `q` quit. NOTHING runs before the confirm screen.
- Runner streams each module's output into log pane + `logs/hopper-<timestamp>.log`.
- Shows final summary: ✅ / ❌ per module, "Log out/in may be needed for fcitx".
- Dry-run mode just echoes commands, changes nothing.

## Build phases
- [x] **Phase 0 — Scaffold:** repo files created, `bun install` + `bunx tsc --noEmit` pass.
- [x] **Phase 1 — Bootstrap module:** `modules/00-bootstrap.sh` done, DRY_RUN tested (yay already present → skips).
- [x] **Phase 2 — Packages:** `packages.txt` filled with user's 23 packages, `10-packages.sh` uses `--needed` + skip-if-installed. DRY_RUN tested (all 23 already installed → skip).
- [x] **Phase 3 — fcitx:** `20-fcitx.sh` installs fcitx5 + chinese-addons + mozc + env file. DRY_RUN tested.
- [x] **Phase 4 — Scripts runner:** `30-scripts.sh` + `scripts/10-multilib.sh` + `scripts/20-opentabletdriver.sh` (cleaned, idempotent, DRY_RUN tested).
- [x] **Phase 5 — TUI wiring:** `index.ts` checklist (Space/Up-Down/Enter/q/d) calls modules via Bun.spawn, logs to `logs/`. `bunx tsc --noEmit` passes.
- [x] **Phase 6 — Polish:** `hopper.sh` remote one-liner (only installs git if missing) + `run.sh` (`--yes/--dry-run/--only/--list/--tui`) + `README.md`. Remaining: push to GitHub + set real `HOPPER_REPO` URL in `hopper.sh`, live test on a fresh hop.
- [x] **Phase 7 — Preview + confirm (added after first live run, trimmed after feedback):** `modules/99-preview.sh` prints a SHORT plan — only what will change (`packages to install (3): ...`, skip counts, `scripts to run (2): Title, Title` via `HOPPER_TITLE`). `run.sh` always shows it then asks Y/n (reads `/dev/tty` so piped runs still confirm; aborts safely with no terminal). TUI: `Enter` opens the same preview, `Enter` again confirms, `Esc` backs out. Also fixed OTD script for repo move (`eng/linux/` → `eng/bash/`) with old-path + built-in fallbacks.
- [x] **Phase 8 — Self-healing updater (added after stale-cache incident):** `hopper.sh` used `pull --ff-only || true`, which silently ran STALE code when the cache diverged (user saw old behavior + old tablet bug). Now: `fetch + checkout -B FETCH_HEAD` resets any diverged cache to the remote; offline prints a dated warning and runs the local copy knowingly. NOTE: `--yes` skips the Y/n question by design — run without it to get the confirmation prompt.
- [x] **Phase 9 — Minimal preview + skip-if-applied (added after "too many words" feedback):** preview is now ONLY the full package list (all names) + script titles — no bootstrap warning, no remote chatter (`hopper.sh` quiet by default, `HOPPER_VERBOSE=1` restores it, errors always show). Scripts support `SUPPORTS_CHECK=1` + `--check` (fast local reads only): applied scripts are skipped by both the runner and the preview. TUI confirm screen word-wraps so full names stay visible.
- [x] **Phase 10 — Skipped section + fcitx autostart:** preview ends with `Skipped (N): <installed package names>, <applied script titles>` below the will-do lines. fcitx step installs a systemd user unit (`~/.config/systemd/user/fcitx5.service`, default target, no sudo) + enables/starts it; custom units are kept as-is; no user session → loud warning with manual fallback.
- [x] **Phase 11 — fcitx input order script:** `scripts/30-fcitx-im-order.sh` writes `~/.config/fcitx5/profile` (backed up first) with EN -> Pinyin -> Mozc + English default; `--check` passes if the order starts that way (extra IMs allowed); restarts the fcitx5 user service if active.
- [x] **Phase 12 — stop-before-write fix:** fcitx5 saves its config ON EXIT, so `restart`-after-write let the old config clobber the new profile (diagnosed from the daemon-rewritten file on disk). Script now stops the daemon, waits for death, writes, then starts. Applied live + verified (daemon loaded pinyin addon, `--check` passes).
- [x] **Phase 13 — immediate session apply:** order script pushes `GTK/QT_IM_MODULE` + `XMODIFIERS` into dbus + the systemd user manager after starting, so newly opened apps work with no logout. Already-open apps still need a restart (per-process env can't be changed from outside) — the script says so.
- [x] **Phase 14 — review fixes:** TUI log appends serialized (no lost lines), preview shows errors instead of blank, `packages.txt` supports trailing `# comments`, OTD keeps existing udev rules if the generator moves again, fcitx order script preserves extra input methods, `hopper.sh` refuses dangerous `HOPPER_DIR`, fcitx unit uses the real `fcitx5` path, script discovery unified (glob+sort), multilib edit touches only its two lines, deps pinned (`@opentui/core` 0.5.10).
- [x] **Phase 15 — self-healing multilib + kernel guard (added after live failures):** bootstrap AND packages both ensure `[multilib]` (steam installs with zero manual pre-steps). OTD script detects running-kernel-without-modules (upgrade without reboot), explains it in plain words, asks `Reboot now? [Y/n]` via `/dev/tty`, and reminds to re-run hopper after.
- [x] **Phase 16 — fcitx skip-if-done:** `20-fcitx.sh` exits after one line (`fcitx5 already set up, skipping`) when packages + env file + autostart unit + enabled state are all in place — no more redundant enable/start on re-runs.
- **v2 (out of scope):** dotfiles manager (bare git repo or stow), theming, Wayland autostart per-DE, snapshots.

## How to use (target UX)
```bash
git clone <hopper-repo> && cd hopper
bun install
bun index.ts
# check boxes -> Run -> reboot/log-out if fcitx asks
```

## Open questions for user (answer anytime, defaults in parens)
1. Paste output of `pacman -Qqe` / `yay -Qm` when ready → becomes `packages.txt`. (starter file has placeholders)
2. Drop personal scripts into `scripts/` when ready. Example of 1-2 helps set conventions.
3. Which desktop/WM? (Hyprland/KDE/GNOME?) — affects fcitx autostart hint only.
4. OK to use `yay-bin` (prebuilt) vs building `yay` from source? (default: `yay-bin`, faster)

## Non-goals / guardrails
- No auto-partitioning, no user creation, no dotfile overwriting in v1.
- No running `yay` under `sudo`. No `--noconfirm` full system `pacman -Syu` without showing user first (bootstrap does update, TUI warns).
- Every module prints what it's about to do, supports dry-run, and exits non-zero on real failure.
