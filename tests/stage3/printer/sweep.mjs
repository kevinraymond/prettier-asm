// node tests/stage3/printer/sweep.mjs [binary] [--list js-fixtures,real,ts-fixtures] [--show-diff N] [--json file]
// Runs every JS and TypeScript case (.js, .mjs, .cjs, .ts, .mts, .cts) of the lists under each
// option set below, Prettier in process (its CLI's parser for the file name) and
// the binary on stdin, and reports identical / refused / DIFFERENT per option set.
// The harness lists cover few option combinations; this covers them all for every case.
// --json writes the counts per option set to a file (cases Prettier itself rejects count as
// oracle_error there; the text output skips them).
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import prettier from "prettier";
import { flagsToOptions } from "../infra/flags.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const bin = path.resolve(argv[0] && !argv[0].startsWith("--") ? argv[0] : path.join(ROOT, "build/prettier-asm"));
const lists = opt("--list", "js-fixtures,real,ts-fixtures").split(",");
const showDiff = Number(opt("--show-diff", 0));
const jsonFile = opt("--json");
const SETS = [
  [], ["--print-width", "40"], ["--print-width", "120"], ["--print-width", "20"], ["--no-semi"],
  ["--single-quote"], ["--trailing-comma", "none"], ["--trailing-comma", "es5"], ["--use-tabs"],
  ["--tab-width", "4"], ["--arrow-parens", "avoid"], ["--no-bracket-spacing"], ["--bracket-same-line"],
  ["--quote-props", "consistent"], ["--quote-props", "preserve"], ["--object-wrap", "collapse"],
  ["--experimental-operator-position", "start"], ["--experimental-ternaries"],
  ["--experimental-ternaries", "--print-width", "40"],
];
const cases = lists.flatMap((l) => fs.readFileSync(path.join(ROOT, `corpus/cases/${l}.jsonl`), "utf8").trim().split("\n").map((x) => JSON.parse(x)))
  .filter((c) => /\.(js|mjs|cjs|ts|mts|cts)$/.test(c.args[c.args.indexOf("--stdin-filepath") + 1] ?? ""));
const run = (args, input) => new Promise((res) => {
  const p = spawn(bin, args);
  const out = [], err = [];
  p.stdout.on("data", (d) => out.push(d));
  p.stderr.on("data", (d) => err.push(d));
  p.on("close", (code) => res({ code, out: Buffer.concat(out).toString(), err: Buffer.concat(err).toString() }));
  p.stdin.end(input);
});
let shown = 0;
const total = { identical: 0, refused: 0, different: 0 };
const perSet = [];
for (const set of SETS) {
  const t = { identical: 0, refused: 0, different: 0 };
  const extra = { oracle_error: 0, different_cases: [] };
  const jobs = cases.map((c) => async () => {
    const fp = c.args[c.args.indexOf("--stdin-filepath") + 1];
    const base = c.args.filter((a, i) => a !== "--stdin-filepath" && c.args[i - 1] !== "--stdin-filepath");
    const flags = [...base.filter((a, i) => !(set.includes(a) || set.includes(base[i - 1]) && base[i - 1].startsWith("--"))), ...set];
    let expected;
    try { expected = await prettier.format(c.stdin, { filepath: fp, ...flagsToOptions(flags) }); } catch { extra.oracle_error++; return; }
    const r = await run(["--stdin-filepath", fp, ...flags], c.stdin);
    if (r.code === 3) t.refused++;
    else if (r.code === 0 && r.out === expected) t.identical++;
    else {
      t.different++;
      extra.different_cases.push(c.name);
      console.log(`DIFFERENT ${c.name} ${flags.join(" ")}`);
      if (shown++ < showDiff) console.log(`--- prettier\n${expected}--- binary\n${r.out}${r.err}---`);
    }
  });
  for (let i = 0; i < jobs.length; i += 16) await Promise.all(jobs.slice(i, i + 16).map((j) => j()));
  console.log(`${(set.join(" ") || "(defaults)").padEnd(40)} ${t.identical} identical, ${t.refused} refused, ${t.different} DIFFERENT`);
  for (const k in t) total[k] += t[k];
  perSet.push({ flags: set, cases: cases.length, ...t, ...extra });
}
console.log(`sweep: ${total.identical} identical, ${total.refused} refused, ${total.different} DIFFERENT`);
if (jsonFile) fs.writeFileSync(jsonFile, JSON.stringify({ binary: bin, lists, cases: cases.length, sets: perSet, total }, null, 1) + "\n");
process.exit(total.different ? 1 : 0);
