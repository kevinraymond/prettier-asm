// Writes RESULTS.md and results/charts/*.svg from results/data/*.json, and nothing else.
// The same data gives byte-identical output. A missing, stale or edited data file stops it
// before anything is written.
//
//   node bench/report.mjs [--data dir] [--out file] [--charts dir] [--gif]
//
// --gif also renders results/charts/headline.gif (and headline.png, its last frame) from
// headline.svg with headless Chromium and ffmpeg, and shrinks it with ImageMagick when that is
// installed. The GIF differs from run to run, so it is made only on request.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const flag = (n) => { const i = argv.indexOf(n); if (i < 0) return false; argv.splice(i, 1); return true; };
const opt = (n, d) => { const i = argv.indexOf(n); return i < 0 ? d : argv.splice(i, 2)[1]; };
const DATA = path.resolve(opt("--data", path.join(ROOT, "results/data")));
const OUT_MD = path.resolve(opt("--out", path.join(ROOT, "RESULTS.md")));
const CHARTS = path.resolve(opt("--charts", path.join(ROOT, "results/charts")));
const wantGif = flag("--gif");
if (argv.length) { console.error("usage: node bench/report.mjs [--data dir] [--out file] [--charts dir] [--gif]"); process.exit(2); }

// ---- load and verify
const SCHEMA = 1;
const FILES = ["environment.json", "binary.json", "correctness.json", "sweep.json", "mutants.json", "performance.json", "resources.json", "hyperfine.json", "upstream.json"];
function fail(msg) { console.error(`report: ${msg}\nreport: nothing written. Run node bench/record.mjs to record a complete set.`); process.exit(1); }
function loadAll() {
  const runFile = path.join(DATA, "run.json");
  if (!fs.existsSync(runFile)) fail(`${path.relative(ROOT, runFile)} is missing`);
  const run = JSON.parse(fs.readFileSync(runFile, "utf8"));
  if (run.schema !== SCHEMA) fail(`run.json has schema ${run.schema}, this report reads ${SCHEMA}`);
  const d = { run };
  for (const f of FILES) {
    const p = path.join(DATA, f);
    if (!fs.existsSync(p)) fail(`${f} is missing from ${path.relative(ROOT, DATA)}`);
    const text = fs.readFileSync(p, "utf8");
    let j;
    try { j = JSON.parse(text); } catch (e) { fail(`${f} is not valid JSON: ${e.message}`); }
    if (j.schema !== SCHEMA) fail(`${f} has schema ${j.schema}, want ${SCHEMA}`);
    if (j.run_id !== run.run_id) fail(`${f} is from run ${j.run_id}, run.json is from ${run.run_id} (stale file)`);
    const h = crypto.createHash("sha256").update(text).digest("hex");
    if (run.files?.[f] !== h) fail(`${f} does not match the checksum run.json recorded for it (edited after the run?)`);
    d[f.replace(/\.json$/, "")] = j;
  }
  return d;
}
const D = loadAll();
const { run, environment: env, binary, correctness, sweep, mutants, performance: perf, resources, hyperfine, upstream } = D;

// ---- numbers
const sum = (a) => a.reduce((x, y) => x + y, 0);
const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const stats = (a) => {
  const mean = sum(a) / a.length;
  const sd = a.length > 1 ? Math.sqrt(sum(a.map((x) => (x - mean) ** 2)) / (a.length - 1)) : 0;
  return { min: Math.min(...a), median: median(a), mean, max: Math.max(...a), stddev: sd, n: a.length };
};
const group = (s) => { const [i, f] = s.split("."); return i.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (f !== undefined ? "." + f : ""); };
const fix = (x, d) => group(x.toFixed(d));
const ms = (x) => (x >= 1000 ? fix(x, 0) : x >= 100 ? fix(x, 1) : x >= 10 ? fix(x, 1) : fix(x, 2)) + " ms";
const ms2 = (x) => fix(x, 2);
const ratio = (x) => (x >= 10 ? x.toFixed(1) : x.toFixed(2)) + "×";
const pct = (n, d) => (d ? ((100 * n) / d).toFixed(1) + "%" : "n/a");
const mib = (b) => (b / 1048576 >= 10 ? (b / 1048576).toFixed(1) : (b / 1048576).toFixed(2)) + " MiB";
const secs = (x) => (x >= 1000 ? (x / 1000).toFixed(2) : (x / 1000).toFixed(3)) + " s";
const mdEsc = (s) => String(s).replace(/[\\`*_[\]<>|]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "|": "\\|" })[c] ?? "\\" + c);

const NAMES = { prettier: "Prettier 3.6.2 (Node)", rust: "Rust port", asm: "asm" };
const MAIN = ["prettier", "rust", "asm"];
const K = Object.fromEntries(perf.contenders.map((k) => [k.name, k]));
const T = Object.fromEntries(perf.contenders.map((k) => [k.name, stats(k.rep_totals_ms)]));
const files = perf.files.map((f) => ({ ...f, med: Object.fromEntries(Object.entries(f.rep_ms).map(([k, v]) => [k, median(v)])) }));
const fileMedian = (k) => median(files.map((f) => f.med[k]));
// Speedup of b over a: ratio of median rep totals; the range is the min and max of per-rep ratios (reps are paired: same pass).
const speedup = (slow, fast) => {
  const r = K[slow].rep_totals_ms.map((x, i) => x / K[fast].rep_totals_ms[i]);
  return { median_ratio: T[slow].median / T[fast].median, min: Math.min(...r), max: Math.max(...r) };
};
const sp = (slow, fast) => { const s = speedup(slow, fast); return `${ratio(s.median_ratio)} (${ratio(s.min)} to ${ratio(s.max)})`; };
const exts = [...new Set(files.map((f) => f.ext))].sort();
const extTotals = Object.fromEntries(exts.map((e) => [e, Object.fromEntries(perf.contenders.map((k) => {
  const idx = files.map((f, i) => (f.ext === e ? i : -1)).filter((i) => i >= 0);
  return [k.name, stats(k.rep_totals_ms.map((_, r) => sum(idx.map((i) => files[i].rep_ms[k.name][r]))))];
}))]));
const nFiles = files.length;
const realCounts = correctness.lists.real.counts;

// ---- SVG scaffolding
const xml = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const r1 = (x) => Math.round(x * 10) / 10;
const LIGHT = { surface: "#fcfcfb", ink: "#0b0b0b", ink2: "#52514e", muted: "#898781", grid: "#e1e0d9", axis: "#c3c2b7",
  prettier: "#1baf7a", rust: "#eb6834", asm: "#2a78d6", floor: "#c3c2b7", good: "#0ca30c", warning: "#fab219", neutral: "#898781", critical: "#d03b3b" };
const DARK = { surface: "#1a1a19", ink: "#f0efec", ink2: "#c3c2b7", muted: "#898781", grid: "#2c2c2a", axis: "#383835",
  prettier: "#199e70", rust: "#d95926", asm: "#3987e5", floor: "#52514e", good: "#0ca30c", warning: "#fab219", neutral: "#6d6c67", critical: "#d03b3b" };
const vars = (p) => Object.entries(p).map(([k, v]) => `--${k}:${v}`).join(";");
const SANS = `system-ui,-apple-system,"Segoe UI",Roboto,sans-serif`;
const MONO = `ui-monospace,SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace`;
function svgDoc(id, w, h, title, desc, body, extraCss = "", palette = { light: LIGHT, dark: DARK }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" class="c" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-labelledby="${id}-t ${id}-d">
<title id="${id}-t">${xml(title)}</title>
<desc id="${id}-d">${xml(desc)}</desc>
<style>
.c{${vars(palette.light)}}
@media (prefers-color-scheme:dark){.c{${vars(palette.dark)}}}
.c text{font-family:${SANS};fill:var(--ink);font-size:12px}
.c .t2{fill:var(--ink2)}.c .mu{fill:var(--muted)}.c .h{font-size:15px;font-weight:600}
.c .num{font-variant-numeric:tabular-nums}
.c .bg{fill:var(--surface)}.c .grid{stroke:var(--grid);stroke-width:1}.c .axis{stroke:var(--axis);stroke-width:1}
${extraCss}</style>
<rect class="bg" width="${w}" height="${h}" rx="8"/>
${body}</svg>
`;
}
// A bar with a 4px rounded data end and a square baseline end (horizontal: baseline on the left).
const hbar = (x, y, w, h, cls, tip, extra = "") => {
  const rr = Math.min(4, w / 2, h / 2);
  if (w <= 0) return "";
  return `<path class="${cls}"${extra} d="M${r1(x)} ${r1(y)}h${r1(w - rr)}a${rr} ${rr} 0 0 1 ${rr} ${rr}v${r1(h - 2 * rr)}a${rr} ${rr} 0 0 1 ${-rr} ${rr}h${r1(-(w - rr))}z"><title>${xml(tip)}</title></path>`;
};
const vbar = (x, yBase, w, h, cls, tip, rounded = true) => {
  if (h <= 0) return "";
  const rr = rounded ? Math.min(4, w / 2, h) : 0;
  return `<path class="${cls}" d="M${r1(x)} ${r1(yBase)}v${r1(-(h - rr))}a${rr} ${rr} 0 0 1 ${rr} ${-rr}h${r1(w - 2 * rr)}a${rr} ${rr} 0 0 1 ${rr} ${rr}v${r1(h - rr)}z"><title>${xml(tip)}</title></path>`;
};
function niceTicks(max, n = 5) {
  const raw = max / n, mag = 10 ** Math.floor(Math.log10(raw)), step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= raw);
  const t = [];
  for (let v = 0; v <= max + step * 1e-9; v += step) t.push(Number(v.toPrecision(12)));
  if (t.at(-1) < max) t.push(Number((t.at(-1) + step).toPrecision(12)));
  return t;
}
const tickLabel = (v) => (Math.abs(v) >= 1000 ? group(String(Math.round(v))) : String(Number(v.toPrecision(6))));
const legend = (x, y, items) => {
  let out = "", cx = x;
  for (const [cls, label, shape] of items) {
    out += shape === "dot" ? `<circle class="${cls}" cx="${cx + 5}" cy="${y - 4}" r="4"/>` : `<rect class="${cls}" x="${cx}" y="${y - 9}" width="10" height="10" rx="2"/>`;
    out += `<text class="t2" x="${cx + 15}" y="${y}">${xml(label)}</text>`;
    cx += 15 + label.length * 6.3 + 20;
  }
  return out;
};
const seriesCss = MAIN.map((k) => `.c .s-${k}{fill:var(--${k})}`).join("") + ".c .s-floor{fill:var(--floor)}" +
  ".c .dot{stroke:var(--surface);stroke-width:2}";

