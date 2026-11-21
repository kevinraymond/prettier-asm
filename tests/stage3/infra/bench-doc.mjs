// node bench-doc.mjs [binary] [file] [runs]
// Time to print one file's doc in the binary's eval mode, against
// prettier.doc.printer.printDocToString in this process. The binary time is
// (time with N prints - time with 0 prints) / N, so reading the doc text
// does not count.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import prettier from "prettier";
import { ROOT } from "../../lib.mjs";
import { docToText, optionsText } from "./doc-text.mjs";

const [bin = path.join(ROOT, "build/prettier-asm"),
  file = path.join(ROOT, "corpus/real/Fuse/test/fuzzy-search.test.js"), runsArg = "200"] = process.argv.slice(2);
const runs = Number(runsArg);
const o = { printWidth: 80, tabWidth: 2, useTabs: false, endOfLine: "lf" };
const doc = await prettier.__debug.printToDoc(fs.readFileSync(file, "utf8"), { filepath: file });
const text = docToText(doc, { exact: true });
const dir = path.join(ROOT, "build/stage3-bench");
fs.mkdirSync(dir, { recursive: true });
const write = (n) => {
  const f = path.join(dir, `bench${n}.txt`);
  fs.writeFileSync(f, `(doc ${text})\n(bench ${n} ${optionsText(o)})\n`);
  return f;
};
const time = (f) => {
  let best = Infinity;
  for (let k = 0; k < 7; k++) {
    const t = process.hrtime.bigint();
    execFileSync(bin, ["--debug-doc-eval", f]);
    best = Math.min(best, Number(process.hrtime.bigint() - t) / 1e6);
  }
  return best;
};
const t0 = time(write(0));
const tn = time(write(runs));
const out = prettier.doc.printer.printDocToString(doc, o).formatted;
let t = process.hrtime.bigint();
for (let k = 0; k < runs; k++) prettier.doc.printer.printDocToString(doc, o);
const js = Number(process.hrtime.bigint() - t) / 1e6 / runs;
console.log(`${path.relative(ROOT, file)}: ${out.length} bytes out, doc text ${text.length} bytes`);
console.log(`binary: read doc + 0 prints ${t0.toFixed(2)} ms; one print ${((tn - t0) / runs * 1000).toFixed(1)} us (best of 7, ${runs} prints)`);
console.log(`prettier printDocToString (warm, in process): ${(js * 1000).toFixed(1)} us per print`);
