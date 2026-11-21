# Results

<img src="results/charts/headline.svg" alt="Format 59 real files, one process per file: Prettier (Node) 4.36 s, Rust port 0.215 s, asm 0.081 s. Peak memory, one file (Fuse/src/search/index.js): Prettier (Node) 65.7 MiB, Rust port 6.44 MiB, asm 0.37 MiB. 59/59 files byte-identical to Prettier 3.6.2." width="820">

Recorded 2026-11-21 02:58:42 UTC by `node bench/record.mjs`. Load average 0.40 at the start and 1.36 at the end. Every number here comes from `results/data/`.

## Headline

| Contender | Median total | Min to max | Per-file median | asm speedup over it |
| --- | ---: | ---: | ---: | ---: |
| Prettier 3.6.2 (Node) | 4.36 s | 4.32 s to 4.39 s | 66.9 ms | 54.0× (52.4× to 56.8×) |
| Rust port | 0.215 s | 0.211 s to 0.221 s | 2.85 ms | 2.66× (2.61× to 2.76×) |
| asm | 0.081 s | 0.077 s to 0.083 s | 1.26 ms | n/a |

Totals are for the 59 real files, one process per file, over 10 reps. The speedup is the ratio of median totals. The range in brackets is the lowest and highest ratio within a single rep. The Rust port over Prettier is 20.3× (19.9× to 20.7×).

Every output was compared byte for byte with Prettier 3.6.2 before the timed reps. On the real list asm formats 59 of 59 files itself and the Rust port formats 59 of 59 itself. Neither runs Node for these files.

<img src="results/charts/total.svg" alt="Total time for the three contenders. The headline table has the values." width="760">

## Environment

- CPU: 13th Gen Intel(R) Core(TM) i9-13900K, 24 cores, 32 threads, max 5800 MHz. Governor `powersave`, energy preference `performance`. Nothing was pinned.
- Memory: 188 GiB. Kernel: Linux 6.12.113+deb13-amd64 x64. Distribution: Debian GNU/Linux 13 (trixie).
- Node v22.21.0. Prettier 3.6.2 from npm. GNU assembler (GNU Binutils for Debian) 2.44. GNU ld (GNU Binutils for Debian) 2.44.
- asm binary: 1,893,360 bytes, static, sha256 `3ef36d3467af6c68`. Source tree sha256 `df2aec493dba9eb8`, no commit.
- asm source: 76 `.s` files and 3 `.inc` files. 51,987 hand-written lines (47,626 not blank or comment) and 6,754 generated lines in `unicode_tables.s` and `ast_types.s`.
- Rust port: rust-anything `dabf50c`, Prettier clone `7a8b05f` (tag 3.6.2), rustc 1.99.1 (58cf8f9c3 2026-10-13). Built with `cargo build --release`; the app crate has no `[profile.release]`, so LTO is off. Binary: 9,127,880 bytes, dynamic (libgcc_s.so.1, libm.so.6, libc.so.6, ld-linux-x86-64.so.2), sha256 `68a3375cfadac923`. bench/rust-baseline.md has the build steps.
- Corpus: ms `3.0.0-canary.1` (`1304f15`), Fuse `v7.1.0` (`8119c18`), json-server `v1.0.0-beta.3` (`6aa56d9`).

## Method

`bench/cli.mjs` starts one process per file with the file on stdin and `--stdin-filepath real/<path>`, as prettier-rs's own `bench/cli.mjs` does. It times each `spawnSync` with `process.hrtime`. All runs start in an empty temporary directory, so no config or ignore file applies.

Before the timed reps, every contender's output for every file is compared byte for byte with Prettier 3.6.2's, exit code included. A mismatch stops the run unless `--allow-mismatch` is given. This pass also warms the file cache.

Each rep runs all files. For each file the contenders run one after another, and the order rotates each rep. A rep total is the sum over the files. The median, min and max are over the 10 rep totals.

