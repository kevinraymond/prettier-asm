// Compares `prettier-asm --debug-ast` with the AST Prettier's babel parser produces (after its
// postprocess), over case lists. TypeScript files (.ts, .mts, .cts) are compared with babel-ts;
// .tsx files must be refused, since JSX is not ported.
//
//   node tests/stage3/parser/run.mjs [--bin build/prettier-asm] [--show N] [--filter S]
//                                    [--refused REASON] [--quiet] list...
//
// A list is a name in corpus/cases (real, js-fixtures, ts-fixtures), a .jsonl path, or a .mjs
// file whose default export is an array of {name, filepath, text}. Only .js, .mjs, .cjs, .jsx,
// .ts, .mts, .cts and .tsx files are used. Each case is one of:
//   identical     same dump
//   refused       the binary exits 3 (grouped by its reason) and Babel parses the file
//   both-reject   Babel throws and the binary exits 3
//   DIFFERENT     anything else: another dump, output where Babel throws, a crash
// Exits 1 when any case is DIFFERENT.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readCases, filepathOf, run, pool, JOBS, ROOT } from "../../lib.mjs";
import { babelAst } from "./babel-ast.mjs";

const args = process.argv.slice(2);
let bin = path.join(ROOT, "build/prettier-asm");
let show = 5;
let filter = null;
let quiet = false;
let listRefused = null;
const lists = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--bin") bin = path.resolve(args[++i]);
  else if (args[i] === "--show") show = Number(args[++i]);
  else if (args[i] === "--filter") filter = args[++i];
  else if (args[i] === "--quiet") quiet = true;
  else if (args[i] === "--refused") listRefused = args[++i];
  else lists.push(args[i]);
}
if (!lists.length) lists.push("real", "js-fixtures", "ts-fixtures");

async function loadList(name) {
  if (name.endsWith(".mjs")) {
    const mod = await import(path.resolve(name));
    return mod.default.map((c) => ({ name: c.name, filepath: c.filepath ?? "x.js", text: c.text }));
  }
  return readCases(name).map((c) => ({ name: c.name, filepath: filepathOf(c), text: c.stdin }));
}

function firstDiff(a, b) {
  const al = a.split("\n"), bl = b.split("\n");
  for (let i = 0; i < Math.max(al.length, bl.length); i++) {
    if (al[i] !== bl[i]) return `line ${i + 1}\n  babel: ${al[i] ?? "<end>"}\n  asm:   ${bl[i] ?? "<end>"}`;
  }
  return "";
}

let anyDifferent = false;
for (const list of lists) {
  let cases = (await loadList(list)).filter((c) => /\.(js|mjs|cjs|jsx|ts|mts|cts|tsx)$/.test(c.filepath));
  if (filter) cases = cases.filter((c) => c.name.includes(filter));
  const results = await pool(cases, JOBS, async (c) => {
    let expected, babelError;
    try { expected = await babelAst(c.text, c.filepath); } catch (e) { babelError = e.message.split("\n")[0]; }
    const r = await run(bin, ["--debug-ast", "--stdin-filepath", c.filepath], { input: c.text, timeout: 10_000 });
    const out = r.stdout.toString("utf8");
    const err = r.stderr.toString("utf8").trim();
    if (r.status === 3) {
      const reason = err.replace(/^unsupported: /, "");
      return babelError ? { kind: "both-reject", c, reason } : { kind: "refused", c, reason };
    }
    if (r.status !== 0) return { kind: "DIFFERENT", c, detail: `exit ${r.status ?? r.signal}${r.timedOut ? " (timeout)" : ""} ${err}` };
    if (babelError) return { kind: "DIFFERENT", c, detail: `Babel throws (${babelError}) but the binary prints a tree` };
    if (out === expected) return { kind: "identical", c };
    return { kind: "DIFFERENT", c, detail: firstDiff(expected, out) };
  });
  const count = (k) => results.filter((r) => r.kind === k).length;
  const reasons = new Map();
  for (const r of results) if (r.kind === "refused") reasons.set(r.reason, (reasons.get(r.reason) ?? 0) + 1);
  console.log(`== ${list}: ${cases.length} cases`);
  console.log(`identical ${count("identical")}, refused ${count("refused")}, both-reject ${count("both-reject")}, DIFFERENT ${count("DIFFERENT")}`);
  if (!quiet) {
    for (const [reason, n] of [...reasons].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(4)}  ${reason}`);
    if (listRefused !== null) {
      for (const r of results) if (r.kind === "refused" && r.reason.includes(listRefused)) console.log(`refused ${r.c.name} (${r.c.filepath}): ${r.reason}`);
    }
    for (const r of results.filter((r) => r.kind === "DIFFERENT").slice(0, show)) {
      console.log(`DIFFERENT ${r.c.name} (${r.c.filepath})\n  ${r.detail}`);
    }
  }
  if (count("DIFFERENT")) anyDifferent = true;
}
process.exit(anyDifferent ? 1 : 0);
