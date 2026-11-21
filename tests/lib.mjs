// Shared helpers: case lists, the oracle cache, process runner, worker pool.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const CORPUS = path.join(ROOT, "corpus");
export const CASES_DIR = path.join(CORPUS, "cases");
export const PRETTIER_CLI = path.join(ROOT, "node_modules/prettier/bin/prettier.cjs");
export const ORACLE_VERSION = "3.6.2";
export const EXPECTED_DIR = path.join(CORPUS, "expected", `prettier-${ORACLE_VERSION}`);
export const JOBS = os.availableParallelism();

// A list name ("real") or a path to a .jsonl file.
export function caseListPath(arg) {
  if (fs.existsSync(arg)) return path.resolve(arg);
  const p = path.join(CASES_DIR, `${arg}.jsonl`);
  if (fs.existsSync(p)) return p;
  throw new Error(`no case list ${arg} (looked in ${CASES_DIR})`);
}

export function readCases(arg) {
  return fs.readFileSync(caseListPath(arg), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

export const filepathOf = (c) => c.args[c.args.indexOf("--stdin-filepath") + 1];

// An empty directory to run from, so no config, .editorconfig or ignore file applies.
let empty;
export function emptyDir() {
  if (empty) return empty;
  empty = fs.mkdtempSync(path.join(os.tmpdir(), "prettier-empty-"));
  const names = [".prettierrc", ".prettierrc.json", ".prettierrc.yaml", ".prettierrc.yml", ".prettierrc.json5",
    ".prettierrc.js", ".prettierrc.mjs", ".prettierrc.cjs", ".prettierrc.toml", "prettier.config.js",
    "prettier.config.mjs", "prettier.config.cjs", "package.json", "package.yaml", ".editorconfig",
    ".prettierignore", ".gitignore"];
  for (let d = empty; ; d = path.dirname(d)) {
    for (const n of names) if (fs.existsSync(path.join(d, n))) throw new Error(`${path.join(d, n)} would apply to the oracle`);
    if (d === path.dirname(d)) break;
  }
  process.on("exit", () => fs.rmSync(empty, { recursive: true, force: true }));
  return empty;
}

export function cacheKey(c) {
  return crypto.createHash("sha256").update(JSON.stringify([ORACLE_VERSION, c.args, c.stdin])).digest("hex");
}
const cacheFile = (key) => path.join(EXPECTED_DIR, key.slice(0, 2), `${key}.json`);

export function readExpected(c) {
  try { return JSON.parse(fs.readFileSync(cacheFile(cacheKey(c)), "utf8")); } catch { return null; }
}

function writeExpected(c, r) {
  const f = cacheFile(cacheKey(c));
  fs.mkdirSync(path.dirname(f), { recursive: true });
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(r));
  fs.renameSync(tmp, f);
}

export function envWithout(...names) {
  const env = { ...process.env };
  for (const n of names) delete env[n];
  return env;
}

// Runs one process with `input` on stdin. Never rejects.
export function run(cmd, args, { input = "", cwd = emptyDir(), env = process.env, timeout = 60_000 } = {}) {
  return new Promise((resolve) => {
    const start = process.hrtime.bigint();
    let child;
    try { child = spawn(cmd, args, { cwd, env, stdio: ["pipe", "pipe", "pipe"], detached: true }); }
    catch (e) { return resolve({ status: null, signal: null, error: e.message, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0), ms: 0 }); }
    const out = [], err = [];
    let timedOut = false, error;
    // Own process group, so a timeout also kills grandchildren that hold the pipes open.
    const timer = setTimeout(() => { timedOut = true; try { process.kill(-child.pid, "SIGKILL"); } catch {} }, timeout);
    child.stdout.on("data", (b) => out.push(b));
    child.stderr.on("data", (b) => err.push(b));
    child.stdin.on("error", () => {}); // EPIPE when the child exits without reading
    child.on("error", (e) => { error = e.message; });
    child.on("close", (status, signal) => {
      clearTimeout(timer);
      resolve({ status, signal, timedOut, error, stdout: Buffer.concat(out), stderr: Buffer.concat(err),
        ms: Number(process.hrtime.bigint() - start) / 1e6 });
    });
    child.stdin.end(input);
  });
}

export async function pool(items, jobs, fn, onDone) {
  let next = 0, done = 0;
  const results = new Array(items.length);
  await Promise.all(Array.from({ length: Math.min(jobs, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
      onDone?.(++done, items.length);
    }
  }));
  return results;
}

export async function runOracle(c) {
  const r = await run(process.execPath, [PRETTIER_CLI, ...c.args], { input: c.stdin, env: envWithout("PRETTIER_ASM_FALLBACK") });
  if (r.timedOut || r.error || r.status === null) throw new Error(`oracle failed on ${c.name}: ${r.error ?? r.signal ?? "timeout"}`);
  return { status: r.status, stdout: r.stdout.toString("utf8"), stderr: r.stderr.toString("utf8") };
}

// Fills the cache for every case not in it yet. Returns {total, ran, ms}.
export async function ensureExpected(cases, { jobs = JOBS, quiet = false } = {}) {
  if (!fs.existsSync(PRETTIER_CLI)) throw new Error(`${PRETTIER_CLI} missing: run npm install`);
  const seen = new Set();
  const todo = cases.filter((c) => { const k = cacheKey(c); if (seen.has(k)) return false; seen.add(k); return !fs.existsSync(cacheFile(k)); });
  const start = Date.now();
  const tty = process.stderr.isTTY && !quiet;
  await pool(todo, jobs, async (c) => writeExpected(c, await runOracle(c)),
    (d, n) => { if (tty && (d % 50 === 0 || d === n)) process.stderr.write(`\roracle ${d}/${n}`); });
  if (tty && todo.length) process.stderr.write("\n");
  return { total: cases.length, ran: todo.length, ms: Date.now() - start };
}
