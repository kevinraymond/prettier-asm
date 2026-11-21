// What Prettier's comment attachment does to a JS file, in the form `prettier-asm
// --debug-comments` writes.
//
//   node tests/stage3/comments/oracle.mjs <filepath> [--experimental-ternaries] < source
//
// attachComments is internal, so a plugin observes its result: the plugin's `babel` and
// `babel-ts` parsers are Prettier's, and its `estree` printer is Prettier's with `print` wrapped. Prettier picks the
// printer from the plugin that supplied the parser, and plugins given in `plugins` come after
// the built-in ones, so the wrapper runs. The first `print` call is for the root, after
// attachComments; the wrapper walks the AST there, records every node's `comments` and throws
// to stop formatting.
//
// One line per comment, in source order:
//   <start> <end> <Block|Line|Interp> <ownLine|endOfLine|remaining> <leading|trailing|dangling>
//     <NodeType> <nodeStart> <nodeEnd>[ marker=<m>][ unignore]
// or `<start> <end> <type> <placement> unattached[ unignore]` for a comment a handler took
// without attaching it (handleIgnoreComments does that).
// then `prettierIgnore <NodeType> <start> <end>` for each node a handler flagged, sorted by
// position. Positions are UTF-16 offsets, as JavaScript counts.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const prettier = await import(path.join(ROOT, "node_modules/prettier/index.mjs"));
const babel = await import(path.join(ROOT, "node_modules/prettier/plugins/babel.mjs"));
const estree = await import(path.join(ROOT, "node_modules/prettier/plugins/estree.mjs"));

const SKIP = new Set(["comments", "leadingComments", "trailingComments", "innerComments", "extra",
  "loc", "range", "tokens"]);
const locStart = (n) => n.range?.[0] ?? n.start;
const locEnd = (n) => n.range?.[1] ?? n.end;
const isNode = (v) => v !== null && typeof v === "object" && typeof v.type === "string";
const TYPES = { CommentBlock: "Block", CommentLine: "Line", InterpreterDirective: "Interp" };

class Done extends Error {}

function collect(ast, all) {
  const rows = [];
  const ignored = [];
  const seen = new Set();
  const walk = (node) => {
    if (seen.has(node)) return;
    seen.add(node);
    if (node.prettierIgnore) ignored.push(node);
    for (const c of node.comments ?? []) rows.push([c, node]);
    for (const [k, v] of Object.entries(node)) {
      if (SKIP.has(k)) continue;
      if (Array.isArray(v)) { for (const x of v) if (isNode(x)) walk(x); }
      else if (isNode(v)) walk(v);
    }
  };
  walk(ast);
  const owner = new Map(rows);
  for (const c of all) if (!owner.has(c)) rows.push([c, null]);
  rows.sort((a, b) => locStart(a[0]) - locStart(b[0]));
  const out = rows.map(([c, n]) => {
    const how = c.leading ? "leading" : c.trailing ? "trailing" : "dangling";
    let s = `${locStart(c)} ${locEnd(c)} ${TYPES[c.type] ?? c.type} ${c.placement}`;
    s += n ? ` ${how} ${n.type} ${locStart(n)} ${locEnd(n)}` : " unattached";
    if (c.marker) s += ` marker=${c.marker}`;
    if (c.unignore) s += " unignore";
    return s;
  });
  ignored.sort((a, b) => locStart(a) - locStart(b) || locEnd(a) - locEnd(b) || (a.type < b.type ? -1 : 1));
  for (const n of ignored) out.push(`prettierIgnore ${n.type} ${locStart(n)} ${locEnd(n)}`);
  return out.join("\n") + (out.length ? "\n" : "");
}

let result;
const printer = estree.printers.estree;
const wrapper = {
  parsers: { babel: babel.parsers.babel, "babel-ts": babel.parsers["babel-ts"] },
  printers: {
    estree: {
      ...printer,
      print(p, options, ...rest) {
        if (p.stack.length === 1) {
          result = collect(p.node, options[Symbol.for("comments")] ?? []);
          throw new Done();
        }
        return printer.print(p, options, ...rest);
      },
    },
  },
};

// The parser for a file: babel, or babel-ts for TypeScript, whose AST shape the port builds
// (Prettier's default for .ts is typescript, which gives estree node types).
export const parserFor = (filepath) => (/\.[mc]?ts$/.test(filepath) ? "babel-ts" : "babel");

// The dump, or throws Prettier's error (a syntax error, for instance). Calls run one at a
// time: the wrapper hands its result over through a module variable.
let queue = Promise.resolve();
export function attachDump(text, filepath, options) {
  const p = queue.then(() => attachDumpNow(text, filepath, options));
  queue = p.catch(() => {});
  return p;
}

async function attachDumpNow(text, filepath, { experimentalTernaries = false } = {}) {
  result = undefined;
  try {
    await prettier.format(text, { filepath, parser: parserFor(filepath), plugins: [wrapper], experimentalTernaries });
  } catch (e) {
    if (!(e instanceof Done)) throw e;
  }
  if (result === undefined) throw new Error("the root was not printed");
  return result;
}

// What `prettier-asm --debug-comment-docs` writes, from Prettier: the comments of
// `prettier.__debug.parse` (babel), each printed by the estree printer's printComment with the
// normalized text as originalText, then printDocToString (width 80, tab width 2, spaces, lf)
// of the doc alone and of indent([hardline, doc]). Returns {out, count}.
const { builders: { indent, hardline } } = await import(path.join(ROOT, "node_modules/prettier/doc.mjs"));
export async function printDump(text, filepath) {
  const { ast } = await prettier.__debug.parse(text, { parser: parserFor(filepath), filepath });
  const originalText = text.replace(/\r\n?/g, "\n").replace(/^\uFEFF/, "");
  const opts = { parser: "babel", printWidth: 80, tabWidth: 2, useTabs: false, endOfLine: "lf" };
  let out = "";
  for (const c of ast.comments ?? []) {
    const doc = printer.printComment({ node: c }, { originalText });
    out += `${locStart(c)} ${locEnd(c)}\n`;
    for (const d of [doc, indent([hardline, doc])]) {
      const { formatted } = await prettier.__debug.printDocToString(d, opts);
      out += `${Buffer.byteLength(formatted)}\n${formatted}\n`;
    }
  }
  return { out, count: (ast.comments ?? []).length };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const text = fs.readFileSync(0, "utf8");
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith("--")) ?? "x.js";
  try {
    process.stdout.write(await attachDump(text, file, { experimentalTernaries: args.includes("--experimental-ternaries") }));
  } catch (e) {
    process.stderr.write(`error: ${e.message}\n`);
    process.exit(2);
  }
}