The process floors run in the same loop with their output unchecked: a static binary that only calls `exit(0)` (`bench/tools/floor.s`) and `/bin/true`, which is dynamically linked like the Rust port.

## Correctness

`tests/harness.mjs` runs each case through the asm binary without a fallback and compares it with Prettier 3.6.2's cached output. Each case lands in one class:

- identical: same exit code and stdout as Prettier.
- refused: asm exits 3 with `unsupported: <reason>` where Prettier formats the case. These cases are not formatted by asm.
- Prettier errors too: Prettier rejects the input and asm exits 3, as it must.
- DIFFERENT: anything else, including a crash or a timeout.

| List | Cases | Identical | Refused | Prettier errors too | DIFFERENT |
| --- | ---: | ---: | ---: | ---: | ---: |
| real | 59 | 59 (100.0%) | 0 (0.0%) | 0 (0.0%) | 0 |
| ts-fixtures | 554 | 492 (88.8%) | 44 (7.9%) | 18 (3.2%) | 0 |
| js-fixtures | 971 | 654 (67.4%) | 225 (23.2%) | 92 (9.5%) | 0 |
| variants | 1,200 | 894 (74.5%) | 210 (17.5%) | 96 (8.0%) | 0 |
| json | 1,478 | 1018 (68.9%) | 1 (0.1%) | 459 (31.1%) | 0 |

Of the cases Prettier formats, asm formats 100.0% on real, 91.8% on ts-fixtures, 74.4% on js-fixtures, 81.0% on variants, 99.9% on json.

<img src="results/charts/coverage.svg" alt="Outcome per case list as stacked bars. The correctness table has the values." width="760">

Stage 1 (`tests/stage1/run.mjs`, JSON fixtures under four file names and the edge cases): 2,584 identical, 18 refused, 586 where Prettier errors too, 0 DIFFERENT.

| Kind | Identical | Refused | Prettier errors too | DIFFERENT |
| --- | ---: | ---: | ---: | ---: |
| .json | 52 | 0 | 57 | 0 |
| .jsonc | 55 | 0 | 54 | 0 |
| .json5 | 52 | 0 | 57 | 0 |
| package.json | 39 | 1 | 69 | 0 |
| edge json | 672 | 4 | 12 | 0 |
| edge jsonc | 672 | 4 | 12 | 0 |
| edge json5 | 672 | 4 | 12 | 0 |
| edge package.json | 370 | 5 | 313 | 0 |

### Refusal reasons

The 15 most common `unsupported:` reasons per list, for cases Prettier formats.

real: no refusals.

ts-fixtures (44 refused, 13 distinct reasons):

| Cases | Reason |
| ---: | --- |
| 16 | no ported parser for this file name |
| 8 | comment in a method's signature (typescript-estree's method value node attaches it differently) |
| 7 | printer: embedded language in a template literal (embed) |
| 2 | comment in or next to an optional chain (typescript-estree's ChainExpression) |
| 2 | syntax error: incompatible modifiers |
| 2 | using declaration (explicit resource management) |
| 1 | syntax error: duplicate modifier |
| 1 | syntax error: element after a rest element |
| 1 | syntax error: identifier expected |
| 1 | syntax error: modifiers out of order |
| 1 | syntax error: type expected |
| 1 | syntax error: unexpected token |
| 1 | syntax error: yield or await outside a generator or async function |

js-fixtures (225 refused, 20 distinct reasons):

| Cases | Reason |
| ---: | --- |
| 92 | JSX |
| 38 | printer: embedded language in a template literal (embed) |
| 25 | using declaration (explicit resource management) |
| 13 | import phase or reflection |
| 10 | bind operator |
| 8 | pipeline operator |
| 6 | module expression |
| 5 | do expression |
| 5 | optional chain as an assignment target |
| 4 | private name in a pattern (destructuring private) |
| 4 | private name in an object or pattern (destructuring private) |
| 3 | V8 intrinsic |
| 2 | no ported parser for this file name |
| 2 | partial application |
| 2 | syntax error: export (or the exportDefaultFrom proposal) |

variants (210 refused, 13 distinct reasons):

| Cases | Reason |
| ---: | --- |
| 72 | JSX |
| 36 | printer: embedded language in a template literal (embed) |
| 24 | using declaration (explicit resource management) |
| 12 | comment in a method's signature (typescript-estree's method value node attaches it differently) |
| 12 | import phase or reflection |
| 12 | no ported parser for this file name |
| 6 | V8 intrinsic |
| 6 | bind operator |
| 6 | module expression |
| 6 | private name in a pattern (destructuring private) |
| 6 | private name in an object or pattern (destructuring private) |
| 6 | syntax error: export (or the exportDefaultFrom proposal) |
| 6 | syntax error: incompatible modifiers |

