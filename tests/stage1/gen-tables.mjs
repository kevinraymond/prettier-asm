// Writes src/unicode_tables.s from Prettier 3.6.2's bundled dependencies, so
// the port uses the same character data:
//   wide_ranges:   code points that isFullWidth || isWide (get-east-asian-width)
//   emoji_nodes,
//   emoji_edges:   a trie of every string the emoji regex can match, in code
//                  points. The regex has no unbounded quantifiers, so its
//                  language is finite, and wherever two matches share a start
//                  the longer one comes first in backtracking order, so the
//                  regex's match at a position is the longest trie match.
//   es5_id_start,
//   es5_id_part:   UTF-16 code units is-es5-identifier-name accepts first and
//                  after the first
//
//   node tests/stage1/gen-tables.mjs <path to the prettier package>
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const pkg = process.argv[2];
const src = fs.readFileSync(path.join(pkg, "doc.mjs"), "utf8");
const estree = fs.readFileSync(path.join(pkg, "plugins/estree.mjs"), "utf8");

const fn = (name) => {
  const start = src.indexOf(`function ${name}(`);
  const end = src.indexOf("\n}\n", start);
  return src.slice(start, end + 2);
};
const isFullWidth = new Function(`${fn("isFullWidth")}; return isFullWidth;`)();
const isWide = new Function(`${fn("isWide")}; return isWide;`)();

const reStart = src.indexOf("var emoji_regex_default = () => {");
const reLine = src.slice(reStart).split("\n")[1].trim();
const reSource = reLine.slice("return /".length, reLine.lastIndexOf("/g;"));

