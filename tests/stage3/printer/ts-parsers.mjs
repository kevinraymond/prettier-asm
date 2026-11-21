// node tests/stage3/printer/ts-parsers.mjs [--list real,ts-fixtures] [--show N] [--json out.json]
// Formats every .ts, .mts and .cts case with Prettier twice, with the `typescript` parser (what
// the CLI uses, so what corpus/expected holds) and with `babel-ts` (the AST shape the binary
// parses), and lists the cases where the two outputs differ or one parser throws.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import prettier from "prettier";
import { flagsToOptions } from "../infra/flags.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const lists = opt("--list", "real,ts-fixtures").split(",");
const show = Number(opt("--show", 0));
const jsonOut = opt("--json", null);

const firstDiff = (a, b) => {
  const al = a.split("\n"), bl = b.split("\n");
  for (let i = 0; i < Math.max(al.length, bl.length); i++)
    if (al[i] !== bl[i]) return `line ${i + 1}\n    typescript: ${al[i] ?? "<end>"}\n    babel-ts:   ${bl[i] ?? "<end>"}`;
  return "";
};

const report = [];
for (const list of lists) {
  const cases = fs.readFileSync(path.join(ROOT, `corpus/cases/${list}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l))
    .filter((c) => /\.(ts|mts|cts)$/.test(c.args[c.args.indexOf("--stdin-filepath") + 1] ?? ""));
  const n = { same: 0, differ: 0, tsError: 0, babelError: 0, bothError: 0 };
  for (const c of cases) {
    const opts = flagsToOptions(c.args);
    const fmt = async (parser) => { try { return { out: await prettier.format(c.stdin, { ...opts, parser }) }; } catch (e) { return { err: String(e.message).split("\n")[0] }; } };
    const ts = await fmt("typescript"), babel = await fmt("babel-ts");
    let kind;
    if (ts.err && babel.err) kind = "bothError";
    else if (ts.err) kind = "tsError";
    else if (babel.err) kind = "babelError";
    else kind = ts.out === babel.out ? "same" : "differ";
    n[kind]++;
    if (kind !== "same" && kind !== "bothError") {
      const detail = kind === "differ" ? firstDiff(ts.out, babel.out) : kind === "tsError" ? `typescript: ${ts.err}` : `babel-ts: ${babel.err}`;
      report.push({ list, name: c.name, kind, detail, ts: ts.out, babel: babel.out });
    }
  }
  console.log(`== ${list}: ${cases.length} cases: same ${n.same}, differ ${n.differ}, typescript throws ${n.tsError}, babel-ts throws ${n.babelError}, both throw ${n.bothError}`);
}
for (const r of report) {
  console.log(`${r.kind.padEnd(10)} ${r.list}/${r.name}\n    ${r.detail}`);
}
let shown = 0;
for (const r of report) if (r.kind === "differ" && shown++ < show) console.log(`--- ${r.name} typescript\n${r.ts}--- babel-ts\n${r.babel}---`);
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify(report, null, 1));
