// node tests/stage3/infra/doc-eval.mjs [binary] [--lists a,b] [--options N] [--limit N]
//
// Checks the binary's doc printer against Prettier's printDocToString:
// harvests docs with prettier.__debug.printToDoc from the corpus case lists,
// adds synthetic-docs.mjs, prints each with several option sets in both, and
// compares. Each doc also goes through the binary's reader and exact dump,
// which must give back the text it was sent.
import fs from "node:fs";
import path from "node:path";
import prettier from "prettier";
import { readCases, run, pool, JOBS, ROOT } from "../../lib.mjs";
import { docToText, optionsText, parseBlocks } from "./doc-text.mjs";
import { flagsToOptions } from "./flags.mjs";
import { syntheticDocs } from "./synthetic-docs.mjs";

const { printDocToString } = prettier.doc.printer;
const argv = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = argv.indexOf(name);
  if (i < 0) return dflt;
  const v = argv[i + 1];
  argv.splice(i, 2);
  return v;
};
const lists = flag("--lists", "js-fixtures,ts-fixtures,real,json,variants").split(",").filter(Boolean);
const optionCount = Number(flag("--options", "4"));
const limit = Number(flag("--limit", "1e9"));
const bin = path.resolve(argv[0] ?? path.join(ROOT, "build/prettier-asm"));
const workDir = path.join(ROOT, "build/stage3-doc-eval");
fs.rmSync(workDir, { recursive: true, force: true });
fs.mkdirSync(workDir, { recursive: true });

// Replaces each __tostr node by its printed string, in text order, as the
// binary does while it reads the doc.
function resolveTostr(doc) {
  const done = new Map();
  const seen = new Set();
  const fix = (d) => {
    if (d && d.type === "__tostr") {
      if (!done.has(d)) {
        const inner = fix(d.contents);
        done.set(d, printDocToString(inner, d.options).formatted);
      }
      return done.get(d);
    }
    if (d && typeof d === "object" && !seen.has(d)) {
      seen.add(d);
      if (Array.isArray(d)) for (let i = 0; i < d.length; i++) d[i] = fix(d[i]);
      else if (d.type === "group" && d.expandedStates) {
        for (let i = 0; i < d.expandedStates.length; i++) d.expandedStates[i] = fix(d.expandedStates[i]);
        d.contents = d.expandedStates[0];
      } else if (d.type === "fill") for (let i = 0; i < d.parts.length; i++) d.parts[i] = fix(d.parts[i]);
      else if (d.type === "if-break") {
        d.breakContents = fix(d.breakContents);
        d.flatContents = fix(d.flatContents);
      } else if ("contents" in d) d.contents = fix(d.contents);
    }
    return d;
  };
  return fix(doc);
}

const extraOptions = [
  { printWidth: 40, tabWidth: 4, useTabs: true, endOfLine: "crlf" },
  { printWidth: 120, tabWidth: 8, useTabs: false, endOfLine: "cr" },
  { printWidth: Number.POSITIVE_INFINITY, tabWidth: 2, useTabs: false, endOfLine: "lf" },
  { printWidth: 20, tabWidth: 3, useTabs: true, endOfLine: "lf" },
  { printWidth: 0, tabWidth: 1, useTabs: false, endOfLine: "lf" },
];

const entries = [];
const skipped = new Map();
const skip = (why) => skipped.set(why, (skipped.get(why) ?? 0) + 1);

function addEntry(name, doc, optionsList) {
  let text;
  try {
    text = docToText(doc, { exact: true });
  } catch (e) {
    return skip("not expressible: " + e.message.slice(0, 60));
  }
  doc = resolveTostr(doc);
  const roundTrip = docToText(doc, { exact: true });
  const prints = [];
  for (const o of optionsList) {
    try {
      prints.push({ o, expected: printDocToString(doc, o).formatted });
    } catch (e) {
      skip("prettier throws: " + e.message.slice(0, 60));
    }
  }
  if (prints.length) entries.push({ name, text, roundTrip, prints });
}

for (const s of syntheticDocs()) addEntry("synthetic:" + s.name, s.doc, s.options);
const syntheticCount = entries.length;

