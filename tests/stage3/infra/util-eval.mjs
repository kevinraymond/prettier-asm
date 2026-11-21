// node tests/stage3/infra/util-eval.mjs [binary] [--random N] [--harvest N]
//
// Checks the binary's doc utils (cleanDoc, stripTrailingHardline,
// removeLines, replaceEndOfLine, propagateBreaks, mapDoc, inheritLabel,
// findInDoc, addAlignmentToDoc, willBreak, canBreak, isEmptyDoc) against Prettier 3.6.2's own
// functions, on random docs, the synthetic docs and harvested docs. Results
// are compared in the exact doc text, which shows array structure, empty
// strings and sharing; replaceEndOfLine in the normalized text, because
// Prettier's mapDoc caches strings by value and the binary by address.
import path from "node:path";
import prettier from "prettier";
import { readCases, ROOT } from "../../lib.mjs";
import { docToText, textToDoc } from "./doc-text.mjs";
import { flagsToOptions } from "./flags.mjs";
import { syntheticDocs } from "./synthetic-docs.mjs";
import { evalItems, showDiff } from "./eval-run.mjs";

const src = await import(path.join(ROOT, "ref/prettier/src/document/utils.js"));
const u = prettier.doc.utils;
const argv = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = argv.indexOf(name);
  if (i < 0) return dflt;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v;
};
const randomCount = Number(flag("--random", "4000"));
const harvestCount = Number(flag("--harvest", "400"));
const bin = path.resolve(argv[0] ?? path.join(ROOT, "build/prettier-asm"));

const UTILS = {
  cleanDoc: (d) => src.cleanDoc(d),
  stripTrailingHardline: (d) => u.stripTrailingHardline(d),
  removeLines: (d) => u.removeLines(d),
  replaceEndOfLine: (d) => u.replaceEndOfLine(d),
  propagateBreaks: (d) => (src.propagateBreaks(d), d),
  mapDoc: (d) => u.mapDoc(d, (x) => x),
  inheritLabel: (d) => src.inheritLabel(d, (x) => [x, "!"]),
  findInDoc: (d) => u.findInDoc(d, (x) => (typeof x === "string" && x !== "" ? x : undefined), "none"),
  addAlignmentToDoc: (d) => prettier.doc.builders.addAlignmentToDoc(d, 7, 3),
};
const PREDS = { willBreak: u.willBreak, canBreak: u.canBreak, isEmptyDoc: src.isEmptyDoc };

// ---------------------------------------------------------------- random docs
function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function randomDoc(seed) {
  const r = mulberry32(seed);
  const pick = (a) => a[Math.floor(r() * a.length)];
  const ids = [Symbol("a"), Symbol("b"), Symbol("c")];
  const pool = [];
  const HARDLINE = [{ type: "line", hard: true }, { type: "break-parent" }];
  const leaf = () => pick([
    () => "", () => "a", () => "b c", () => "x\n", () => "y\r\n\n", () => "\n", () => "é",
    () => ({ type: "line" }), () => ({ type: "line", soft: true }), () => ({ type: "line", hard: true }),
    () => ({ type: "line", hard: true, literal: true }), () => ({ type: "break-parent" }),
    () => ({ type: "line-suffix-boundary" }), () => ({ type: "trim" }), () => HARDLINE,
  ])();
  const node = (depth) => {
    if (pool.length && r() < 0.1) return pick(pool);
    if (depth <= 0 || r() < 0.3) return leaf();
    const sub = () => node(depth - 1);
    const brk = () => pick([false, false, true, "propagated"]);
    const d = pick([
      () => Array.from({ length: Math.floor(r() * 5) }, sub),
      () => [sub(), [sub(), [sub()]], ""],
      () => ({ type: "group", contents: sub(), break: brk(), id: r() < 0.3 ? pick(ids) : undefined }),
      () => {
        const id = r() < 0.3 ? pick(ids) : undefined;
        const b = brk();
        return { type: "group", contents: { type: "group", contents: sub(), break: r() < 0.7 ? b : brk(), id: r() < 0.7 ? id : pick(ids) }, break: b, id };
      },
      () => {
        const states = Array.from({ length: 1 + Math.floor(r() * 3) }, sub);
        return { type: "group", contents: states[0], break: brk(), expandedStates: states, id: r() < 0.2 ? pick(ids) : undefined };
      },
      () => ({ type: "indent", contents: sub() }),
      () => ({ type: "align", contents: sub(), n: pick([2, -1, 0, "> ", "", Number.NEGATIVE_INFINITY, { type: "root" }]) }),
      () => ({ type: "fill", parts: Array.from({ length: Math.floor(r() * 4) }, () => (r() < 0.3 ? "" : sub())) }),
      () => ({ type: "if-break", breakContents: r() < 0.3 ? "" : sub(), flatContents: r() < 0.5 ? "" : sub(), groupId: r() < 0.3 ? pick(ids) : undefined }),
      () => ({ type: "indent-if-break", contents: sub(), groupId: pick(ids), negate: r() < 0.5 }),
      () => ({ type: "line-suffix", contents: sub() }),
      () => ({ type: "label", label: pick([{ memberChain: true }, { embed: true, hug: false }]), contents: sub() }),
    ])();
    pool.push(d);
    return d;
  };
  return node(5);
}

