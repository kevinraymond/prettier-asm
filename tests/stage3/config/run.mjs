// Config, .editorconfig and ignore files: builds a directory tree per case,
// runs Prettier and the binary from the case's working directory, and sorts
// each case into identical, refused or DIFFERENT. Exit 1 on any DIFFERENT.
//
//   node tests/stage3/config/run.mjs [--bin path] [--random N] [--seed S]
//        [--jobs J] [--only text] [--show N] [--keep]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import { handCases } from "./cases.mjs";
import { randomCases } from "./random.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const PRETTIER = process.env.PRETTIER_CJS || path.join(ROOT, "node_modules/prettier/bin/prettier.cjs");

const argv = process.argv.slice(2);
const opt = (name, def) => {
  const i = argv.indexOf(name);
  return i === -1 ? def : argv[i + 1];
};
const BIN = path.resolve(opt("--bin", process.env.PRETTIER_ASM_BIN || path.join(ROOT, "build/prettier-asm")));
const RANDOM = Number(opt("--random", 300));
const SEED = Number(opt("--seed", 1));
const JOBS = Number(opt("--jobs", Math.max(2, Math.min(16, os.availableParallelism()))));
const ONLY = opt("--only", null);
const SHOW = Number(opt("--show", 5));
const KEEP = argv.includes("--keep");
// Prettier's results, keyed by the case, so reruns and mutants only run the binary.
const CACHE_FILE = path.join(ROOT, "build/stage3-config-oracle.json");
const cache = (() => {
  try { return JSON.parse(fs.readFileSync(CACHE_FILE, "utf8")); } catch { return {}; }
})();
const keyOf = (c) => crypto.createHash("sha256").update(JSON.stringify([c.tree, c.cwd, c.file, c.abs, c.args, c.mode,
  Buffer.isBuffer(c.input) ? c.input.toString("base64") : c.input, (c.tree && Object.values(c.tree).map((v) => Buffer.isBuffer(v) ? v.toString("base64") : v))])).digest("hex");
const QUIET = argv.includes("--quiet");

// Every name Prettier probes; none may sit above the base directory.
const PROBED = ["package.json", "package.yaml", ".prettierrc", ".prettierrc.json", ".prettierrc.yaml",
  ".prettierrc.yml", ".prettierrc.json5", ".prettierrc.js", ".prettierrc.ts", ".prettierrc.mjs",
  ".prettierrc.mts", ".prettierrc.cjs", ".prettierrc.cts", "prettier.config.js", "prettier.config.ts",
  "prettier.config.mjs", "prettier.config.mts", "prettier.config.cjs", "prettier.config.cts",
  ".prettierrc.toml", ".editorconfig", ".git", ".hg"];

function makeBase() {
  const parent = process.env.CONFIG_TEST_BASE || os.tmpdir();
  fs.mkdirSync(parent, { recursive: true });
  const base = fs.mkdtempSync(path.join(parent, "prettier-asm-config-"));
  for (let d = path.dirname(base); ; d = path.dirname(d)) {
    for (const n of PROBED) {
      if (fs.existsSync(path.join(d, n))) throw new Error(`${path.join(d, n)} would apply to every case`);
    }
    if (d === path.dirname(d)) break;
  }
  return base;
}

// tree: { "rel/path": string | Buffer (file), null (directory) }
function writeTree(dir, tree) {
  fs.mkdirSync(dir, { recursive: true });
  for (const [rel, content] of Object.entries(tree)) {
    const p = path.join(dir, rel);
    if (content === null) {
      fs.mkdirSync(p, { recursive: true });
    } else if (typeof content === "object" && content.symlink) {
      fs.mkdirSync(path.dirname(p), { recursive: true });
      fs.symlinkSync(content.symlink, p);
    } else {
      fs.mkdirSync(path.dirname(p), { recursive: true });
      fs.writeFileSync(p, content);
    }
  }
}

function runProcess(cmd, args, { cwd, input, env }) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd, env, stdio: ["pipe", "pipe", "pipe"] });
    const out = [];
    const err = [];
    const timer = setTimeout(() => child.kill("SIGKILL"), 60_000);
    child.stdout.on("data", (d) => out.push(d));
    child.stderr.on("data", (d) => err.push(d));
    child.on("error", (e) => err.push(Buffer.from(String(e))));
    child.on("close", (status, signal) => {
      clearTimeout(timer);
      resolve({ status, signal, stdout: Buffer.concat(out), stderr: Buffer.concat(err).toString() });
    });
    child.stdin.on("error", () => {});
    child.stdin.end(input ?? "");
  });
}

