// Hand-made docs for the printer paths real code rarely reaches. Each entry:
// { name, doc, options: [printDocToString options...] }. A `__tostr` node
// stands for printDocToString(contents, options).formatted, computed while
// the doc is read (as printTemplateLiteral does while it builds its doc).
const L = { type: "line" };
const SL = { type: "line", soft: true };
const HLnb = { type: "line", hard: true };
const LLnb = { type: "line", hard: true, literal: true };
const BP = { type: "break-parent" };
const HL = [HLnb, BP];
const LL = [LLnb, BP];
const TRIM = { type: "trim" };
const LSB = { type: "line-suffix-boundary" };
const g = (contents, extra = {}) => ({ type: "group", contents, break: false, ...extra });
const cg = (states, extra = {}) => ({ type: "group", contents: states[0], break: false, expandedStates: states, ...extra });
const ind = (c) => ({ type: "indent", contents: c });
const al = (n, c) => ({ type: "align", contents: c, n });
const fill = (parts) => ({ type: "fill", parts });
const ib = (b, f = "", groupId) => ({ type: "if-break", breakContents: b, flatContents: f, groupId });
const iib = (c, groupId, negate) => ({ type: "indent-if-break", contents: c, groupId, negate });
const ls = (c) => ({ type: "line-suffix", contents: c });
const label = (l, c) => ({ type: "label", label: l, contents: c });
const tostr = (contents, options) => ({ type: "__tostr", contents, options });
const words = (s) => s.split(" ").flatMap((w, i) => (i ? [L, w] : [w]));
const call = (name, args) =>
  g([name, "(", ind([SL, ...args.flatMap((a, i) => (i ? [",", L, a] : [a]))]), ib(","), SL, ")"]);

const base = { printWidth: 80, tabWidth: 2, useTabs: false, endOfLine: "lf" };
const grid = [];
for (const printWidth of [0, 1, 5, 10, 20, 40, 80])
  for (const useTabs of [false, true])
    for (const tabWidth of [1, 2, 4, 8]) grid.push({ ...base, printWidth, useTabs, tabWidth });
const small = [base, { ...base, printWidth: 10 }, { ...base, printWidth: 3, useTabs: true, tabWidth: 4 },
  { ...base, endOfLine: "crlf" }, { ...base, printWidth: Number.POSITIVE_INFINITY }];