// ---------------------------------------------------------------- doc texts
const texts = [];
for (let s = 1; s <= randomCount; s++) texts.push(["random:" + s, docToText(randomDoc(s), { exact: true })]);
for (const s of syntheticDocs()) {
  try {
    const t = docToText(s.doc, { exact: true });
    textToDoc(t);
    texts.push(["synthetic:" + s.name, t]);
  } catch {}
}
let harvested = 0;
for (const c of readCases("js-fixtures")) {
  if (harvested >= harvestCount) break;
  try {
    const doc = await prettier.__debug.printToDoc(c.stdin, flagsToOptions(c.args));
    texts.push(["harvest:" + c.name, docToText(doc, { exact: true })]);
    harvested++;
  } catch {}
}

// ---------------------------------------------------------------- expected
const items = [];
const counts = {};
for (const [name, text] of texts) {
  for (const [util, fn] of Object.entries(UTILS)) {
    let expected;
    try {
      const exact = util !== "replaceEndOfLine";
      expected = docToText(fn(textToDoc(text)), { exact });
      items.push({ name, util, expected, commands: `(doc ${text})\n(util ${util})\n(${exact ? "dumpx" : "dump"})\n`, blocks: 1 });
    } catch (e) {
      { const k = "prettier throws " + util + ": " + e.message.slice(0, 60); counts[k] = (counts[k] ?? 0) + 1; }
    }
  }
  for (const [pred, fn] of Object.entries(PREDS)) {
    items.push({ name, util: pred, expected: String(fn(textToDoc(text))), commands: `(doc ${text})\n(pred ${pred})\n`, blocks: 1 });
  }
}

const results = await evalItems(bin, items, path.join(ROOT, "build/stage3-util-eval"));
const perUtil = {};
let same = 0, different = 0, refused = 0;
const diffs = [];
items.forEach((item, i) => {
  const r = results[i];
  const p = (perUtil[item.util] ??= { same: 0, different: 0, refused: 0 });
  if (r.refused) {
    refused++;
    p.refused++;
    diffs.push(`${item.name} ${item.util}: refused: ${r.refused}`);
  } else if (r[0] === item.expected) {
    same++;
    p.same++;
  } else {
    different++;
    p.different++;
    diffs.push(`${item.name} ${item.util}: ${showDiff(item.expected, r[0])}`);
  }
});
for (const d of diffs.slice(0, 10)) console.log(d);
for (const [k, n] of Object.entries(counts)) console.log(`skipped ${n}: ${k}`);
for (const [k, p] of Object.entries(perUtil)) console.log(`  ${k.padEnd(22)} ${p.same} same, ${p.different} different, ${p.refused} refused`);
console.log(`util-eval: ${texts.length} docs, ${items.length} checks: ${same} same, ${different} DIFFERENT, ${refused} refused`);
process.exit(different || refused ? 1 : 0);