// (a) total time
function chartTotal() {
  const W = 760, H = 210, L = 170, R = 110, top = 56, row = 40, bh = 20;
  const max = Math.max(...MAIN.map((k) => T[k].median));
  const ticks = niceTicks(max / 1000, 5).map((s) => s * 1000), xmax = ticks.at(-1), sx = (v) => L + (v / xmax) * (W - L - R);
  let b = `<text class="h" x="16" y="26">Total time for the ${nFiles} real files, median of ${perf.reps} reps</text>`;
  b += `<text class="t2" x="16" y="44">One process per file. Linear scale, seconds.</text>`;
  const axisY = top + MAIN.length * row + 4;
  for (const t of ticks) b += `<line class="grid" x1="${r1(sx(t))}" y1="${top - 6}" x2="${r1(sx(t))}" y2="${axisY}"/><text class="mu num" x="${r1(sx(t))}" y="${axisY + 16}" text-anchor="middle">${tickLabel(t / 1000)}</text>`;
  MAIN.forEach((k, i) => {
    const y = top + i * row, w = Math.max(3, sx(T[k].median) - L);
    b += `<text x="${L - 10}" y="${y + bh / 2 + 4}" text-anchor="end">${xml(NAMES[k])}</text>`;
    b += hbar(L, y, w, bh, `s-${k}`, `${NAMES[k]}: median ${secs(T[k].median)}, min ${secs(T[k].min)}, max ${secs(T[k].max)}`);
    b += `<text class="num" x="${r1(L + w + 8)}" y="${y + bh / 2 + 4}">${secs(T[k].median)}</text>`;
  });
  b += `<line class="axis" x1="${L}" y1="${top - 6}" x2="${L}" y2="${axisY}"/>`;
  return svgDoc("total", W, H, "Total time for the 59 real files", `Median total over ${perf.reps} reps: ` + MAIN.map((k) => `${NAMES[k]} ${secs(T[k].median)}`).join(", ") + ".", b, seriesCss);
}

// (b) per-file time, sorted by Prettier, log y
function chartPerFile() {
  const W = 760, H = 380, L = 56, R = 16, top = 84, bottom = 330;
  const order = [...files].sort((a, b) => a.med.prettier - b.med.prettier || (a.name < b.name ? -1 : 1));
  const all = order.flatMap((f) => MAIN.map((k) => f.med[k]));
  const steps125 = (v, up) => { const e = 10 ** Math.floor(Math.log10(v)), c = [1, 2, 5, 10].map((m) => m * e); return up ? c.find((x) => x >= v) : [...c].reverse().find((x) => x <= v); };
  const lo = steps125(Math.min(...all), false), hi = steps125(Math.max(...all), true);
  const sy = (v) => bottom - ((Math.log10(v) - Math.log10(lo)) / (Math.log10(hi) - Math.log10(lo))) * (bottom - top);
  const step = (W - L - R) / order.length, sx = (i) => L + step * (i + 0.5);
  let b = `<text class="h" x="16" y="26">Time per file, median of ${perf.reps} reps</text>`;
  b += legend(16, 50, MAIN.map((k) => [`s-${k}`, NAMES[k], "dot"]));
  for (let e = Math.floor(Math.log10(lo)); e <= Math.ceil(Math.log10(hi)); e++) for (const m of [1, 2, 5]) {
    const v = Number((m * 10 ** e).toPrecision(6));
    if (v < lo * 0.999 || v > hi * 1.001) continue;
    b += `<line class="grid" x1="${L}" y1="${r1(sy(v))}" x2="${W - R}" y2="${r1(sy(v))}"/><text class="mu num" x="${L - 6}" y="${r1(sy(v) + 4)}" text-anchor="end">${tickLabel(v)}</text>`;
  }
  b += `<text class="mu" x="16" y="${top - 14}">ms, log scale</text>`;
  b += `<line class="axis" x1="${L}" y1="${bottom}" x2="${W - R}" y2="${bottom}"/>`;
  b += `<text class="mu" x="${L}" y="${bottom + 18}">${nFiles} files, sorted by Prettier's time; fastest left</text>`;
  order.forEach((f, i) => {
    for (const k of MAIN) b += `<circle class="dot s-${k}" cx="${r1(sx(i))}" cy="${r1(sy(f.med[k]))}" r="4"><title>${xml(`${f.path}: ${NAMES[k]} ${ms2(f.med[k])} ms`)}</title></circle>`;
  });
  return svgDoc("perfile", W, H, "Time per file for the three contenders", `Each of the ${nFiles} files, sorted by Prettier's time, on a log scale. Per-file medians: ` + MAIN.map((k) => `${NAMES[k]} ${ms(fileMedian(k))}`).join(", ") + ". The per-file table in RESULTS.md has every value.", b, seriesCss);
}

