// node tests/stage3/printer/ts-ast.mjs [--parser typescript|babel-ts] (-e CODE | FILE)
// Prints the AST Prettier's parser hands the printer (after postprocess), without positions,
// to compare the typescript-estree shape with the babel-ts one.
import fs from "node:fs";
import prettier from "prettier";

const argv = process.argv.slice(2);
let parser = "typescript";
const pi = argv.indexOf("--parser");
if (pi >= 0) { parser = argv[pi + 1]; argv.splice(pi, 2); }
const text = argv[0] === "-e" ? argv[1] : fs.readFileSync(argv[0], "utf8");
const { ast } = await prettier.__debug.parse(text, { parser, filepath: "x.ts" });
const skip = new Set(["loc", "range", "start", "end", "comments", "tokens", "extra", "parent", "leadingComments", "trailingComments", "innerComments"]);
function show(node, indent) {
  if (Array.isArray(node)) return node.length ? "[\n" + node.map((n) => indent + "  " + show(n, indent + "  ")).join("\n") + "\n" + indent + "]" : "[]";
  if (!node || typeof node !== "object") return JSON.stringify(node);
  const keys = Object.keys(node).filter((k) => !skip.has(k) && k !== "type" && node[k] !== undefined);
  const head = node.type ?? "{}";
  const parts = keys.map((k) => `${indent}  ${k}: ${show(node[k], indent + "  ")}`);
  return parts.length ? `${head}\n${parts.join("\n")}` : head;
}
console.log(show(ast.type === "File" ? ast.program : ast, ""));
