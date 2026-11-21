// Collects every measurement the report uses into results/data/*.json. Each run overwrites the
// files; git history is the archive. bench/report.mjs reads only these files.
//
//   node bench/record.mjs [--reps N] [--skip-sweep] [--skip-mutants] [--quick] [--force]
//                         [--allow-mismatch] [--asm-bin path] [--out dir]
//
// --reps N          timed passes over the 59 real files (default 10, 3 with --quick)
// --quick           3 reps, no sweep, no mutants, one upstream-method run, no hyperfine
// --force           record even when the 1-minute load average is above 1.0 at the start
// --allow-mismatch  passed to bench/cli.mjs: a file any contender gets wrong is dropped for all
// --asm-bin path    the binary to record instead of build/prettier-asm (it is copied first)
// --out dir         where the data goes (default results/data)
//
// The binary is copied to build/record-tmp/ at the start, so a rebuild during the run does not
// change what is measured. PRETTIER_ASM_FALLBACK and RUST_ANYTHING_* are removed from the
// environment of every child.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SCHEMA = 1;
const LISTS = ["real", "ts-fixtures", "js-fixtures", "variants", "json"];
const REPRESENTATIVE = "real/Fuse/src/search/index.js"; // the file bench/rust-baseline.md traced
const GENERATED = new Set(["unicode_tables.s", "ast_types.s"]);
const MUTANT_SCRIPTS = ["tests/stage1/mutants.mjs", "tests/stage3/config/mutants.mjs", "tests/stage3/infra/mutants.mjs",
  "tests/stage3/parser/mutants.mjs", "tests/stage3/comments/mutants.mjs", "tests/stage3/printer/ts-mutants.mjs"];

// ---- arguments
const argv = process.argv.slice(2);
const flag = (n) => { const i = argv.indexOf(n); if (i < 0) return false; argv.splice(i, 1); return true; };
const opt = (n, d) => { const i = argv.indexOf(n); return i < 0 ? d : argv.splice(i, 2)[1]; };
const quick = flag("--quick"), force = flag("--force"), allowMismatch = flag("--allow-mismatch");
const skipSweep = flag("--skip-sweep") || quick, skipMutants = flag("--skip-mutants") || quick;
const reps = Number(opt("--reps", quick ? 3 : 10));
const asmSource = path.resolve(opt("--asm-bin", path.join(ROOT, "build/prettier-asm")));
const OUT = path.resolve(opt("--out", path.join(ROOT, "results/data")));
if (argv.length || !Number.isInteger(reps) || reps < 1) {
  console.error("usage: node bench/record.mjs [--reps N] [--skip-sweep] [--skip-mutants] [--quick] [--force] [--allow-mismatch] [--asm-bin path] [--out dir]");
  process.exit(2);
}

const TMP = path.join(ROOT, "build/record-tmp");
fs.mkdirSync(TMP, { recursive: true });
const PRETTIER_CLI = path.join(ROOT, "node_modules/prettier/bin/prettier.cjs");
const RUST_BIN = path.join(ROOT, "ref/prettier/rust/app/target/release/prettier");
const UPSTREAM_SCRIPT = path.join(ROOT, "ref/rust-anything/demo/real-world/prettier-rs/bench/cli.mjs");
const UPSTREAM_PRETTIER = path.join(ROOT, "ref/prettier/dist/prettier/bin/prettier.cjs");
const ASM = path.join(TMP, "prettier-asm");
const FLOOR = path.join(TMP, "floor"), RUSAGE = path.join(TMP, "rusage");

for (const k of Object.keys(process.env)) if (k === "PRETTIER_ASM_FALLBACK" || k.startsWith("RUST_ANYTHING_")) delete process.env[k];

const log = (s) => process.stderr.write(`[record] ${s}\n`);
const rel = (p) => path.relative(ROOT, p) || ".";
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");
const run = (cmd, args, o = {}) => {
  const start = process.hrtime.bigint();
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 1 << 30, ...o });
  return { ...r, ms: Number(process.hrtime.bigint() - start) / 1e6 };
};
const which = (name) => { const r = run("sh", ["-c", `command -v ${name}`]); return r.status === 0 ? r.stdout.trim() : null; };
const firstLine = (s) => (s ?? "").split("\n").find((l) => l.trim()) ?? "";
const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const load1 = () => os.loadavg()[0];
const loadNow = () => { const [a, b, c] = os.loadavg(); return { load_1min: a, load_5min: b, load_15min: c }; };

