// node tests/stage3/printer/ts-both.mjs [-e CODE | FILE] [-- prettier flags]
// Formats one TypeScript input with Prettier's `typescript` parser (what the CLI uses) and with
// `babel-ts` (the AST shape the binary parses) and shows both outputs, or says they agree.
import fs from "node:fs";
import prettier from "prettier";
import { flagsToOptions } from "../infra/flags.mjs";

const argv = process.argv.slice(2);
const dd = argv.indexOf("--");
const flags = dd >= 0 ? argv.slice(dd + 1) : [];
const own = dd >= 0 ? argv.slice(0, dd) : argv;
const text = own[0] === "-e" ? own[1] : fs.readFileSync(own[0], "utf8");
const out = {};
for (const parser of ["typescript", "babel-ts"]) {
  try { out[parser] = await prettier.format(text, { filepath: "x.ts", ...flagsToOptions(flags), parser }); }
  catch (e) { out[parser] = `ERROR ${String(e.message).split("\n")[0]}\n`; }
}
if (out.typescript === out["babel-ts"]) process.stdout.write(`same\n${out.typescript}`);
else process.stdout.write(`--- typescript\n${out.typescript}--- babel-ts\n${out["babel-ts"]}`);
