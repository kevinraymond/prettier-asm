// node tests/stage3/infra/path-eval.mjs [binary]
//
// Checks src/path.s against Prettier 3.6.2's AstPath (src/common/ast-path.js):
// both walk the json5 AST of the same texts with path.call and path.each and
// write, per node, what key, index, isFirst, isLast, previous, next, parent,
// grandparent, siblings, match(...), findAncestor and callParent return.
// Texts come from the JSON corpus (ASCII only, so offsets agree) plus a few
// written here.
import path from "node:path";
import prettier from "prettier";
import { readCases, ROOT } from "../../lib.mjs";
import { evalItems, showDiff } from "./eval-run.mjs";

const { default: AstPath } = await import(path.join(ROOT, "ref/prettier/src/common/ast-path.js"));
const bin = path.resolve(process.argv[2] ?? path.join(ROOT, "build/prettier-asm"));

const TYPES = { JsonRoot: 1, ObjectExpression: 2, ArrayExpression: 3, ObjectProperty: 4, UnaryExpression: 5,
  StringLiteral: 6, NumericLiteral: 7, NullLiteral: 8, BooleanLiteral: 9, Identifier: 10, TemplateLiteral: 11,
  TemplateElement: 12 };
const KEYS = { node: 1, properties: 2, elements: 3, key: 4, value: 5, argument: 6, quasis: 7, expressions: 8 };
const t = (n) => (n ? TYPES[n.type] : 0);
const isLiteral = (n) => ["StringLiteral", "NumericLiteral", "NullLiteral", "BooleanLiteral", "Identifier", "TemplateLiteral"].includes(n.type);
const lists = [
  [isLiteral, (n) => n.type === "ObjectProperty"],
  [undefined, (n, k) => k === "value" && n.type === "ObjectProperty", (n, k, i) => n.type === "ObjectExpression" && k === "properties" && i === 0],
  [undefined, (n, k, i) => k === "elements" && i >= 1],
  [undefined, undefined, (n) => n.type === "JsonRoot"],
];

function walk(ast) {
  const out = [];
  const p = new AstPath(ast);
  const visit = () => {
    const n = p.node;
    if (!n) return;
    const sib = p.siblings;
    const anc = p.findAncestor((a) => a.type === "ObjectExpression");
    const cp = p.parent ? p.callParent((q) => t(q.node)) : 0;
    out.push([t(n), KEYS[p.key] ?? 0, p.index ?? -1, +p.isFirst, +p.isLast, t(p.previous), t(p.next), t(p.parent),
      t(p.grandparent), sib ? sib.length : -1, ...lists.map((l) => +p.match(...l)), anc ? anc.start : -1, cp].join(" "));
    switch (n.type) {
      case "JsonRoot": if (n.node) p.call(visit, "node"); break;
      case "UnaryExpression": p.call(visit, "argument"); break;
      case "ObjectExpression": p.each(visit, "properties"); break;
      case "ArrayExpression": p.each(visit, "elements"); break;
      case "ObjectProperty": p.call(visit, "key"); p.call(visit, "value"); break;
      case "TemplateLiteral": p.each(visit, "quasis"); p.each(visit, "expressions"); break;
    }
  };
  visit();
  return out.join("\n") + "\n";
}

const texts = ['{"a":[1,-2,`x`],b:{c:null}}', "[[1,2],[3,[4,{x:+5}]]]", '{"k":{"k":{"k":[]}}}', "[]", "{}", "1",
  '{a:1,b:2,c:3,d:[true,false,null,"s"]}'];
for (const c of readCases("json")) if (!/[^\x00-\x7f]/.test(c.stdin)) texts.push(c.stdin);

const items = [];
for (const text of texts) {
  let expected;
  try {
    const { ast } = await prettier.__debug.parse(text, { parser: "json5" });
    expected = walk(ast);
  } catch {
    continue;
  }
  items.push({ name: JSON.stringify(text.slice(0, 40)), commands: `(text ${JSON.stringify(text)})\n(pathwalk)\n`, expected, blocks: 1 });
}
const results = await evalItems(bin, items, path.join(ROOT, "build/stage3-path-eval"));
let same = 0, different = 0, refused = 0, nodes = 0;
const diffs = [];
items.forEach((item, i) => {
  const r = results[i];
  if (r.refused) return refused++;
  if (r[0] === item.expected) {
    same++;
    nodes += item.expected.split("\n").length - 1;
  } else {
    different++;
    diffs.push(`${item.name}: ${showDiff(item.expected, r[0])}`);
  }
});
for (const d of diffs.slice(0, 8)) console.log(d);
console.log(`path-eval: ${items.length} ASTs, ${same} same (${nodes} nodes), ${different} DIFFERENT, ${refused} refused by the JSON parser`);
process.exit(different ? 1 : 0);
