#!/usr/bin/env bash
# Builds the Rust front door of rust-anything's prettier-rs (the baseline to beat) and measures it
# against Prettier 3.6.2's CLI on the 59 real files. Everything goes under ref/ (gitignored).
#
#   bench/build-rust-baseline.sh build    # Prettier clone, yarn install/build, cargo build, real repos, cases
#   bench/build-rust-baseline.sh verify   # 59 files: identical output? formatted in Rust or fell back?
#   bench/build-rust-baseline.sh bench    # 5 runs each: cli.mjs method and a plain shell loop
#   bench/build-rust-baseline.sh stats    # per-file min/median/max from the last bench
#   bench/build-rust-baseline.sh floor    # the same timing on /bin/true: the cost of a process
#   bench/build-rust-baseline.sh all      # all of the above
#
# REF overrides the ref/ folder. Needs git, cargo, nvm with Node 22, and strace for `bench`.
# Each step is skipped when its output is already there, so the script can be run again.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
REF=${REF:-$HERE/ref}
PRETTIER=$REF/prettier                        # Prettier clone at 3.6.2; prettier-rs goes in rust/
RA=$REF/rust-anything                         # github.com/erkamyaman/rust-anything (MIT)
REAL=$REF/real                                # ms, Fuse, json-server at the tags prettier-rs used
WORK=$REF/bench-work                          # cases, helper scripts, results
BIN=$PRETTIER/rust/app/target/release/prettier
CLI=$PRETTIER/dist/prettier/bin/prettier.cjs  # Prettier 3.6.2 built from the clone
EMPTY=${EMPTY:-$(mktemp -d)}                  # cwd for every run, so no config applies

# shellcheck disable=SC1091
source "$HOME/.nvm/nvm.sh" >/dev/null
nvm use 22 >/dev/null
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

clone() { # url tag dir
  [ -d "$3/.git" ] || git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$3"
}

build() {
  mkdir -p "$REF" "$REAL" "$WORK"
  clone https://github.com/erkamyaman/rust-anything.git main "$RA"
  clone https://github.com/prettier/prettier.git 3.6.2 "$PRETTIER"

  # Their README: corepack yarn install, corepack yarn build --no-minify.
  if [ ! -f "$PRETTIER/dist/prettier/bin/prettier.cjs" ]; then
    (cd "$PRETTIER" && corepack yarn install && corepack yarn build --no-minify)
  fi

  # The front door falls back to `node <root>/node_modules/prettier/bin/prettier.cjs`, with
  # <root> = rust/app/../.. baked in at compile time. yarn install puts Prettier 3.6.1 there (the
  # repository's own devDependency); DECISIONS.md says the built dist goes there instead.
  if ! grep -q '"version": "3.6.2"' "$PRETTIER/node_modules/prettier/package.json"; then
    rm -rf "$PRETTIER/node_modules/.prettier-from-yarn"
    mv "$PRETTIER/node_modules/prettier" "$PRETTIER/node_modules/.prettier-from-yarn"
    cp -a "$PRETTIER/dist/prettier" "$PRETTIER/node_modules/prettier"
  fi

  # Their README: put the prettier-rs folder at rust/ of the clone. Copied so ref/rust-anything
  # stays as cloned.
  [ -d "$PRETTIER/rust" ] || cp -a "$RA/demo/real-world/prettier-rs" "$PRETTIER/rust"
  (cd "$PRETTIER/rust/app" && cargo build --release)

  clone https://github.com/vercel/ms.git 3.0.0-canary.1 "$REAL/ms"
  clone https://github.com/krisk/Fuse.git v7.1.0 "$REAL/Fuse"
  clone https://github.com/typicode/json-server.git v1.0.0-beta.3 "$REAL/json-server"

  # Their gen-inputs.mjs writes every CLI case; the real files are the ones named real-*.
  (cd "$WORK" && node "$PRETTIER/rust/scripts/gen-inputs.mjs" "$PRETTIER" "$REAL" all-inputs.jsonl)
  grep '"name":"real-' "$WORK/all-inputs.jsonl" > "$WORK/real.jsonl"
  node -e 'for (const l of require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean)) console.log(JSON.parse(l).name)' \
    "$WORK/real.jsonl" > "$WORK/names.txt"
  node -e 'for (const l of require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean)) console.log(JSON.parse(l).args.at(-1).slice(5))' \
    "$WORK/real.jsonl" > "$WORK/real-files.txt"
  echo "real files: $(wc -l < "$WORK/real.jsonl")"
}

