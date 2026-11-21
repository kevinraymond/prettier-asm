// Node-type and comment statistics for a case list, parsed with Prettier 3.6.2's own parsers
// (prettier.__debug.parse, which includes Prettier's AST postprocess).
// ESTree view: typescript-estree for .ts/.tsx/.mts/.cts, acorn for the rest (then espree, meriyah, typescript if acorn fails).
// Babel view: what Prettier's default parser hands the printer for non-TS files.
// Usage: node tests/node-stats.mjs [caselist] [out]    (default: real, corpus/real-node-types.txt)
import fs from "node:fs";
import path from "node:path";
import * as prettier from "prettier";
import { CORPUS, readCases, filepathOf } from "./lib.mjs";

const [listArg = "real", out = path.join(CORPUS, `${listArg}-node-types.txt`)] = process.argv.slice(2);
const cases = readCases(listArg);
const SKIP = new Set(["loc", "range", "start", "end", "extra", "tokens", "comments", "errors", "parent"]);

// Variants that change what the printer does; listed under "detail".
function details(n) {
  const d = [], t = n.type;
  if (t === "Literal") d.push(`Literal:${n.regex ? "regex" : n.bigint !== undefined ? "bigint" : n.value === null ? "null" : typeof n.value}`);
  if (/^(Binary|Logical|Assignment|Unary|Update)Expression$/.test(t)) d.push(`${t}:${n.operator}${t === "UpdateExpression" ? (n.prefix ? " prefix" : " postfix") : ""}`);
  if (t === "VariableDeclaration") d.push(`${t}:${n.kind}`);
  if (t === "Property" || t === "ObjectProperty" || t === "ObjectMethod") {
    if (n.shorthand) d.push(`${t}:shorthand`);
    if (n.method || t === "ObjectMethod") d.push(`${t}:method`);
    if (n.kind === "get" || n.kind === "set") d.push(`${t}:${n.kind}`);
    if (n.computed) d.push(`${t}:computed`);
  }
  if (t === "MethodDefinition" || t === "ClassMethod" || t === "TSAbstractMethodDefinition") {
    d.push(`${t}:${n.kind}`);
    if (n.static) d.push(`${t}:static`);
  }
  if (t === "PropertyDefinition" || t === "ClassProperty") { if (n.static) d.push(`${t}:static`); if (n.value == null) d.push(`${t}:no-value`); }
  if (t === "MemberExpression" || t === "OptionalMemberExpression") { if (n.computed) d.push(`${t}:computed`); if (n.optional) d.push(`${t}:optional`); }
  if ((t === "CallExpression" || t === "OptionalCallExpression") && n.optional) d.push(`${t}:optional`);
  if (/Function/.test(t) && !/^TS/.test(t)) {
    if (n.async) d.push(`${t}:async`);
    if (n.generator) d.push(`${t}:generator`);
    if (t === "ArrowFunctionExpression") d.push(`${t}:${n.expression || n.body?.type !== "BlockStatement" ? "expression-body" : "block-body"}`);
  }
  if (t === "TemplateLiteral") d.push(`${t}:${n.expressions.length ? "with-expressions" : "no-expressions"}`);
  if (t === "ExportNamedDeclaration") d.push(`${t}:${n.declaration ? "declaration" : n.source ? "from" : "specifiers"}`);
  if ((t === "ImportDeclaration" || t === "ExportNamedDeclaration") && (n.importKind === "type" || n.exportKind === "type")) d.push(`${t}:type`);
  if (t === "ForOfStatement" && n.await) d.push(`${t}:await`);
  if (t === "ExpressionStatement" && n.directive) d.push(`${t}:directive`);
  return d;
}

function collect(ast) {
  const types = new Map(), detail = new Map();
  const inc = (m, k) => m.set(k, (m.get(k) ?? 0) + 1);
  const walk = (n) => {
    if (Array.isArray(n)) return n.forEach(walk);
    if (!n || typeof n !== "object") return;
    if (typeof n.type === "string" && n.type !== "File") { inc(types, n.type); for (const d of details(n)) inc(detail, d); }
    for (const [k, v] of Object.entries(n)) if (!SKIP.has(k)) walk(v);
  };
  walk(ast);
  return { types, detail };
}

function commentKinds(ast, text) {
  const m = new Map();
  const inc = (k) => m.set(k, (m.get(k) ?? 0) + 1);
  for (const c of ast.comments ?? []) {
    const start = c.range?.[0] ?? c.start;
    if (text.startsWith("#!", start)) { inc("hashbang"); continue; }
    const block = /Block/.test(c.type);
    if (!block) inc("line");
    else if (c.value.startsWith("*")) inc(c.value.includes("\n") ? "jsdoc /** */ multi-line" : "jsdoc /** */ one-line");
    else inc(c.value.includes("\n") ? "block multi-line" : "block one-line");
    if (/^\s*prettier-ignore\b/.test(c.value)) inc("(prettier-ignore)");
    if (/^\s*eslint|^\s*@ts-|^\s*istanbul|^\s*c8\b|^\s*global\b/.test(c.value)) inc("(tool directive: eslint, @ts-, istanbul...)");
  }
  return m;
}

