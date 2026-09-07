# Hopper — one command to set up any Arch-based distro

Fresh install -> working system: packages via yay, fcitx5 Chinese/Japanese keyboards,
multilib, osu! tablet fix, plus your own scripts. Pick via checklist TUI or plain bash.

## Use from a fresh install (no clone needed)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LyKhoris/hopper/main/hopper.sh) --yes
```

- What it installs by itself: only `git` (if missing, needed to download hopper).
  Everything else is your own list below, which you can read on GitHub first.
- Flags: `--yes` (skip confirm), `--dry-run` (print only), `--only bootstrap,packages,fcitx,scripts`, `--list`.

## Use from a clone (to edit your lists)

```bash
git clone <your-hopper-url> && cd hopper
bun install
bun index.ts        # checklist TUI: Space toggle, Up/Down move, Enter run, d dry-run, q quit
# or without TUI:
bash run.sh --yes
```

## Edit your setup (no coding needed)

- `packages.txt` — one package per line, `#` comments OK. Add/remove anytime.
- `scripts/` — drop `NN-name.sh` files (run in order). See `scripts/README.md`.
- `modules/20-fcitx.sh` — fixed fcitx5 Pinyin + Mozc list, usually untouched.

## What's inside

- `hopper.sh` — remote entrypoint for the curl one-liner (only fetches git + repo).
- `run.sh` — local runner, same steps as the TUI, logs to `logs/hopper-<time>.log`.
- `modules/` — `00-bootstrap` (base-devel/git/yay), `10-packages`, `20-fcitx`, `30-scripts`.
- `scripts/` — `10-multilib` (enables multilib for steam/games), `20-opentabletdriver` (osu! tablet fix).
- `index.ts` — OpenTUI checklist, calls the same modules.

All steps are safe to run twice — they skip what's already done.