async function runCase(base, c, index) {
  const dir = path.join(base, `case${index}`);
  writeTree(dir, c.tree ?? {});
  for (const [rel, mode] of Object.entries(c.chmod ?? {})) fs.chmodSync(path.join(dir, rel), mode);
  const cwd = path.join(dir, c.cwd ?? ".");
  fs.mkdirSync(cwd, { recursive: true });
  const fileArg = c.abs ? path.join(dir, c.file) : c.file;
  const args = [...(c.args ?? [])];
  let input = c.input ?? "";
  if (c.mode === "file") {
    args.push(fileArg);
    input = "";
  } else {
    args.push("--stdin-filepath", fileArg);
  }
  const env = { ...process.env };
  delete env.PRETTIER_ASM_FALLBACK;
  const key = keyOf(c);
  const cached = cache[key];
  const [p, b] = await Promise.all([
    cached
      ? { ...cached, stdout: Buffer.from(cached.stdout, "base64") }
      : runProcess(process.execPath, [PRETTIER, ...args], { cwd, input, env }),
    runProcess(BIN, args, { cwd, input, env }),
  ]);
  if (!cached) cache[key] = { status: p.status, stdout: p.stdout.toString("base64"), stderr: p.stderr };
  let cls;
  if (b.status === 3 && b.stderr.startsWith("unsupported: ")) cls = "refused";
  else if (p.status === b.status && p.stdout.equals(b.stdout) && (p.status === 0 || p.stderr === b.stderr)) cls = "identical";
  else cls = "DIFFERENT";
  return { c, p, b, cls, dir };
}

async function pool(items, jobs, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: jobs }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  }));
  return results;
}

const cases = [...handCases(), ...randomCases(RANDOM, SEED)].filter((c) => !ONLY || c.name.includes(ONLY));
const base = makeBase();
const results = await pool(cases, JOBS, (c, i) => runCase(base, c, i));

const count = { identical: 0, refused: 0, DIFFERENT: 0 };
let unchanged = 0;
const reasons = new Map();
const groups = { hand: { identical: 0, refused: 0, DIFFERENT: 0 }, random: { identical: 0, refused: 0, DIFFERENT: 0 } };
let shown = 0;
for (const r of results) {
  count[r.cls]++;
  if (r.cls === "identical" && r.p.stdout.equals(Buffer.from(r.c.input ?? ""))) unchanged++;
  groups[r.c.name.startsWith("random") ? "random" : "hand"][r.cls]++;
  if (r.cls === "refused") {
    const reason = r.b.stderr.trim();
    reasons.set(reason, (reasons.get(reason) ?? 0) + 1);
  }
  if (r.cls === "DIFFERENT" && shown++ < SHOW) {
    console.log(`DIFFERENT ${r.c.name}  (${r.dir})`);
    console.log(`  tree: ${JSON.stringify(r.c.tree)}`);
    console.log(`  cwd: ${r.c.cwd ?? "."}  file: ${r.c.file}  args: ${JSON.stringify(r.c.args ?? [])}  mode: ${r.c.mode ?? "stdin"}`);
    console.log(`  prettier exit ${r.p.status}: ${JSON.stringify(r.p.stdout.toString().slice(0, 400))} ${r.p.stderr.slice(0, 300)}`);
    console.log(`  binary   exit ${r.b.status}: ${JSON.stringify(r.b.stdout.toString().slice(0, 400))} ${r.b.stderr.slice(0, 300)}`);
  }
  if (!QUIET && r.cls !== "DIFFERENT" && process.env.VERBOSE) {
    console.log(`${r.cls.padEnd(9)} ${r.c.name}${r.cls === "refused" ? "  " + r.b.stderr.trim() : ""}${r.p.status ? "  (prettier exit " + r.p.status + ")" : ""}`);
  }
}
if (!QUIET) {
  for (const [reason, n] of [...reasons].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(4)}  ${reason}`);
  for (const [g, v] of Object.entries(groups)) {
    console.log(`${g.padEnd(6)} identical ${v.identical}  refused ${v.refused}  DIFFERENT ${v.DIFFERENT}`);
  }
}
console.log(`identical cases printed unchanged (ignored files): ${unchanged}`);
console.log(`total ${cases.length}  identical ${count.identical}  refused ${count.refused}  DIFFERENT ${count.DIFFERENT}`);
if (!KEEP) {
  for (const [i, c] of cases.entries()) {
    for (const rel of Object.keys(c.chmod ?? {})) fs.chmodSync(path.join(base, `case${i}`, rel), 0o755);
  }
  fs.rmSync(base, { recursive: true, force: true });
}
fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
fs.writeFileSync(CACHE_FILE + ".tmp", JSON.stringify(cache));
fs.renameSync(CACHE_FILE + ".tmp", CACHE_FILE);
process.exit(count.DIFFERENT > 0 ? 1 : 0);