// (c) time against input size, rust and asm
function chartSize() {
  const W = 760, H = 380, L = 56, R = 24, top = 84, bottom = 320;
  const ks = ["rust", "asm"];
  const xmax = niceTicks(Math.max(...files.map((f) => f.input_bytes)) / 1024, 6).at(-1) * 1024;
  const yt = niceTicks(Math.max(...files.flatMap((f) => ks.map((k) => f.med[k]))), 5), ymax = yt.at(-1);
  const sx = (v) => L + (v / xmax) * (W - L - R), sy = (v) => bottom - (v / ymax) * (bottom - top);
  let b = `<text class="h" x="16" y="26">Time against input size, median of ${perf.reps} reps</text>`;
  b += legend(16, 50, ks.map((k) => [`s-${k}`, NAMES[k], "dot"]));
  for (const t of yt) b += `<line class="grid" x1="${L}" y1="${r1(sy(t))}" x2="${W - R}" y2="${r1(sy(t))}"/><text class="mu num" x="${L - 6}" y="${r1(sy(t) + 4)}" text-anchor="end">${tickLabel(t)}</text>`;
  for (const t of niceTicks(xmax / 1024, 6)) b += `<text class="mu num" x="${r1(sx(t * 1024))}" y="${bottom + 18}" text-anchor="middle">${tickLabel(t)}</text>`;
  b += `<text class="mu" x="16" y="${top - 14}">ms</text><text class="mu" x="${W - R}" y="${bottom + 36}" text-anchor="end">input size, KiB</text>`;
  b += `<line class="axis" x1="${L}" y1="${bottom}" x2="${W - R}" y2="${bottom}"/>`;
  for (const k of ks) for (const f of files) b += `<circle class="dot s-${k}" cx="${r1(sx(f.input_bytes))}" cy="${r1(sy(f.med[k]))}" r="4"><title>${xml(`${f.path} (${group(String(f.input_bytes))} bytes): ${NAMES[k]} ${ms2(f.med[k])} ms`)}</title></circle>`;
  return svgDoc("size", W, H, "Time against input size", `Per-file median time against input bytes for the Rust port and asm. The per-file table in RESULTS.md has every value.`, b, seriesCss);
}

// (d) asm per file: process floor and work above it
function chartFloor() {
  const W = 760, H = 390, L = 56, R = 16, top = 98, bottom = 330;
  const order = [...files].sort((a, b) => a.input_bytes - b.input_bytes || (a.name < b.name ? -1 : 1));
  const yt = niceTicks(Math.max(...order.map((f) => f.med.asm)), 5), ymax = yt.at(-1);
  const sy = (v) => (v / ymax) * (bottom - top), step = (W - L - R) / order.length, bw = Math.min(24, step - 2);
  const floorT = T.floor_static.median, asmT = T.asm.median;
  let negative = 0;
  let b = `<text class="h" x="16" y="26">asm time per file: process floor and work above it</text>`;
  b += `<text class="t2" x="16" y="44">Totals: asm ${secs(asmT)}, floor ${secs(floorT)} (${pct(floorT, asmT)} of asm). Files sorted by size.</text>`;
  b += legend(16, 68, [["s-floor", "process floor: exit(0), static", "rect"], ["s-asm", "asm above the floor", "rect"]]);
  for (const t of yt) b += `<line class="grid" x1="${L}" y1="${r1(bottom - sy(t))}" x2="${W - R}" y2="${r1(bottom - sy(t))}"/><text class="mu num" x="${L - 6}" y="${r1(bottom - sy(t) + 4)}" text-anchor="end">${tickLabel(t)}</text>`;
  b += `<text class="mu" x="16" y="${top - 14}">ms</text>`;
  order.forEach((f, i) => {
    const x = L + step * i + (step - bw) / 2, fl = Math.min(f.med.floor_static, f.med.asm), work = f.med.asm - f.med.floor_static;
    if (work < 0) negative++;
    const tip = `${f.path} (${group(String(f.input_bytes))} bytes): asm ${ms2(f.med.asm)} ms, floor ${ms2(f.med.floor_static)} ms`;
    const hf = sy(fl), hw = Math.max(0, sy(work));
    b += vbar(x, bottom, bw, hw > 2 ? hf : hf, "s-floor", tip, hw <= 2);
    if (hw > 2) b += vbar(x, bottom - hf - 2, bw, hw - 2, "s-asm", tip);
  });
  b += `<line class="axis" x1="${L}" y1="${bottom}" x2="${W - R}" y2="${bottom}"/>`;
  b += `<text class="mu" x="${L}" y="${bottom + 18}">${nFiles} files, smallest left${negative ? `; ${negative} files where asm's median is below the floor's draw the floor only` : ""}</text>`;
  return svgDoc("floor", W, H, "asm time per file split into process floor and work", `Per-file median of asm and of a static exit(0) binary started the same way. asm total ${secs(asmT)}, floor ${secs(floorT)}.`, b, seriesCss);
}

