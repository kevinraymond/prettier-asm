// Many patterns against many paths, without a Prettier process per case: the
// expected output comes from Prettier's own API (the same bundle as its CLI):
// getFileInfo for ignore files, resolveConfig then format for .editorconfig
// sections and overrides. The binary runs once per path and is classed
// identical, refused or DIFFERENT. Exit 1 on any DIFFERENT.
//
//   node tests/stage3/config/fuzz.mjs [--bin path] [--n N] [--seed S] [--only ignore|ec|ov] [--show N]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const prettier = await import(path.join(ROOT, "node_modules/prettier/index.mjs"));

const argv = process.argv.slice(2);
const opt = (name, def) => {
  const i = argv.indexOf(name);
  return i === -1 ? def : argv[i + 1];
};
const BIN = path.resolve(opt("--bin", process.env.PRETTIER_ASM_BIN || path.join(ROOT, "build/prettier-asm")));
const N = Number(opt("--n", 200));
const SEED = Number(opt("--seed", 7));
const ONLY = opt("--only", null);
const SHOW = Number(opt("--show", 5));
const PATHS = Number(opt("--paths", 12));

const INPUT = '{"a":{"b":[1,2,{"c":"d"}]},"list":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25]}';

function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    pick: (xs) => xs[Math.floor(next() * xs.length)],
    chance: (p) => next() < p,
  };
}
const r = rng(SEED);

const PROBED = ["package.json", "package.yaml", ".prettierrc", ".prettierrc.json", ".prettierrc.yaml", ".prettierrc.yml",
  ".prettierrc.json5", ".prettierrc.js", ".prettierrc.toml", "prettier.config.js", ".editorconfig", ".git", ".hg"];
const parent = process.env.CONFIG_TEST_BASE || os.tmpdir();
fs.mkdirSync(parent, { recursive: true });
const base = fs.mkdtempSync(path.join(parent, "prettier-asm-fuzz-"));
for (let d = path.dirname(base); ; d = path.dirname(d)) {
  for (const n of PROBED) if (fs.existsSync(path.join(d, n))) throw new Error(`${path.join(d, n)} would apply`);
  if (d === path.dirname(d)) break;
}

const DIRS = ["a", "b", "x", "src", "deep", "ab", "Sub", ".hidden", "node_modules", "a.b", "lib"];
const FILES = ["x.json", "a.json", "b.json", "X.JSON", ".a.json", "ab.json", "x.jsonc", "a.json5", "xa.json", "src.json"];
function randomPath() {
  const segs = [];
  for (let n = r.int(0, 3); n > 0; n--) segs.push(r.pick(DIRS));
  segs.push(r.pick(FILES));
  return segs.join("/");
}

function ignoreLine() {
  const atoms = ["a", "b", "x", "src", "deep", "*", "**", "?", "*.json", "x*", "[ab]", "[a-c]", "[A-Z]*", ".json", "*.js*",
    "node_modules", "a.b", "Sub", ".*", "X.JSON", "x.json"];
  const parts = [];
  for (let n = r.int(1, 3); n > 0; n--) parts.push(r.chance(0.3) ? r.pick(atoms) + r.pick(atoms) : r.pick(atoms));
  let p = parts.join("/");
  if (r.chance(0.15)) p = "/" + p;
  if (r.chance(0.1)) p = "**/" + p;
  if (r.chance(0.15)) p += "/";
  if (r.chance(0.2)) p = "!" + p;
  if (r.chance(0.05)) p += "   ";
  if (r.chance(0.03)) p = "\\" + p;
  if (r.chance(0.03)) p = "# " + p;
  return p;
}

const ecAtoms = ["*", "**", "?", "x", "a", "b", ".json", "{a,x}", "{json,jsonc}", "src", "deep", "{a,{b,x}}", "*.json", "Sub", ".*"];
function ecGlob() {
  const parts = [];
  for (let n = r.int(1, 3); n > 0; n--) {
    let seg = "";
    for (let k = r.int(1, 2); k > 0; k--) seg += r.pick(ecAtoms);
    parts.push(seg);
  }
  let g = parts.join("/");
  if (r.chance(0.2)) g = "/" + g;
  if (r.chance(0.03)) g = "[" + g + "]";
  return g;
}

const ovAtoms = ["*", "?", "x", "a", "b", ".json", "*.json", "{json,jsonc}", "{a,x}", "src", "deep", "Sub", ".*", "x.json"];
function ovGlob() {
  const parts = [];
  for (let n = r.int(1, 3); n > 0; n--) {
    if (r.chance(0.2)) { parts.push("**"); continue; }
    let seg = "";
    for (let k = r.int(1, 2); k > 0; k--) seg += r.pick(ovAtoms);
    parts.push(seg);
  }
  return parts.join("/");
}

