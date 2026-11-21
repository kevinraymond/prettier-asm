// node tests/stage3/printer/check.mjs [--bin build/NAME/prettier-asm] [--name x.js] (-e CODE | FILE)... [-- prettier flags]
// Formats each input with Prettier and the binary (stdin, --stdin-filepath) and reports
// identical, refused (with the reason) or DIFFERENT. For DIFFERENT it prints both outputs
// and where the two docs (--debug-doc against printToDoc) first differ.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import prettier from "prettier";
import { docToText } from "../infra/doc-text.mjs";
import { flagsToOptions } from "../infra/flags.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const argv = process.argv.slice(2);
let bin = path.join(ROOT, "build/prettier-asm");
let name = "check.js";
const inputs = [];
let flags = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--") { flags = argv.slice(i + 1); break; }
  if (a === "--bin") bin = path.resolve(argv[++i]);
  else if (a === "--name") name = argv[++i];
  else if (a === "-e") inputs.push({ label: `-e ${JSON.stringify(argv[i + 1]).slice(0, 60)}`, text: argv[++i] });
  else inputs.push({ label: a, text: fs.readFileSync(a, "utf8") });
}
let bad = 0;
for (const { label, text } of inputs) {
  const opts = { filepath: name, ...flagsToOptions(flags) };
  let expected, expectedDoc;
  try {
    expected = await prettier.format(text, opts);
    expectedDoc = docToText(await prettier.__debug.printToDoc(text, opts), {});
  } catch (e) {
    console.log(`${label}: prettier error: ${String(e.message).split("\n")[0]}`);
    continue;
  }
  const r = spawnSync(bin, ["--stdin-filepath", name, ...flags], { input: text });
  if (r.error) throw r.error;
  if (r.status === 3) {
    console.log(`${label}: refused: ${r.stderr.toString().trim()}`);
    continue;
  }
  const actual = r.stdout.toString();
  if (r.status === 0 && actual === expected) {
    console.log(`${label}: identical`);
    continue;
  }
  bad++;
  console.log(`${label}: DIFFERENT (exit ${r.status}) ${r.stderr.toString().trim()}`);
  console.log("--- prettier\n" + expected + "--- binary\n" + actual + "---");
  const d = spawnSync(bin, ["--debug-doc", "--stdin-filepath", name, ...flags], { input: text });
  const actualDoc = d.stdout.toString().replace(/\n$/, "");
  if (actualDoc === expectedDoc) console.log("docs are the same");
  else {
    let i = 0;
    while (actualDoc[i] === expectedDoc[i]) i++;
    console.log(`docs differ at ${i}\n  prettier: ${expectedDoc.slice(Math.max(0, i - 100), i + 100)}\n  binary:   ${actualDoc.slice(Math.max(0, i - 100), i + 100)}`);
  }
}
process.exit(bad ? 1 : 0);