// (e) coverage per list
const CLASSES = [["identical", "identical", "s-good"], ["refused", "refused", "s-warning"], ["oracle_error", "Prettier errors too", "s-neutral"], ["different", "DIFFERENT", "s-critical"]];
function chartCoverage() {
  const lists = Object.keys(correctness.lists);
  const W = 760, L = 110, R = 16, top = 80, row = 38, bh = 24, H = top + lists.length * row + 30;
  let b = `<text class="h" x="16" y="26">Outcome per case list, share of cases</text>`;
  b += legend(16, 54, CLASSES.map(([, label, cls]) => [cls, label, "rect"]));
  const sx = (v) => v * (W - L - R);
  lists.forEach((l, i) => {
    const c = correctness.lists[l].counts, y = top + i * row;
    b += `<text x="${L - 10}" y="${y + bh / 2 + 4}" text-anchor="end">${xml(l)}</text>`;
    b += `<text class="mu num" x="${L - 10}" y="${y + bh / 2 + 17}" text-anchor="end" font-size="10">${group(String(c.cases))} cases</text>`;
    let x = L;
    const parts = CLASSES.filter(([k]) => c[k] > 0);
    parts.forEach(([k, label, cls], j) => {
      const w = sx(c[k] / c.cases) - (j < parts.length - 1 ? 2 : 0), rr = Math.min(4, w / 2);
      const first = j === 0, last = j === parts.length - 1;
      const d = `M${r1(x + (first ? rr : 0))} ${y}h${r1(w - (first ? rr : 0) - (last ? rr : 0))}${last ? `a${rr} ${rr} 0 0 1 ${rr} ${rr}v${bh - 2 * rr}a${rr} ${rr} 0 0 1 ${-rr} ${rr}` : `v${bh}`}h${r1(-(w - (first ? rr : 0) - (last ? rr : 0)))}${first ? `a${rr} ${rr} 0 0 1 ${-rr} ${-rr}v${-(bh - 2 * rr)}a${rr} ${rr} 0 0 1 ${rr} ${-rr}` : `v${-bh}`}z`;
      b += `<path class="${cls}" d="${d}"><title>${xml(`${l}: ${label} ${c[k]} of ${c.cases} (${pct(c[k], c.cases)})`)}</title></path>`;
      const txt = group(String(c[k])), tw = txt.length * 7 + 10;
      if (w > tw) b += `<text class="num ${k === "refused" ? "on-light" : "on-dark"}" x="${r1(x + 6)}" y="${y + bh / 2 + 4}">${txt}</text>`;
      x += w + 2;
    });
  });
  const css = ".c .s-good{fill:var(--good)}.c .s-warning{fill:var(--warning)}.c .s-neutral{fill:var(--neutral)}.c .s-critical{fill:var(--critical)}" +
    ".c text.on-light{fill:#0b0b0b}.c text.on-dark{fill:#ffffff}";
  return svgDoc("coverage", W, H, "Outcome per case list", "Per list: " + lists.map((l) => { const c = correctness.lists[l].counts; return `${l} ${c.identical} identical, ${c.refused} refused, ${c.oracle_error} Prettier errors, ${c.different} DIFFERENT of ${c.cases}`; }).join("; ") + ".", b, css);
}

// (f) run-to-run spread
function chartSpread() {
  const ks = [...MAIN, "floor_static"];
  const W = 760, L = 170, R = 24, top = 70, row = 34, H = top + ks.length * row + 40;
  const dev = Object.fromEntries(ks.map((k) => [k, K[k].rep_totals_ms.map((x) => (100 * (x - T[k].median)) / T[k].median)]));
  const m = Math.max(1, ...Object.values(dev).flat().map(Math.abs)), lim = niceTicks(m, 3).at(-1);
  const sx = (v) => L + ((v + lim) / (2 * lim)) * (W - L - R);
  let b = `<text class="h" x="16" y="26">Run-to-run spread of the total, ${perf.reps} reps</text>`;
  b += `<text class="t2" x="16" y="44">Each dot is one rep's total, as a difference from that contender's median.</text>`;
  const bottom = top + ks.length * row;
  for (const t of niceTicks(lim, 3).flatMap((v) => (v ? [-v, v] : [0]))) b += `<line class="${t === 0 ? "axis" : "grid"}" x1="${r1(sx(t))}" y1="${top - 8}" x2="${r1(sx(t))}" y2="${bottom}"/><text class="mu num" x="${r1(sx(t))}" y="${bottom + 16}" text-anchor="middle">${t > 0 ? "+" : ""}${tickLabel(t)}%</text>`;
  ks.forEach((k, i) => {
    const y = top + i * row + 10, name = NAMES[k] ?? "process floor (static)";
    b += `<text x="${L - 10}" y="${y + 4}" text-anchor="end">${xml(name)}</text>`;
    b += `<line class="axis" x1="${r1(sx(Math.min(...dev[k])))}" y1="${y}" x2="${r1(sx(Math.max(...dev[k])))}" y2="${y}"/>`;
    dev[k].forEach((d, r) => { b += `<circle class="dot ${k === "floor_static" ? "s-floor" : `s-${k}`}" cx="${r1(sx(d))}" cy="${y}" r="4"><title>${xml(`${name}, rep ${r + 1}: ${ms(K[k].rep_totals_ms[r])} (${d >= 0 ? "+" : ""}${d.toFixed(1)}%)`)}</title></circle>`; });
  });
  return svgDoc("spread", W, H, "Run-to-run spread per contender", "Per contender, relative standard deviation of the rep totals: " + ks.map((k) => `${NAMES[k] ?? "floor"} ${((100 * T[k].stddev) / T[k].mean).toFixed(1)}%`).join(", ") + ".", b, seriesCss);
}

