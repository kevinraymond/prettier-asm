// Clones the real repositories into corpus/real and writes the case lists to corpus/cases.
// The lists come from prettier-rs's own generators (MIT), run unchanged from ref/.
// Usage: node tests/setup-corpus.mjs
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { ROOT, CORPUS, CASES_DIR, filepathOf } from "./lib.mjs";

const PRETTIER_SRC = process.env.PRETTIER_SRC ?? path.join(ROOT, "ref/prettier");
const GEN = process.env.PRETTIER_RS_SCRIPTS ?? path.join(ROOT, "ref/rust-anything/demo/real-world/prettier-rs/scripts");
const REAL = path.join(CORPUS, "real");
const REPOS = [
  ["ms", "https://github.com/vercel/ms", "3.0.0-canary.1"],
  ["Fuse", "https://github.com/krisk/Fuse", "v7.1.0"],
  ["json-server", "https://github.com/typicode/json-server", "v1.0.0-beta.3"],
];

const git = (...a) => execFileSync("git", a, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();

for (const p of [path.join(PRETTIER_SRC, "tests/format"), path.join(GEN, "gen-inputs.mjs"), path.join(GEN, "gen-json-inputs.mjs")])
  if (!fs.existsSync(p)) throw new Error(`missing ${p}`);
if (git("-C", PRETTIER_SRC, "describe", "--tags") !== "3.6.2") throw new Error(`${PRETTIER_SRC} is not at tag 3.6.2`);

fs.mkdirSync(REAL, { recursive: true });
for (const [dir, url, tag] of REPOS) {
  const d = path.join(REAL, dir);
  if (!fs.existsSync(d)) git("-c", "advice.detachedHead=false", "clone", "-q", "--depth", "1", "--branch", tag, url, d);
  const at = git("-C", d, "describe", "--tags", "--exact-match");
  if (at !== tag) throw new Error(`${d} is at ${at}, want ${tag}`);
  if (git("-C", d, "status", "--porcelain")) throw new Error(`${d} has local changes`);
}

const gen = path.join(CORPUS, "gen");
fs.mkdirSync(gen, { recursive: true });
const node = (script, ...a) => execFileSync(process.execPath, [path.join(GEN, script), ...a], { encoding: "utf8", cwd: gen });
node("gen-inputs.mjs", PRETTIER_SRC, REAL, path.join(gen, "inputs.jsonl"));
node("gen-json-inputs.mjs", PRETTIER_SRC, REAL, path.join(gen, "json-inputs.jsonl"));

const read = (f) => fs.readFileSync(path.join(gen, f), "utf8").split("\n").filter(Boolean);
const lists = { real: [], "js-fixtures": [], "ts-fixtures": [], variants: [], json: read("json-inputs.jsonl") };
for (const line of read("inputs.jsonl")) {
  const c = JSON.parse(line), fp = filepathOf(c);
  if (fp.startsWith("real/")) lists.real.push(line);
  else if (!/^(js|jsx|typescript)-/.test(c.name)) lists.variants.push(line); // names start with the option
  else if (fp.startsWith("tests/format/typescript/")) lists["ts-fixtures"].push(line);
  else lists["js-fixtures"].push(line);
}

fs.mkdirSync(CASES_DIR, { recursive: true });
for (const [k, v] of Object.entries(lists)) fs.writeFileSync(path.join(CASES_DIR, `${k}.jsonl`), v.join("\n") + "\n");
console.log(Object.fromEntries(Object.entries(lists).map(([k, v]) => [k, v.length])));
if (lists.real.length !== 59) { console.error(`real has ${lists.real.length} files, want 59`); process.exit(1); }