let harvested = 0;
for (const list of lists) {
  for (const c of readCases(list)) {
    if (harvested >= limit) break;
    let opts, doc;
    try {
      opts = flagsToOptions(c.args);
      doc = await prettier.__debug.printToDoc(c.stdin, opts);
    } catch {
      skip("printToDoc fails");
      continue;
    }
    harvested++;
    const own = { printWidth: opts.printWidth ?? 80, tabWidth: opts.tabWidth ?? 2, useTabs: opts.useTabs ?? false, endOfLine: "lf" };
    addEntry(`${list}:${c.name}`, doc, [own, ...extraOptions.slice(0, optionCount - 1)]);
  }
}

function commandsFor(e) {
  return `(doc ${e.text})\n(dumpx)\n` + e.prints.map((p) => `(print ${optionsText(p.o)})\n`).join("");
}

// chunks of about 200 KB of input
const chunks = [];
let cur = [], size = 0;
for (const e of entries) {
  cur.push(e);
  size += e.text.length;
  if (size > 200_000 || cur.length >= 40) {
    chunks.push(cur);
    cur = [];
    size = 0;
  }
}
if (cur.length) chunks.push(cur);

const result = { prints: 0, identical: 0, different: 0, refused: 0, roundTripBad: 0 };
const refusals = new Map();
const diffs = [];

function check(e, blocks) {
  if (blocks[0] !== e.roundTrip) {
    result.roundTripBad++;
    let i = 0;
    while (blocks[0][i] === e.roundTrip[i]) i++;
    diffs.push(`${e.name}: round trip differs at ${i}\n  sent: ${e.roundTrip.slice(i - 40, i + 60)}\n  got:  ${blocks[0].slice(i - 40, i + 60)}`);
  }
  e.prints.forEach((p, k) => {
    result.prints++;
    const got = blocks[k + 1];
    if (got === p.expected) result.identical++;
    else {
      result.different++;
      let i = 0;
      while (got[i] === p.expected[i]) i++;
      diffs.push(`${e.name} ${optionsText(p.o)}: differs at ${i}\n  prettier: ${JSON.stringify(p.expected.slice(Math.max(0, i - 40), i + 40))}\n  binary:   ${JSON.stringify(got?.slice(Math.max(0, i - 40), i + 40))}`);
    }
  });
}

async function runEntries(list, file) {
  fs.writeFileSync(file, list.map(commandsFor).join(""));
  return run(bin, ["--debug-doc-eval", file], { timeout: 300_000 });
}

await pool(chunks, JOBS, async (chunk, ci) => {
  const r = await runEntries(chunk, path.join(workDir, `chunk${ci}.txt`));
  if (r.status === 0) {
    const blocks = parseBlocks(r.stdout);
    let at = 0;
    for (const e of chunk) {
      check(e, blocks.slice(at, at + 1 + e.prints.length));
      at += 1 + e.prints.length;
    }
    return;
  }
  // find the entries the binary refuses
  for (const [k, e] of chunk.entries()) {
    const r1 = await runEntries([e], path.join(workDir, `chunk${ci}-${k}.txt`));
    if (r1.status === 0) check(e, parseBlocks(r1.stdout));
    else {
      result.refused += e.prints.length;
      const why = r1.stderr.toString().trim() || `exit ${r1.status} ${r1.signal ?? ""}`;
      refusals.set(why, (refusals.get(why) ?? 0) + 1);
    }
  }
});

for (const d of diffs.slice(0, 12)) console.log(d);
for (const [why, n] of skipped) console.log(`skipped ${n}: ${why}`);
for (const [why, n] of refusals) console.log(`refused ${n} docs: ${why}`);
console.log(`doc-eval: ${entries.length} docs (${syntheticCount} synthetic, ${entries.length - syntheticCount} harvested), ` +
  `${result.prints} prints: ${result.identical} identical, ${result.different} DIFFERENT, ${result.refused} refused; ` +
  `${result.roundTripBad} round-trip differences`);
process.exit(result.different || result.roundTripBad || result.refused ? 1 : 0);
