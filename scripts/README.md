# scripts/ — your personal drop-in scripts

Drop any `.sh` file here named `NN-name.sh`, for example:
- `10-multilib.sh` — enable multilib repo (already included)
- `20-opentabletdriver.sh` — fix osu! tablet detection (already included)
- `30-fcitx-im-order.sh` — set fcitx input order EN -> Pinyin -> Mozc (already included)
- `30-my-tweaks.sh` — anything you add later

Rules (kept simple on purpose):
1. Number prefix decides order: `10-` runs before `20-`.
2. Every script must be safe to run twice (check before you do).
3. Support dry-run: wrap real changes so `DRY_RUN=1 bash scripts/30-foo.sh` only prints.
4. Start each file with `set -euo pipefail`.
5. Give it a short display name for the pre-install preview: `HOPPER_TITLE="Fix osu! tablet detection"`
   (shown as `Scripts (2): Enable multilib repo, Fix osu! tablet detection`).
   Without it, the filename is prettified automatically.
6. Optional but recommended: support `--check` so applied scripts get skipped
   instantly (no re-running). Add `SUPPORTS_CHECK=1` at the top plus a block
   that exits 0 when there's nothing to do, 1 when work is needed:
   ```bash
   if [ "${1:-}" = "--check" ]; then
     if grep -q "thing-im-done" /path/to/state 2>/dev/null; then
       exit 0
     else
       exit 1
     fi
   fi
   ```
   Keep the check to fast local reads only (no sudo, no network).
5. To test one script: `DRY_RUN=1 bash scripts/NN-name.sh`, then for real: `bash scripts/NN-name.sh`.

The TUI checkbox "Run personal scripts" just runs all of these in order via `modules/30-scripts.sh`.
To skip one temporarily, rename it to `NN-name.sh.off`.