// ---- load gate
const loadStart = loadNow();
if (loadStart.load_1min > 1.0 && !force) {
  console.error(`record: the 1-minute load average is ${loadStart.load_1min.toFixed(2)} (above 1.0); wait for an idle machine or pass --force`);
  process.exit(1);
}
// The old set stops being a set as soon as this run starts writing: report.mjs needs run.json.
fs.rmSync(path.join(OUT, "run.json"), { force: true });
const runId = new Date().toISOString();
const startedMs = Date.now();
log(`run ${runId}, load ${loadStart.load_1min.toFixed(2)}, ${reps} reps${quick ? ", quick" : ""}`);

// ---- output: every file carries run_id; paths are made relative; nothing personal gets written
const PERSONAL = [os.homedir(), os.hostname(), os.userInfo().username].filter((s) => s && s.length > 2);
const written = {};
function save(name, data) {
  let text = JSON.stringify({ schema: SCHEMA, run_id: runId, ...data }, null, 1) + "\n";
  text = text.split(ROOT + "/").join("").split(ROOT).join(".");
  for (const p of PERSONAL) if (text.includes(p)) throw new Error(`${name}: would record a personal string (${p === os.homedir() ? "home path" : "user or host name"})`);
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, name), text);
  written[name] = sha256(text);
  log(`wrote ${rel(path.join(OUT, name))}`);
}

// ---- tools
function assemble(name) {
  const src = path.join(ROOT, "bench/tools", `${name}.s`), obj = path.join(TMP, `${name}.o`), bin = path.join(TMP, name);
  for (const [c, a] of [["as", ["--64", "-o", obj, src]], ["ld", ["-static", "-o", bin, obj]]]) {
    const r = run(c, a);
    if (r.status !== 0) throw new Error(`${c} ${name}: ${r.stderr}`);
  }
}
assemble("floor");
assemble("rusage");
if (!fs.existsSync(asmSource)) throw new Error(`${asmSource} does not exist; run make`);
fs.copyFileSync(asmSource, ASM);
fs.chmodSync(ASM, 0o755);
for (const f of [PRETTIER_CLI, RUST_BIN]) if (!fs.existsSync(f)) throw new Error(`${rel(f)} is missing (see bench/rust-baseline.md and tests/README.md)`);

const EMPTY = fs.mkdtempSync(path.join(os.tmpdir(), "record-empty-"));
process.on("exit", () => fs.rmSync(EMPTY, { recursive: true, force: true }));

