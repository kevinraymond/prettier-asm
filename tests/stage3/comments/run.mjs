// Compares `prettier-asm --debug-comments` with where Prettier attaches each comment
// (oracle.mjs), over case lists.
//
//   node tests/stage3/comments/run.mjs [--bin build/prettier-asm] [--show N] [--filter S]
//                                      [--quiet] list...
//
// A list is a name in corpus/cases (real, js-fixtures), a .jsonl path, or a .mjs file whose
// default export is an array of {name, filepath, text, options}. Only .js, .mjs, .cjs, .ts, .mts
// and .cts files are used; TypeScript goes through babel-ts. `--experimental-ternaries` in a case's args is passed on to both sides. Per list it
// reports files identical, refused (exit 3, grouped by reason), both-reject (Prettier throws and
// the binary exits 3) and DIFFERENT, and the comments compared and how many lines differ.
// Exits 1 when any case is DIFFERENT.
import path from "node:path";
import { readCases, filepathOf, run, pool, JOBS, ROOT } from "../../lib.mjs";
import { attachDump } from "./oracle.mjs";

const args = process.argv.slice(2);
let bin = path.join(ROOT, "build/prettier-asm");
let show = 5;
let filter = null;
let quiet = false;
const lists = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--bin") bin = path.resolve(args[++i]);
  else if (args[i] === "--show") show = Number(args[++i]);
  else if (args[i] === "--filter") filter = args[++i];
  else if (args[i] === "--quiet") quiet = true;
  else lists.push(args[i]);
}
if (!lists.length) lists.push("real", "js-fixtures", "tests/stage3/comments/cases.mjs");

async function loadList(name) {
  if (name.endsWith(".mjs")) {
    const mod = await import(path.resolve(name));
    return mod.default.map((c) => ({ name: c.name, filepath: c.filepath ?? "x.js", text: c.text,
      ternaries: !!c.options?.experimentalTernaries }));
  }
  return readCases(name).map((c) => ({ name: c.name, filepath: filepathOf(c), text: c.stdin,
    ternaries: c.args.includes("--experimental-ternaries") }));
}

// Lines of a dump that differ, as a count over the longer of the two
function lineDiffs(a, b) {
  const al = a.split("\n"), bl = b.split("\n");
  let n = 0, first = null;
  for (let i = 0; i < Math.max(al.length, bl.length); i++) {
    if (al[i] !== bl[i]) { n++; first ??= `line ${i + 1}\n  prettier: ${al[i] ?? "<end>"}\n  asm:      ${bl[i] ?? "<end>"}`; }
  }
  return { n, first };
}

let anyDifferent = false;
for (const list of lists) {
  let cases = (await loadList(list)).filter((c) => /\.(js|mjs|cjs|ts|mts|cts)$/.test(c.filepath));
  if (filter) cases = cases.filter((c) => c.name.includes(filter));
  const results = await pool(cases, JOBS, async (c) => {
    // Blank input is formatted without parsing, so Prettier never attaches anything.
    if (!c.text.trim()) return { kind: "identical", c, comments: 0, diffs: 0 };
    let expected, oracleError;
    try { expected = await attachDump(c.text, c.filepath, { experimentalTernaries: c.ternaries }); }
    catch (e) { oracleError = e.message.split("\n")[0]; }
    const flags = ["--debug-comments", "--stdin-filepath", c.filepath];
    if (c.ternaries) flags.push("--experimental-ternaries");
    const r = await run(bin, flags, { input: c.text, timeout: 10_000 });
    const out = r.stdout.toString("utf8");
    const err = r.stderr.toString("utf8").trim();
    if (r.status === 3) {
      const reason = err.replace(/^unsupported: /, "");
      return oracleError ? { kind: "both-reject", c, reason } : { kind: "refused", c, reason };
    }
    if (r.status !== 0) return { kind: "DIFFERENT", c, detail: `exit ${r.status ?? r.signal}${r.timedOut ? " (timeout)" : ""} ${err}` };
    if (oracleError) return { kind: "DIFFERENT", c, detail: `Prettier throws (${oracleError}) but the binary attaches` };
    const comments = expected.split("\n").filter((l) => /^\d/.test(l)).length;
    if (out === expected) return { kind: "identical", c, comments, diffs: 0 };
    const d = lineDiffs(expected, out);
    return { kind: "DIFFERENT", c, comments, diffs: d.n, detail: d.first };
  });
  const count = (k) => results.filter((r) => r.kind === k).length;
  const sum = (f) => results.reduce((s, r) => s + (r[f] ?? 0), 0);
  const reasons = new Map();
  for (const r of results) if (r.kind === "refused") reasons.set(r.reason, (reasons.get(r.reason) ?? 0) + 1);
  console.log(`== ${list}: ${cases.length} files`);
  console.log(`identical ${count("identical")}, refused ${count("refused")}, both-reject ${count("both-reject")}, DIFFERENT ${count("DIFFERENT")}`);
  console.log(`comments compared ${sum("comments")}, differing lines ${sum("diffs")}`);
  if (!quiet) for (const [reason, n] of [...reasons].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(4)}  ${reason}`);
  const diffs = results.filter((r) => r.kind === "DIFFERENT");
  if (diffs.length) anyDifferent = true;
  for (const r of diffs.slice(0, show)) console.log(`DIFFERENT ${r.c.name}\n  ${r.detail}`);
}
process.exit(anyDifferent ? 1 : 0);
