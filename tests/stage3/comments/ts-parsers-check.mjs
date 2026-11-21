// node tests/stage3/comments/ts-parsers-check.mjs found.json [--bin build/prettier-asm]
// Runs the binary on the variants ts-parsers-fuzz.mjs found (where the typescript and babel-ts
// parsers format differently): each must be refused or equal the typescript parser's output.
import fs from "node:fs";
import { spawnSync } from "node:child_process";

const argv = process.argv.slice(2);
const bi = argv.indexOf("--bin");
const bin = bi >= 0 ? argv[bi + 1] : "build/prettier-asm";
const found = JSON.parse(fs.readFileSync(argv[0], "utf8"));
const reasons = new Map();
let same = 0, bad = 0;
for (const f of found) {
  const r = spawnSync(bin, ["--stdin-filepath", "x.ts"], { input: f.variant });
  if (r.status === 3) { const k = r.stderr.toString().trim(); reasons.set(k, (reasons.get(k) ?? 0) + 1); continue; }
  if (r.status === 0 && r.stdout.toString() === f.typescript) { same++; continue; }
  bad++;
  console.log(`DIFFERENT ${f.name} @${f.at} ${JSON.stringify(f.variant.slice(Math.max(0, f.at - 40), f.at + 40))}${r.status === 0 && r.stdout.toString() === f.babel ? " (babel-ts output)" : ""}`);
}
console.log(`${found.length} variants: ${same} identical to typescript, ${bad} DIFFERENT`);
for (const [k, n] of reasons) console.log(`  ${String(n).padStart(4)}  ${k}`);
process.exit(bad ? 1 : 0);
