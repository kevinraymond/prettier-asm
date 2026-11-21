// Edge cases for stage 1, each run under every JSON parser's file name.
const names = [
  ["json", "x.json"],
  ["jsonc", "x.jsonc"],
  ["json5", "x.json5"],
  ["package.json", "package.json"],
];

const BOM = "﻿";

function fixed() {
  const longString = "x".repeat(100);
  const nest = (n, open, close, inner) => open.repeat(n) + inner + close.repeat(n);
  const width = (n) => {
    // `{ "k": "vvv" }` printed at exactly n columns
    const v = "v".repeat(n - '{ "k": "" }'.length);
    return `{"k": "${v}"}`;
  };
  const arrWidth = (n) => {
    // `["aaa", ...]` printed at exactly n columns
    const items = [];
    let len = 2;
    while (len + 5 + 2 <= n) {
      items.push('"a"');
      len += items.length === 1 ? 3 : 5;
    }
    const pad = n - len;
    if (pad > 0) items[0] = `"${"a".repeat(1 + pad)}"`;
    return `[${items.join(",")}]`;
  };
  const numbers = (count, digits) =>
    "[" +
    Array.from({ length: count }, (_, i) => String((i * 7919) % 10 ** digits)).join(", ") +
    "]";
  return {
    "empty": "",
    "whitespace-only": "  \n\t\n  ",
    "bom-object": BOM + '{"a":1}',
    "bom-only": BOM,
    "bom-whitespace": BOM + "  \n",
    "crlf-object": '{\r\n  "a": 1,\r\n  "b": [1,\r\n 2]\r\n}\r\n',
    "crlf-comments": '{\r\n  // c\r\n  "a": 1 /* d\r\n e */\r\n}\r\n',
    "cr-only": '{\r"a": 1,\r"b": 2\r}\r',
    "no-trailing-newline": '{"a": [1, 2, {"b": null}]}',
    "trailing-newlines": '{"a": 1}\n\n\n',
    "long-string": `{"key": "${longString}"}`,
    "long-key": `{"${longString}": 1}`,
    "long-array-strings": "[" + Array.from({ length: 30 }, (_, i) => `"item${i}"`).join(",") + "]",
    "long-line-object": "{" + Array.from({ length: 20 }, (_, i) => `"k${i}": ${i}`).join(", ") + "}",
    "deep-arrays-100": nest(100, "[", "]", "1"),
    "deep-objects-100": nest(100, '{"a":', "}", "1"),
    "deep-mixed-500": nest(500, '[{"a":', "}]", "[]"),
    "numbers-short": numbers(5, 3),
    "numbers-fill-40": numbers(40, 4),
    "numbers-fill-200": numbers(200, 6),
    "numbers-negative": "[" + Array.from({ length: 40 }, (_, i) => (i % 3 ? -i * 13 : i * 1.5)).join(", ") + "]",
    "numbers-blank-line": "[1, 2, 3,\n\n4, 5, 6]",
    "numbers-line-comment": "[1, // one\n2, 3]",
    "numbers-block-comment": "[1, /* one */ 2, 3]",
    "numbers-leading-comment": "[1,\n// two\n2, 3]",
    "numbers-plus": "[+1, -2, +3e5, 0x10, 0b11, 0o7, .5, 5.]",
    "numbers-mixed": "[1, 2, \"three\", 4]",
    "numbers-nested": "[[1, 2, 3], [4, 5, 6]]",
    "objects-in-array": '[{"a": 1, "b": 2}, {"a": 3, "b": 4}]',
    "arrays-in-array": "[[1, 2], [3, 4], [5, 6]]",
    "empty-object-block-comment": "{ /* c */ }",
    "empty-object-line-comment": "{\n  // c\n}",
    "empty-array-block-comment": "[ /* c */ ]",
    "empty-array-line-comment": "[\n  // c\n]",
    "empty-array-two-comments": "[/* a */ /* b */]",
    "comment-before-root": "// top\n{\"a\": 1}",
    "comment-after-root": "{\"a\": 1}\n// bottom\n",
    "block-before-root": "/* top */ {\"a\": 1}",
    "block-after-root": "{\"a\": 1} /* end */",
    "comment-before-key": '{\n  // c\n  "a": 1\n}',
    "comment-after-key": '{\n  "a" /* c */: 1\n}',
    "comment-after-colon": '{\n  "a": /* c */ 1\n}',
    "line-comment-after-colon": '{\n  "a": // c\n  1\n}',
    "own-line-comment-before-value": '{\n  "a":\n  // c\n  1\n}',
    "comment-after-value": '{\n  "a": 1 // c\n}',
    "comment-after-comma": '{\n  "a": 1, // c\n  "b": 2\n}',
    "comment-before-comma": '{\n  "a": 1 /* c */, "b": 2\n}',
    "comment-end-of-object": '{\n  "a": 1\n  // last\n}',
    "comment-end-of-array": "[\n  1,\n  2\n  // last\n]",
    "comment-in-array": "[1, /* c */ 2]",
    "comment-blank-lines": '{\n  "a": 1,\n\n  // c\n\n  "b": 2\n}',
    "jsdoc-comment": '{\n  /**\n   * Doc\n   * more\n   */\n  "a": 1\n}',
    "multiline-block-comment": '{\n  /* line one\n     line two */\n  "a": 1\n}',
    "type-cast-comment": '{"a": /** @type {number} */ 1}',
    "prettier-ignore": '{\n  // prettier-ignore\n  "a":   [1,2,   3],\n  "b":   [1,2,   3]\n}',
    "prettier-ignore-value": '[\n  // prettier-ignore\n  {"a":1,   "b":2},\n  {"a":1,   "b":2}\n]',
    "unary-comment": "[- /* c */ 1]",
    "json5-keys": "{'a': 1, b: 2, 'c-d': 3, \"e\": 4, 'f\\'g': 5, 1: 6, 0x10: 7, 'h\"i': \"x'y\", $x: 8, _y: 9}",
    "json5-strings": "['a', \"b\", 'c\"d', \"e'f\", 'g\\'h', \"i\\\"j\", '\\x41\\u0042']",
    "json5-number-keys": "{1: 1, 1.5: 2, 1.0: 3, 0.5: 4, .5: 5, 1e3: 6, 10: 7, 999999999999999: 8}",
    "keywords-as-keys": "{null: 1, true: 2, false: 3, if: 4, undefined: 5, Infinity: 6, NaN: 7}",
    "special-values": "[Infinity, -Infinity, NaN, +NaN, undefined, null, true, false]",
    "template-literals": "[`a`, `b\nc`, `d\\`e`, `\\u{1F409}`]",
    "string-escapes": '["\\b\\f\\n\\r\\t", "\\u0000\\u001f", "\\/", "\\\\", "\\\'", "\\0"]',
    "sloppy-escapes": '["\\8", "\\9", "\\01", "\\0", "\\08", "\\377", "\\400", "\\x41\\u{41}"]',
    "template-escapes": "[`\\0`, `\\x41`, `\\u{41}`, `a\\\nb`]",
    "template-bad-octal": "[`\\01`]",
    "template-bad-8": "[`\\8`]",
    "html-comment": "[1, <!-- x\n 2]",
    "vertical-tab-formfeed": '{\u000b"a":\u000c1}',
    "string-line-continuation": '{"a": "one \\\ntwo"}',
    "width-80": width(80),
    "width-81": width(81),
    "width-79": width(79),
    "array-width-80": arrWidth(80),
    "array-width-81": arrWidth(81),
    "nested-width-80": `{"outer": ${width(80 - 2 - '"outer": '.length - 2)}}`,
    "nested-width-81": `{"outer": ${width(81 - 2 - '"outer": '.length - 2)}}`,
    "object-newline-preserve": '{"a": {\n"b": 1}, "c": {"d": 2}}',
    "object-first-key-newline": '{"a": 1,\n"b": 2}',
    "holes": "[1,,2,,,]",
    "only-holes": "[,,]",
    "trailing-commas": '{"a": [1, 2,], "b": {"c": 1,},}',
    "proto-twice": '{"__proto__": 1, "__proto__": 2}',
    "proto-once": '{"__proto__": 1, "a": 2}',
    "bigint": "[1n]",
    "separator": "[1_000, 0x1_0]",
    "legacy-octal": "[0123, 00, 08]",
    "noctal-decimals": "[08, 09.5, 08e1, 0189.50, 0800, 09E-2]",
    "noctal-keys": "{08: 1, 08.5: 2, 010: 3, 00: 4}",
    "legacy-octal-dot": "[07.5]",
    "noctal-separator": "[08_1]",
    "number-forms": "[1E5, 1e+05, 1e-05, 1.50, 1.0, 0.0, 0e0, 1.e3, .1e-2, 0XAB, 1_0.5_0]",
    "big-numbers": "[123456789012345678901234567890, 1e400, 5e-324, 0.1, 9007199254740993]",
    "overflow-numbers": "{\"a\": [1e400, 1e-400, 0.5e310, 1e309, 0e99999, -1e400], 1e999999999999999999: 1, 1e-999: 2}",
    "stringify-numbers": "[1E21, 1e20, 123e-20, 0.000001, 0.0000001, 1.5e-7, 100, 1e2, 0x1F, 0o17, 0b101, 1_000_000, 0.1e1, 9007199254740992, 0x20000000000000, 12345678901234.5]",
    "tiny-numbers": "[5e-324, 3e-324, 2e-324, 1e-324, 9e-325, 0.5e-323, 1e-400]",
    "huge-numbers": "[1.7976931348623157e308, 1e308, 1e309, 2e308, 0.1e310]",
    "stringify-number-keys": "{1e21: 1, 0.0000001: 2, 0x1F: 3, 1_0: 4, 1.50: 5}",
    "non-ascii-string": '{"a": "héllo"}',
    "cjk-width-80": `{"k": "${"漢".repeat(34)}xx"}`,
    "cjk-width-81": `{"k": "${"漢".repeat(34)}xxx"}`,
    "cjk-width-79": `{"k": "${"漢".repeat(34)}x"}`,
    "latin-width-80": `{"k": "${"é".repeat(69)}"}`,
    "latin-width-81": `{"k": "${"é".repeat(70)}"}`,
    "combining-width": `{"k": "${"e\u0301".repeat(69)}", "j": "${"a\u0300".repeat(70)}"}`,
    "fullwidth-forms": `["${"Ａ".repeat(30)}", "${"Ａ".repeat(40)}"]`,
    "hangul-jamo": `{"k": "${"\u1100".repeat(35)}", "l": "${"한".repeat(40)}"}`,
    "box-drawing": `["${"─".repeat(76)}", "${"─".repeat(78)}"]`,
    "c1-control": '{"k": "a\u0085b"}',
    "line-separator-in-string": '["a\u2028b", "c\u2029d"]',
    "cjk-comment-width": `{\n  // ${"注".repeat(40)}\n  "a": [1, 2, 3]\n}`,
    "cjk-block-comment": `{"a": /* ${"注".repeat(30)} */ [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]}`,
    "nbsp-in-comment": '{"a": 1 /* x\u00a0*/}',
    "nbsp-line-comment-end": '{"a": 1 // x\u00a0\n}',
    "copyright-sign": '{"a": "© 2024"}',
    "emoji-zoo": '["😀", "👍🏽", "👨‍👩‍👧", "🇯🇵", "1️⃣", "©", "©️", "™", "↔", "☺️", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "❤", "❤️", "\ufe0f", "\u200d", "#⃣", "🏽", "🇯", "😀😀", "a👍🏽b", "🇯🇵🇯"]',
    "emoji-width-80": `{"k": "${"😀".repeat(35)}x"}`,
    "emoji-width-81": `{"k": "${"😀".repeat(35)}xx"}`,
    "emoji-zwj-width": `{"k": "${"👨‍👩‍👧".repeat(35)}x", "l": "${"👨‍👩‍👧".repeat(35)}xx"}`,
    "emoji-flags-width": `{"k": "${"🇯🇵".repeat(35)}x", "l": "${"🇯🇵🇯".repeat(23)}"}`,
    "emoji-text-default-width": `{"k": "${"©".repeat(70)}", "l": "${"©".repeat(71)}", "m": "${"↔".repeat(71)}"}`,
    "emoji-in-comment": `{\n  // ${"🎉".repeat(30)}\n  "a": [${"1, ".repeat(25)}1]\n}`,
    "emoji-numbers-fill": `["😀", ${Array.from({ length: 40 }, (_, i) => i * 37).join(", ")}]`,
    "cjk-numbers-fill": `["${"字".repeat(10)}", 1, 2]`,
    "cjk-key": `{"${"键".repeat(20)}": [${Array.from({ length: 20 }, (_, i) => i).join(", ")}]}`,
    "json5-cjk-key": "{'键': 1, 'é': 2}",
    "non-ascii-key": '{"é": 1}',
    "emoji": '["😀"]',
    "surrogate-escapes": '["\\ud83d\\ude00", "\\ud83d", "\\ude00x", "\\u{1F600}"]',
    "nbsp-whitespace": '{"a": 1}',
    "tab-in-string": '{"a": "x\ty"}',
    "del-in-string": '{"a": "x\u007fy"}',
    "hashbang": "#!/usr/bin/env node\n{}",
    "garbage-after": '{"a": 1} x',
    "two-values": "{} {}",
    "unterminated": '{"a": 1',
    "string-newline": '"a\nb"',
  };
}