// Headline card: animated bars. Each animated element sets --d (its start); --seek and --play let
// a renderer freeze any instant (bench/report.mjs --gif does).
function headline() {
  const W = 820, padX = 32, L = padX + 150, R = 110, bh = 18, row = 32;
  const rep = resources.rusage.per_file.find((x) => perf.files.find((f) => f.name === x.name)?.path === resources.representative_file) ??
    resources.rusage.per_file[0];
  const repPath = perf.files.find((f) => f.name === rep.name)?.path ?? resources.representative_file;
  const panels = [
    { heading: `Format ${nFiles} real files, one process per file`, sub: `median of ${perf.reps} runs`, values: MAIN.map((k) => [k, T[k].median, secs(T[k].median)]) },
    { heading: "Peak memory, one file", sub: repPath.replace(/^real\//, ""), values: MAIN.map((k) => [k, rep[k].peak_rss_bytes, mib(rep[k].peak_rss_bytes)]) },
  ];
  let y = 70, b = "", t0 = 0.25;
  b += `<text class="title" x="${W / 2}" y="44" text-anchor="middle">Prettier 3.6.2, ported to hand-written x86-64 assembly</text>`;
  const labels = { prettier: "Prettier (Node)", rust: "Rust port", asm: "asm" };
  for (const p of panels) {
    b += `<text class="ph" x="${padX}" y="${y + 18}">${xml(p.heading)}</text><text class="mu" x="${W - padX}" y="${y + 18}" text-anchor="end">${xml(p.sub)}</text>`;
    y += 34;
    const max = Math.max(...p.values.map((v) => v[1]));
    p.values.forEach(([k, v, label], i) => {
      const w = Math.max(4, (v / max) * (W - L - R)), d = t0 + i * 0.15;
      b += `<text class="lab${k === "asm" ? " feat" : ""}" x="${padX}" y="${y + bh / 2 + 5}">${labels[k]}</text>`;
      b += `<rect class="track" x="${L}" y="${y}" width="${W - L - R}" height="${bh}" rx="4"/>`;
      b += hbar(L, y, w, bh, `grow ${k === "asm" ? "feat-bar" : "base-bar"}`, `${labels[k]}: ${label}`, ` style="--d:${d.toFixed(2)}s"`);
      b += `<text class="val${k === "asm" ? " feat" : ""}" x="${W - padX}" y="${y + bh / 2 + 5}" text-anchor="end" style="--d:${(d + 1.1).toFixed(2)}s">${xml(label)}</text>`;
      y += row;
    });
    y += 14;
    t0 += 0.6;
  }
  const foot = `${realCounts.identical}/${realCounts.cases} files byte-identical to Prettier 3.6.2`;
  b += `<text class="foot" x="${W / 2}" y="${y + 18}" text-anchor="middle" style="--d:${(t0 + 0.9).toFixed(2)}s">${xml(foot)}</text>`;
  const H = y + 44;
  const card = { surface: "#ffffff", ink: "#0b0b0b", ink2: "#52514e", muted: "#6d6c67", track: "#f0efec", base: "#a3a29c", feat: "#2a78d6", edge: "#e1e0d9" };
  const cardDark = { surface: "#141413", ink: "#f0efec", ink2: "#c3c2b7", muted: "#9a9993", track: "#242422", base: "#6d6c67", feat: "#3987e5", edge: "#2c2c2a" };
  const css = `.c .title{font-size:19px;font-weight:600}.c .ph{font-size:14px;font-weight:600;fill:var(--ink2)}
.c .lab{font-size:14px;fill:var(--ink2)}.c .lab.feat{fill:var(--ink);font-weight:600}
.c .val{font-family:${MONO};font-size:15px;fill:var(--ink2)}.c .val.feat{fill:var(--ink);font-weight:700}
.c .foot{font-size:14px;fill:var(--ink2)}.c .track{fill:var(--track)}.c .base-bar{fill:var(--base)}.c .feat-bar{fill:var(--feat)}
.c .bg{stroke:var(--edge);stroke-width:1}
.c .grow{transform-box:fill-box;transform-origin:0 50%;animation:grow 1.1s cubic-bezier(.25,.8,.25,1) both}
.c .val,.c .foot{animation:fade .35s ease-out both}
.c .grow,.c .val,.c .foot{animation-delay:calc(var(--d) - var(--seek,0s));animation-play-state:var(--play,running)}
@keyframes grow{from{transform:scaleX(0)}to{transform:scaleX(1)}}
@keyframes fade{from{opacity:0}to{opacity:1}}
@media (prefers-reduced-motion:reduce){.c .grow,.c .val,.c .foot{animation:none}}
`;
  const desc = `${panels[0].heading}: ` + MAIN.map((k, i) => `${labels[k]} ${panels[0].values[i][2]}`).join(", ") + `. ${panels[1].heading} (${panels[1].sub}): ` +
    MAIN.map((k, i) => `${labels[k]} ${panels[1].values[i][2]}`).join(", ") + `. ${foot}.`;
  const svg = svgDoc("headline", W, H, "Prettier 3.6.2, ported to hand-written x86-64 assembly", desc, b, css, { light: card, dark: cardDark })
    .replace(`<rect class="bg" width="${W}" height="${H}" rx="8"/>`, `<rect class="bg" x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="14"/>`);
  return { svg, W, H, desc, end: t0 + 1.3 };
}

// ---- RESULTS.md
const md = [];
const p = (s = "") => md.push(s);
const table = (head, rows, align) => {
  p(`| ${head.join(" | ")} |`);
  p(`| ${head.map((_, i) => (align?.[i] === "r" ? "---:" : "---")).join(" | ")} |`);
  for (const r of rows) p(`| ${r.join(" | ")} |`);
  p();
};
const head = headline();
const loadS = run.load_start.load_1min, loadE = run.load_end.load_1min;

p("# Results");
p();
p(`<img src="results/charts/headline.svg" alt="${xml(head.desc)}" width="820">`);
p();
const banners = [];
if (loadS > 1.0) banners.push(`The 1-minute load average was ${loadS.toFixed(2)} when the run started, above the limit of 1.0. The run was forced, so the times are provisional.`);
if (run.flags.quick) banners.push("This is a quick run: fewer reps, and the sweep, the mutants and hyperfine were skipped.");
if (perf.dropped_cases.length) banners.push(`${perf.dropped_cases.length} of the ${nFiles + perf.dropped_cases.length} real files ${perf.dropped_cases.length === 1 ? "was" : "were"} dropped from the timing because a contender's output differed from Prettier's (--allow-mismatch). The times below leave them out for every contender.`);
for (const x of banners) p(`> **${x}**`), p(">");
if (banners.length) { md.pop(); p(); }
p(`Recorded ${run.started_utc.replace("T", " ").replace(/\.\d+Z$/, " UTC")} by \`${run.command}\`. Load average ${loadS.toFixed(2)} at the start and ${loadE.toFixed(2)} at the end. Every number here comes from \`${path.relative(ROOT, DATA)}/\`.`);
p();

p("## Headline");
p();
table(["Contender", "Median total", "Min to max", "Per-file median", "asm speedup over it"], MAIN.map((k) => [
  NAMES[k], secs(T[k].median), `${secs(T[k].min)} to ${secs(T[k].max)}`, ms(fileMedian(k)), k === "asm" ? "n/a" : sp(k, "asm"),
]), ["", "r", "r", "r", "r"]);
p(`Totals are for the ${nFiles} real files, one process per file, over ${perf.reps} reps. The speedup is the ratio of median totals. The range in brackets is the lowest and highest ratio within a single rep. The Rust port over Prettier is ${sp("prettier", "rust")}.`);
p();
const nat = perf.native, allNative = nat.asm_formatted_itself === realCounts.cases && nat.rust_formatted_itself === realCounts.cases;
p(`Every output was compared byte for byte with Prettier 3.6.2 before the timed reps. On the real list asm formats ${nat.asm_formatted_itself} of ${realCounts.cases} files itself and the Rust port formats ${nat.rust_formatted_itself} of ${realCounts.cases} itself.${allNative ? " Neither runs Node for these files." : ` Files the Rust port hands to Node: ${nat.rust_fell_back.length}. Files asm refuses: ${nat.asm_refused.length}.`}`);
p();
p('<img src="results/charts/total.svg" alt="Total time for the three contenders. The headline table has the values." width="760">');
p();

p("## Environment");
p();
const e = env;
p(`- CPU: ${e.cpu_model}, ${e.cpu_cores} cores, ${e.cpu_threads} threads, max ${e.cpu_max_mhz} MHz. Governor \`${e.governor}\`, energy preference \`${e.energy_performance_preference}\`. Nothing was pinned.`);
p(`- Memory: ${(e.memory_bytes / 2 ** 30).toFixed(0)} GiB. Kernel: ${e.kernel}. Distribution: ${e.distro}.`);
p(`- Node ${e.node}. Prettier ${e.prettier} from npm. ${e.as}. ${e.ld}.`);
p(`- asm binary: ${group(String(binary.asm.size_bytes))} bytes, ${binary.asm.linkage}, sha256 \`${binary.asm.sha256.slice(0, 16)}\`. Source tree sha256 \`${e.repo.src_tree_sha256.slice(0, 16)}\`${e.repo.commit ? `, commit \`${e.repo.commit.slice(0, 12)}\`${e.repo.dirty ? " with local changes" : ""}` : ", no commit"}.`);
p(`- asm source: ${binary.source.s_files} \`.s\` files and ${binary.source.inc_files} \`.inc\` files. ${group(String(binary.source.hand_written_lines))} hand-written lines (${group(String(binary.source.hand_written_code_lines))} not blank or comment) and ${group(String(binary.source.generated_lines))} generated lines in ${binary.source.generated_files.map((f) => `\`${f}\``).join(" and ")}.`);
const rb = e.rust_baseline;
p(`- Rust port: rust-anything \`${rb.rust_anything_commit.slice(0, 7)}\`, Prettier clone \`${rb.prettier_clone_commit.slice(0, 7)}\` (tag ${rb.prettier_clone_tag}), ${rb.rustc}. Built with \`cargo build --release\`; the app crate ${rb.app_crate_has_release_profile ? "has" : "has no"} \`[profile.release]\`, so LTO is ${rb.lto ? "on" : "off"}. Binary: ${group(String(binary.rust.size_bytes))} bytes, ${binary.rust.linkage} (${(binary.rust.shared_libraries ?? []).map((l) => path.basename(l)).join(", ")}), sha256 \`${binary.rust.sha256.slice(0, 16)}\`. bench/rust-baseline.md has the build steps.`);
p(`- Corpus: ${Object.entries(e.corpus).map(([k, v]) => `${k} \`${v.tag}\` (\`${(v.commit ?? "").slice(0, 7)}\`)`).join(", ")}.`);
p();

p("## Method");
p();
p(`\`bench/cli.mjs\` starts one process per file with the file on stdin and \`--stdin-filepath real/<path>\`, as prettier-rs's own \`bench/cli.mjs\` does. It times each \`spawnSync\` with \`process.hrtime\`. All runs start in an empty temporary directory, so no config or ignore file applies.`);
p();
p(`Before the timed reps, every contender's output for every file is compared byte for byte with Prettier 3.6.2's, exit code included. A mismatch stops the run unless \`--allow-mismatch\` is given. This pass also warms the file cache.`);
p();
p(`Each rep runs all files. For each file the contenders run one after another, and the order rotates each rep. A rep total is the sum over the files. The median, min and max are over the ${perf.reps} rep totals.`);
p();
p(`The process floors run in the same loop with their output unchecked: a static binary that only calls \`exit(0)\` (\`bench/tools/floor.s\`) and \`/bin/true\`, which is dynamically linked like the Rust port.`);
p();

