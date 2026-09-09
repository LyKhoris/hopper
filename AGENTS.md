# AGENTS.md — instructions for AI agents working on Hopper

> Hopper = Arch distro-hop bootstrapper with OpenTUI checklist. Owner has zero coding
> experience and is vibe-coding. Optimize for simplicity, plain language, and safe re-runs.

## Project summary
- One repo turns a fresh Arch-based install into a working daily driver.
- Stack: **Bun 1.3+ + TypeScript + @opentui/core** for TUI, **Bash** for system modules.
- TUI (`index.ts`) is a thin checklist that shells out to `modules/*.sh` via `Bun.$`.
- Modules must also work standalone: `bash modules/10-packages.sh` with no TUI.

## Repo layout (do not restructure without asking)
```
index.ts            # OpenTUI checklist UI, no business logic beyond wiring
packages.txt        # one package per line, # comments allowed
modules/00-bootstrap.sh  # Arch check, base-devel+git, yay-bin install
modules/10-packages.sh   # yay install loop over packages.txt
modules/20-fcitx.sh      # fcitx5 + chinese-addons + mozc + env vars
modules/30-scripts.sh    # runs scripts/*.sh sorted
scripts/            # user drop-in scripts, numbered NN-name.sh
logs/               # gitignored run logs
PLAN.md             # product plan + interview decisions
```

## Commands (Bun project, Arch host)
- Install deps: `bun install`
- Run TUI: `bun index.ts` (or `bun run start`)
- Typecheck: `bunx tsc --noEmit`
- Lint shell: `shellcheck modules/*.sh scripts/*.sh` (if shellcheck installed)
- Test module standalone: `bash -n modules/<file>.sh` (syntax) then `DRY_RUN=1 bash modules/<file>.sh`
- Do NOT run full installers in CI/verification unless explicitly asked — use `DRY_RUN=1`.

## Coding conventions
1. **Vibe-code friendly:** prefer flat, commented Bash + small TS functions. No clever one-liners, no frameworks beyond `@opentui/core`. Explain every new file in `scripts/README.md` or code header.
2. **Idempotency is mandatory:** every module must be safe to run twice. Pattern: check-before-do (`command -v yay`, `pacman -Q pkg`, `grep -q` before append). Report skips via `log_skip` (hidden unless `HOPPER_VERBOSE=1` — the preview already listed them); summaries always print.
3. **Arch safety rules:**
   - Detect Arch: require `pacman` binary + ID_LIKE containing `arch` in `/etc/os-release`. Exit 1 with friendly message otherwise.
   - NEVER `sudo yay`. yay must run as normal user. Only `pacman -S` uses `sudo`.
   - Use `--needed --noconfirm` for non-interactive installs, but TUI must warn before `pacman -Syu`.
   - No overwriting user configs: write new files only if missing, or append guarded by `grep -q` marker. Back up before edit (`cp -n file file.bak`).
4. **Bash style:** `set -euo pipefail`, double-quote vars, functions named `step_*` / `ensure_*`. Support `DRY_RUN=1` env that echoes instead of executing.
5. **TypeScript style:** `import { createCliRenderer, Box, Text } from "@opentui/core"`. Keep `index.ts` under ~300 lines; extract runner to `lib/runner.ts` if it grows. Stream child output line-by-line to log pane, never block renderer.
6. **TUI keys (fixed):** `Space` toggle, `↑/↓` navigate, `Enter` review full plan, `Enter` again confirm / `Esc` back, `q` quit, `d` toggle dry-run. `Enter` must NEVER run anything directly — always via the `modules/99-preview.sh` confirm screen. Keep single-screen "Checklist and Go" — do not add wizard pages without asking.
7. **Logging:** every run writes `logs/hopper-<YYYYMMDD-HHMMSS>.log`. Module output goes to both log pane + file. Final summary lists ✅/❌ per module.
8. **fcitx specifics (locked):** packages = `fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-chinese-addons fcitx5-mozc`. Env vars `GTK_IM_MODULE=fcitx`, `QT_IM_MODULE=fcitx`, `XMODIFIERS=@im=fcitx` via `~/.config/environment.d/fcitx.conf` (preferred) — do not edit `/etc/environment` unless user asks.

## What NOT to do
- Don't add dotfiles management (v2), theming engines, or multi-distro (Debian/Fedora) support.
- Don't add React/Solid bindings — stick to `@opentui/core` imperative API for v1.
- Don't commit `logs/`, `node_modules/`, or personal `scripts/*.sh` contents beyond examples (check with owner).
- Don't change `packages.txt` format (one-per-line) — owner edits it by hand.

## Before finishing any task
1. `bunx tsc --noEmit` passes (once TS exists).
2. `bash -n` passes on touched shell files.
3. New behavior is runnable via both TUI checkbox AND standalone `bash modules/...`.
4. Update `PLAN.md` checkboxes + `scripts/README.md` if conventions changed.
5. Summarize in plain, non-technical language what changed and how to try it (owner is non-coder).
