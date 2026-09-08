// Hopper TUI — "Checklist and Go" built with @opentui/core.
// Run: bun install && bun index.ts
// The TUI is a thin wrapper: it just calls the same modules/run.sh the CLI uses,
// so TUI and `bash run.sh` always do the same thing.
import { createCliRenderer, Box, Text } from "@opentui/core";

type Step = { id: string; label: string; module: string; checked: boolean };

const steps: Step[] = [
  { id: "bootstrap", label: "1. Bootstrap system (base-devel, git, yay)", module: "modules/00-bootstrap.sh", checked: true },
  { id: "packages", label: "2. Install packages from packages.txt", module: "modules/10-packages.sh", checked: true },
  { id: "fcitx", label: "3. Setup fcitx5 (Pinyin + Mozc)", module: "modules/20-fcitx.sh", checked: true },
  { id: "scripts", label: "4. Run personal scripts (multilib + tablet fix)", module: "modules/30-scripts.sh", checked: true },
];

let selected = 0; // which row is highlighted (0..steps.length = dry-run row)
let dryRun = false;
let running = false;
let screen: "list" | "confirm" | "running" = "list";
let previewLines: string[] = [];
let logLines: string[] = ["Ready. Space=toggle  Enter=review  d=dry-run  q=quit"];

// Count packages + scripts for the labels (static, read once).
async function counts(): Promise<{ pkgs: number; scripts: number }> {
  let pkgs = 0;
  try {
    const txt = await Bun.file("packages.txt").text();
    for (const line of txt.split("\n")) {
      const t = line.trim();
      if (t && !t.startsWith("#")) pkgs++;
    }
  } catch {}
  let scripts = 0;
  try {
    const { readdir } = await import("node:fs/promises");
    const files = await readdir("scripts");
    scripts = files.filter((f) => /^[0-9]+-.*\.sh$/.test(f)).length;
  } catch {}
  return { pkgs, scripts };
}

function pushLog(line: string) {
  // Keep last 200 lines, display last 12.
  for (const part of line.split("\n")) {
    const clean = part.replace(/\r/g, "").slice(0, 200);
    if (clean.trim()) logLines.push(clean);
  }
  if (logLines.length > 200) logLines = logLines.slice(-200);
  render();
}

async function runModule(step: Step, logFile: string): Promise<boolean> {
  pushLog(`>>> [${step.id}] bash ${step.module}`);
  const env = { ...process.env, DRY_RUN: dryRun ? "1" : "0" };
  const proc = Bun.spawn(["bash", step.module], { stdout: "pipe", stderr: "pipe", env });
  // Serialize all file appends through one promise chain so the stdout and
  // stderr pumps can't interleave a read-modify-write and lose lines.
  // (Bun.write overwrites, so concurrent read+write would drop output.)
  let chain: Promise<void> = Promise.resolve();
  const appendLog = (text: string): Promise<void> => {
    chain = chain.then(async () => {
      try {
        const { appendFile } = await import("node:fs/promises");
        await appendFile(logFile, text);
      } catch {}
    });
    return chain;
  };
  const pump = async (s: ReadableStream<Uint8Array> | null) => {
    if (!s) return;
    const reader = s.getReader();
    const dec = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = dec.decode(value);
      pushLog(text);
      await appendLog(text);
    }
  };
  await Promise.all([pump(proc.stdout), pump(proc.stderr)]);
  const code = await proc.exited;
  // Wait for pending appends so the log file has everything before we continue.
  await chain;
  const tail = code === 0 ? `<<< [${step.id}] OK` : `<<< [${step.id}] FAILED (code ${code})`;
  pushLog(tail);
  await appendLog(tail + "\n");
  return code === 0;
}

async function runSelected() {
  if (running) return;
  running = true;
  screen = "running";
  render();
  const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const logFile = `logs/hopper-${ts}.log`;
  try {
    const { mkdir } = await import("node:fs/promises");
    await mkdir("logs", { recursive: true });
    await Bun.write(logFile, `hopper TUI run dry_run=${dryRun}\n`);
  } catch {}
  pushLog(`Logging to ${logFile}`);
  let failed = 0;
  for (const s of steps) {
    if (!s.checked) continue;
    const ok = await runModule(s, logFile);
    if (!ok) {
      failed++;
      break; // stop on first failure (matches run.sh default)
    }
  }
  pushLog(failed ? "Done with ERRORS — see log above." : "All done. fcitx may need a log-out/in.");
  running = false;
  screen = "list";
  render();
}

// Wrap long lines on word boundaries so full package names stay visible.
function wrapLine(line: string, width = 100): string[] {
  const words = line.split(" ");
  const lines: string[] = [];
  let cur = "";
  for (const word of words) {
    const next = cur ? cur + " " + word : word;
    if (next.length > width && cur) {
      lines.push(cur);
      cur = word;
    } else {
      cur = next;
    }
  }
  if (cur) lines.push(cur);
  return lines;
}