p("## Correctness");
p();
p(`\`tests/harness.mjs\` runs each case through the asm binary without a fallback and compares it with Prettier 3.6.2's cached output. Each case lands in one class:`);
p();
p("- identical: same exit code and stdout as Prettier.");
p("- refused: asm exits 3 with `unsupported: <reason>` where Prettier formats the case. These cases are not formatted by asm.");
p("- Prettier errors too: Prettier rejects the input and asm exits 3, as it must.");
p("- DIFFERENT: anything else, including a crash or a timeout.");
p();
table(["List", "Cases", "Identical", "Refused", "Prettier errors too", "DIFFERENT"], Object.entries(correctness.lists).map(([l, x]) => {
  const c = x.counts;
  return [l, group(String(c.cases)), `${c.identical} (${pct(c.identical, c.cases)})`, `${c.refused} (${pct(c.refused, c.cases)})`, `${c.oracle_error} (${pct(c.oracle_error, c.cases)})`, `${c.different}`];
}), ["", "r", "r", "r", "r", "r"]);
p(`Of the cases Prettier formats, asm formats ${Object.entries(correctness.lists).map(([l, x]) => `${pct(x.counts.identical, x.counts.identical + x.counts.refused + x.counts.different)} on ${l}`).join(", ")}.`);
p();
p('<img src="results/charts/coverage.svg" alt="Outcome per case list as stacked bars. The correctness table has the values." width="760">');
p();
const s1 = correctness.stage1;
p(`Stage 1 (\`tests/stage1/run.mjs\`, JSON fixtures under four file names and the edge cases): ${group(String(s1.total.identical))} identical, ${s1.total.refused} refused, ${s1.total.oracle_error} where Prettier errors too, ${s1.total.different} DIFFERENT.`);
p();
table(["Kind", "Identical", "Refused", "Prettier errors too", "DIFFERENT"], s1.rows.map((r) => [r.kind, r.identical, r.refused, r.oracle_error, r.different]), ["", "r", "r", "r", "r"]);

p("### Refusal reasons");
p();
p("The 15 most common `unsupported:` reasons per list, for cases Prettier formats.");
p();
for (const [l, x] of Object.entries(correctness.lists)) {
  if (!x.refusal_reasons.length) { p(`${l}: no refusals.`); p(); continue; }
  p(`${l} (${x.counts.refused} refused, ${x.refusal_reasons.length} distinct reasons):`);
  p();
  table(["Cases", "Reason"], x.refusal_reasons.slice(0, 15).map((r) => [r.cases, mdEsc(r.reason)]), ["r", ""]);
}

p("## Option sweep");
p();
if (sweep.skipped) { p("Not run in this record (`--skip-sweep`)."); p(); }
else {
  p(`\`tests/stage3/printer/sweep.mjs\` runs every JS and TS case of ${sweep.lists.join(", ")} (${group(String(sweep.cases))} cases) under each option set, against Prettier's \`format()\` in process. Cases Prettier rejects under a set are counted apart.`);
  p();
  table(["Options", "Identical", "Refused", "Prettier errors", "DIFFERENT"], sweep.sets.map((s) => [s.flags.length ? `\`${s.flags.join(" ")}\`` : "(defaults)", group(String(s.identical)), group(String(s.refused)), s.oracle_error, s.different]), ["", "r", "r", "r", "r"]);
  p(`Total: ${group(String(sweep.total.identical))} identical, ${group(String(sweep.total.refused))} refused, ${sweep.total.different} DIFFERENT.`);
  p();
}

p("## Mutation tests");
p();
if (mutants.skipped) { p("Not run in this record (`--skip-mutants`)."); p(); }
else {
  p("Each script builds deliberately broken binaries and checks that the tests report them. A killed mutant was reported. A survivor was not.");
  p();
  const rows = [];
  for (const s of mutants.scripts) {
    if (!s.present) { rows.push([`\`${s.script}\``, "not present", "", "", "", ""]); continue; }
    if (s.crashed) { rows.push([`\`${s.script}\``, "crashed", "", "", "", mdEsc(s.error ?? `exit ${s.exit}`)]); continue; }
    if (s.summary_agrees === false) { rows.push([`\`${s.script}\``, "output not understood", "", "", "", mdEsc(s.summary_lines.join("; "))]); continue; }
    rows.push([`\`${s.script}\``, s.total, s.killed, s.survived, s.survived_equivalent, s.not_applied]);
    const kinds = [...new Set(s.mutants.map((m) => m.kind).filter(Boolean))];
    for (const k of kinds) {
      const ms_ = s.mutants.filter((m) => m.kind === k);
      rows.push([`  ${k}`, ms_.length, ms_.filter((m) => m.outcome === "killed").length, ms_.filter((m) => m.outcome === "survived").length, ms_.filter((m) => m.equivalent).length, ms_.filter((m) => m.outcome === "not_applied").length]);
    }
  }
  table(["Script", "Mutants", "Killed", "Survived", "Survived, marked equivalent", "Not applied"], rows, ["", "r", "r", "r", "r", "r"]);
  const refusalKills = mutants.scripts.filter((s) => s.present && !s.crashed).flatMap((s) => s.mutants.filter((m) => /^refusals only/.test(m.killed_by ?? "")).map(() => s.script));
  if (refusalKills.length) { p(`In \`${[...new Set(refusalKills)].join("`, `")}\`, ${refusalKills.length} of the killed mutants were caught only because a case the unmutated binary formats was refused. They produced no DIFFERENT output.`); p(); }
  const com = mutants.scripts.find((s) => s.script.includes("/comments/") && s.present && !s.crashed);
  if (com) { p("The comments script expects most swaps to survive: handlers whose conditions never overlap can trade places without effect. Its equivalent mutants carry a reason in the script."); p(); }
  const surv = mutants.scripts.filter((s) => s.present && !s.crashed).flatMap((s) => s.mutants.filter((m) => m.outcome === "survived" && !m.equivalent && m.kind !== "swap").map((m) => [s.script, m.name]));
  if (surv.length) { p("Survivors not marked equivalent:"); p(); for (const [s, n] of surv) p(`- \`${s}\`: ${mdEsc(n)}`); p(); }
}