const readCases = (list) => fs.readFileSync(path.join(ROOT, "corpus/cases", `${list}.jsonl`), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const filepathOf = (c) => c.args[c.args.indexOf("--stdin-filepath") + 1];
const realCases = readCases("real");

// ---- environment
function collectEnvironment() {
  const read = (f) => { try { return fs.readFileSync(f, "utf8").trim(); } catch { return null; } };
  const lscpu = run("lscpu", []).stdout ?? "";
  const lsField = (k) => lscpu.match(new RegExp(`^${k}:\\s*(.+)$`, "m"))?.[1]?.trim() ?? null;
  const cores = Number(lsField("Core\\(s\\) per socket")) * Number(lsField("Socket\\(s\\)") ?? 1);
  const osRelease = read("/etc/os-release") ?? "";
  const git = (dir, ...a) => { const r = run("git", ["-C", dir, ...a]); return r.status === 0 ? r.stdout.trim() : null; };
  const ver = (c, a = ["--version"]) => { const r = run(c, a); return r.status === 0 ? firstLine(r.stdout) : null; };
  const cargoToml = read(path.join(ROOT, "ref/prettier/rust/app/Cargo.toml")) ?? "";
  const srcFiles = fs.readdirSync(path.join(ROOT, "src")).filter((f) => /\.(s|inc)$/.test(f)).sort();
  const tree = crypto.createHash("sha256");
  for (const f of srcFiles) tree.update(f).update("\0").update(fs.readFileSync(path.join(ROOT, "src", f))).update("\0");
  const repoHead = git(ROOT, "rev-parse", "HEAD");
  return {
    date_utc: runId,
    cpu_model: os.cpus()[0].model,
    cpu_cores: Number.isFinite(cores) ? cores : null,
    cpu_threads: os.cpus().length,
    cpu_max_mhz: Number(lsField("CPU max MHz")) || null,
    governor: read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
    energy_performance_preference: read("/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
    memory_bytes: os.totalmem(),
    kernel: `${os.type()} ${os.release()} ${os.arch()}`,
    distro: osRelease.match(/^PRETTY_NAME="?([^"\n]+)"?/m)?.[1] ?? null,
    node: process.version,
    as: ver("as"),
    ld: ver("ld"),
    prettier: JSON.parse(fs.readFileSync(path.join(ROOT, "node_modules/prettier/package.json"), "utf8")).version,
    repo: { commit: repoHead, dirty: repoHead ? Boolean(git(ROOT, "status", "--porcelain")) : null, src_tree_sha256: tree.digest("hex") },
    rust_baseline: {
      prettier_clone_commit: git(path.join(ROOT, "ref/prettier"), "rev-parse", "HEAD"),
      prettier_clone_tag: git(path.join(ROOT, "ref/prettier"), "describe", "--tags"),
      rust_anything_commit: git(path.join(ROOT, "ref/rust-anything"), "rev-parse", "HEAD"),
      rustc: ver("rustc"),
      cargo: ver("cargo"),
      build_profile: "cargo build --release in ref/prettier/rust/app (see bench/rust-baseline.md)",
      app_crate_has_release_profile: /^\[profile\.release\]/m.test(cargoToml),
      lto: /^\[profile\.release\][^[]*lto\s*=\s*(true|"fat"|"thin")/m.test(cargoToml),
    },
    corpus: Object.fromEntries(["ms", "Fuse", "json-server"].map((d) => {
      const dir = path.join(ROOT, "corpus/real", d);
      return [d, { tag: git(dir, "describe", "--tags", "--exact-match"), commit: git(dir, "rev-parse", "HEAD") }];
    })),
    tools: { strace: ver("strace", ["-V"]), perf: which("perf") ? ver("perf", ["--version"]) : null, hyperfine: which("hyperfine") ? ver("hyperfine") : null },
  };
}

// ---- binaries
function elfInfo(file) {
  const b = fs.readFileSync(file);
  const info = { sha256: sha256(b), size_bytes: b.length, linkage: null, interpreter: null };
  if (b.readUInt32BE(0) !== 0x7f454c46 || b[4] !== 2) return { ...info, linkage: "not a 64-bit ELF file" };
  const phoff = Number(b.readBigUInt64LE(0x20)), phentsize = b.readUInt16LE(0x36), phnum = b.readUInt16LE(0x38);
  info.linkage = "static";
  for (let i = 0; i < phnum; i++) {
    const p = phoff + i * phentsize, type = b.readUInt32LE(p);
    if (type === 3) { // PT_INTERP
      const off = Number(b.readBigUInt64LE(p + 8)), sz = Number(b.readBigUInt64LE(p + 32));
      info.interpreter = b.subarray(off, off + sz).toString().replace(/\0+$/, "");
    }
    if (type === 2) info.linkage = "dynamic"; // PT_DYNAMIC
  }
  if (info.interpreter) info.linkage = "dynamic";
  const ldd = info.linkage === "dynamic" ? run("ldd", [file]) : null;
  if (ldd?.status === 0) info.shared_libraries = ldd.stdout.split("\n").map((l) => l.trim().split(/\s/)[0]).filter((l) => l && !l.startsWith("linux-vdso"));
  const strip = run("readelf", ["-S", "-W", file]);
  info.has_symbols = strip.status === 0 ? /\.symtab/.test(strip.stdout) : null;
  return info;
}
function sourceLines() {
  const files = fs.readdirSync(path.join(ROOT, "src")).filter((f) => /\.(s|inc)$/.test(f)).sort();
  const count = (f) => {
    const lines = fs.readFileSync(path.join(ROOT, "src", f), "utf8").split("\n");
    if (lines.at(-1) === "") lines.pop();
    const code = lines.filter((l) => { const t = l.trim(); return t && !t.startsWith("#") && !t.startsWith("//"); }).length;
    return { file: f, lines: lines.length, code_lines: code, generated: GENERATED.has(f) };
  };
  const per = files.map(count);
  const sum = (sel, k) => per.filter(sel).reduce((a, x) => a + x[k], 0);
  const hand = (x) => !x.generated, gen = (x) => x.generated;
  return {
    files: per.length,
    s_files: per.filter((x) => x.file.endsWith(".s")).length,
    inc_files: per.filter((x) => x.file.endsWith(".inc")).length,
    generated_files: [...GENERATED].filter((f) => per.some((x) => x.file === f)),
    hand_written_lines: sum(hand, "lines"),
    hand_written_code_lines: sum(hand, "code_lines"),
    generated_lines: sum(gen, "lines"),
    generated_code_lines: sum(gen, "code_lines"),
    code_lines_rule: "a code line is a line that is not blank and does not start with # or //",
    per_file: per,
  };
}

// ---- correctness
function harnessList(list) {
  const r = run(process.execPath, [path.join(ROOT, "tests/harness.mjs"), ASM, list, "--json"], { cwd: ROOT });
  if (!r.stdout.trim().startsWith("{")) throw new Error(`harness ${list} failed (exit ${r.status}): ${r.stderr.slice(0, 500)}`);
  const h = JSON.parse(r.stdout);
  const cls = { identical: "identical", fallback: "refused", "oracle-error": "oracle_error", DIFFERENT: "different" };
  const cases = h.cases.map((c) => ({ name: c.name, status: cls[c.class], exit: c.status, ...(c.reason ? { reason: c.reason } : {}), ...(c.detail ? { detail: c.detail } : {}) }));
  const counts = { cases: cases.length, identical: 0, refused: 0, oracle_error: 0, different: 0 };
  const hist = (status) => {
    const m = new Map();
    for (const c of cases) if (c.status === status) m.set(c.reason, (m.get(c.reason) ?? 0) + 1);
    return [...m].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1)).map(([reason, n]) => ({ reason, cases: n }));
  };
  for (const c of cases) counts[c.status]++;
  return { list, harness_exit: r.status, wall_ms: h.wall_ms, counts, refusal_reasons: hist("refused"), oracle_error_reasons: hist("oracle_error"), cases };
}
function stage1() {
  const r = run(process.execPath, [path.join(ROOT, "tests/stage1/run.mjs")], { cwd: ROOT, env: { ...process.env, PRETTIER_ASM_BIN: ASM } });
  const rows = [];
  for (const l of r.stdout.split("\n")) {
    const m = l.match(/^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/);
    if (m && !l.startsWith(" ")) rows.push({ kind: m[1].trim(), identical: +m[2], refused: +m[3] - +m[4], oracle_error: +m[4], different: +m[5] });
  }
  const total = rows.find((x) => x.kind === "total");
  if (!total) throw new Error(`stage1: no total line (exit ${r.status}): ${r.stderr.slice(0, 500)}`);
  return { exit: r.status, wall_ms: r.ms, rows: rows.filter((x) => x !== total), total,
    note: "refused counts exit 3 where Prettier formats; oracle_error counts exit 3 where Prettier exits non-zero" };
}
function sweep() {
  const f = path.join(TMP, "sweep.json");
  fs.rmSync(f, { force: true });
  const r = run(process.execPath, [path.join(ROOT, "tests/stage3/printer/sweep.mjs"), ASM, "--json", f], { cwd: ROOT });
  if (!fs.existsSync(f)) throw new Error(`sweep wrote no JSON (exit ${r.status}): ${r.stderr.slice(0, 500)}`);
  return { exit: r.status, wall_ms: r.ms, ...JSON.parse(fs.readFileSync(f, "utf8")) };
}

