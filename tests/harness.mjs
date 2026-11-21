// Runs every case through a binary (without PRETTIER_ASM_FALLBACK) and compares to the oracle cache.
// Usage: node tests/harness.mjs <binary> <caselist> [--filter re] [--limit N] [--show-diff N] [--json] [--jobs N] [--timeout ms]
// Classes: identical, fallback (exit 3), oracle-error (Prettier errors, binary exits 3), DIFFERENT (anything else).
// Exit status: 0 when nothing is DIFFERENT, 1 otherwise, 2 on usage errors.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { JOBS, readCases, readExpected, ensureExpected, run, pool, envWithout } from "./lib.mjs";

const argv = process.argv.slice(2);
const flag = (n) => { const i = argv.indexOf(n); if (i < 0) return false; argv.splice(i, 1); return true; };
const opt = (n, def) => { const i = argv.indexOf(n); return i < 0 ? def : argv.splice(i, 2)[1]; };
const filter = opt("--filter"), showDiff = Number(opt("--show-diff", 0)), jobs = Number(opt("--jobs", JOBS));
const timeout = Number(opt("--timeout", 10_000)), limit = Number(opt("--limit", Infinity)), asJson = flag("--json");
if (argv.length !== 2) {
  console.error("usage: node tests/harness.mjs <binary> <caselist> [--filter re] [--limit N] [--show-diff N] [--json] [--jobs N] [--timeout ms]");
  process.exit(2);
}
const [binArg, listArg] = argv;
const bin = binArg.includes("/") ? path.resolve(binArg) : binArg;
if (binArg.includes("/") && !fs.existsSync(bin)) { console.error(`harness: ${bin} does not exist`); process.exit(2); }
const listName = path.basename(listArg).replace(/\.jsonl$/, "");

let cases = readCases(listArg);
if (filter) { const re = new RegExp(filter); cases = cases.filter((c) => re.test(c.name)); }
cases = cases.slice(0, limit);
await ensureExpected(cases);

const env = envWithout("PRETTIER_ASM_FALLBACK");
const firstLine = (b) => b.toString("utf8").split("\n").find((l) => l.trim()) ?? "";
const start = Date.now();
const results = await pool(cases, jobs, async (c) => {
  const exp = readExpected(c);
  const r = await run(bin, c.args, { input: c.stdin, env, timeout });
  const res = { name: c.name, ms: Math.round(r.ms), status: r.status };
  const same = r.status === exp.status && r.stdout.equals(Buffer.from(exp.stdout)) &&
    (exp.status === 0 || r.stderr.equals(Buffer.from(exp.stderr)));
  if (same) res.class = "identical";
  else if (r.status === 3) {
    res.class = exp.status === 0 ? "fallback" : "oracle-error";
    const l = firstLine(r.stderr);
    res.reason = l.startsWith("unsupported: ") ? l.slice(13) : `(no "unsupported:" line) ${l}`.trimEnd();
  } else {
    res.class = "DIFFERENT";
    res.detail = r.timedOut ? `timeout after ${timeout} ms`
      : r.error ? `spawn error: ${r.error}`
      : r.signal ? `signal ${r.signal}`
      : r.status !== 0 ? `exit ${r.status}: ${firstLine(r.stderr)}`
      : exp.status !== 0 ? `output where Prettier exits ${exp.status}`
      : "output differs";
    if (r.status === 0) { res.actual = r.stdout.toString("utf8"); res.expected = exp.stdout; }
  }
  return res;
});
const wall = Date.now() - start;

const CLASSES = ["identical", "fallback", "oracle-error", "DIFFERENT"];
const counts = Object.fromEntries(CLASSES.map((k) => [k, results.filter((r) => r.class === k).length]));
const different = results.filter((r) => r.class === "DIFFERENT");
const reasons = new Map();
for (const r of results) if (r.reason) reasons.set(r.reason, (reasons.get(r.reason) ?? 0) + 1);
const summary = `harness ${listName}: ${cases.length} cases, ` + CLASSES.map((k) => `${counts[k]} ${k}`).join(", ") +
  ` (${(wall / 1000).toFixed(1)} s): ${different.length ? "FAIL" : "PASS"}`;

if (asJson) {
  console.log(JSON.stringify({ list: listName, binary: bin, counts, wall_ms: wall,
    fallback_reasons: Object.fromEntries([...reasons].sort((a, b) => b[1] - a[1])),
    cases: results.map(({ actual, expected, ...r }) => r) }, null, 1));
} else report();
process.exitCode = different.length ? 1 : 0; // not process.exit(): it would cut off piped stdout

function report() {
  if (different.length) {
    console.log(`DIFFERENT (${different.length}):`);
    for (const r of different) console.log(`  ${r.name}  ${r.detail}`);
  }
  const diffable = different.filter((r) => r.actual !== undefined).slice(0, showDiff);
  if (diffable.length) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "harness-diff-"));
    for (const r of diffable) {
      fs.writeFileSync(path.join(tmp, "e"), r.expected); fs.writeFileSync(path.join(tmp, "a"), r.actual);
      const d = spawnSync("diff", ["-u", "--label", `${r.name} (prettier)`, "--label", `${r.name} (binary)`,
        path.join(tmp, "e"), path.join(tmp, "a")], { encoding: "utf8" }).stdout.split("\n");
      console.log(`\n${d.slice(0, 200).join("\n")}${d.length > 200 ? `\n... ${d.length - 200} more lines` : ""}`);
    }
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  if (reasons.size) {
    console.log(`${different.length || diffable.length ? "\n" : ""}Fallback reasons (fallback + oracle-error):`);
    for (const [k, n] of [...reasons].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))) console.log(`  ${String(n).padStart(5)}  ${k}`);
  }
  console.log(summary);
}
