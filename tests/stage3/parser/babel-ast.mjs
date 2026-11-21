// Prints the AST that Prettier's `babel` parser (`babel-ts` for TypeScript files) hands the printer
// (after Prettier's postprocess) in the canonical text form that `prettier-asm --debug-ast` writes.
//
//   node tests/stage3/parser/babel-ast.mjs <filepath> < source
//
// One line per node, pre-order, indented one space per level:
//   <key>: <Type> <start> <end> [prop ...]
// start and end are Prettier's locStart and locEnd.
// Child keys come in alphabetical order, array items as key[i]. Null children and empty arrays
// are left out; holes in arrays print as `key[i]: null`. Props are the node's scalar fields in
// alphabetical order: `name` for true, `name=value` for strings and numbers; false, null and
// undefined are left out. From `extra` only `parenthesized` and `deprecatedAssertSyntax` are
// printed (the printer reads `extra.raw`, which is always the source text of the node's range).
// TemplateElement prints `cooked`. NumericLiteral's `value` is left out. Strings print in double
// quotes; code units outside printable ASCII, `"` and `\` are escaped as \uXXXX, \" and \\.
// The comments follow under `comments:` as `<type> <start> <end> <value>`.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const prettier = await import(path.join(ROOT, "node_modules/prettier/index.mjs"));

const SKIP = new Set(["type", "start", "end", "loc", "range", "extra", "comments", "errors",
  "leadingComments", "trailingComments", "innerComments"]);

export function quote(s) {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 0x22) out += '\\"';
    else if (c === 0x5c) out += "\\\\";
    else if (c >= 0x20 && c < 0x7f) out += s[i];
    else out += "\\u" + c.toString(16).padStart(4, "0");
  }
  return out + '"';
}

// Prettier's locStart and locEnd (language-js/loc.js): postprocess moves some ranges into `range`,
// which they prefer, and a node with decorators starts at its first decorator.
function locStart(n) {
  const start = n.range?.[0] ?? n.start;
  const firstDecorator = (n.declaration?.decorators ?? n.decorators)?.[0];
  return firstDecorator ? Math.min(locStart(firstDecorator), start) : start;
}
const locEnd = (n) => n.range?.[1] ?? n.end;
const isNode = (v) => v !== null && typeof v === "object" && typeof v.type === "string";

function line(out, depth, key, node) {
  const props = [];
  for (const [k, v] of Object.entries(node)) {
    if (SKIP.has(k)) continue;
    if (node.type === "NumericLiteral" && k === "value") continue;
    if (node.type === "TemplateElement" && k === "value") {
      props.push(["cooked", v.cooked === null ? "cooked=null" : `cooked=${quote(v.cooked)}`]);
      continue;
    }
    if (v === true) props.push([k, k]);
    else if (typeof v === "string") props.push([k, `${k}=${quote(v)}`]);
    else if (typeof v === "number") props.push([k, `${k}=${v}`]);
    else if (v !== null && typeof v === "object" && !Array.isArray(v) && !isNode(v)) props.push([k, `?${k}`]);
  }
  for (const k of ["parenthesized", "deprecatedAssertSyntax"]) if (node.extra?.[k]) props.push([k, k]);
  props.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  out.push(`${" ".repeat(depth)}${key}: ${node.type} ${locStart(node)} ${locEnd(node)}${props.map((p) => " " + p[1]).join("")}`);
  const keys = Object.keys(node).filter((k) => !SKIP.has(k)).sort();
  for (const k of keys) {
    const v = node[k];
    if (Array.isArray(v)) {
      v.forEach((item, i) => {
        if (isNode(item)) line(out, depth + 1, `${k}[${i}]`, item);
        else if (item === null) out.push(`${" ".repeat(depth + 1)}${k}[${i}]: null`);
        else out.push(`${" ".repeat(depth + 1)}?${k}[${i}]`);
      });
    } else if (isNode(v)) line(out, depth + 1, k, v);
  }
}

export function dump(ast) {
  const out = [];
  line(out, 0, "root", ast);
  out.push("comments:");
  for (const c of ast.comments ?? []) out.push(` ${c.type} ${locStart(c)} ${locEnd(c)} ${quote(c.value)}`);
  return out.join("\n") + "\n";
}

// The parser Prettier picks for the file: babel-ts for TypeScript (the Babel shape this port
// gives TypeScript files), babel otherwise.
export const oracleParser = (filepath) => (/\.(ts|mts|cts|tsx)$/i.test(filepath) ? "babel-ts" : "babel");

export async function babelAst(text, filepath) {
  const { ast } = await prettier.__debug.parse(text, { parser: oracleParser(filepath), filepath });
  return dump(ast);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const text = fs.readFileSync(0, "utf8");
  try {
    process.stdout.write(await babelAst(text, process.argv[2] ?? "x.js"));
  } catch (e) {
    process.stderr.write(`error: ${e.message}\n`);
    process.exit(2);
  }
}