// ---- mutants: each script prints its own format; every line is read by one of these rules
const MUTANT_RULES = [
  [/^(.+?): total .* -> caught$/, "killed"], [/^(.+?): total .* -> NOT CAUGHT$/, "survived"],      // stage1
  [/^(\S+)\s+DIFFERENT \d+\s+NOT CAUGHT$/, "survived"], [/^(\S+)\s+DIFFERENT [1-9]\d*$/, "killed"], // config
  [/^(\S+): (?:the text to mutate is not in .* exactly once|build failed)$/, "not_applied"],
  [/^caught: (.+?)(?: \(by .*\))?$/, "killed"], [/^MISSED: (.+)$/, "survived"],                       // infra
  [/^caught {2}(.+): \d+ DIFFERENT$/, "killed"], [/^MISSED {2}(.+): \d+ DIFFERENT$/, "survived"],      // parser
  [/^MUTANT NOT APPLIED(?: \(pattern not found once\))?: (.+)$/, "not_applied"], [/^MUTANT DID NOT BUILD: (.+)$/, "not_applied"],
  [/^killed (.+) by .*$/, "killed"], [/^ {2}survived: (.+)$/, "survived"],                          // comments, VERBOSE=1
  [/^killed: (.+) \(((?:\d+ DIFFERENT, first|refusals only: ).*)\)$/, "killed"], [/^SURVIVED: (.+)$/, "survived"], // ts-mutants
];
// The comments script names its mutants by kind; its summary lines count them per kind.
const kindOf = (script, name) => !script.includes("/comments/") ? null
  : /^pjs_comment_print\.s: /.test(name) ? "print" : /: drop /.test(name) ? "deletion" : /: swap /.test(name) ? "swap" : "condition";