json (1 refused, 1 distinct reasons):

| Cases | Reason |
| ---: | --- |
| 1 | number needs a full double conversion (json-stringify) |

## Option sweep

`tests/stage3/printer/sweep.mjs` runs every JS and TS case of js-fixtures, real, ts-fixtures (1,565 cases) under each option set, against Prettier's `format()` in process. Cases Prettier rejects under a set are counted apart.

| Options | Identical | Refused | Prettier errors | DIFFERENT |
| --- | ---: | ---: | ---: | ---: |
| (defaults) | 1,205 | 251 | 109 | 0 |
| `--print-width 40` | 1,205 | 251 | 109 | 0 |
| `--print-width 120` | 1,205 | 251 | 109 | 0 |
| `--print-width 20` | 1,205 | 251 | 109 | 0 |
| `--no-semi` | 1,205 | 251 | 109 | 0 |
| `--single-quote` | 1,205 | 251 | 109 | 0 |
| `--trailing-comma none` | 1,205 | 251 | 109 | 0 |
| `--trailing-comma es5` | 1,205 | 251 | 109 | 0 |
| `--use-tabs` | 1,204 | 251 | 110 | 0 |
| `--tab-width 4` | 1,205 | 251 | 109 | 0 |
| `--arrow-parens avoid` | 1,205 | 251 | 109 | 0 |
| `--no-bracket-spacing` | 1,205 | 251 | 109 | 0 |
| `--bracket-same-line` | 1,205 | 251 | 109 | 0 |
| `--quote-props consistent` | 1,205 | 251 | 109 | 0 |
| `--quote-props preserve` | 1,206 | 250 | 109 | 0 |
| `--object-wrap collapse` | 1,205 | 251 | 109 | 0 |
| `--experimental-operator-position start` | 1,205 | 251 | 109 | 0 |
| `--experimental-ternaries` | 1,205 | 251 | 109 | 0 |
| `--experimental-ternaries --print-width 40` | 1,205 | 251 | 109 | 0 |

Total: 22,895 identical, 4,768 refused, 0 DIFFERENT.

## Mutation tests

Each script builds deliberately broken binaries and checks that the tests report them. A killed mutant was reported. A survivor was not.

| Script | Mutants | Killed | Survived | Survived, marked equivalent | Not applied |
| --- | ---: | ---: | ---: | ---: | ---: |
| `tests/stage1/mutants.mjs` | 2 | 2 | 0 | 0 | 0 |
| `tests/stage3/config/mutants.mjs` | 6 | 6 | 0 | 0 | 0 |
| `tests/stage3/infra/mutants.mjs` | 12 | 12 | 0 | 0 | 0 |
| `tests/stage3/parser/mutants.mjs` | 7 | 7 | 0 | 0 | 0 |
| `tests/stage3/comments/mutants.mjs` | 153 | 102 | 51 | 7 | 0 |
|   deletion | 48 | 43 | 5 | 5 | 0 |
|   swap | 45 | 1 | 44 | 0 | 0 |
|   condition | 55 | 53 | 2 | 2 | 0 |
|   print | 5 | 5 | 0 | 0 | 0 |
| `tests/stage3/printer/ts-mutants.mjs` | 49 | 43 | 6 | 6 | 0 |