const parse = async (text, filepath, parser) => (await prettier.__debug.parse(text, { filepath, parser })).ast;
const files = [];
for (const c of cases) {
  const fp = filepathOf(c), ts = /\.[mc]?tsx?$/.test(fp);
  let parser, ast;
  for (const p of ts ? ["typescript"] : ["acorn", "espree", "meriyah", "typescript"]) {
    try { ast = await parse(c.stdin, fp, p); parser = p; break; } catch {}
  }
  if (!ast) { files.push({ fp, size: Buffer.byteLength(c.stdin), error: true }); continue; }
  const f = { fp, parser, size: Buffer.byteLength(c.stdin), lines: c.stdin.split("\n").length - (c.stdin.endsWith("\n") ? 1 : 0),
    ...collect(ast), comments: commentKinds(ast, c.stdin) };
  if (!ts) { try { const b = await parse(c.stdin, fp, "babel"); f.babel = collect(b); } catch { f.babelError = true; } }
  files.push(f);
}

const ok = files.filter((f) => !f.error);
function table(title, pick, note) {
  const occ = new Map(), inFiles = new Map();
  for (const f of ok) { const m = pick(f); if (!m) continue; for (const [k, n] of m) { occ.set(k, (occ.get(k) ?? 0) + n); inFiles.set(k, (inFiles.get(k) ?? 0) + 1); } }
  const rows = [...occ.keys()].sort((a, b) => inFiles.get(b) - inFiles.get(a) || occ.get(b) - occ.get(a) || (a < b ? -1 : 1));
  const L = [`## ${title}`, ...(note ? [note] : []), `${"files".padStart(5)} ${"count".padStart(6)}  type`];
  for (const k of rows) L.push(`${String(inFiles.get(k)).padStart(5)} ${String(occ.get(k)).padStart(6)}  ${k}`);
  return L.join("\n");
}

// Greedy: take next the file that needs the fewest types not yet taken. Comments count as types.
function order() {
  const need = ok.map((f) => ({ fp: f.fp, set: new Set([...f.types.keys(), ...[...f.comments.keys()].filter((k) => !k.startsWith("(")).map((k) => `comment: ${k}`)]) }));
  const have = new Set(), L = ["## Porting order (greedy: next the file needing fewest new types; comment kinds count as types)",
    `${"files".padStart(5)} ${"types".padStart(5)}  file  [new types]`];
  while (need.length) {
    need.sort((a, b) => [...a.set].filter((t) => !have.has(t)).length - [...b.set].filter((t) => !have.has(t)).length || (a.fp < b.fp ? -1 : 1));
    const f = need.shift(), add = [...f.set].filter((t) => !have.has(t)).sort();
    add.forEach((t) => have.add(t));
    L.push(`${String(ok.length - need.length).padStart(5)} ${String(have.size).padStart(5)}  ${f.fp}  [${add.join(", ")}]`);
  }
  return L.join("\n");
}

const total = (k) => ok.reduce((a, f) => a + f[k], 0);
const byRepo = {};
for (const f of files) { const [, repo] = f.fp.split("/"), ext = path.extname(f.fp); byRepo[repo] ??= {}; byRepo[repo][ext] = (byRepo[repo][ext] ?? 0) + 1; }
const out_ = [
  `# Node types in ${listArg} (${files.length} files, ${total("size")} bytes, ${total("lines")} lines), Prettier ${prettier.version}`,
  `# by repo and extension: ${JSON.stringify(byRepo)}`,
  `# parsers: ${JSON.stringify(Object.fromEntries(["acorn", "espree", "meriyah", "typescript"].map((p) => [p, ok.filter((f) => f.parser === p).length]).filter(([, n]) => n)))}` +
    (files.length - ok.length ? `; ${files.length - ok.length} did not parse: ${files.filter((f) => f.error).map((f) => f.fp).join(" ")}` : ""),
  `# files: how many files contain the type; count: occurrences over all files.`,
  "",
  table("ESTree node types", (f) => f.types, "typescript-estree for TS files, acorn for JS files (typescript where acorn cannot parse)."),
  "",
  table("Detail (operators, kinds, literal types, flags)", (f) => f.detail),
  "",
  table("Comments by kind", (f) => f.comments, "Parenthesized rows are subsets of the kinds above."),
  "",
  table("Babel AST of the non-TS files (Prettier's default parser for .js/.mjs; what its printer sees)", (f) => f.babel?.types,
    `${ok.filter((f) => f.babel).length} files; names differ from ESTree: StringLiteral/NumericLiteral for Literal, ObjectProperty for Property, ClassMethod for MethodDefinition...`),
  "",
  order(),
  "",
  "## Per file",
  ...ok.flatMap((f) => [
    `${f.fp}  ${f.size} bytes, ${f.lines} lines, ${f.parser}, comments: ${[...f.comments].map(([k, n]) => `${k} ${n}`).join(", ") || "none"}`,
    "    " + [...f.types].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([k, n]) => `${k} ${n}`).join(", "),
  ]),
];
fs.writeFileSync(out, out_.join("\n") + "\n");
console.log(`wrote ${out}`);