function mutants() {
  const scripts = [];
  for (const s of MUTANT_SCRIPTS) {
    const file = path.join(ROOT, s);
    if (!fs.existsSync(file)) { scripts.push({ script: s, present: false }); continue; }
    log(`mutants: ${s}`);
    const r = run(process.execPath, [file], { cwd: ROOT, env: { ...process.env, VERBOSE: "1" }, timeout: 3_600_000 });
    const list = [];
    for (const l of r.stdout.split("\n")) {
      for (const [re, outcome] of MUTANT_RULES) {
        const m = l.match(re);
        if (!m) continue;
        const eq = outcome === "survived" ? m[1].match(/^(.*) \(equivalent: (.*)\)$/) : null;
        const name = eq ? eq[1] : m[1];
        list.push({ name, outcome, ...(kindOf(s, name) ? { kind: kindOf(s, name) } : {}), ...(eq ? { equivalent: eq[2] } : {}), ...(m[2] ? { killed_by: m[2] } : {}) });
        break;
      }
    }
    const summaries = r.stdout.split("\n").filter((l) => /\b\d+ of \d+ (killed|caught)\b/.test(l));
    const n = (o) => list.filter((x) => x.outcome === o).length;
    let summaryTotal = null, summaryKilled = null;
    if (summaries.length) {
      summaryKilled = 0; summaryTotal = 0;
      for (const l of summaries) { const m = l.match(/(\d+) of (\d+)/); summaryKilled += +m[1]; summaryTotal += +m[2]; }
    }
    scripts.push({
      script: s, present: true, exit: r.status, signal: r.signal ?? null, wall_ms: r.ms,
      total: list.length, killed: n("killed"), survived: n("survived"), not_applied: n("not_applied"),
      survived_equivalent: list.filter((x) => x.equivalent).length,
      summary_lines: summaries,
      summary_agrees: summaryTotal === null ? null : summaryTotal === list.length && summaryKilled === n("killed"),
      crashed: r.status !== 0 && r.status !== 1 || (r.status === 1 && list.length === 0),
      error: (r.status !== 0 && list.length === 0) ? firstLine(r.stderr) || firstLine(r.stdout) : null,
      mutants: list,
    });
  }
  return { scripts };
}

// ---- performance: bench/cli.mjs, the three contenders plus two process floors
function benchCli(list, contenders, { reps: n, noCheck = [], extra = [] }) {
  const args = [path.join(ROOT, "bench/cli.mjs"), list, ...contenders, "--reps", String(n), "--json", ...extra];
  if (noCheck.length) args.push("--no-check", noCheck.join(","));
  if (allowMismatch) args.push("--allow-mismatch");
  return run(process.execPath, args, { cwd: ROOT, timeout: 4 * 3_600_000 });
}
const CONTENDERS = [
  { name: "prettier", label: "Prettier 3.6.2 CLI (Node)", spec: `prettier=node ${rel(PRETTIER_CLI)}` },
  { name: "rust", label: "Rust port (prettier-rs front door)", spec: `rust=${rel(RUST_BIN)}` },
  { name: "asm", label: "asm (this repository)", spec: `asm=${rel(ASM)}` },
];
const FLOORS = [
  { name: "floor_static", label: "exit(0), static, no libc", spec: `floor_static=${rel(FLOOR)}` },
  { name: "floor_dynamic", label: "/bin/true, dynamic", spec: "floor_dynamic=/bin/true" },
];
function performance() {
  const r = benchCli("real", [...CONTENDERS, ...FLOORS].map((c) => c.spec), { reps, noCheck: FLOORS.map((f) => f.name) });
  if (r.status !== 0) {
    console.error(r.stderr);
    console.error(`record: bench/cli.mjs refused to time the contenders (exit ${r.status}).` +
      (allowMismatch ? "" : " A contender's output differs from Prettier; see above. --allow-mismatch drops those files for every contender."));
    process.exit(1);
  }
  const j = JSON.parse(r.stdout);
  if (j.cases === 0) { console.error("record: no file is left to time after dropping mismatches"); process.exit(1); }
  const byName = new Map(realCases.map((c) => [c.name, c]));
  const files = j.case_names.map((name, ci) => {
    const c = byName.get(name), fp = filepathOf(c), bytes = Buffer.byteLength(c.stdin);
    const nl = (c.stdin.match(/\n/g) ?? []).length;
    return { name, path: fp, ext: path.extname(fp).slice(1), input_bytes: bytes, input_lines: nl + (c.stdin.length && !c.stdin.endsWith("\n") ? 1 : 0),
      rep_ms: Object.fromEntries(j.contenders.map((k) => [k.name, k.case_rep_ms[ci]])) };
  });
  const all = [...CONTENDERS, ...FLOORS];
  return {
    tool: "bench/cli.mjs",
    method: "one process per file, the file on stdin with --stdin-filepath, spawnSync timed with process.hrtime; untimed check pass first; contender order rotates each rep",
    reps: j.reps, cases: j.cases, dropped_cases: j.dropped, mismatches: j.mismatches, allow_mismatch: allowMismatch,
    load_start: { load_1min: j.loadavg[0] }, load_end: { load_1min: j.loadavg_end[0] },
    contenders: j.contenders.map((k) => ({ name: k.name, label: all.find((c) => c.name === k.name).label, command: k.label, output_checked: k.checked, rep_totals_ms: k.rep_totals_ms })),
    files,
  };
}