In `tests/stage3/printer/ts-mutants.mjs`, 5 of the killed mutants were caught only because a case the unmutated binary formats was refused. They produced no DIFFERENT output.

The comments script expects most swaps to survive: handlers whose conditions never overlap can trade places without effect. Its equivalent mutants carry a reason in the script.

## Per file

Median of 10 reps per file, in ms. The last column is the Rust port's time over asm's.

| File | Bytes | Lines | Prettier | Rust | asm | Rust ÷ asm |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Fuse/src/core/computeScore.js` | 510 | 22 | 64.83 | 2.68 | 1.11 | 2.42× |
| `Fuse/src/core/config.js` | 3,061 | 69 | 66.96 | 3.28 | 1.24 | 2.65× |
| `Fuse/src/core/errorMessages.js` | 600 | 16 | 63.99 | 2.39 | 1.12 | 2.14× |
| `Fuse/src/core/format.js` | 668 | 33 | 64.17 | 2.60 | 1.14 | 2.27× |
| `Fuse/src/core/index.js` | 6,074 | 273 | 90.25 | 5.15 | 1.52 | 3.39× |
| `Fuse/src/core/queryParser.js` | 1,920 | 86 | 75.23 | 3.42 | 1.50 | 2.27× |
| `Fuse/src/core/register.js` | 483 | 18 | 61.58 | 2.57 | 1.21 | 2.12× |
| `Fuse/src/entry.js` | 525 | 21 | 61.18 | 2.46 | 1.21 | 2.03× |
| `Fuse/src/helpers/diacritics.js` | 2,251 | 3 | 60.95 | 2.43 | 1.11 | 2.19× |
| `Fuse/src/helpers/get.js` | 1,279 | 54 | 69.80 | 2.85 | 1.27 | 2.25× |
| `Fuse/src/helpers/types.js` | 1,609 | 64 | 66.25 | 2.81 | 1.08 | 2.59× |
| `Fuse/src/index.d.ts` | 9,863 | 371 | 91.06 | 4.28 | 1.75 | 2.45× |
| `Fuse/src/search/bitap/computeScore.js` | 547 | 27 | 63.74 | 3.15 | 1.14 | 2.75× |
| `Fuse/src/search/bitap/constants.js` | 48 | 2 | 57.63 | 2.92 | 1.23 | 2.38× |
| `Fuse/src/search/bitap/convertMaskToIndices.js` | 688 | 31 | 65.10 | 2.70 | 1.21 | 2.24× |
| `Fuse/src/search/bitap/createPatternAlphabet.js` | 247 | 10 | 62.26 | 2.56 | 1.17 | 2.18× |
| `Fuse/src/search/bitap/index.js` | 3,227 | 140 | 74.67 | 3.68 | 1.46 | 2.51× |
| `Fuse/src/search/bitap/search.js` | 5,232 | 188 | 79.04 | 4.72 | 1.59 | 2.97× |
| `Fuse/src/search/extended/BaseMatch.js` | 392 | 17 | 63.84 | 2.57 | 1.26 | 2.03× |
| `Fuse/src/search/extended/ExactMatch.js` | 547 | 29 | 64.43 | 2.72 | 1.29 | 2.10× |
| `Fuse/src/search/extended/FuzzyMatch.js` | 1,094 | 45 | 65.59 | 2.67 | 1.29 | 2.06× |
| `Fuse/src/search/extended/IncludeMatch.js` | 805 | 41 | 67.40 | 2.82 | 1.29 | 2.19× |
| `Fuse/src/search/extended/InverseExactMatch.js` | 609 | 30 | 66.59 | 2.62 | 1.26 | 2.07× |
| `Fuse/src/search/extended/InversePrefixExactMatch.js` | 610 | 29 | 64.92 | 2.70 | 1.18 | 2.28× |
| `Fuse/src/search/extended/InverseSuffixExactMatch.js` | 606 | 27 | 64.67 | 2.62 | 1.22 | 2.14× |
| `Fuse/src/search/extended/PrefixExactMatch.js` | 583 | 28 | 64.33 | 2.62 | 1.17 | 2.24× |
| `Fuse/src/search/extended/SuffixExactMatch.js` | 605 | 28 | 64.74 | 2.69 | 1.13 | 2.39× |
| `Fuse/src/search/extended/index.js` | 4,315 | 149 | 75.70 | 3.44 | 1.52 | 2.27× |
| `Fuse/src/search/extended/parseQuery.js` | 2,087 | 72 | 69.83 | 4.27 | 1.18 | 3.61× |
| `Fuse/src/search/index.js` | 114 | 4 | 56.81 | 2.29 | 1.03 | 2.22× |
| `Fuse/src/tools/FuseIndex.js` | 4,127 | 173 | 85.42 | 4.39 | 1.54 | 2.84× |
| `Fuse/src/tools/KeyStore.js` | 1,568 | 79 | 72.72 | 3.32 | 1.41 | 2.36× |
| `Fuse/src/tools/norm.js` | 755 | 31 | 64.86 | 3.21 | 1.33 | 2.42× |
| `Fuse/src/transform/index.js` | 141 | 4 | 59.56 | 2.33 | 0.99 | 2.34× |
| `Fuse/src/transform/transformMatches.js` | 559 | 33 | 66.87 | 2.70 | 1.23 | 2.19× |
| `Fuse/src/transform/transformScore.js` | 85 | 3 | 58.61 | 2.34 | 1.17 | 2.01× |
| `Fuse/test/extended-search.test.js` | 4,019 | 154 | 79.83 | 6.10 | 1.49 | 4.09× |
| `Fuse/test/feature-flags.test.js` | 644 | 22 | 63.23 | 2.70 | 1.24 | 2.18× |
| `Fuse/test/fixtures/pokedex.js` | 1,622 | 61 | 68.75 | 3.58 | 1.36 | 2.63× |
| `Fuse/test/fixtures/pokedex.ts` | 1,905 | 69 | 74.12 | 3.62 | 1.45 | 2.51× |
| `Fuse/test/fixtures/types.js` | 39 | 2 | 57.36 | 2.23 | 1.01 | 2.22× |
| `Fuse/test/fixtures/types.ts` | 925 | 54 | 66.66 | 2.70 | 1.06 | 2.55× |
| `Fuse/test/fuzzy-search.test.js` | 30,932 | 1,253 | 119.31 | 13.49 | 3.34 | 4.04× |
| `Fuse/test/indexing.test.js` | 4,208 | 155 | 89.25 | 5.20 | 1.57 | 3.32× |
| `Fuse/test/logical-search.test.js` | 6,143 | 261 | 89.29 | 5.75 | 1.85 | 3.11× |
| `Fuse/test/scoring.test.js` | 2,025 | 64 | 70.40 | 3.75 | 1.36 | 2.75× |
| `Fuse/test/typings.test.ts` | 2,637 | 105 | 81.63 | 4.10 | 1.51 | 2.71× |
| `Fuse/vitest.config.ts` | 150 | 10 | 63.80 | 2.34 | 1.18 | 1.98× |
| `json-server/.prettier.config.js` | 79 | 5 | 57.41 | 2.19 | 1.12 | 1.95× |
| `json-server/eslint.config.js` | 281 | 11 | 59.32 | 2.31 | 1.04 | 2.22× |
| `json-server/src/app.test.ts` | 4,112 | 129 | 95.40 | 4.56 | 1.51 | 3.03× |
| `json-server/src/app.ts` | 3,689 | 145 | 98.80 | 5.61 | 1.72 | 3.26× |
| `json-server/src/bin.ts` | 5,469 | 227 | 101.30 | 7.07 | 1.80 | 3.92× |
| `json-server/src/observer.ts` | 634 | 36 | 70.41 | 2.75 | 1.24 | 2.21× |
| `json-server/src/service.test.ts` | 9,046 | 392 | 111.68 | 7.13 | 2.07 | 3.44× |
| `json-server/src/service.ts` | 11,495 | 459 | 115.96 | 7.91 | 2.40 | 3.29× |
| `ms/scripts/build.js` | 1,995 | 73 | 73.15 | 3.36 | 1.43 | 2.35× |
| `ms/src/index.test.ts` | 8,045 | 296 | 106.31 | 8.36 | 1.90 | 4.40× |
| `ms/src/index.ts` | 4,225 | 205 | 87.15 | 4.58 | 1.59 | 2.88× |

Totals by file type, median of the rep totals:

| Type | Files | Prettier | Rust | asm | asm speedup over Rust |
| --- | ---: | ---: | ---: | ---: | ---: |
| .js | 46 | 3,186 ms | 151.8 ms | 60.0 ms | 2.53× (2.45× to 2.64×) |
| .ts | 13 | 1,169 ms | 63.5 ms | 21.0 ms | 3.02× (2.94× to 3.14×) |

<img src="results/charts/per-file.svg" alt="Time per file for the three contenders on a log scale. The per-file table has the values." width="760">

<img src="results/charts/size.svg" alt="Time against input size for the Rust port and asm. The per-file table has the values." width="760">

## Spread

| Contender | Min | Median | Mean | Max | Std. dev. | Rel. std. dev. |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Prettier 3.6.2 (Node) | 4,322 ms | 4,363 ms | 4,360 ms | 4,394 ms | 24.7 ms | 0.6% |
| Rust port | 211.2 ms | 215.4 ms | 215.4 ms | 220.8 ms | 3.25 ms | 1.5% |
| asm | 76.9 ms | 80.8 ms | 80.8 ms | 83.3 ms | 1.83 ms | 2.3% |
| exit(0), static, no libc | 52.5 ms | 54.1 ms | 53.8 ms | 54.8 ms | 0.71 ms | 1.3% |
| /bin/true, dynamic | 64.5 ms | 66.3 ms | 66.0 ms | 67.5 ms | 0.98 ms | 1.5% |

<img src="results/charts/spread.svg" alt="Each rep total as a difference from its contender median. The spread table has the values." width="760">

## Process floor

Starting a process that does nothing costs 54.1 ms for the 59 files (0.92 ms a file) when the binary is static, and 66.3 ms (1.13 ms a file) for `/bin/true`, which is dynamic.
asm takes 80.8 ms, so 26.7 ms (33.0%) is above the static floor. The Rust port takes 215.4 ms, 149.1 ms above the dynamic floor.

<img src="results/charts/floor.svg" alt="asm time per file split into the process floor and the work above it. The per-file table and this section have the values." width="760">

## System calls and memory

System calls on `Fuse/src/search/index.js` (114 bytes), counted with `strace -c -f`, threads included. The run starts in a directory 2 levels below `/`. Each contender looks for config files in every directory from there up to `/`, so the counts grow with depth.

| Contender | Calls | Failed | Most frequent |
| --- | ---: | ---: | --- |
| Prettier 3.6.2 (Node) | 2,748 | 243 | futex 669, epoll_pwait 286, read 278, statx 191, write 156 |
| Rust port | 263 | 181 | statx 155, openat 28, mmap 20, read 11, mprotect 6 |
| asm | 17 | 1 | getdents64 6, openat 4, read 2, execve 1, getcwd 1 |
| process floor (static) | 1 | 0 | execve 1 |

Peak resident memory per process, one run per file (`bench/tools/rusage.s`). Peak RSS is the larger of `ru_maxrss` and the `Rss` line of `/proc/<pid>/smaps_rollup`, read when the process calls exit. Linux counts `ru_maxrss` in per-CPU batches, so it reads low by up to a few hundred KiB on a small process. `Rss` at exit misses memory freed before exit. CPU time is user plus system time from `wait4`, summed over the 59 files.

| Contender | Peak RSS, one file | Median over files | Max over files | CPU time, all files |
| --- | ---: | ---: | ---: | ---: |
| Prettier 3.6.2 (Node) | 65.7 MiB | 67.4 MiB | 86.0 MiB | 5,204 ms |
| Rust port | 6.44 MiB | 7.01 MiB | 14.2 MiB | 179.4 ms |
| asm | 0.37 MiB | 0.40 MiB | 2.08 MiB | 42.4 ms |

Instruction and cycle counts: not recorded, perf is not installed.

## Cross-check with hyperfine

Not run: hyperfine is not installed.

## Upstream method

rust-anything's own `bench/cli.mjs` (`ref/rust-anything/demo/real-world/prettier-rs/bench/cli.mjs`, sha256 `6b5350342373e01b`), run unchanged from an empty directory with Prettier's `dist` build from the clone. The script times Prettier against one front door, file by file. For asm, the asm binary takes the front door's slot in a separate run. The script counts stdout equal to Prettier's as identical and rounds each total to whole ms.

| Run | Front door | Load | Prettier | Front door time | Identical |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | Rust port | 1.54 | 4,365 ms | 215 ms | 59/59 |
| 1 | asm | 1.49 | 4,325 ms | 85 ms | 59/59 |
| 2 | Rust port | 1.45 | 4,349 ms | 219 ms | 59/59 |
| 2 | asm | 1.42 | 4,321 ms | 85 ms | 59/59 |
| 3 | Rust port | 1.38 | 4,365 ms | 219 ms | 59/59 |
| 3 | asm | 1.51 | 4,334 ms | 88 ms | 59/59 |
| 4 | Rust port | 1.51 | 4,347 ms | 227 ms | 59/59 |
| 4 | asm | 1.47 | 4,317 ms | 91 ms | 59/59 |
| 5 | Rust port | 1.51 | 4,311 ms | 222 ms | 59/59 |
| 5 | asm | 1.39 | 4,334 ms | 84 ms | 59/59 |

Medians: Prettier 4,349 ms against the Rust port's 219 ms, and 4,325 ms against asm's 85 ms. asm over the Rust port by this method: 2.58×.
Their published figure is 3.63 s against 0.20 s (run 1 of their 2), on Apple M4 (10 cores, 16 GB), macOS 27.3, Node 24.15.0 (`ref/rust-anything/docs/real-world.md`).

## What was not tested

- Only Linux on x86-64. The binary does not run anywhere else.
- One machine. Results on other CPUs, kernels and file systems are not known.
- The Rust port was built and timed here on x86-64. The figure in its README is from Apple M4 (10 cores, 16 GB), macOS 27.3, Node 24.15.0. That machine was not used here.
- Refused inputs are not counted as formatted. With `PRETTIER_ASM_FALLBACK` set, asm hands them to Node, and they then run at Node's speed. That mode was not timed here.
- `.tsx`, JSX, Flow and proposals are refused by design.
- Only the 59 real files were timed. The fixture lists were checked for output, not timed.

## Reproduce

```sh
npm install
node tests/setup-corpus.mjs        # corpus/real and corpus/cases
node tests/build-expected.mjs      # Prettier's output for every case
bench/build-rust-baseline.sh build # the Rust port, under ref/
make                               # build/prettier-asm
make results                       # node bench/record.mjs, then node bench/report.mjs
node bench/report.mjs --gif        # also results/charts/headline.gif
```

`node bench/record.mjs` refuses to run when the 1-minute load average is above 1.0. `--force` overrides that, and the report then says so at the top. `results/README.md` lists what each data file holds.