// A parser for the subset of regex syntax emoji-regex uses; anything else
// throws, so a changed regex cannot be misread.
let at = 0;
const re = reSource;
const parseAlt = () => {
  const alts = [parseSeq()];
  while (re[at] === "|") {
    at++;
    alts.push(parseSeq());
  }
  return { t: "alt", alts };
};
const parseSeq = () => {
  const items = [];
  while (at < re.length && re[at] !== "|" && re[at] !== ")") {
    let a = parseAtom();
    if (re[at] === "?") {
      at++;
      a = { t: "opt", a };
    } else if ("*+{".includes(re[at])) throw new Error(`quantifier ${re[at]}`);
    items.push(a);
  }
  return { t: "seq", items };
};
const unit = () => {
  if (re[at] !== "\\") {
    if ("().^$|".includes(re[at])) throw new Error(`metacharacter ${re[at]}`);
    return re.charCodeAt(at++);
  }
  const k = re[at + 1];
  if (k === "u") {
    at += 6;
    return parseInt(re.slice(at - 4, at), 16);
  }
  if (k === "x") {
    at += 4;
    return parseInt(re.slice(at - 2, at), 16);
  }
  throw new Error(`escape \\${k}`);
};
const parseAtom = () => {
  if (re.startsWith("(?:", at)) {
    at += 3;
    const a = parseAlt();
    if (re[at++] !== ")") throw new Error("unclosed group");
    return a;
  }
  if (re[at] === "[") {
    at++;
    if (re[at] === "^") throw new Error("negated class");
    const set = [];
    while (re[at] !== "]") {
      const a = unit();
      if (re[at] === "-" && re[at + 1] !== "]") {
        at++;
        const b = unit();
        for (let c = a; c <= b; c++) set.push(c);
      } else set.push(a);
    }
    at++;
    return { t: "set", set };
  }
  return { t: "set", set: [unit()] };
};
const reAst = parseAlt();
if (at !== re.length) throw new Error(`regex parse stopped at ${at}`);
// The language, in backtracking order (greedy `?` tries the atom first).
function* lang(n) {
  if (n.t === "set") for (const c of n.set) yield [c];
  else if (n.t === "opt") {
    yield* lang(n.a);
    yield [];
  } else if (n.t === "alt") for (const a of n.alts) yield* lang(a);
  else yield* seqLang(n.items, 0);
}
function* seqLang(items, k) {
  if (k === items.length) {
    yield [];
    return;
  }
  for (const head of lang(items[k])) for (const tail of seqLang(items, k + 1)) yield [...head, ...tail];
}
const emojiStrings = [];
for (const units of lang(reAst)) {
  if (units.length === 0) throw new Error("the regex matches the empty string");
  const str = String.fromCharCode(...units);
  const cps = [...str].map((c) => c.codePointAt(0));
  if (cps.some((c) => c >= 0xd800 && c <= 0xdfff)) throw new Error("a match splits a surrogate pair");
  emojiStrings.push(cps);
}
const orderOf = new Map(emojiStrings.map((cps, i) => [cps.join(","), i]));
for (const [key, i] of orderOf) {
  const parts = key.split(",");
  for (let n = 1; n < parts.length; n++) {
    const shorter = orderOf.get(parts.slice(0, n).join(","));
    if (shorter !== undefined && shorter < i) throw new Error("a shorter match is tried first");
  }
}
// Check the claim on the real regex: longest trie match == regex match.
{
  const real = new RegExp(re, "g");
  for (const cps of emojiStrings) {
    const str = String.fromCodePoint(...cps);
    real.lastIndex = 0;
    const m = real.exec(str + "x");
    if (!m || m.index !== 0 || m[0] !== str) throw new Error("regex does not match its own string");
  }
}
const trie = [{ edges: new Map(), terminal: false }];
for (const cps of emojiStrings) {
  let node = 0;
  for (const c of cps) {
    let next = trie[node].edges.get(c);
    if (next === undefined) {
      next = trie.length;
      trie.push({ edges: new Map(), terminal: false });
      trie[node].edges.set(c, next);
    }
    node = next;
  }
  trie[node].terminal = true;
}
// Check the trie and tables against Prettier's own getStringWidth on random
// strings built from emoji, their parts, wide, narrow and control characters.
{
  const { util } = await import(path.join(pkg, "index.mjs"));
  const cpWidth = (cp) => {
    if (cp <= 0x1f || (cp >= 0x7f && cp <= 0x9f)) return 0;
    if (cp >= 0x300 && cp <= 0x36f) return 0;
    return isFullWidth(cp) || isWide(cp) ? 2 : 1;
  };
  const trieWidth = (str) => {
    const cps = [...str].map((c) => c.codePointAt(0));
    let width = 0;
    for (let i = 0; i < cps.length; ) {
      let node = 0;
      let best = 0;
      for (let j = i; j < cps.length; j++) {
        const next = trie[node].edges.get(cps[j]);
        if (next === undefined) break;
        node = next;
        if (trie[node].terminal) best = j + 1 - i;
      }
      if (best) {
        width += 2;
        i += best;
      } else width += cpWidth(cps[i++]);
    }
    return width;
  };
  let seed = 7;
  const rnd = (n) => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  };
  const pieces = [
    () => String.fromCodePoint(...emojiStrings[rnd(emojiStrings.length)]),
    () => String.fromCodePoint(emojiStrings[rnd(emojiStrings.length)][0]),
    () => ["\u200d", "\ufe0f", "\u20e3", "\u{1f3fd}", "\u{1f1ef}", "\u{e0067}"][rnd(6)],
    () => "a1#*é漢ｚ\u0301\t\u0085"[rnd(10)],
  ];
  for (let n = 0; n < 50000; n++) {
    let str = "x";
    for (let k = rnd(6); k >= 0; k--) str += pieces[rnd(pieces.length)]();
    if (trieWidth(str) !== util.getStringWidth(str)) {
      throw new Error(`width differs for ${JSON.stringify(str)}`);
    }
  }
}

const nodeWords = [];
const edgeWords = [];
for (const n of trie) {
  const edges = [...n.edges].sort((a, b) => a[0] - b[0]);
  nodeWords.push(edgeWords.length / 2, edges.length | (n.terminal ? 0x80000000 : 0));
  for (const [c, child] of edges) edgeWords.push(c, child);
}

