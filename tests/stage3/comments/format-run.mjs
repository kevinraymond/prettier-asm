// Formats the comment case lists end to end with Prettier and the binary and compares the
// output where the binary does not refuse. Until the printer handles everything, this covers
// the cases whose code it prints.
//
//   node tests/stage3/comments/format-run.mjs [--bin build/prettier-asm] [--show N] list...
import path from "node:path";
import { run, pool, JOBS, ROOT } from "../../lib.mjs";

const prettier = await import(path.join(ROOT, "node_modules/prettier/index.mjs"));
const args = process.argv.slice(2);
let bin = path.join(ROOT, "build/prettier-asm");
let show = 5;
const lists = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--bin") bin = path.resolve(args[++i]);
  else if (args[i] === "--show") show = Number(args[++i]);
  else lists.push(args[i]);
}
if (!lists.length) lists.push("tests/stage3/comments/print-cases.mjs", "tests/stage3/comments/cases.mjs");

let anyDifferent = false;
for (const list of lists) {
  const cases = (await import(path.resolve(list))).default;
  const results = await pool(cases, JOBS, async (c) => {
    let expected = null;
    try { expected = await prettier.format(c.text, { filepath: c.filepath, ...c.options }); } catch {}
    const flags = ["--stdin-filepath", c.filepath];
    if (c.options?.experimentalTernaries) flags.push("--experimental-ternaries");
    const r = await run(bin, flags, { input: c.text, timeout: 10_000 });
    if (r.status === 3) return { kind: "refused", c };
    const out = r.stdout.toString("utf8");
    if (r.status === 0 && out === expected) return { kind: "identical", c };
    return { kind: "DIFFERENT", c, detail: `exit ${r.status}\n--- prettier\n${expected}--- asm\n${out}${r.stderr}` };
  });
  const count = (k) => results.filter((r) => r.kind === k).length;
  console.log(`== ${list}: ${cases.length} cases\nidentical ${count("identical")}, refused ${count("refused")}, DIFFERENT ${count("DIFFERENT")}`);
  const diffs = results.filter((r) => r.kind === "DIFFERENT");
  if (diffs.length) anyDifferent = true;
  for (const r of diffs.slice(0, show)) console.log(`DIFFERENT ${r.c.name}\n${r.detail}`);
}
process.exit(anyDifferent ? 1 : 0);
