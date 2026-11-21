// node debug-doc.mjs <file> [prettier flags...]
// Writes Prettier's doc for the file in the text form of --debug-doc.
import fs from "node:fs";
import prettier from "prettier";
import { docToText } from "./doc-text.mjs";
import { flagsToOptions } from "./flags.mjs";

const [file, ...flags] = process.argv.slice(2);
const opts = { filepath: file, ...flagsToOptions(flags) };
const doc = await prettier.__debug.printToDoc(fs.readFileSync(file, "utf8"), opts);
process.stdout.write(docToText(doc, { exact: process.env.DOC_EXACT === "1" }) + "\n");
