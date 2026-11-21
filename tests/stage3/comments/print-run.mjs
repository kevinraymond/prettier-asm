// Compares `prettier-asm --debug-comment-docs` with Prettier's printComment for the JS printer
// (print/comment.js), comment by comment, over case lists.
//
//   node tests/stage3/comments/print-run.mjs [--bin build/prettier-asm] [--show N] list...
//
// Prettier's side is printDump in oracle.mjs.
// A list is a name in corpus/cases, a .jsonl path, or a .mjs file of {name, filepath, text}.
// Exits 1 when any comment prints differently.
import path from "node:path";
import { readCases, filepathOf, run, pool, JOBS, ROOT } from "../../lib.mjs";

import { printDump } from "./oracle.mjs";

const args = process.argv.slice(2);
let bin = path.join(ROOT, "build/prettier-asm");
let show = 5;
const lists = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--bin") bin = path.resolve(args[++i]);
  else if (args[i] === "--show") show = Number(args[++i]);
  else lists.push(args[i]);
}
if (!lists.length) lists.push("tests/stage3/comments/print-cases.mjs", "tests/stage3/comments/cases.mjs", "real", "js-fixtures");

async function loadList(name) {
  if (name.endsWith(".mjs")) {
    const mod = await import(path.resolve(name));
    return mod.default.map((c) => ({ name: c.name, filepath: c.filepath ?? "x.js", text: c.text }));
  }
  return readCases(name).map((c) => ({ name: c.name, filepath: filepathOf(c), text: c.stdin }));
}

let anyDifferent = false;
for (const list of lists) {
  const cases = (await loadList(list)).filter((c) => /\.(js|mjs|cjs|ts|mts|cts)$/.test(c.filepath));
  const results = await pool(cases, JOBS, async (c) => {
    let expected;
    try { expected = await printDump(c.text, c.filepath); } catch { expected = null; }
    const r = await run(bin, ["--debug-comment-docs", "--stdin-filepath", c.filepath], { input: c.text, timeout: 10_000 });
    if (r.status === 3) return { kind: expected ? "refused" : "both-reject", c, reason: r.stderr.toString("utf8").trim() };
    if (!expected) return { kind: "DIFFERENT", c, detail: "Prettier cannot parse the file" };
    const out = r.stdout.toString("utf8");
    if (r.status !== 0) return { kind: "DIFFERENT", c, comments: expected.count, detail: `exit ${r.status ?? r.signal} ${r.stderr}` };
    if (out === expected.out) return { kind: "identical", c, comments: expected.count };
    const a = expected.out.split("\n"), b = out.split("\n");
    const i = a.findIndex((l, k) => l !== b[k]);
    return { kind: "DIFFERENT", c, comments: expected.count, detail: `line ${i + 1}\n  prettier: ${JSON.stringify(a[i])}\n  asm:      ${JSON.stringify(b[i])}` };
  });
  const count = (k) => results.filter((r) => r.kind === k).length;
  const comments = results.filter((r) => r.kind === "identical").reduce((s, r) => s + r.comments, 0);
  console.log(`== ${list}: ${cases.length} files`);
  console.log(`identical ${count("identical")} (${comments} comments), refused ${count("refused")}, both-reject ${count("both-reject")}, DIFFERENT ${count("DIFFERENT")}`);
  const diffs = results.filter((r) => r.kind === "DIFFERENT");
  if (diffs.length) anyDifferent = true;
  for (const r of diffs.slice(0, show)) console.log(`DIFFERENT ${r.c.name}\n  ${r.detail}`);
}
process.exit(anyDifferent ? 1 : 0);
