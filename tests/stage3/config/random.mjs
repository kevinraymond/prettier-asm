// Randomized trees: config files, package.json, .editorconfig, .git and
// ignore files at random levels, a random file somewhere in the tree, random
// ignore patterns. Seeded, so a run can be repeated.
import { INPUTS } from "./cases.mjs";

function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const r = {
    next,
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    pick: (xs) => xs[Math.floor(next() * xs.length)],
    chance: (p) => next() < p,
    some: (xs, max) => {
      const n = r.int(0, max);
      return Array.from({ length: n }, () => r.pick(xs));
    },
  };
  return r;
}

const DIRS = ["a", "b", "src", "lib", "deep", "x", "node_modules", "Sub"];
const FILES = ["x.json", "a.json", "data.jsonc", "conf.json5", "package.json", "X.JSON", ".babelrc", "b.json", "tsconfig.json"];

function options(r, depth = 0) {
  const o = {};
  if (r.chance(0.4)) o.tabWidth = r.int(1, 8);
  if (r.chance(0.3)) o.printWidth = r.pick([10, 20, 30, 40, 60, 80, 120]);
  if (r.chance(0.3)) o.useTabs = r.chance(0.5);
  if (r.chance(0.2)) o.singleQuote = r.chance(0.5);
  if (r.chance(0.2)) o.bracketSpacing = r.chance(0.5);
  if (r.chance(0.2)) o.quoteProps = r.pick(["as-needed", "consistent", "preserve"]);
  if (r.chance(0.2)) o.trailingComma = r.pick(["all", "es5", "none"]);
  if (r.chance(0.2)) o.objectWrap = r.pick(["preserve", "collapse"]);
  if (r.chance(0.1)) o.semi = r.chance(0.5);
  if (r.chance(0.05)) o.arrowParens = r.pick(["always", "avoid"]);
  if (r.chance(0.05)) o.bracketSameLine = r.chance(0.5);
  if (r.chance(0.05)) o.jsxSingleQuote = r.chance(0.5);
  if (r.chance(0.05)) o.proseWrap = r.pick(["always", "never", "preserve"]);
  if (r.chance(0.05)) o.experimentalTernaries = r.chance(0.5);
  if (r.chance(0.05)) o.experimentalOperatorPosition = r.pick(["start", "end"]);
  if (r.chance(0.05)) o.singleAttributePerLine = r.chance(0.5);
  if (r.chance(0.05)) o.endOfLine = r.pick(["lf", "crlf", "auto"]);
  if (r.chance(0.03)) o.unknownThing = 1;
  if (depth === 0 && r.chance(0.35)) {
    o.overrides = Array.from({ length: r.int(1, 3) }, () => {
      const ov = { files: r.chance(0.3) ? r.some(overrideGlobs, 3) : r.pick(overrideGlobs) };
      if (r.chance(0.3)) ov.excludeFiles = r.chance(0.5) ? r.pick(overrideGlobs) : r.some(overrideGlobs, 2);
      ov.options = options(r, 1);
      return ov;
    });
  }
  return o;
}

const overrideGlobs = ["*.json", "*.jsonc", "x.json", "a/*.json", "a/**/*.json", "**/*.json", "src/**", "*",
  "*.{json,jsonc}", "?.json", "deep/x.json", "**/b/*", "*rc", "package.json", "b/**/x.json", "*.json5", "lib/*"];

function yamlOf(o) {
  const lines = [];
  for (const [k, v] of Object.entries(o)) {
    if (typeof v === "object") return null;
    lines.push(`${k}: ${v}`);
  }
  return lines.join("\n") + "\n";
}

const ecGlobs = ["*", "*.json", "*.{json,jsonc}", "**.json", "{x,a}.json", "a/*.json", "/a/**", "**/b/*", "x.json",
  "*.md", "src/**/*.json", "?.json", "*.json5", "/x.json", "deep/**", "{*.json,*.jsonc}", "package.json"];
const ecProps = {
  indent_style: ["tab", "space", "TAB", "unset", "foo"],
  indent_size: ["2", "4", "tab", "unset", "3"],
  tab_width: ["3", "8", "unset", "4"],
  max_line_length: ["40", "80", "30", "off", "0"],
  quote_type: ["single", "double", "auto"],
  end_of_line: ["lf", "lf", "crlf"],
  charset: ["utf-8"],
};