// Untimed: which of the 59 the Rust front door formats itself (its fallback log), and which asm refuses.
function nativeCoverage(correctness) {
  const logFile = path.join(TMP, "rust-fallback.log");
  const perFile = [];
  for (const c of realCases) {
    fs.writeFileSync(logFile, "");
    const r = spawnSync(RUST_BIN, c.args, { input: c.stdin, cwd: EMPTY, env: { ...process.env, RUST_ANYTHING_FALLBACK_LOG: logFile }, maxBuffer: 1 << 28 });
    perFile.push({ name: c.name, rust_fell_back: fs.readFileSync(logFile, "utf8").trim().length > 0, rust_exit: r.status });
  }
  const asmReal = correctness.lists.real.cases;
  return {
    rust_formatted_itself: perFile.filter((x) => !x.rust_fell_back).length,
    rust_fell_back: perFile.filter((x) => x.rust_fell_back).map((x) => x.name),
    asm_formatted_itself: asmReal.filter((c) => c.status === "identical").length,
    asm_refused: asmReal.filter((c) => c.status !== "identical").map((c) => c.name),
    method: "Rust: RUST_ANYTHING_FALLBACK_LOG gets a line when the front door runs Node; asm: the harness run without PRETTIER_ASM_FALLBACK",
  };
}

// ---- resources: peak RSS and CPU time per file, syscalls on one file, perf counters
const contenderCmd = (name) => ({ prettier: [process.execPath, PRETTIER_CLI], rust: [RUST_BIN], asm: [ASM], floor_static: [FLOOR] })[name];
function rusageOne(name, c) {
  const out = path.join(TMP, "rusage.txt"), [cmd, ...pre] = contenderCmd(name);
  fs.rmSync(out, { force: true });
  const r = spawnSync(RUSAGE, [out, cmd, ...pre, ...c.args], { input: c.stdin, cwd: EMPTY, maxBuffer: 1 << 28 });
  if (r.status !== 0 || !fs.existsSync(out)) throw new Error(`rusage ${name} ${c.name}: exit ${r.status}`);
  const [first, ...rollup] = fs.readFileSync(out, "utf8").split("\n");
  const kv = Object.fromEntries(first.trim().split(" ").map((x) => x.split("=")).map(([k, v]) => [k, Number(v)]));
  if (kv.status !== 0) throw new Error(`${name} exits with wait status ${kv.status} on ${c.name}`);
  const rssExitKib = Number(rollup.join("\n").match(/^Rss:\s+(\d+) kB$/m)?.[1]);
  if (!Number.isFinite(rssExitKib)) throw new Error(`rusage ${name} ${c.name}: no smaps_rollup`);
  return { peak_rss_bytes: Math.max(kv.maxrss_kb, rssExitKib) * 1024, maxrss_bytes: kv.maxrss_kb * 1024, rss_at_exit_bytes: rssExitKib * 1024,
    user_cpu_ms: kv.utime_us / 1000, sys_cpu_ms: kv.stime_us / 1000 };
}
function straceOne(name, c) {
  if (!which("strace")) return { available: false, reason: "strace is not installed" };
  const out = path.join(TMP, `strace-${name}.txt`), [cmd, ...pre] = contenderCmd(name);
  const r = spawnSync("strace", ["-c", "-f", "-o", out, cmd, ...pre, ...c.args], { input: c.stdin, cwd: EMPTY, maxBuffer: 1 << 28 });
  if (r.status !== 0) return { available: false, reason: `strace exit ${r.status}: ${firstLine(r.stderr?.toString())}` };
  const rows = [];
  for (const l of fs.readFileSync(out, "utf8").split("\n")) {
    const t = l.trim().split(/\s+/);
    if (t.length < 5 || !/^\d/.test(t[0]) || !/^\d+$/.test(t[3])) continue;
    rows.push({ syscall: t.at(-1), calls: Number(t[3]), errors: t.length === 6 ? Number(t[4]) : 0 });
  }
  const total = rows.find((x) => x.syscall === "total");
  return { available: true, total_calls: total?.calls ?? null, total_errors: total?.errors ?? null,
    by_syscall: rows.filter((x) => x !== total).sort((a, b) => b.calls - a.calls || (a.syscall < b.syscall ? -1 : 1)) };
}
function writeSetScript() {
  // A shell loop over the 59 real files, for perf stat and hyperfine: run-set.sh <command...>
  const dir = path.join(TMP, "inputs");
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  const lines = ["#!/bin/sh", "# Runs the command on each of the 59 real files, one process per file, stdout discarded.", `cd ${JSON.stringify(EMPTY)} || exit 1`];
  realCases.forEach((c, i) => {
    const f = path.join(dir, `${i}.in`);
    fs.writeFileSync(f, c.stdin);
    lines.push(`"$@" --stdin-filepath ${JSON.stringify(filepathOf(c))} < ${JSON.stringify(f)} > /dev/null || exit 1`);
  });
  const script = path.join(TMP, "run-set.sh");
  fs.writeFileSync(script, lines.join("\n") + "\n", { mode: 0o755 });
  return script;
}
function perfStat(script) {
  if (!which("perf")) return { available: false, reason: "perf is not installed" };
  const res = {};
  for (const name of ["rust", "asm", "floor_static"]) {
    const out = path.join(TMP, `perf-${name}.csv`);
    const r = run("perf", ["stat", "-x", ",", "-e", "instructions:u,cycles:u,instructions:k,cycles:k", "-o", out, "--", "sh", script, ...contenderCmd(name)]);
    if (r.status !== 0) return { available: false, reason: `perf stat exit ${r.status}: ${firstLine(r.stderr)}` };
    const counters = {};
    for (const l of fs.readFileSync(out, "utf8").split("\n")) {
      const t = l.split(",");
      if (t.length > 3 && /^\d+$/.test(t[0])) counters[t[2].replace(":", "_")] = Number(t[0]);
      else if (t.length > 3 && /not (supported|counted)/.test(t[0])) return { available: false, reason: `perf: ${t[2]} ${t[0]}` };
    }
    res[name] = counters;
  }
  return { available: true, scope: "the shell loop over the 59 files, sh included (floor_static shows the loop's own share)", counters: res };
}
function resources() {
  const rep = realCases.find((c) => filepathOf(c) === REPRESENTATIVE);
  if (!rep) throw new Error(`${REPRESENTATIVE} is not in the real list`);
  const names = ["prettier", "rust", "asm", "floor_static"];
  const perFile = realCases.map((c) => ({ name: c.name, ...Object.fromEntries(names.map((n) => [n, rusageOne(n, c)])) }));
  const syscalls = Object.fromEntries(names.map((n) => [n, straceOne(n, rep)]));
  const script = writeSetScript();
  return {
    representative_file: REPRESENTATIVE,
    representative_bytes: Buffer.byteLength(rep.stdin),
    cwd_depth: EMPTY.split("/").filter(Boolean).length,
    rusage: { tool: "bench/tools/rusage.s: fork, ptrace, execve, wait4", peak_rss_rule: "the larger of ru_maxrss and the Rss line of /proc/<pid>/smaps_rollup read when the process calls exit; ru_maxrss reads low by up to a few hundred KiB on small processes, and Rss at exit misses memory freed before exit",
      per_file: perFile },
    syscalls: { tool: "strace -c -f", file: REPRESENTATIVE, ...syscalls },
    perf: perfStat(script),
  };
}

