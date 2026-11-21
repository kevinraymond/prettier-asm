// Runs the oracle (Prettier 3.6.2 CLI) once per case and caches status, stdout and stderr.
// Usage: node tests/build-expected.mjs [list...] [--jobs N] [--verify N]
//   default: every list in corpus/cases; --verify N re-runs N random cached cases per list and compares.
import fs from "node:fs";
import { CASES_DIR, JOBS, readCases, readExpected, ensureExpected, runOracle, pool } from "./lib.mjs";

const argv = process.argv.slice(2);
const opt = (name, def) => { const i = argv.indexOf(name); return i >= 0 ? Number(argv.splice(i, 2)[1]) : def; };
const jobs = opt("--jobs", JOBS), verify = opt("--verify", 0);
const lists = argv.length ? argv : fs.readdirSync(CASES_DIR).filter((f) => f.endsWith(".jsonl")).map((f) => f.slice(0, -6)).sort();

let bad = 0;
for (const l of lists) {
  const cases = readCases(l);
  const r = await ensureExpected(cases, { jobs });
  const errors = cases.filter((c) => readExpected(c).status !== 0).length;
  console.log(`${l}: ${r.total} cases, ${r.ran} run in ${(r.ms / 1000).toFixed(1)} s (${jobs} jobs), ${errors} oracle errors`);
  if (!verify) continue;
  const sample = [...cases].sort(() => Math.random() - 0.5).slice(0, verify);
  const diffs = (await pool(sample, jobs, async (c) => {
    const a = readExpected(c), b = await runOracle(c);
    return a.status === b.status && a.stdout === b.stdout && a.stderr === b.stderr ? null : c.name;
  })).filter(Boolean);
  bad += diffs.length;
  console.log(`  verify: ${sample.length - diffs.length}/${sample.length} reruns match the cache${diffs.length ? ": " + diffs.join(" ") : ""}`);
}
process.exit(bad ? 1 : 0);