function editorconfig(r) {
  const lines = [];
  if (r.chance(0.25)) lines.push("root = true");
  if (r.chance(0.2)) lines.push("# comment");
  for (let s = r.int(1, 3); s > 0; s--) {
    lines.push(`[${r.pick(ecGlobs)}]`);
    for (let p = r.int(1, 3); p > 0; p--) {
      const key = r.pick(Object.keys(ecProps));
      lines.push(`${r.chance(0.1) ? key.toUpperCase() : key} = ${r.pick(ecProps[key])}`);
    }
  }
  return lines.join("\n") + "\n";
}

const ignoreAtoms = () => [...DIRS, ...FILES, "*.json", "*", "**", "?.json", "*.js*", "[ax].json", "[a-c]*", "x*"];

function ignorePattern(r, names) {
  const parts = [];
  for (let n = r.int(1, 3); n > 0; n--) parts.push(r.pick([...names, ...ignoreAtoms()]));
  let p = parts.join("/");
  if (r.chance(0.15)) p = "/" + p;
  if (r.chance(0.1)) p = "**/" + p;
  if (r.chance(0.15)) p += "/";
  if (r.chance(0.2)) p = "!" + p;
  if (r.chance(0.05)) p += "  ";
  return p;
}

export function randomCases(n, seed) {
  const r = rng(seed);
  const out = [];
  for (let i = 0; i < n; i++) {
    const tree = {};
    const depth = r.int(0, 3);
    const chain = Array.from({ length: depth }, () => r.pick(DIRS));
    const levels = [""];
    for (let k = 1; k <= depth; k++) levels.push(chain.slice(0, k).join("/"));
    const at = (lv, name) => (lv ? `${lv}/${name}` : name);
    for (const lv of levels) {
      if (lv) tree[lv] = null;
      if (r.chance(0.25)) {
        const o = options(r);
        const y = r.chance(0.4) ? yamlOf(o) : null;
        tree[at(lv, ".prettierrc")] = y ?? JSON.stringify(o, null, r.pick([0, 2]));
      } else if (r.chance(0.1)) {
        tree[at(lv, ".prettierrc.json")] = JSON.stringify(options(r));
      }
      if (r.chance(0.25)) {
        const pkg = { name: "p", version: "1.0.0" };
        if (r.chance(0.3)) pkg.prettier = options(r);
        tree[at(lv, "package.json")] = JSON.stringify(pkg, null, 2);
      }
      if (r.chance(0.25)) tree[at(lv, ".editorconfig")] = editorconfig(r);
      if (r.chance(0.1)) tree[at(lv, ".git")] = null;
    }
    // working directory: the root, a level, or a sibling of the file's directory
    let cwd = r.pick(levels);
    let file = at(levels[levels.length - 1], r.pick(FILES));
    let rel = cwd ? file.slice(cwd.length + 1) : file;
    if (cwd && !file.startsWith(cwd + "/")) rel = file;
    if (r.chance(0.1)) {
      cwd = "other";
      tree.other = null;
      rel = "../" + file;
    }
    const names = [...new Set(file.split("/"))];
    for (const ign of [".prettierignore", ".gitignore"]) {
      if (r.chance(0.35)) {
        const lines = Array.from({ length: r.int(1, 4) }, () => ignorePattern(r, names));
        if (r.chance(0.2)) lines.unshift("# ignore");
        tree[at(cwd, ign)] = lines.join("\n") + "\n";
      }
    }
    const args = [];
    if (r.chance(0.1)) args.push("--tab-width", String(r.int(1, 6)));
    if (r.chance(0.05)) args.push("--use-tabs");
    if (r.chance(0.05)) args.push("--no-editorconfig");
    if (r.chance(0.03)) args.push("--no-config");
    if (r.chance(0.05)) args.push("--print-width", "30");
    out.push({ name: `random-${seed}-${i}`, tree, cwd, file: rel, input: r.pick(INPUTS), args, mode: "stdin" });
  }
  return out;
}