// Confirm screen: show the FULL preview before anything runs.
// Same source as `bash run.sh` (modules/99-preview.sh), so both agree.
async function gotoConfirm() {
  if (!steps.some((s) => s.checked)) {
    pushLog("Nothing selected — tick at least one box first.");
    return;
  }
  screen = "confirm";
  previewLines = ["Checking what's already installed..."];
  render();
  try {
    const only = steps.filter((s) => s.checked).map((s) => s.id).join(",");
    const proc = Bun.spawn(["bash", "modules/99-preview.sh"], {
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env, HOPPER_ONLY: only },
    });
    const out = await new Response(proc.stdout).text();
    const errText = await new Response(proc.stderr).text();
    const code = await proc.exited;
    if (code !== 0 || !out.trim()) {
      const errTail = errText.trim().split("\n").slice(-3).join("\n");
      previewLines = [
        `Preview failed (exit ${code}). Nothing was changed.`,
        ...(errTail ? [errTail] : []),
        "Run DRY_RUN=1 bash run.sh to see the plan.",
      ].flatMap((l) => wrapLine(l));
    } else {
      previewLines = out.split("\n").flatMap((l) => wrapLine(l));
    }
  } catch {
    previewLines = ["Could not build preview. Run DRY_RUN=1 bash run.sh to see the plan."];
  }
  render();
}

// --- Renderer setup ---
const renderer = await createCliRenderer({ exitOnCtrlC: true });
const root = Box({ flexDirection: "column", padding: 1, gap: 1 });
const header = Text({ content: "Hopper — Arch distro-hop setup", fg: "#00FFFF" });
const listText = Text({ content: "" });
const logText = Text({ content: "" });
const footer = Text({ content: "", fg: "#888888" });
root.add(header);
root.add(listText);
root.add(logText);
root.add(footer);
renderer.root.add(root);

function render() {
  // NOTE: proxied Text types content as StyledText, but the runtime accepts
  // plain strings — cast to keep this vibe-simple.
  if (screen === "confirm") {
    const extra = previewLines.length > 30 ? `\n... (+${previewLines.length - 30} more)` : "";
    (listText as any).content = "Review — about to install/run:";
    (logText as any).content = previewLines.slice(0, 30).join("\n") + extra;
    (footer as any).content = "Enter=yes, run it | Esc=no, go back";
    renderer.requestRender();
    return;
  }
  const rows = steps.map((s, i) => {
    const box = s.checked ? "[x]" : "[ ]";
    const arrow = i === selected ? ">" : " ";
    return `${arrow} ${box} ${s.label}`;
  });
  const dryRow = `${selected === steps.length ? ">" : " "} ${dryRun ? "[x]" : "[ ]"} Dry run (print only, change nothing) [d]`;
  (listText as any).content = rows.join("\n") + "\n" + dryRow;
  (logText as any).content = "--- log ---\n" + logLines.slice(-12).join("\n");
  (footer as any).content = screen === "running" ? "Running... please wait" : "Space toggle | Up/Down move | Enter review | d dry-run | q quit";
  renderer.requestRender();
}

renderer.keyInput.on("keypress", async (key: any) => {
  const name = key.name ?? key.sequence ?? "";
  if (name === "q" || (key.ctrl && name === "c")) {
    if (screen === "running") return; // don't quit mid-install
    renderer.destroy();
    process.exit(0);
  }
  if (screen === "confirm") {
    if (name === "return" || name === "enter" || name === "y") await runSelected();
    else if (name === "escape" || name === "n") { screen = "list"; render(); }
    return;
  }
  if (screen === "running") return;
  if (name === "up" || name === "k") {
    selected = (selected + steps.length) % (steps.length + 1);
    render();
  } else if (name === "down" || name === "j") {
    selected = (selected + 1) % (steps.length + 1);
    render();
  } else if (name === "space") {
    if (selected < steps.length) steps[selected].checked = !steps[selected].checked;
    else dryRun = !dryRun;
    render();
  } else if (name === "d") {
    dryRun = !dryRun;
    render();
  } else if (name === "return" || name === "enter") {
    await gotoConfirm(); // Enter reviews first — nothing runs until confirmed
  }
});

// Allow run.sh --tui to preselect steps.
const only = (process.env.HOPPER_ONLY ?? "").split(",").filter(Boolean);
if (only.length) {
  for (const s of steps) s.checked = only.includes(s.id);
}
if (process.env.HOPPER_DRY_RUN === "1") dryRun = true;

const c = await counts();
steps[1].label = `2. Install packages from packages.txt (${c.pkgs} found)`;
steps[3].label = `4. Run personal scripts (${c.scripts} found)`;
render();