export function syntheticDocs() {
  const docs = [];
  const add = (name, doc, options = small) => docs.push({ name, doc, options });

  add("hardline-trailing-space", ["   ", HL, "Prettier", HL]);
  add("call", [call("someFunction", ["argumentNumberOne", "argumentNumberTwo", call("inner", ["x", "yy", "zzz"])]), ";", HL], grid);
  add("fill-words", fill(words("the quick brown fox jumps over the lazy dog and keeps running far away")), grid);
  add("align-mix", ind([HL, al(4, [HL, "four", al(2, [HL, "six", ind([HL, "x"])])]), HL, al("> ", [HL, "quoted", HL, "more"])]), grid);
  add("align-dedent-root", ind([HL, "a", al(-1, [HL, "dedented"]), al(Number.NEGATIVE_INFINITY, [HL, "root"]),
    al({ type: "root" }, ind([HL, "marked", al(Number.NEGATIVE_INFINITY, [HL, "toRoot"]), LL, "lit"]))]), grid);
  add("align-tabs", ind([al(3, ind([al(2, [HL, "a", al("--", [HL, "b", ind([HL, "c"])]), ind(al(1, [HL, "d"]))])]))]), grid);
  add("align-zero-empty", ind([al(0, [HL, "zero"]), al("", [HL, "empty"]), al(-3, [HL, "neg"])]), grid);
  add("dedent-twice", ind(ind(al(2, al(-1, al(-1, [HL, "x", al(-1, [HL, "y"])]))))), grid);
  add("root-dedent", ind(al({ type: "root" }, ind(al(-1, [HL, "a", LL, "b"])))), grid);
  add("string-align-nonascii", ind(al("é😀 ", [HL, "x", ind([HL, "y"])])), grid);
  for (const endOfLine of ["lf", "crlf", "cr"])
    add("eol-" + endOfLine, ["a\nb", HL, "c", ind([HL, "d\ne"]), LL, "f", g(["x", L, "y\nz"])], [{ ...base, endOfLine }, { ...base, endOfLine, printWidth: 3 }]);
  add("ifbreak-groupid", (() => {
    const id = Symbol("g1");
    return g(["const x = ", g(["[", ind([SL, "1", ",", L, "2"]), SL, "]"], { id }), ib(" // broken", " // flat", id)]);
  })(), grid);
  add("iib-negate", (() => {
    const id = Symbol("g1");
    return g(["const x = ", g(["[", ind([SL, "1", ",", L, "2", BP]), SL, "]"], { id }), ib(" // broken", " // flat", id),
      iib([HL, "y"], id), iib([HL, "z"], id, true)]);
  })(), grid);
  add("iib-unknown-id", g(["x", iib([L, "y"], Symbol("nope"))]));
  add("ifbreak-unknown-id", g(["x", ib("B", "F", Symbol("nope")), L, "y"]));
  add("iib-self", (() => {
    const id = Symbol("g9");
    return g(["x", iib([L, "y"], id, true)], { id });
  })(), grid);
  add("iib-self-hard", (() => {
    const id = Symbol("g9");
    return g(["x", iib([HL, "y"], id, true), iib([HL, "z"], id)], { id });
  })(), [{ ...base, printWidth: 1 }, base]);
  add("ifbreak-later-group", (() => {
    const id = Symbol("later");
    return [g(["a", ib("B", "F", id), L, "b"]), g(["c", L, "d"], { id })];
  })(), grid);
  add("line-suffix", ["a", ls(" // comment"), "b", HL, "c", ls(" // end")]);
  add("line-suffix-boundary", g(["a", ls(" // c"), LSB, L, "b"]));
  add("lsb-alone", ["x", LSB, "y"]);
  add("line-suffix-in-group", g([g(["a", ls(" // 1"), L, "b"]), L, ls(" // 2"), "c", LSB, "d"]), grid);
  add("line-suffix-end", g(["a", ls([" //", HL, "x"])]));
  add("line-suffix-nested", ["a", ls(["b", ls("c")]), HL, "d"]);
  add("label", label({ memberChain: true }, g(["a", SL, ".b()"])));
  const states = [["f(", "a", ")"], ["f(", ind([SL, "a"]), SL, ")"], ["f(", ind([HL, "averyveryverylongargument"]), HL, ")"]];
  for (const w of [3, 6, 30]) {
    const o = [{ ...base, printWidth: w }];
    add("cgroup-" + w, cg(states), o);
    add("cgroup-break-" + w, cg(states, { break: true }), o);
    add("cgroup-two-" + w, cg([states[0], states[1]]), o);
    add("cgroup-nested-" + w, g(["x(", cg([[cg(states), "y"], [ind([HL, cg(states)]), "y"]]), ")"]), o);
    add("cgroup-in-flat-" + w, g([g(["start", L, cg(states)]), HL, "z"]), o);
  }
  add("cgroup-hard-state", g(["(", cg([["a", HL, "b"], ["c", L, "d"]]), ")"]), grid);
  for (const s of ["😀 emoji", "👨‍👩‍👧 family", "日本語テキスト", "é́", "a\u0000b\u007f\u0085", "🇹🇷 flag", "1️⃣ keycap", "©️ ©", "한국어", "ｆｕｌｌ", "‍​"]) {
    for (const w of [8, 12]) add("width-" + s, g(["start ", ind([SL, s, L, s]), SL, "end"]), [{ ...base, printWidth: w }]);
    add("fill-width-" + s, fill([s, L, s, L, s, L, s]), [{ ...base, printWidth: 10 }]);
  }
  add("fill-empty", fill([]));
  add("fill-one", fill(["only"]), [{ ...base, printWidth: 2 }]);
  add("fill-two", fill(["a", L]), [{ ...base, printWidth: 0 }, base]);
  add("fill-group", fill([g(["x", HL, "y"]), L, "z"]));
  add("fill-break-content", fill(["aaaa", L, g(["b", L, "c"], { break: true }), L, "dddd", L, "e"]), grid);
  add("fill-softline", fill(["aaaa", SL, "bbbb", SL, "cccc", SL, "dddd"]), grid);
  add("fill-line-suffix", fill(["a", L, ls(" // x"), L, "b", L, LSB, L, "c"]), grid);
  add("fill-in-group", g(["[", ind([SL, fill(words("1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16"))]), SL, "]"]), grid);
  add("fill-hard", fill(["a", HL, "b", L, "c"]));
  add("trim", ["trailing   ", TRIM, "x  \t", TRIM, HL]);
  add("trim-in-fits", g(["a  ", TRIM, "b", L, "c"]), [{ ...base, printWidth: 5 }, { ...base, printWidth: 4 }, base]);
  add("trim-in-fits-all", g(["a", L, "   ", "\t", TRIM, "b", L, "c"]), [{ ...base, printWidth: 5 }, { ...base, printWidth: 6 }]);
  add("trim-in-fits-rest", [g(["aaaa", L, "b"]), "   ", TRIM, "cc"], [{ ...base, printWidth: 6 }, { ...base, printWidth: 7 }]);
  add("trim-across", ind(["x", HL, "  ", "   ", TRIM, "y"]));
  add("trim-to-start", ["   ", TRIM, "x"]);
  add("trim-after-indent", ind([HL, TRIM, "x"]));
  add("group-hard-inside", g([g(["a", HL, "b"]), L, "c"]));
  add("group-break-inner", g(["a", L, g(["b", L, "c"], { break: true })]));
  add("ifbreak-breakparent", g(["a", ib(g(["x", BP]), "y"), L, "b"]));
  add("fits-boundary", g(["fits", L, "rest"]), [{ ...base, printWidth: 7 }, { ...base, printWidth: 8 }, { ...base, printWidth: 9 }]);
  add("nested-arrays", ["", [], [[["deep"]]], ""]);
  add("infinite", g(["a", L, "b"]), [{ ...base, printWidth: Number.POSITIVE_INFINITY }]);
  add("remeasure", g([g(["aaaa", L, "bbbb"]), HL, g(["cccc", L, "dddd"])]), [{ ...base, printWidth: 9 }]);
  add("root-literal", ind(["a", al({ type: "root" }, ind([HL, "b", LL, "literal", al(2, [LL, "x"])]))]));
  add("literal-no-root", ind(["a", LL, "noRoot"]));
  add("propagated-shared", (() => {
    const shared = g(["s", HL, "t"]);
    return [g(["a", L, shared]), g(["b", L, shared]), cg([["c", shared], ["d"]])];
  })());
  add("tostr", (() => {
    const inner = g(["inner(", ind([SL, "aaaa", ",", L, "bbbb"]), SL, ")"]);
    return g(["`${", tostr(inner, { ...base, printWidth: Number.POSITIVE_INFINITY }), "}` ", L, inner]);
  })(), [{ ...base, printWidth: 10 }, base]);
  add("tostr-shared-id", (() => {
    const id = Symbol("shared");
    const inner = g(["x", L, "y", ib("!", "?", id)], { id });
    return [tostr([inner, HL, "z"], { ...base, printWidth: 2, endOfLine: "crlf" }), HL, inner, ib("B", "F", id)];
  })(), [{ ...base, printWidth: 2 }, base]);
  add("tostr-nested", tostr(["a", tostr(g(["b", L, "c"]), { ...base, printWidth: 1 }), L, "d"], { ...base, printWidth: Number.POSITIVE_INFINITY }));
  return docs;
}