const ranges = (pred, max) => {
  const out = [];
  let start = -1;
  for (let cp = 0; cp <= max + 1; cp++) {
    const inside = cp <= max && pred(cp);
    if (inside && start < 0) start = cp;
    if (!inside && start >= 0) {
      out.push([start, cp - 1]);
      start = -1;
    }
  }
  return out;
};

// is-es5-identifier-name, minified in the estree plugin as `var Sl=/^[...][...]*$/`
// and used as `Bl=e=>Sl.test(e)`.
const idStart = estree.indexOf("var Sl=/^");
let idEnd = idStart + "var Sl=/".length;
for (let inClass = false; ; idEnd++) {
  const c = estree[idEnd];
  if (c === "\\") idEnd++;
  else if (c === "[") inClass = true;
  else if (c === "]") inClass = false;
  else if (c === "/" && !inClass) break;
}
if (!estree.slice(idEnd, idEnd + 30).startsWith("/,Bl=e=>Sl.test(e)")) {
  throw new Error("is-es5-identifier-name regex not found where expected");
}
const es5Re = new RegExp(estree.slice(idStart + "var Sl=/".length, idEnd));
const es5Start = ranges((u) => u >= 0x80 && es5Re.test(String.fromCharCode(u)), 0xffff);
const es5Part = ranges((u) => u >= 0x80 && es5Re.test("a" + String.fromCharCode(u)), 0xffff);
for (let u = 0; u < 0x80; u++) {
  const c = String.fromCharCode(u);
  if (es5Re.test(c) !== /[$A-Z_a-z]/.test(c)) throw new Error("ASCII identifier start differs");
  if (es5Re.test("a" + c) !== /[$0-9A-Z_a-z]/.test(c)) throw new Error("ASCII identifier part differs");
}

for (const [a, b] of [...es5Start, ...es5Part]) {
  if (b >= 0xd800 && a <= 0xdfff) throw new Error("surrogate in an identifier table");
}

const wide = ranges((cp) => isFullWidth(cp) || isWide(cp), 0x10ffff);

const words = (list) => {
  const lines = [];
  for (let k = 0; k < list.length; k += 8) {
    lines.push("    .long " + list.slice(k, k + 8).map((w) => "0x" + (w >>> 0).toString(16)).join(", "));
  }
  return lines.join("\n");
};
const fmt = (list) =>
  list.map(([a, b]) => `    .long 0x${a.toString(16)}, 0x${b.toString(16)}`).join("\n");

const out = `# Generated by tests/stage1/gen-tables.mjs from Prettier 3.6.2's bundled
# get-east-asian-width (isFullWidth || isWide), emoji-regex and
# is-es5-identifier-name. Range tables are pairs of inclusive bounds, sorted;
# the es5 tables hold UTF-16 code units at or above 0x80.
    .section .rodata
    .balign 4
    .globl wide_ranges, wide_ranges_count, emoji_nodes, emoji_edges
    .globl es5_id_start, es5_id_start_count, es5_id_part, es5_id_part_count
wide_ranges:
${fmt(wide)}
wide_ranges_count: .long ${wide.length}
# emoji_nodes: per node, first edge index and edge count (bit 31: a match
# ends here). emoji_edges: per edge, code point and child node, sorted by
# code point within a node. Node 0 is the root.
emoji_nodes:
${words(nodeWords)}
emoji_edges:
${words(edgeWords)}
es5_id_start:
${fmt(es5Start)}
es5_id_start_count: .long ${es5Start.length}
es5_id_part:
${fmt(es5Part)}
es5_id_part_count: .long ${es5Part.length}
`;
fs.writeFileSync(path.join(root, "src/unicode_tables.s"), out);
console.log(
  `wide ${wide.length}, es5 start ${es5Start.length}, es5 part ${es5Part.length} ranges; emoji trie ${trie.length} nodes from ${emojiStrings.length} strings`,
);