p("## Per file");
p();
p(`Median of ${perf.reps} reps per file, in ms. The last column is the Rust port's time over asm's.`);
p();
table(["File", "Bytes", "Lines", "Prettier", "Rust", "asm", "Rust ÷ asm"], [...files].sort((a, b) => (a.path < b.path ? -1 : 1)).map((f) => [
  `\`${f.path.replace(/^real\//, "")}\``, group(String(f.input_bytes)), group(String(f.input_lines)), ms2(f.med.prettier), ms2(f.med.rust), ms2(f.med.asm), ratio(f.med.rust / f.med.asm),
]), ["", "r", "r", "r", "r", "r", "r"]);
p("Totals by file type, median of the rep totals:");
p();
table(["Type", "Files", "Prettier", "Rust", "asm", "asm speedup over Rust"], exts.map((x) => {
  const t = extTotals[x], n = files.filter((f) => f.ext === x).length;
  const idx = files.map((f, i) => (f.ext === x ? i : -1)).filter((i) => i >= 0);
  const per = K.rust.rep_totals_ms.map((_, rr) => sum(idx.map((i) => files[i].rep_ms.rust[rr])) / sum(idx.map((i) => files[i].rep_ms.asm[rr])));
  return [`.${x}`, n, ms(t.prettier.median), ms(t.rust.median), ms(t.asm.median), `${ratio(t.rust.median / t.asm.median)} (${ratio(Math.min(...per))} to ${ratio(Math.max(...per))})`];
}), ["", "r", "r", "r", "r", "r"]);
p('<img src="results/charts/per-file.svg" alt="Time per file for the three contenders on a log scale. The per-file table has the values." width="760">');
p();
p('<img src="results/charts/size.svg" alt="Time against input size for the Rust port and asm. The per-file table has the values." width="760">');
p();

p("## Spread");
p();
table(["Contender", "Min", "Median", "Mean", "Max", "Std. dev.", "Rel. std. dev."], [...MAIN, "floor_static", "floor_dynamic"].map((k) => [
  NAMES[k] ?? K[k].label, ms(T[k].min), ms(T[k].median), ms(T[k].mean), ms(T[k].max), ms(T[k].stddev), `${((100 * T[k].stddev) / T[k].mean).toFixed(1)}%`,
]), ["", "r", "r", "r", "r", "r", "r"]);
p('<img src="results/charts/spread.svg" alt="Each rep total as a difference from its contender median. The spread table has the values." width="760">');
p();

p("## Process floor");
p();
const fs_ = T.floor_static, fd = T.floor_dynamic;
p(`Starting a process that does nothing costs ${ms(fs_.median)} for the ${nFiles} files (${ms(fileMedian("floor_static"))} a file) when the binary is static, and ${ms(fd.median)} (${ms(fileMedian("floor_dynamic"))} a file) for \`/bin/true\`, which is dynamic.`);
p(`asm takes ${ms(T.asm.median)}, so ${ms(T.asm.median - fs_.median)} (${pct(T.asm.median - fs_.median, T.asm.median)}) is above the static floor. The Rust port takes ${ms(T.rust.median)}, ${ms(T.rust.median - fd.median)} above the dynamic floor.`);
p();
p('<img src="results/charts/floor.svg" alt="asm time per file split into the process floor and the work above it. The per-file table and this section have the values." width="760">');
p();

p("## System calls and memory");
p();
const sc = resources.syscalls;
p(`System calls on \`${resources.representative_file.replace(/^real\//, "")}\` (${group(String(resources.representative_bytes))} bytes), counted with \`strace -c -f\`, threads included. The run starts in a directory ${resources.cwd_depth} levels below \`/\`. Each contender looks for config files in every directory from there up to \`/\`, so the counts grow with depth.`);
p();
const scRow = (k) => { const x = sc[k]; if (!x?.available) return [NAMES[k] ?? "process floor (static)", "n/a", "n/a", x?.reason ?? "n/a"];
  return [NAMES[k] ?? "process floor (static)", group(String(x.total_calls)), group(String(x.total_errors)), x.by_syscall.slice(0, 5).map((r) => `${r.syscall} ${r.calls}`).join(", ")]; };
table(["Contender", "Calls", "Failed", "Most frequent"], [...MAIN, "floor_static"].map(scRow), ["", "r", "r", ""]);
const ru = resources.rusage.per_file;
const rss = (k) => ru.map((x) => x[k].peak_rss_bytes), cpu = (k) => sum(ru.map((x) => x[k].user_cpu_ms + x[k].sys_cpu_ms));
const repRu = ru.find((x) => perf.files.find((f) => f.name === x.name)?.path === resources.representative_file) ?? ru[0];
p(`Peak resident memory per process, one run per file (\`bench/tools/rusage.s\`). Peak RSS is the larger of \`ru_maxrss\` and the \`Rss\` line of \`/proc/<pid>/smaps_rollup\`, read when the process calls exit. Linux counts \`ru_maxrss\` in per-CPU batches, so it reads low by up to a few hundred KiB on a small process. \`Rss\` at exit misses memory freed before exit. CPU time is user plus system time from \`wait4\`, summed over the ${ru.length} files.`);
p();
table(["Contender", "Peak RSS, one file", "Median over files", "Max over files", "CPU time, all files"], MAIN.map((k) => [
  NAMES[k], mib(repRu[k].peak_rss_bytes), mib(median(rss(k))), mib(Math.max(...rss(k))), ms(cpu(k)),
]), ["", "r", "r", "r", "r"]);
if (resources.perf.available) {
  p("`perf stat` over the shell loop of all files (the loop's own share shows in the floor row):");
  p();
  table(["Contender", "Instructions (user)", "Cycles (user)", "Instructions (kernel)", "Cycles (kernel)"], Object.entries(resources.perf.counters).map(([k, c]) => [NAMES[k] ?? "process floor (static)", group(String(c.instructions_u ?? "n/a")), group(String(c.cycles_u ?? "n/a")), group(String(c.instructions_k ?? "n/a")), group(String(c.cycles_k ?? "n/a"))]), ["", "r", "r", "r", "r"]);
} else { p(`Instruction and cycle counts: not recorded, ${resources.perf.reason}.`); p(); }

p("## Cross-check with hyperfine");
p();
if (hyperfine.available) {
  p(`${hyperfine.version}, ${hyperfine.method}.`);
  p();
  table(["Contender", "Mean", "Std. dev.", "Median", "Min", "Max"], hyperfine.results.map((x) => [NAMES[x.name] ?? "process floor (static)", secs(x.mean_s * 1000), secs(x.stddev_s * 1000), secs(x.median_s * 1000), secs(x.min_s * 1000), secs(x.max_s * 1000)]), ["", "r", "r", "r", "r", "r"]);
} else { p(`Not run: ${hyperfine.reason}.`); p(); }

