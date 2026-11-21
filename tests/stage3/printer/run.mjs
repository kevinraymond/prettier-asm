// node tests/stage3/printer/run.mjs [binary] [cases.mjs] [--filter text] [--show-diff]
// Runs the snippets of a case file (cases.mjs by default; ts-cases.mjs has the TypeScript ones),
// each under its flags and under --print-width 40 and --no-semi, through Prettier and the binary:
// identical, refused (grouped by reason) or DIFFERENT. Where Prettier throws, the binary must
// refuse (counted as prettier errors). The file's `filepath` export names the input (case.js
// when it has none). Exits 1 on any DIFFERENT.
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import prettier from "prettier";
import { flagsToOptions } from "../infra/flags.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const argv = process.argv.slice(2);
const showDiff = argv.includes("--show-diff");
const fi = argv.indexOf("--filter");
const filter = fi >= 0 ? argv[fi + 1] : null;
const positional = argv.filter((a, i) => !a.startsWith("--") && argv[i - 1] !== "--filter");
const bin = path.resolve(positional.find((a) => !a.endsWith(".mjs")) ?? path.join(ROOT, "build/prettier-asm"));
const mod = await import(path.resolve(positional.find((a) => a.endsWith(".mjs")) ?? path.join(ROOT, "tests/stage3/printer/cases.mjs")));
const cases = mod.default, filepath = mod.filepath ?? "case.js";
const counts = { identical: 0, refused: 0, prettierError: 0, different: 0 };
const reasons = new Map();
for (const c of cases) {
  const [code, flags = []] = Array.isArray(c) ? c : [c];
  if (filter && !code.includes(filter)) continue;
  for (const extra of [[], ["--print-width", "40"], ["--no-semi"]]) {
    const all = [...flags, ...extra];
    let expected = null;
    try {
      expected = await prettier.format(code, { filepath, ...flagsToOptions(all) });
    } catch {}
    const r = spawnSync(bin, ["--stdin-filepath", filepath, ...all], { input: code });
    if (expected === null && r.status === 3) counts.prettierError++;
    else if (r.status === 3) {
      counts.refused++;
      const why = r.stderr.toString().trim();
      reasons.set(why, (reasons.get(why) ?? 0) + 1);
    } else if (r.status === 0 && r.stdout.toString() === expected) counts.identical++;
    else {
      counts.different++;
      console.log(`DIFFERENT ${JSON.stringify(code)} ${all.join(" ")}`);
      if (showDiff) console.log(`--- prettier\n${expected}--- binary\n${r.stdout}${r.stderr}---`);
    }
  }
}
for (const [why, n] of [...reasons].sort((a, b) => b[1] - a[1])) console.log(`${String(n).padStart(6)}  ${why}`);
console.log(`printer cases: ${counts.identical} identical, ${counts.refused} refused, ${counts.prettierError} prettier errors, ${counts.different} DIFFERENT`);
process.exit(counts.different ? 1 : 0);
