# Results

`make results` runs `node bench/record.mjs`, then `node bench/report.mjs`. The first writes
`data/`, the second reads only `data/` and writes `../RESULTS.md` and `charts/`. Each run
overwrites them; git history is the archive.

`record.mjs` refuses to start when the 1-minute load average is above 1.0, unless given
`--force`. Its other flags: `--reps N` (default 10), `--skip-sweep`, `--skip-mutants`, `--quick`
(3 reps, no sweep, mutants or hyperfine, one upstream-method run), `--allow-mismatch`,
`--asm-bin path` and `--out dir`. It copies the binary to `build/record-tmp/` first, so a rebuild
during the run does not change what is measured.

`report.mjs` stops without writing anything when a data file is missing, carries another run's
`run_id`, has another schema, or does not match the checksum in `run.json`. The same data gives
byte-identical output. `--gif` also renders `charts/headline.gif` and `charts/headline.png` with
headless Chromium, ffmpeg and ImageMagick.

## Data files

Every file has `schema` and `run_id` (the start time in UTC). Units are in the key names: `_ms`,
`_s`, `_bytes`. Paths are relative to the repository root.

| File | What it holds |
| --- | --- |
| `run.json` | start and end time, duration, 1-minute load at start and end, the flags, the command, and the sha256 of every other file. Written last, so a run that stops early leaves no `run.json`. |
| `environment.json` | CPU model, cores, threads, governor, memory, kernel, distribution, Node, `as`, `ld`, Prettier version, the source tree's sha256, the Rust port's commits, `rustc`, build profile and LTO, the corpus tags and commits, and which of strace, perf and hyperfine are installed |
| `binary.json` | sha256, size and linkage of the asm binary, the Rust binary and the floor binary, and line counts of `src/` split into hand-written and generated files |
| `correctness.json` | per list (real, ts-fixtures, js-fixtures, variants, json): counts of identical, refused, oracle_error and different, every case with its status and refusal reason, and the reasons ranked. Also the stage 1 totals per kind. |
| `sweep.json` | `tests/stage3/printer/sweep.mjs --json`: counts per option set, with the cases that differ |
| `mutants.json` | per mutants script: exit code, mutants total, killed, survived, survivors marked equivalent, not applied, and every mutant by name |
| `performance.json` | `bench/cli.mjs --json` on the 59 real files: every rep's total and every file's time in every rep, for Prettier, the Rust port, asm and two process floors; input bytes and lines per file; dropped files and mismatches; which files the Rust port and asm format themselves |
| `resources.json` | per file and contender: peak RSS, `ru_maxrss`, RSS at exit, user and system CPU time (`bench/tools/rusage.s`); system calls per contender on one file (`strace -c -f`); perf counters or why there are none |
| `hyperfine.json` | hyperfine's results on a shell loop over the 59 files, or why it did not run |
| `upstream.json` | rust-anything's own `bench/cli.mjs`, run unchanged, once with the Rust port and once with asm in the front door's slot per run; their published figure, read from their docs |

## Charts

| File | What it shows |
| --- | --- |
| `headline.svg` | the animated card for the README: median total time and peak memory on one file |
| `total.svg` | median total time for the three contenders |
| `per-file.svg` | each file's median time, sorted by Prettier's, log scale |
| `size.svg` | Rust port and asm time against input size |
| `floor.svg` | asm time per file split into the process floor and the work above it |
| `coverage.svg` | identical, refused, Prettier-error and different cases per list |
| `spread.svg` | each rep's total against its contender's median |

`RESULTS.md` has every charted value in its tables.
