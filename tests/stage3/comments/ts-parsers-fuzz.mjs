// node tests/stage3/comments/ts-parsers-fuzz.mjs [--list real,ts-fixtures] [--per N] [--seed S] [--at punct|space] [--json out]
// Inserts a block or line comment at token boundaries of the TypeScript cases and formats each
// variant with Prettier's `typescript` and `babel-ts` parsers. Prints the variants whose outputs
// differ (both parsers succeeding), to find where comment attachment depends on the AST shape.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import prettier from "prettier";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const lists = opt("--list", "real,ts-fixtures").split(",");
const per = Number(opt("--per", 12));
let seed = Number(opt("--seed", 1));
const jsonOut = opt("--json", null);
// --at punct: next to punctuators (default); --at space: next to whitespace
const at = opt("--at", "punct");
const boundary = at === "space" ? /\s/ : /[(){}\[\]<>,:;=|&?]/;
const rand = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);

const found = [];
let tried = 0;
for (const list of lists) {
  const cases = fs.readFileSync(path.join(ROOT, `corpus/cases/${list}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l))
    .filter((c) => /\.(ts|mts|cts)$/.test(c.args[c.args.indexOf("--stdin-filepath") + 1] ?? ""));
  for (const c of cases) {
    const text = c.stdin;
    if (text.length > 20000) continue;
    // candidate offsets: just after a punctuator or before one, outside strings (roughly)
    const offs = [];
    for (let i = 1; i < text.length; i++) if (boundary.test(text[i - 1]) || boundary.test(text[i])) offs.push(i);
    for (let k = 0; k < per && offs.length; k++) {
      const at = offs[Math.floor(rand() * offs.length)];
      const comment = rand() < 0.5 ? " /* c */ " : " // c\n";
      const variant = text.slice(0, at) + comment + text.slice(at);
      const fmt = async (parser) => { try { return await prettier.format(variant, { filepath: "x.ts", parser }); } catch { return null; } };
      const a = await fmt("typescript");
      if (a === null) continue;
      const b = await fmt("babel-ts");
      if (b === null) continue;
      tried++;
      if (a !== b) found.push({ name: c.name, at, comment, variant, typescript: a, babel: b });
    }
  }
}
console.log(`variants formatted by both parsers: ${tried}, differing: ${found.length}`);
for (const f of found.slice(0, 40)) {
  const al = f.typescript.split("\n"), bl = f.babel.split("\n");
  let i = 0; while (al[i] === bl[i]) i++;
  console.log(`${f.name} @${f.at} ${JSON.stringify(f.comment)}\n  src: ${JSON.stringify(f.variant.slice(Math.max(0, f.at - 40), f.at + 50))}\n  typescript: ${al[i]}\n  babel-ts:   ${bl[i]}`);
}
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify(found, null, 1));