helpers() {
  cat > "$WORK/verify.mjs" <<'EOF'
// Runs each case through Prettier's CLI and the front door from the current directory and
// compares stdout, stderr and exit code. A line in RUST_ANYTHING_FALLBACK_LOG marks a fallback.
// usage: node verify.mjs <prettier.cjs> <front door> <cases.jsonl> <fallback log>
import fs from "node:fs";
import { spawnSync } from "node:child_process";
const [prettierCli, frontDoor, inputs, logPath] = process.argv.slice(2);
const cases = fs.readFileSync(inputs, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
fs.writeFileSync(logPath, "");
const lines = () => fs.readFileSync(logPath, "utf8").split("\n").filter(Boolean).length;
let identical = 0, fellBack = 0;
for (const c of cases) {
  const a = spawnSync(process.execPath, [prettierCli, ...c.args], { input: c.stdin, timeout: 60_000 });
  const before = lines();
  const b = spawnSync(frontDoor, c.args, {
    input: c.stdin, timeout: 60_000,
    env: { ...process.env, RUST_ANYTHING_FALLBACK_LOG: logPath },
  });
  const same = a.status === b.status && a.stdout.equals(b.stdout) && a.stderr.equals(b.stderr);
  const fb = lines() > before;
  identical += same; fellBack += fb;
  console.log(`${same ? "same" : "DIFF"} ${fb ? "node" : "rust"} ${c.args.at(-1)}`);
}
console.log(JSON.stringify({ cases: cases.length, identical, in_rust: cases.length - fellBack, fell_back: fellBack }));
EOF
  cat > "$WORK/perfile.mjs" <<'EOF'
// bench/cli.mjs's timing (spawnSync per file, hrtime around each) for one command, per file.
// usage: node perfile.mjs <cases.jsonl> <command|node> [args...]
import fs from "node:fs";
import { spawnSync } from "node:child_process";
const [inputs, cmd, ...pre] = process.argv.slice(2);
const cases = fs.readFileSync(inputs, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const ms = [];
for (const c of cases) {
  const start = process.hrtime.bigint();
  const r = spawnSync(cmd === "node" ? process.execPath : cmd, [...pre, ...c.args], { input: c.stdin, timeout: 60_000 });
  ms.push(Number(process.hrtime.bigint() - start) / 1e6);
  if (r.status !== 0) throw new Error(`exit ${r.status} ${c.name}`);
}
console.log(JSON.stringify({ total_ms: ms.reduce((a, b) => a + b, 0), per_file_ms: ms }));
EOF
  cat > "$WORK/stats.mjs" <<'EOF'
// Per-file min/median/max from the perfile.mjs lines in bench.out.
// usage: node stats.mjs <bench.out> <names.txt>
import fs from "node:fs";
const lines = fs.readFileSync(process.argv[2], "utf8").split("\n").filter((l) => /^(node|rust) run/.test(l) && l.includes("{"));
const names = fs.readFileSync(process.argv[3], "utf8").split("\n").filter(Boolean);
const q = (a) => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return { min: s[0], median: s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2, max: s.at(-1) }; };
const f = (x) => x.toFixed(2);
for (const who of ["node", "rust"]) {
  const runs = lines.filter((l) => l.startsWith(who)).map((l) => JSON.parse(l.slice(l.indexOf("{"))).per_file_ms);
  runs.forEach((r, i) => { const s = q(r); console.log(`${who} run ${i + 1}: per-file min ${f(s.min)} median ${f(s.median)} max ${f(s.max)} (${names[r.indexOf(s.max)]})`); });
  const perFileMedian = runs[0].map((_, j) => q(runs.map((r) => r[j])).median);
  const s = q(perFileMedian);
  console.log(`${who} per-file median of ${runs.length} runs: min ${f(s.min)} (${names[perFileMedian.indexOf(s.min)]}) median ${f(s.median)} max ${f(s.max)} (${names[perFileMedian.indexOf(s.max)]})`);
}
EOF
}

verify() {
  helpers
  (cd "$EMPTY" && node "$WORK/verify.mjs" "$CLI" "$BIN" "$WORK/real.jsonl" "$WORK/fallback.log") | tee "$WORK/verify.out" | tail -1
  # The same check from the other side: count execs of node under strace.
  (cd "$EMPTY" && while read -r rel; do
     strace -f -qq -e trace=execve -o "$WORK/execve.tmp" "$BIN" --stdin-filepath "real/$rel" < "$REAL/$rel" > /dev/null
     grep -c 'execve(' "$WORK/execve.tmp"
   done < "$WORK/real-files.txt") | sort | uniq -c | sed 's/^/execve calls per run (count, execs): /'
}

load() { cut -d' ' -f1 /proc/loadavg; }

shell_loop() { # command...
  local t0 t1
  t0=$(date +%s%N)
  while read -r rel; do
    "$@" --stdin-filepath "real/$rel" < "$REAL/$rel" > /dev/null
  done < "$WORK/real-files.txt"
  t1=$(date +%s%N)
  echo $(( (t1 - t0) / 1000000 ))
}

bench() {
  helpers
  cd "$EMPTY"
  local out=$WORK/bench.out
  : > "$out"
  echo "== their bench/cli.mjs, 5 runs" | tee -a "$out"
  for i in 1 2 3 4 5; do
    echo "run $i load $(load) $(node "$PRETTIER/rust/bench/cli.mjs" "$CLI" "$BIN" "$WORK/real.jsonl" "$WORK/names.txt")" | tee -a "$out"
  done
  echo "== same method, one command per pass, per-file times (ms)" | tee -a "$out"
  for i in 1 2 3 4 5; do
    echo "node run $i load $(load) $(node "$WORK/perfile.mjs" "$WORK/real.jsonl" node "$CLI")" >> "$out"
    echo "rust run $i load $(load) $(node "$WORK/perfile.mjs" "$WORK/real.jsonl" "$BIN")" >> "$out"
  done
  grep -E '^(node|rust) run' "$out" | sed -E 's/\{"total_ms":([0-9.]+).*/total_ms \1/'
  echo "== plain bash loop, 5 runs, total ms" | tee -a "$out"
  for i in 1 2 3 4 5; do
    echo "node run $i load $(load) total_ms $(shell_loop node "$CLI")" | tee -a "$out"
  done
  for i in 1 2 3 4 5; do
    echo "rust run $i load $(load) total_ms $(shell_loop "$BIN")" | tee -a "$out"
  done
  echo "== start-up, one small file (Fuse/src/search/index.js)" | tee -a "$out"
  local f=Fuse/src/search/index.js
  strace -c -f -o "$WORK/strace-c.txt" "$BIN" --stdin-filepath "real/$f" < "$REAL/$f" > /dev/null
  strace -f -o "$WORK/strace-full.txt" "$BIN" --stdin-filepath "real/$f" < "$REAL/$f" > /dev/null
  tail -3 "$WORK/strace-c.txt" | tee -a "$out"
  ldd "$BIN" | tee -a "$out"
}

# Per-file min/median/max from the last `bench`.
stats() {
  helpers
  node "$WORK/stats.mjs" "$WORK/bench.out" "$WORK/names.txt"
}

# The cost of starting a process at all: /bin/true with the same arguments and stdin, 3 runs.
floor() {
  helpers
  cd "$EMPTY"
  for i in 1 2 3; do
    echo "/bin/true, cli.mjs method, run $i load $(load) $(node "$WORK/perfile.mjs" "$WORK/real.jsonl" /bin/true |
      node -e 'const r = JSON.parse(require("fs").readFileSync(0, "utf8")); const s = r.per_file_ms.sort((a, b) => a - b); console.log("total_ms", r.total_ms.toFixed(1), "median_ms", s[s.length >> 1].toFixed(2))')"
  done
  for i in 1 2 3; do
    echo "/bin/true, bash loop, run $i load $(load) total_ms $(shell_loop /bin/true)"
  done
}

case ${1:-all} in
  build) build ;;
  verify) verify ;;
  bench) bench ;;
  stats) stats ;;
  floor) floor ;;
  all) build; verify; bench; stats; floor ;;
  *) echo "usage: $0 [build|verify|bench|stats|floor|all]" >&2; exit 2 ;;
esac
