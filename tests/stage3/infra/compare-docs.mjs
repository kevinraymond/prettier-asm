// node compare-docs.mjs [--exact] [binary] [case list...]
// Runs `binary --debug-doc` on every case and compares the doc text with the
// one written from prettier.__debug.printToDoc. Cases where either side
// refuses or errors are counted, not compared.
import path from "node:path";
import prettier from "prettier";
import { readCases, run, pool, JOBS, ROOT } from "../../lib.mjs";
import { docToText } from "./doc-text.mjs";
import { flagsToOptions } from "./flags.mjs";

const argv = process.argv.slice(2);
const exact = argv.includes("--exact");
const [binArg = path.join(ROOT, "build/prettier-asm"), ...lists] = argv.filter((a) => a !== "--exact");
const bin = path.resolve(binArg);
const cases = (lists.length ? lists : ["json"]).flatMap((l) => readCases(l));
const counts = { same: 0, different: 0, refused: 0, prettierError: 0 };
const diffs = [];

await pool(cases, JOBS, async (c) => {
  let expected;
  try {
    const doc = await prettier.__debug.printToDoc(c.stdin, flagsToOptions(c.args));
    expected = docToText(doc, { exact });
  } catch {
    counts.prettierError++;
    return;
  }
  const r = await run(bin, [exact ? "--debug-doc-exact" : "--debug-doc", ...c.args], { input: c.stdin });
  if (r.status !== 0) {
    counts.refused++;
    return;
  }
  const actual = r.stdout.toString("utf8").replace(/\n$/, "");
  if (actual === expected) counts.same++;
  else {
    counts.different++;
    let i = 0;
    while (actual[i] === expected[i]) i++;
    diffs.push(`${c.name} at ${i}\n  prettier: ${expected.slice(Math.max(0, i - 60), i + 60)}\n  binary:   ${actual.slice(Math.max(0, i - 60), i + 60)}`);
  }
});
for (const d of diffs.slice(0, 10)) console.log(d);
console.log(`docs: ${cases.length} cases, ${counts.same} same, ${counts.different} DIFFERENT, ${counts.refused} refused by the binary, ${counts.prettierError} Prettier errors`);
process.exit(counts.different ? 1 : 0);
