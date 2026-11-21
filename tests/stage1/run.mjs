// Stage 1 check: runs every JSON case through Prettier 3.6.2 (the oracle) and
// build/prettier-asm, and reports identical / fallback / DIFFERENT.
//
//   node tests/stage1/run.mjs [--verbose] [--filter <substring>] [--list <file>] [--options]
//
// --list adds the files named in <file> (one path per line), each formatted
// under its own file name. --options also runs the fixtures and the edge
// cases under each ported CLI option.
//
// Env:
//   PRETTIER_CJS      prettier 3.6.2's bin/prettier.cjs (default: node_modules/prettier)
//   PRETTIER_ASM_BIN  binary under test (default build/prettier-asm)
//
// Oracle results are cached in build/oracle-cache.json, keyed by file name and
// content. Exit code is 1 when any case is DIFFERENT.
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { edgeCases } from "./edge-cases.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const fixturesRoot = path.join(root, "ref/prettier/tests/format");
const bin = process.env.PRETTIER_ASM_BIN ?? path.join(root, "build/prettier-asm");
const localPrettier = path.join(root, "node_modules/prettier/bin/prettier.cjs");
const prettierCjs =
  process.env.PRETTIER_CJS ?? (fs.existsSync(localPrettier) ? localPrettier : undefined);
const cachePath = path.join(root, "build/oracle-cache.json");
const verbose = process.argv.includes("--verbose");
const filterIndex = process.argv.indexOf("--filter");
const filter = filterIndex === -1 ? undefined : process.argv[filterIndex + 1];
const listIndex = process.argv.indexOf("--list");
const listFile = listIndex === -1 ? undefined : process.argv[listIndex + 1];
const withOptions = process.argv.includes("--options");
const optionSets = [
  ["--tab-width", "4"],
  ["--use-tabs"],
  ["--print-width", "40"],
  ["--single-quote"],
  ["--quote-props", "preserve"],
  ["--quote-props", "consistent"],
  ["--trailing-comma", "none"],
  ["--trailing-comma", "es5"],
  ["--no-bracket-spacing"],
  ["--object-wrap", "collapse"],
  ["--single-quote", "--quote-props", "consistent", "--print-width=60"],
];

// File names that select each parser, as Prettier's language list does.
const variants = [
  { ext: ".json", name: (base) => `${base}.json` },
  { ext: ".jsonc", name: (base) => `${base}.jsonc` },
  { ext: ".json5", name: (base) => `${base}.json5` },
  { ext: "package.json", name: () => "package.json" },
];

function collectFixtures() {
  const dirs = [
    "json",
    "misc/json-unknown-extension",
    "misc/check-ignore-pragma",
    "misc/require-pragma",
    "misc/insert-pragma",
  ];
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name !== "__snapshots__") walk(full);
      } else if (/\.(json|json5|jsonc|notjson)$/.test(entry.name)) {
        files.push(full);
      }
    }
  };
  for (const dir of dirs) walk(path.join(fixturesRoot, dir));
  return files.sort().map((file) => ({
    id: path.relative(fixturesRoot, file),
    source: fs.readFileSync(file),
  }));
}

// Snippets that Prettier's own tests keep inside format.test.js files.
function collectSnippets() {
  const LS = " ";
  const PS = " ";
  const chars = [LS, PS, "_", " "];
  const snippets = [];
  for (const c of chars) snippets.push(`'${c}'`);
  for (const c of [...chars, "\n"]) snippets.push(`'\\${c}'`);
  for (const c of chars) snippets.push(`'\\\\${c}'`);
  snippets.push(
    "// Line comment 1\n    /** Block comment 1 */\n    // Line comment 2\n      /** Block comment 3 */",
  );
  snippets.push(
    "{foo}",
    '{["foo"]:"bar"}',
    '{"foo": ~1}',
    '{"foo": false || "bar"}',
    '{"foo": () => {}}',
    String.raw`packages\the-hub\cypress\fixtures\gridConfiguration.json`,
    "1+2",
    "{Infinity}",
    "{[key]: 1}",
    "{[key()]: 1}",
    "{['CallExpression']: 1}",
    "{['StringLiteral']: 1}",
    "{['string']: 1}",
    "{[1]: 1}",
    "{[Infinity]: 1}",
    "{[-Infinity]: 1}",
    "{[{key: 'value'}]: 1}",
    "{[[]]: 1}",
    "{[null]: 1}",
    "{key: +foo()}",
    "{key: void foo()}",
    "#!/usr/bin/env node\n{}",
    '"use strict"\n{}',
    "/* comment */",
    "// comment",
    "`foo${1}bar`",
    "-+1",
    "-+Infinity",
    "-undefined",
    "-null",
    "-false",
    "+'string'",
    "{key: +{}}",
    '{"identifier": identifier}',
    "(1)",
    "+(1)",
    "([1,])",
    "[1, (2)]",
    "----123",
  );
  return snippets.map((code, i) => ({
    id: `snippet-${String(i).padStart(2, "0")}`,
    source: Buffer.from(code),
  }));
}

function run(cmd, args, input, env) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd: emptyDir, env });
    const out = [];
    const err = [];
    child.stdout.on("data", (d) => out.push(d));
    child.stderr.on("data", (d) => err.push(d));
    child.on("close", (code) =>
      resolve({
        code,
        stdout: Buffer.concat(out),
        stderr: Buffer.concat(err).toString(),
      }),
    );
    child.stdin.on("error", () => {});
    child.stdin.end(input);
  });
}

async function pool(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: limit }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}

const emptyDir = fs.mkdtempSync(path.join(os.tmpdir(), "prettier-asm-stage1-"));
const cache = fs.existsSync(cachePath)
  ? JSON.parse(fs.readFileSync(cachePath, "utf8"))
  : {};

