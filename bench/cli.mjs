// CLI benchmark, one process per file, the method of prettier-rs's bench/cli.mjs (spawnSync per case,
// hrtime around it, the file on stdin), for any number of contenders.
// Usage: node bench/cli.mjs <caselist> <name=command>... [--reps N] [--names file] [--filter re]
//          [--cwd dir] [--allow-mismatch] [--no-check name,...] [--json]
// A command is split on spaces; leading VAR=value words set env, relative paths that exist are made absolute.
// Example:
//   node bench/cli.mjs real "prettier=node node_modules/prettier/bin/prettier.cjs" \
//     "asm=PRETTIER_ASM_FALLBACK=node_modules/prettier/bin/prettier.cjs build/prettier-asm"
// Every contender's output is checked against the oracle cache first (untimed, also the warm-up);
// a mismatch stops the run, or with --allow-mismatch drops that case for every contender.
// --no-check names contenders whose output is not compared (a do-nothing binary timed as a process floor).
// --json adds every rep's total and every case's time per rep, for bench/record.mjs.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { readCases, readExpected, ensureExpected, emptyDir } from "../tests/lib.mjs";

const argv = process.argv.slice(2);
const flag = (n) => { const i = argv.indexOf(n); if (i < 0) return false; argv.splice(i, 1); return true; };
const opt = (n, def) => { const i = argv.indexOf(n); return i < 0 ? def : argv.splice(i, 2)[1]; };
const reps = Number(opt("--reps", 5)), namesFile = opt("--names"), filter = opt("--filter");
const cwd = path.resolve(opt("--cwd", emptyDir())), allowMismatch = flag("--allow-mismatch"), asJson = flag("--json");
const noCheck = new Set((opt("--no-check", "") || "").split(",").filter(Boolean));
const [listArg, ...specs] = argv;
if (!listArg || !specs.length || specs.some((s) => !s.includes("="))) {
  console.error("usage: node bench/cli.mjs <caselist> <name=command>... [--reps N] [--names file] [--filter re] [--cwd dir] [--allow-mismatch] [--no-check name,...] [--json]");
  process.exit(2);
}

const abs = (s) => (s.includes("/") && fs.existsSync(s) ? path.resolve(s) : s);
const contenders = specs.map((s) => {
  const name = s.slice(0, s.indexOf("=")), words = s.slice(s.indexOf("=") + 1).trim().split(/\s+/);
  const env = {};
  while (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0])) { const w = words.shift(), k = w.slice(0, w.indexOf("=")); env[k] = abs(w.slice(k.length + 1)); }
  const [cmd, ...args] = words.map(abs);
  return { name, cmd: cmd === "node" ? process.execPath : cmd, args, env: { ...process.env, ...env }, label: s.slice(name.length + 1) };
});

let cases = readCases(listArg);
if (namesFile) { const want = new Set(fs.readFileSync(namesFile, "utf8").split("\n").filter(Boolean)); cases = cases.filter((c) => want.has(c.name)); }
if (filter) { const re = new RegExp(filter); cases = cases.filter((c) => re.test(c.name)); }
await ensureExpected(cases, { quiet: true });

const run = (k, c) => {
  const start = process.hrtime.bigint();
  const r = spawnSync(k.cmd, [...k.args, ...c.args], { input: c.stdin, cwd, env: k.env, timeout: 60_000, maxBuffer: 1 << 28 });
  const ms = Number(process.hrtime.bigint() - start) / 1e6;
  if (r.status === null) throw new Error(`${k.name}: ${r.error?.message ?? r.signal ?? "timeout"} on ${c.name}`);
  return { ms, r };
};
const log = asJson ? () => {} : console.log;
const load = os.loadavg();
log(`load average ${load.map((x) => x.toFixed(2)).join(" ")}; ${os.cpus()[0].model}, ${os.cpus().length} threads; node ${process.version}`);
for (const k of contenders) log(`  ${k.name}: ${k.label}${noCheck.has(k.name) ? " (output not checked)" : ""}`);
for (const n of noCheck) if (!contenders.some((k) => k.name === n)) { console.error(`--no-check ${n}: no such contender`); process.exit(2); }
if (contenders.every((k) => noCheck.has(k.name))) { console.error("--no-check: at least one contender must be checked"); process.exit(2); }

// Check, untimed.
const bad = new Set(), mismatches = [];
for (const k of contenders) for (const c of cases) {
  const e = readExpected(c), { r } = run(k, c);
  if (noCheck.has(k.name)) continue;
  if (r.status !== e.status || !r.stdout.equals(Buffer.from(e.stdout))) {
    bad.add(c.name);
    mismatches.push({ contender: k.name, case: c.name, exit: r.status, want_exit: e.status });
    log(`  mismatch: ${k.name} on ${c.name} (exit ${r.status}, want ${e.status})`);
  }
}
if (bad.size && !allowMismatch) { console.error(`${bad.size} cases differ from Prettier; fix them or pass --allow-mismatch`); process.exit(1); }
cases = cases.filter((c) => !bad.has(c.name));
if (!cases.length) { console.error("no case is left to time"); process.exit(1); }
log(`${cases.length} cases, every output checked against Prettier${bad.size ? ` (${bad.size} dropped)` : ""}; ${reps} reps`);

// Timed reps; the contender order rotates each rep.
const totals = contenders.map(() => []);            // [contender][rep] ms
const perCase = contenders.map(() => cases.map(() => [])); // [contender][case][rep] ms
for (let rep = 0; rep < reps; rep++) {
  const t = contenders.map(() => 0);
  cases.forEach((c, ci) => {
    for (let j = 0; j < contenders.length; j++) {
      const i = (j + rep) % contenders.length, { ms } = run(contenders[i], c);
      t[i] += ms; perCase[i][ci].push(ms);
    }
  });
  t.forEach((ms, i) => totals[i].push(ms));
}

const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const rows = contenders.map((k, i) => ({
  name: k.name,
  rep_min_ms: Math.min(...totals[i]), rep_median_ms: median(totals[i]), total_ms: totals[i].reduce((a, b) => a + b, 0),
  file_median_ms: median(perCase[i].map(median)),
}));
const base = rows[0].rep_median_ms;
if (asJson) {
  console.log(JSON.stringify({ loadavg: load, loadavg_end: os.loadavg(), cases: cases.length, dropped: [...bad], mismatches, reps,
    case_names: cases.map((c) => c.name),
    contenders: rows.map((r, i) => ({ ...r, vs_first: base / r.rep_median_ms, label: contenders[i].label, checked: !noCheck.has(r.name),
      rep_totals_ms: totals[i], case_rep_ms: perCase[i] })) }, null, 1));
} else {
  const f = (ms) => (ms / 1000).toFixed(3).padStart(9);
  log(`\n${"contender".padEnd(14)}  ${"min s".padStart(9)}  ${"median s".padStart(9)}  ${"total s".padStart(9)}  ${"file med ms".padStart(11)}  speedup`);
  for (const r of rows) log(`${r.name.padEnd(14)}  ${f(r.rep_min_ms)}  ${f(r.rep_median_ms)}  ${f(r.total_ms)}  ${r.file_median_ms.toFixed(2).padStart(11)}  ${(base / r.rep_median_ms).toFixed(2)}x`);
  log(`min/median: per-rep total over ${cases.length} cases; total: all ${reps} reps; file med: median over cases of each case's median; speedup: vs ${rows[0].name} on median`);
  log(`load average at end ${os.loadavg().map((x) => x.toFixed(2)).join(" ")}`);
}