// ---- hyperfine cross-check
function hyperfine() {
  if (!which("hyperfine")) return { available: false, reason: "hyperfine is not installed" };
  const script = path.join(TMP, "run-set.sh"), out = path.join(TMP, "hyperfine.json");
  const q = (a) => a.map((x) => `'${x}'`).join(" ");
  const cmds = ["prettier", "rust", "asm", "floor_static"].map((n) => `sh ${q([script, ...contenderCmd(n)])}`);
  const r = run("hyperfine", ["-N", "--warmup", "1", "--runs", String(Math.max(3, Math.min(reps, 10))), "--export-json", out, ...cmds]);
  if (r.status !== 0) return { available: false, reason: `hyperfine exit ${r.status}: ${firstLine(r.stderr)}` };
  const j = JSON.parse(fs.readFileSync(out, "utf8"));
  return { available: true, version: firstLine(run("hyperfine", ["--version"]).stdout), method: "hyperfine -N on a shell loop over the 59 files; outputs are not checked here (bench/cli.mjs checked them)",
    results: j.results.map((x, i) => ({ name: ["prettier", "rust", "asm", "floor_static"][i], mean_s: x.mean, stddev_s: x.stddev, median_s: x.median, min_s: x.min, max_s: x.max, runs_s: x.times })) };
}

