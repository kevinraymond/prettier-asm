# Tests

The oracle is Prettier 3.6.2 from npm (`npm install` puts it in `node_modules/`). Every oracle and
binary run starts in an empty temporary directory, so no config, `.editorconfig` or ignore file
applies.

## Setup

```sh
npm install
node tests/setup-corpus.mjs      # clones the real repositories, writes corpus/cases/*.jsonl
node tests/build-expected.mjs    # runs the oracle once per case into corpus/expected/
```

`setup-corpus.mjs` clones ms `3.0.0-canary.1`, Fuse.js `v7.1.0` and json-server `v1.0.0-beta.3`
into `corpus/real/`, then runs prettier-rs's `gen-inputs.mjs` and `gen-json-inputs.mjs` from
`ref/` unchanged and splits their output into these lists:

| List | Cases | What |
| --- | ---: | --- |
| `real` | 59 | the benchmark files from the three repositories |
| `js-fixtures` | 971 | `tests/format/js` and `tests/format/jsx`, with each folder's options |
| `ts-fixtures` | 554 | `tests/format/typescript`, with each folder's options |
| `variants` | 1200 | every seventh fixture under six common options |
| `json` | 1478 | JSON fixtures under four file names, option variants, real JSON files, snippets |

The cache is keyed by a hash of the arguments and stdin, so a re-run only runs new cases.
`build-expected.mjs --verify N` re-runs N random cached cases per list and compares.

## Running a binary

```sh
node tests/harness.mjs build/prettier-asm real
node tests/harness.mjs build/prettier-asm js-fixtures --filter arrows --show-diff 3
node tests/harness.mjs build/prettier-asm json --json > result.json
```

The harness unsets `PRETTIER_ASM_FALLBACK` and puts each case in one class:

- `identical`: same exit code and stdout as Prettier (and the same stderr when Prettier errors)
- `fallback`: exit 3; the report groups the `unsupported: <reason>` lines
- `oracle-error`: Prettier errors on the case and the binary exits 3, as it must
- `DIFFERENT`: anything else, including a crash, a timeout (`--timeout`, 10 s) and output where
  Prettier errors

It exits 1 when any case is DIFFERENT. The last line is the summary for `make test`.
`node tests/selftest.mjs` checks the harness against the stand-ins in `tests/stand-ins/`.

## Benchmark

```sh
node bench/cli.mjs real \
  "prettier=node node_modules/prettier/bin/prettier.cjs" \
  "rust=<path to the prettier-rs front door>" \
  "asm=PRETTIER_ASM_FALLBACK=node_modules/prettier/bin/prettier.cjs build/prettier-asm" \
  --reps 5
```

One process per file with the file on stdin, timed with `hrtime`, as prettier-rs's
`bench/cli.mjs` does. Each contender's output is checked against the oracle first (untimed);
a mismatch stops the run unless `--allow-mismatch` is given. The contender order rotates each rep.
Commands run from an empty directory; `--cwd` picks another one. `--no-check name` times a
contender without comparing its output (a process floor), and `--json` prints every rep's total
and every file's time. `make results` records everything with `bench/record.mjs`;
`results/README.md` describes the data.

## Node types

```sh
node tests/node-stats.mjs        # writes corpus/real-node-types.txt
```

Node types, operators and comment kinds per file and overall, from Prettier's own parsers, plus
a greedy porting order that lists which file each new node type unlocks.