function runBin(cwd, rel) {
  return new Promise((resolve) => {
    const env = { ...process.env };
    delete env.PRETTIER_ASM_FALLBACK;
    const child = spawn(BIN, ["--stdin-filepath", rel], { cwd, env });
    const out = [], err = [];
    child.stdout.on("data", (d) => out.push(d));
    child.stderr.on("data", (d) => err.push(d));
    child.on("close", (status) => resolve({ status, stdout: Buffer.concat(out).toString(), stderr: Buffer.concat(err).toString() }));
    child.stdin.end(INPUT);
  });
}

async function expected(dir, rel, kind) {
  const abs = path.join(dir, rel);
  try {
    // as the CLI: .prettierignore from the working directory, plus node_modules
    const info = await prettier.getFileInfo(abs, { ignorePath: [path.join(dir, ".prettierignore")] });
    if (info.ignored) return INPUT;
    const config = await prettier.resolveConfig(abs, { editorconfig: true, useCache: false });
    return await prettier.format(INPUT, { ...config, filepath: abs });
  } catch (e) {
    return { error: String(e.message).split("\n")[0] };
  }
}

const count = { identical: 0, refused: 0, DIFFERENT: 0 };
const reasons = new Map();
let shown = 0;
let ignoredSeen = 0, matchedSeen = 0;
async function check(kind, dir, content) {
  const rels = Array.from({ length: PATHS }, randomPath);
  await Promise.all(rels.map(async (rel) => {
    const [want, got] = await Promise.all([expected(dir, rel, kind), runBin(dir, rel)]);
    let cls;
    if (got.status === 3 && got.stderr.startsWith("unsupported: ")) {
      cls = "refused";
      const reason = got.stderr.trim();
      reasons.set(reason, (reasons.get(reason) ?? 0) + 1);
      if (process.env.SHOW_REFUSED) console.log(`refused ${kind} ${JSON.stringify(content)} ${rel} ${reason}`);
    } else if (typeof want === "string" && got.status === 0 && got.stdout === want) {
      cls = "identical";
      if (kind === "ignore" && want === INPUT) ignoredSeen++;
      if (kind !== "ignore" && !want.includes('\n  "a"')) matchedSeen++;
    } else cls = "DIFFERENT";
    count[cls]++;
    if (cls === "DIFFERENT" && shown++ < SHOW) {
      console.log(`DIFFERENT ${kind} ${dir}\n  file content: ${JSON.stringify(content)}\n  path: ${rel}`);
      console.log(`  expected: ${JSON.stringify(want).slice(0, 300)}\n  binary exit ${got.status}: ${JSON.stringify(got.stdout).slice(0, 300)} ${got.stderr.slice(0, 200)}`);
    }
  }));
}

const tabs = [3, 5, 7, 4];
for (let i = 0; i < N; i++) {
  if (!ONLY || ONLY === "ignore") {
    const dir = path.join(base, `ignore${i}`);
    fs.mkdirSync(dir);
    const content = Array.from({ length: r.int(1, 5) }, ignoreLine).join("\n") + "\n";
    fs.writeFileSync(path.join(dir, ".prettierignore"), content);
    await check("ignore", dir, content);
  }
  if (!ONLY || ONLY === "ec") {
    const dir = path.join(base, `ec${i}`);
    fs.mkdirSync(dir);
    const lines = [];
    for (let s = r.int(1, 3); s > 0; s--) lines.push(`[${ecGlob()}]`, `indent_size = ${r.pick(tabs)}`);
    const content = lines.join("\n") + "\n";
    fs.writeFileSync(path.join(dir, ".editorconfig"), content);
    await check("ec", dir, content);
  }
  if (!ONLY || ONLY === "ov") {
    const dir = path.join(base, `ov${i}`);
    fs.mkdirSync(dir);
    const overrides = [];
    for (let s = r.int(1, 3); s > 0; s--) {
      const o = { files: r.chance(0.3) ? [ovGlob(), ovGlob()] : ovGlob(), options: { tabWidth: r.pick(tabs) } };
      if (r.chance(0.4)) o.excludeFiles = r.chance(0.5) ? ovGlob() : [ovGlob(), ovGlob()];
      overrides.push(o);
    }
    const content = JSON.stringify({ overrides });
    fs.writeFileSync(path.join(dir, ".prettierrc.json"), content);
    await check("ov", dir, content);
  }
}

for (const [reason, n] of [...reasons].sort((a, b) => b[1] - a[1])) console.log(`  ${String(n).padStart(5)}  ${reason}`);
console.log(`identical paths that were ignored: ${ignoredSeen}; identical paths where a section or override applied: ${matchedSeen}`);
console.log(`total ${count.identical + count.refused + count.DIFFERENT}  identical ${count.identical}  refused ${count.refused}  DIFFERENT ${count.DIFFERENT}`);
fs.rmSync(base, { recursive: true, force: true });
process.exit(count.DIFFERENT > 0 ? 1 : 0);