// ---- upstream method: rust-anything's own bench/cli.mjs, unchanged, from ref/
function upstream(runs) {
  if (!fs.existsSync(UPSTREAM_SCRIPT) || !fs.existsSync(UPSTREAM_PRETTIER)) return { available: false, reason: "ref/rust-anything or ref/prettier/dist is missing" };
  const names = path.join(TMP, "upstream-names.txt");
  fs.writeFileSync(names, realCases.map((c) => c.name).join("\n") + "\n");
  const inputs = path.join(ROOT, "corpus/cases/real.jsonl");
  const res = [];
  for (let i = 0; i < runs; i++) for (const [name, frontDoor] of [["rust", RUST_BIN], ["asm", ASM]]) {
    const load = load1();
    const r = run(process.execPath, [UPSTREAM_SCRIPT, UPSTREAM_PRETTIER, frontDoor, inputs, names], { cwd: EMPTY, timeout: 3_600_000 });
    if (r.status !== 0) throw new Error(`upstream script (${name}): exit ${r.status} ${r.stderr.slice(0, 300)}`);
    const j = JSON.parse(r.stdout.trim().split("\n").at(-1));
    res.push({ run: i + 1, front_door: name, load_1min: load, cases: j.cases, identical: j.identical, prettier_ms: j.prettier_ms, front_door_ms: j.front_door_ms });
  }
  return {
    available: true,
    script: rel(UPSTREAM_SCRIPT),
    script_sha256: sha256(fs.readFileSync(UPSTREAM_SCRIPT)),
    command: "node <script> ref/prettier/dist/prettier/bin/prettier.cjs <front door> corpus/cases/real.jsonl <names>, from an empty directory",
    script_changed: false,
    method: "each run times Prettier against one front door, file by file; asm takes the front door's slot in its own runs; identical counts stdout equal to Prettier's; totals are rounded to whole ms by the script",
    published: published(),
    runs: res,
  };
}
// Their own figure for the 59 files, read from their docs so it is quoted, not typed.
function published() {
  const f = path.join(ROOT, "ref/rust-anything/docs/real-world.md");
  if (!fs.existsSync(f)) return null;
  const t = fs.readFileSync(f, "utf8");
  const row = t.match(/^\| CLI, the 59 real repository files \| ([\d.]+) s \/ ([\d.]+) s \| ([\d.]+) s \/ ([\d.]+) s \|/m);
  const machine = t.match(/^Benchmark: (Apple M4 \([^)]*\)), (macOS [\d.]+), (Node [\d.]+)/m);
  if (!row || !machine) return null;
  return { prettier_s: Number(row[1]), front_door_s: Number(row[3]), runs_prettier_s: [Number(row[1]), Number(row[2])], runs_front_door_s: [Number(row[3]), Number(row[4])],
    machine: `${machine[1]}, ${machine[2]}, ${machine[3]}`, source: "ref/rust-anything/docs/real-world.md, the Prettier benchmark table" };
}

// ---- go
const env = collectEnvironment();
save("environment.json", env);

save("binary.json", {
  asm: { source: rel(asmSource), recorded_copy: rel(ASM), ...elfInfo(ASM) },
  rust: { path: rel(RUST_BIN), ...elfInfo(RUST_BIN) },
  floor_static: { path: rel(FLOOR), source: "bench/tools/floor.s", ...elfInfo(FLOOR) },
  source: sourceLines(),
});

log("correctness: harness lists");
const lists = {};
for (const l of LISTS) { lists[l] = harnessList(l); log(`  ${l}: ${JSON.stringify(lists[l].counts)}`); }
log("correctness: stage 1");
const correctness = { binary: rel(ASM), lists, stage1: stage1() };
save("correctness.json", correctness);

if (skipSweep) save("sweep.json", { skipped: true });
else { log("option sweep"); save("sweep.json", { skipped: false, ...sweep() }); }

if (skipMutants) save("mutants.json", { skipped: true });
else { log("mutants"); save("mutants.json", { skipped: false, ...mutants() }); }

log(`performance: ${reps} reps`);
const perf = performance();
perf.native = nativeCoverage(correctness);
save("performance.json", perf);

log("resources: rusage, strace, perf");
save("resources.json", resources());

log("hyperfine");
save("hyperfine.json", quick ? { available: false, reason: "skipped in a quick run" } : hyperfine());

log("upstream method");
save("upstream.json", upstream(quick ? 1 : Math.min(reps, 5)));

const loadEnd = loadNow();
save("run.json", {
  started_utc: runId, finished_utc: new Date().toISOString(), duration_s: (Date.now() - startedMs) / 1000,
  load_start: loadStart, load_end: loadEnd, load_limit_1min: 1.0, forced: force && loadStart.load_1min > 1.0,
  flags: { reps, quick, skip_sweep: skipSweep, skip_mutants: skipMutants, force, allow_mismatch: allowMismatch, asm_bin: rel(asmSource) },
  command: `node bench/record.mjs ${process.argv.slice(2).join(" ")}`.trim(),
  files: { ...written },
});
log(`done in ${((Date.now() - startedMs) / 1000).toFixed(0)} s; load ${loadStart.load_1min.toFixed(2)} at start, ${loadEnd.load_1min.toFixed(2)} at end`);
