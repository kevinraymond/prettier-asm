// node tests/stage3/infra/text-eval.mjs [binary] [--texts N]
//
// Checks the binary's text helpers (src/text.s, src/literal.s, src/width.s)
// against prettier.util and Prettier 3.6.2's sources on random texts made of
// spaces, line breaks (\n, \r\n, \r, U+2028, U+2029), comments, Unicode
// spaces, quotes and astral characters, at every index.
//
// Prettier's indices count UTF-16 units, the binary's count bytes. A forward
// index maps to the byte offset of the character starting there; a backward
// character position maps to the offset of that character's last byte.
import path from "node:path";
import prettier from "prettier";
import { ROOT } from "../../lib.mjs";
import { evalItems, showDiff } from "./eval-run.mjs";

const util = prettier.util;
const { default: getMinNotPresentContinuousCount } = await import(
  path.join(ROOT, "ref/prettier/src/utils/get-min-not-present-continuous-count.js"));
const argv = process.argv.slice(2);
const ti = argv.indexOf("--texts");
const textCount = ti >= 0 ? Number(argv.splice(ti, 2)[1]) : 400;
const bin = path.resolve(argv[0] ?? path.join(ROOT, "build/prettier-asm"));

function mulberry32(a) {
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const PIECES = [" ", " ", "\t", "\n", "\n", "\r\n", "\r", "a", "b", "x", ",", ";", "/*", "*/", "/* c */",
  "// x", "/", "*", " ", " ", " ", "　", "﻿", " ", "é", "😀", "'", '"', "\\",
  "\\'", '\\"', "\\n", "``", "`", "(", "\v", "\f"];

// UTF-16 index -> byte offset, for every index (inside a surrogate pair: the
// pair's start); and -> offset of the last byte of the character there.
function maps(text) {
  const first = [], last = [];
  let b = 0;
  for (let u = 0; u < text.length;) {
    const cp = text.codePointAt(u);
    const n = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    const units = cp >= 0x10000 ? 2 : 1;
    for (let k = 0; k < units; k++) {
      first[u + k] = b;
      last[u + k] = b + n - 1;
    }
    u += units;
    b += n;
  }
  first[text.length] = b;
  last[text.length] = b;
  first[-1] = -1;
  last[-1] = -1;
  return { first, last, bytes: b };
}
const isHigh = (text, u) => /[\ud800-\udbff]/.test(text[u] ?? "");
const isLow = (text, u) => /[\udc00-\udfff]/.test(text[u] ?? "");

const items = [];
const add = (name, commands, expected) => items.push({ name, commands, expected, blocks: 1 });
const idx = (m, r, back) => (r === false ? "false" : String((back ? m.last : m.first)[r]));

const r = mulberry32(7);
for (let n = 0; n < textCount; n++) {
  let text = "";
  const len = 1 + Math.floor(r() * 24);
  for (let k = 0; k < len; k++) text += PIECES[Math.floor(r() * PIECES.length)];
  const m = maps(text);
  const T = `(text ${JSON.stringify(text)})\n`;
  const cmds = [];
  const expect = [];
  const push = (cmd, e) => {
    cmds.push(cmd);
    expect.push(e);
  };
  for (let u = -1; u <= text.length; u++) {
    const startOfChar = u < 0 || u >= text.length || !isLow(text, u);
    if (startOfChar) {
      const b = m.first[u];
      push(`(t skip 1 ${b} 0)`, idx(m, util.skipSpaces(text, u), false));
      push(`(t skip 2 ${b} 0)`, idx(m, util.skipToLineEnd(text, u), false));
      push(`(t skip 3 ${b} 0)`, idx(m, util.skipEverythingButNewLine(text, u), false));
      push(`(t skip 4 ${b} 0)`, idx(m, util.skipWhitespace(text, u), false));
      push(`(t skipNewline ${b} 0)`, idx(m, util.skipNewline(text, u), false));
      push(`(t skipInlineComment ${b})`, idx(m, util.skipInlineComment(text, u), false));
      push(`(t skipTrailingComment ${b})`, idx(m, util.skipTrailingComment(text, u), false));
      push(`(t hasNewline ${b} 0)`, String(util.hasNewline(text, u)));
      push(`(t hasSpaces ${b} 0)`, String(util.hasSpaces(text, u)));
      push(`(t isNextLineEmpty ${b})`, String(util.isNextLineEmpty(text, u)));
      push(`(t nextIndex ${b})`, idx(m, util.getNextNonSpaceNonCommentCharacterIndex(text, u), false));
      // the binary returns the code point where charAt returns a lone surrogate
      const ni = util.getNextNonSpaceNonCommentCharacterIndex(text, u);
      const nc = util.getNextNonSpaceNonCommentCharacter(text, u);
      push(`(t nextChar ${b})`, isHigh(text, ni) ? String.fromCodePoint(text.codePointAt(ni)) : nc);
      // a boundary for the backward forms that step back first
      push(`(t hasNewline ${b} 1)`, String(util.hasNewline(text, u, { backwards: true })));
      push(`(t hasSpaces ${b} 1)`, String(util.hasSpaces(text, u, { backwards: true })));
      if (u >= 0) push(`(t isPreviousLineEmpty ${b})`, String(util.isPreviousLineEmpty(text, u)));
      for (let e = u; e <= text.length; e += 3) {
        if (e < text.length && isLow(text, e)) continue;
        push(`(t hasNewlineInRange ${b} ${m.first[e]})`, String(util.hasNewlineInRange(text, u, e)));
      }
    }
    // backward scans examine the character at u: skip high surrogates
    if (!isHigh(text, u)) {
      const b = m.last[u];
      push(`(t skip 1 ${b} 1)`, idx(m, util.skipSpaces(text, u, { backwards: true }), true));
      push(`(t skip 2 ${b} 1)`, idx(m, util.skipToLineEnd(text, u, { backwards: true }), true));
      push(`(t skip 4 ${b} 1)`, idx(m, util.skipWhitespace(text, u, { backwards: true }), true));
      push(`(t skipNewline ${b} 1)`, idx(m, util.skipNewline(text, u, { backwards: true }), true));
    }
  }
  for (const tw of [1, 2, 4, 8]) {
    push(`(t alignmentSize ${JSON.stringify(text)} ${tw} 0)`, String(util.getAlignmentSize(text, tw)));
    push(`(t indentSize ${JSON.stringify(text)} ${tw})`, String(util.getIndentSize(text, tw)));
  }
  for (const search of ["`", "*", "a", "ab", "\n", "😀", "``"]) {
    push(`(t maxCount ${JSON.stringify(text)} ${JSON.stringify(search)})`, String(util.getMaxContinuousCount(text, search)));
    push(`(t minNotPresent ${JSON.stringify(text)} ${JSON.stringify(search)})`, String(getMinNotPresentContinuousCount(text, search)));
  }
  push(`(t preferredQuote ${JSON.stringify(text)} 0)`, util.getPreferredQuote(text, false));
  push(`(t preferredQuote ${JSON.stringify(text)} 1)`, util.getPreferredQuote(text, true));
  for (const q of ['"', "'"]) push(`(t makeString ${JSON.stringify(text)} ${JSON.stringify(q)})`, util.makeString(text, q));
  push(`(t stringWidth ${JSON.stringify(text)})`, String(util.getStringWidth(text)));
  items.push({ name: JSON.stringify(text), commands: T + cmds.join("\n") + "\n", cmdList: cmds, expected: expect, blocks: cmds.length });
}

const results = await evalItems(bin, items, path.join(ROOT, "build/stage3-text-eval"), { chunkItems: 20 });
let same = 0, different = 0, refused = 0;
const perHelper = {};
const diffs = [];
items.forEach((item, i) => {
  const res = results[i];
  if (res.refused) {
    refused += item.blocks;
    diffs.push(`${item.name}: refused: ${res.refused}`);
    return;
  }
  item.expected.forEach((e, k) => {
    const helper = item.cmdList[k].split(" ").slice(1, 2).join("") + (item.cmdList[k].startsWith("(t skip ") ? item.cmdList[k].split(" ")[2] : "");
    const p = (perHelper[helper] ??= { same: 0, different: 0 });
    if (res[k] === e) {
      same++;
      p.same++;
    } else {
      different++;
      p.different++;
      diffs.push(`${item.name} ${item.cmdList[k]}: ${showDiff(e, res[k] ?? "(missing)")}`);
    }
  });
});
for (const d of diffs.slice(0, 12)) console.log(d);
for (const [k, p] of Object.entries(perHelper)) console.log(`  ${k.padEnd(22)} ${p.same} same, ${p.different} different`);
console.log(`text-eval: ${items.length} texts, ${same + different} checks: ${same} same, ${different} DIFFERENT, ${refused} refused`);
process.exit(different || refused ? 1 : 0);