// Seeded generator of JSON-like documents around the 80-column boundary, with
// comments, blank lines and JSON5 syntax mixed in.
function random(count, { comments }) {
  let seed = comments ? 4242 : 12345;
  const rnd = () => {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed / 0x7fffffff;
  };
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  const comment = () =>
    pick([
      () => "// note",
      () => "/* c */",
      () => "/* two\n   lines */",
      () => "/**\n * doc\n */",
      () => "// prettier-ignore",
      () => "/** @type {x} */",
    ])();
  const ws = () => {
    const base = pick(["", " ", "  ", "\n", "\n  ", " \n", "\n\n"]);
    if (!comments || rnd() > 0.15) return base;
    const c = comment();
    return base + c + (c.startsWith("//") ? "\n" : pick([" ", "\n", ""]));
  };
  const word = () =>
    (comments && rnd() < 0.3 ? "aé漢ŝ字ö한ｚ" : "abcdefghij").slice(0, 1 + Math.floor(rnd() * 10)).repeat(1 + Math.floor(rnd() * 3));
  const asciiWord = () => "abcdefghij".slice(0, 1 + Math.floor(rnd() * 10));
  const key = () =>
    comments
      ? pick([() => `"${word()}"`, () => asciiWord(), () => `'${word()}'`, () => String(Math.floor(rnd() * 100))])()
      : `"${word()}"`;
  const value = (depth) => {
    const r = rnd();
    if (depth > 3 || r < 0.35) {
      return pick([
        () => `"${word()}"`,
        () => String(Math.floor(rnd() * 100000)),
        () => String(-Math.floor(rnd() * 1000)),
        () => "true",
        () => "null",
        () => (rnd() * 1000).toFixed(2),
      ])();
    }
    if (r < 0.5) {
      const n = Math.floor(rnd() * 30);
      const items = Array.from({ length: n }, () => ws() + String(Math.floor(rnd() * 10 ** (1 + Math.floor(rnd() * 5)))) + ws());
      return "[" + items.join(",") + (rnd() < 0.2 ? "," : "") + "]";
    }
    if (r < 0.7) {
      const n = Math.floor(rnd() * 6);
      const items = Array.from({ length: n }, () => ws() + value(depth + 1) + ws());
      return "[" + items.join(",") + "]";
    }
    const n = Math.floor(rnd() * 5);
    const props = Array.from({ length: n }, () => `${ws()}${key()}${ws()}:${ws()}${value(depth + 1)}${ws()}`);
    return "{" + props.join(",") + (comments && n && rnd() < 0.2 ? "," : "") + ws() + "}";
  };
  const out = {};
  const tag = comments ? "random-comments" : "random";
  for (let i = 0; i < count; i++) out[`${tag}-${String(i).padStart(3, "0")}`] = ws() + value(0) + ws();
  return out;
}

export function edgeCases() {
  const cases = [];
  for (const [id, source] of [...Object.entries(fixed()), ...Object.entries(random(150, { comments: false })), ...Object.entries(random(400, { comments: true }))]) {
    for (const [kind, fileName] of names) {
      cases.push({ id: `edge/${id}`, kind: `edge ${kind}`, fileName, source });
    }
  }
  return cases;
}