p("## Upstream method");
p();
if (!upstream.available) { p(`Not run: ${upstream.reason}.`); p(); }
else {
  p(`rust-anything's own \`bench/cli.mjs\` (\`${upstream.script}\`, sha256 \`${upstream.script_sha256.slice(0, 16)}\`), run unchanged from an empty directory with Prettier's \`dist\` build from the clone. The script times Prettier against one front door, file by file. For asm, the asm binary takes the front door's slot in a separate run. The script counts stdout equal to Prettier's as identical and rounds each total to whole ms.`);
  p();
  table(["Run", "Front door", "Load", "Prettier", "Front door time", "Identical"], upstream.runs.map((x) => [x.run, NAMES[x.front_door], x.load_1min.toFixed(2), `${group(String(x.prettier_ms))} ms`, `${group(String(x.front_door_ms))} ms`, `${x.identical}/${x.cases}`]), ["r", "", "r", "r", "r", "r"]);
  const um = (fd) => median(upstream.runs.filter((x) => x.front_door === fd).map((x) => x.front_door_ms));
  const up = (fd) => median(upstream.runs.filter((x) => x.front_door === fd).map((x) => x.prettier_ms));
  p(`Medians: Prettier ${group(String(up("rust")))} ms against the Rust port's ${group(String(um("rust")))} ms, and ${group(String(up("asm")))} ms against asm's ${group(String(um("asm")))} ms. asm over the Rust port by this method: ${ratio(um("rust") / um("asm"))}.`);
  if (upstream.published) p(`Their published figure is ${upstream.published.prettier_s.toFixed(2)} s against ${upstream.published.front_door_s.toFixed(2)} s (run 1 of their 2), on ${upstream.published.machine} (\`${upstream.published.source.split(",")[0]}\`).`);
  p();
}

p("## What was not tested");
p();
p("- Only Linux on x86-64. The binary does not run anywhere else.");
p("- One machine. Results on other CPUs, kernels and file systems are not known.");
p(`- The Rust port was built and timed here on x86-64. The figure in its README is from ${upstream.published ? upstream.published.machine : "an Apple M4"}. That machine was not used here.`);
p("- Refused inputs are not counted as formatted. With `PRETTIER_ASM_FALLBACK` set, asm hands them to Node, and they then run at Node's speed. That mode was not timed here.");
p("- `.tsx`, JSX, Flow and proposals are refused by design.");
p(`- Only the ${nFiles} real files were timed. The fixture lists were checked for output, not timed.`);
p();

p("## Reproduce");
p();
p("```sh");
p("npm install");
p("node tests/setup-corpus.mjs        # corpus/real and corpus/cases");
p("node tests/build-expected.mjs      # Prettier's output for every case");
p("bench/build-rust-baseline.sh build # the Rust port, under ref/");
p("make                               # build/prettier-asm");
p("make results                       # node bench/record.mjs, then node bench/report.mjs");
p("node bench/report.mjs --gif        # also results/charts/headline.gif");
p("```");
p();
p(`\`node bench/record.mjs\` refuses to run when the 1-minute load average is above 1.0. \`--force\` overrides that, and the report then says so at the top. \`results/README.md\` lists what each data file holds.`);
p();

const mdText = md.join("\n").replace(/\n{3,}/g, "\n\n").replace(/\n+$/, "\n");
const dashes = (mdText.match(/—/g) ?? []).length;
if (dashes > 2) fail(`RESULTS.md would have ${dashes} em-dashes`);

// ---- write
const charts = {
  "headline.svg": head.svg, "total.svg": chartTotal(), "per-file.svg": chartPerFile(), "size.svg": chartSize(),
  "floor.svg": chartFloor(), "coverage.svg": chartCoverage(), "spread.svg": chartSpread(),
};
fs.mkdirSync(CHARTS, { recursive: true });
for (const [f, s] of Object.entries(charts)) fs.writeFileSync(path.join(CHARTS, f), s);
fs.writeFileSync(OUT_MD, mdText);
console.log(`wrote ${path.relative(ROOT, OUT_MD)} and ${Object.keys(charts).length} charts in ${path.relative(ROOT, CHARTS)}`);

if (wantGif) renderGif();

// ---- GIF: Chromium screenshots of the headline at fixed instants, then ffmpeg
function renderGif() {
  const find = (names) => names.map((n) => spawnSync("sh", ["-c", `command -v ${n}`], { encoding: "utf8" }).stdout.trim()).find(Boolean);
  const browser = find(["chromium", "chromium-browser", "google-chrome", "google-chrome-stable"]);
  const ffmpeg = find(["ffmpeg"]);
  const magick = find(["magick", "convert"]);
  if (!browser || !ffmpeg) { console.error(`report: --gif needs headless Chromium and ffmpeg; missing: ${[!browser && "chromium", !ffmpeg && "ffmpeg"].filter(Boolean).join(", ")}`); process.exit(1); }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "headline-gif-"));
  const dark = head.svg.replace("@media (prefers-color-scheme:dark){", "@media all{");
  const fps = 30, end = head.end, frames = Math.ceil(end * fps) + 1;
  const shot = (t, out) => {
    const html = path.join(tmp, "f.html");
    fs.writeFileSync(html, `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}svg{display:block;--seek:${t.toFixed(4)}s;--play:paused}</style>${dark}`);
    const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-sandbox", "--force-device-scale-factor=2",
      `--window-size=${head.W},${head.H}`, "--default-background-color=00000000", `--screenshot=${out}`, `file://${html}`], { encoding: "utf8", timeout: 60_000 });
    if (!fs.existsSync(out)) { console.error(r.stderr); throw new Error(`no screenshot at t=${t}`); }
  };
  for (let i = 0; i < frames; i++) shot(Math.min(i / fps, end), path.join(tmp, `f${String(i).padStart(4, "0")}.png`));
  const last = path.join(tmp, `f${String(frames - 1).padStart(4, "0")}.png`);
  fs.copyFileSync(last, path.join(CHARTS, "headline.png"));
  // Every frame lasts 1/fps; the last one is held 4 s (a concat list with durations).
  const list = path.join(tmp, "frames.txt");
  const lines = [];
  for (let i = 0; i < frames; i++) lines.push(`file 'f${String(i).padStart(4, "0")}.png'`, `duration ${i === frames - 1 ? 4 : (1 / fps).toFixed(6)}`);
  lines.push(`file 'f${String(frames - 1).padStart(4, "0")}.png'`); // the concat demuxer drops the last duration otherwise
  fs.writeFileSync(list, lines.join("\n") + "\n");
  const gif = path.join(CHARTS, "headline.gif"), raw = path.join(tmp, "raw.gif");
  const r = spawnSync(ffmpeg, ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list, "-fps_mode", "vfr",
    "-filter_complex", "[0:v]split[a][b];[a]palettegen=max_colors=48:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle", "-loop", "0", raw], { encoding: "utf8" });
  if (r.status !== 0) { console.error(r.stderr); process.exit(1); }
  // ffmpeg stores every frame whole when the frames have transparency; ImageMagick keeps only what changes.
  const m = magick ? spawnSync(magick, [raw, "-layers", "Optimize", gif], { encoding: "utf8" }) : null;
  if (!m || m.status !== 0) fs.copyFileSync(raw, gif);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`wrote ${path.relative(ROOT, gif)} (${frames} frames at ${fps} fps, the last held 4 s, ${fs.statSync(gif).size} bytes) and headline.png`);
}