async function oracle(fileName, source, options) {
  const key = crypto
    .createHash("sha256")
    .update(options.length ? `${options.join("\0")}\0${fileName}` : fileName)
    .update("\0")
    .update(source)
    .digest("hex");
  if (cache[key]) {
    const c = cache[key];
    return { code: c.code, stdout: Buffer.from(c.stdout, "base64") };
  }
  if (!prettierCjs) {
    throw new Error("PRETTIER_CJS is not set and the oracle cache has no entry");
  }
  const r = await run(
    process.execPath,
    [prettierCjs, ...options, "--stdin-filepath", fileName],
    source,
    process.env,
  );
  cache[key] = { code: r.code, stdout: r.stdout.toString("base64") };
  return r;
}

function firstDifference(a, b) {
  const sa = a.toString();
  const sb = b.toString();
  let i = 0;
  while (i < sa.length && sa[i] === sb[i]) i++;
  const line = sa.slice(0, i).split("\n").length;
  return `first difference at line ${line}:\n  prettier: ${JSON.stringify(sa.slice(Math.max(0, i - 30), i + 40))}\n  asm:      ${JSON.stringify(sb.slice(Math.max(0, i - 30), i + 40))}`;
}

const cases = [];
for (const fixture of [...collectFixtures(), ...collectSnippets()]) {
  for (const v of variants) {
    cases.push({
      id: fixture.id,
      kind: v.ext,
      fileName: v.name(path.basename(fixture.id).replace(/\.[^.]*$/, "")),
      source: fixture.source,
    });
  }
}
for (const edge of edgeCases()) cases.push({ ...edge, source: Buffer.from(edge.source) });
if (listFile) {
  for (const file of fs.readFileSync(listFile, "utf8").split("\n").filter(Boolean)) {
    const name = path.basename(file);
    const kind = /^(package|package-lock|composer)\.json$/.test(name) ? name : path.extname(name) || name;
    cases.push({ id: file, kind: `list ${kind}`, fileName: name, source: fs.readFileSync(file) });
  }
}
for (const c of [...cases]) {
  c.options = [];
  if (withOptions && !c.kind.startsWith("list")) {
    for (const options of optionSets) {
      cases.push({ ...c, options, kind: `${c.kind} +opt` });
    }
  }
}
const selected = filter ? cases.filter((c) => `${c.id} ${c.fileName}`.includes(filter)) : cases;

const asmEnv = { ...process.env };
delete asmEnv.PRETTIER_ASM_FALLBACK;

const results = await pool(selected, Math.max(2, os.cpus().length), async (c) => {
  const [expected, actual] = await Promise.all([
    oracle(c.fileName, c.source, c.options),
    run(bin, [...c.options, "--stdin-filepath", c.fileName], c.source, asmEnv),
  ]);
  let status;
  if (actual.code === 3 && actual.stdout.length === 0 && actual.stderr.startsWith("unsupported: ")) {
    status = "fallback";
  } else if (actual.code === expected.code && actual.stdout.equals(expected.stdout)) {
    status = "identical";
  } else {
    status = "DIFFERENT";
  }
  return { ...c, status, expected, actual };
});

fs.mkdirSync(path.dirname(cachePath), { recursive: true });
fs.writeFileSync(cachePath, JSON.stringify(cache));
fs.rmSync(emptyDir, { recursive: true, force: true });

const byKind = new Map();
const reasons = new Map();
for (const r of results) {
  const counts = byKind.get(r.kind) ?? { identical: 0, fallback: 0, DIFFERENT: 0, oracleError: 0 };
  counts[r.status]++;
  if (r.status === "fallback" && r.expected.code !== 0) counts.oracleError++;
  byKind.set(r.kind, counts);
  if (r.status === "fallback") {
    const reason = r.actual.stderr.trim().replace(/^unsupported: /, "");
    const why = r.expected.code === 0 ? reason : `${reason} [prettier exits ${r.expected.code}]`;
    const list = reasons.get(why) ?? [];
    list.push(`${r.id} as ${r.fileName} ${r.options.join(" ")}`);
    reasons.set(why, list);
  }
  if (r.status === "DIFFERENT") {
    console.log(`DIFFERENT ${r.id} as ${r.fileName} ${r.options.join(" ")}`);
    console.log(`  exit: prettier ${r.expected.code}, asm ${r.actual.code}`);
    if (r.actual.stderr) console.log(`  asm stderr: ${r.actual.stderr.trim()}`);
    console.log("  " + firstDifference(r.expected.stdout, r.actual.stdout));
  }
}

console.log("\nfallback reasons:");
for (const [why, list] of [...reasons].sort((a, b) => b[1].length - a[1].length)) {
  console.log(`  ${String(list.length).padStart(4)}  ${why}`);
  if (verbose) for (const item of list) console.log(`          ${item}`);
}

// "of which prettier errors": fallbacks where Prettier itself exits non-zero
console.log("\nkind                    identical  fallback  (prettier errors)  DIFFERENT");
const total = { identical: 0, fallback: 0, DIFFERENT: 0, oracleError: 0 };
const row = (kind, c) =>
  console.log(
    `${kind.padEnd(23)} ${String(c.identical).padStart(9)} ${String(c.fallback).padStart(9)} ${String(c.oracleError).padStart(18)} ${String(c.DIFFERENT).padStart(10)}`,
  );
for (const [kind, c] of byKind) {
  row(kind, c);
  for (const k of Object.keys(total)) total[k] += c[k];
}
row("total", total);
process.exitCode = total.DIFFERENT > 0 ? 1 : 0;
