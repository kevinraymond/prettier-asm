# Rust baseline: prettier-rs front door

The baseline is the Rust front door from rust-anything's `demo/real-world/prettier-rs`
(github.com/erkamyaman/rust-anything, MIT, commit `dabf50c`), built and measured on this machine.
`bench/build-rust-baseline.sh` holds the steps; everything it makes is under `ref/`.

## Setup

- Intel Core i9-13900K (32 threads), 188 GB RAM, Debian 13, Linux 6.12.113. Governor `powersave`
  with energy preference `performance`, as the machine was; nothing was pinned.
- Node 22.21.0 (nvm), rustc and cargo 1.99.1. Their numbers used Node 24.15.0 on an Apple M4.
  Node 22 built and ran everything, so Node 24 was not installed.
- Prettier 3.6.2 (commit `7a8b05f`), cloned to `ref/prettier`, built with
  `corepack yarn install` (yarn 4.9.2) and `corepack yarn build --no-minify`.
- Real repositories under `ref/real`: ms `3.0.0-canary.1` (`1304f15`), Fuse.js `v7.1.0`
  (`8119c18`), json-server `v1.0.0-beta.3` (`6aa56d9`), the commits their DECISIONS.md names.
  Their `scripts/gen-inputs.mjs` walk picks 59 files, the same count as theirs.

## The binary

```
ref/prettier/rust/app/target/release/prettier --stdin-filepath real/<rel> < file
```

It is built with plain `cargo build --release` in `ref/prettier/rust/app`, after copying
`prettier-rs` to `rust/` of the Prettier clone as their README says. The `rust-anything` CLI is
not needed for this. The build took 17 s from an empty `target/`, with the crates already downloaded. The app crate is its own
workspace with no `[profile.release]`, so the `lto = true` in the unit crates does not apply:
the binary is built without LTO. It is 9.1 MB, not stripped, and dynamically linked against
`libgcc_s.so.1`, `libm.so.6` and `libc.so.6` (`ldd`).

Fallback: `app/src/original.rs` runs `node <root>/node_modules/prettier/bin/prettier.cjs` with
the same arguments, where `<root>` is `CARGO_MANIFEST_DIR/../..`, baked in at compile time
(here `ref/prettier/rust/app/../..`, the Prettier clone). `node` comes from `PATH`; with no
`node` on `PATH` a fallback exits 127. `yarn install` puts Prettier 3.6.1 in
`ref/prettier/node_modules/prettier` (the repository's own devDependency), so the script moves
that aside and copies `dist/prettier` (3.6.2) there, as their DECISIONS.md describes. Moving
the clone means rebuilding.

Environment variables it reads: `RUST_ANYTHING_FALLBACK_LOG=<file>` appends a line per
fallback, and `RUST_ANYTHING_UNIT_JS_FORMAT=original` sends every case to Prettier.

The glue resolves config itself: `.gitignore` and `.prettierignore` in the cwd, then
`.editorconfig` and Prettier's config files in every directory from the file's folder up to `/`.

## Correctness

Each of the 59 files was run through `node ref/prettier/dist/prettier/bin/prettier.cjs` and the
front door, with stdin input and `--stdin-filepath real/<rel>`, from an empty `mktemp -d`
directory with no config files above it.

- 59 of 59 identical: stdout, stderr and exit code.
- 59 formatted in Rust, 0 fell back.
- Prettier changes all 59 files, so identical output is not the input passed through.
- The dist build and npm's `prettier@3.6.2` give the same output on all 59.

Fallbacks were counted with `RUST_ANYTHING_FALLBACK_LOG`. With
`RUST_ANYTHING_UNIT_JS_FORMAT=original` set, the log gets a line per run, so it does detect a
fallback. `strace -f -e trace=execve` agrees: on all 59 files the front door makes one `execve`
(its own), while a forced fallback execs `node` as well.

## Timing

All runs from an empty `mktemp -d` directory. The load is the 1-minute average when each run
started. Other agents were working on the machine: a first attempt saw the load climb from 1.9
to 13.8 mid-run and two passes slowed by up to 2x, so it was thrown away and the numbers below
are from a second attempt that started at load 0.96.

Their `bench/cli.mjs`, unchanged (spawnSync per file, hrtime around each, Prettier and the front
door alternating file by file):

| Run | Load | Prettier CLI | Front door |
| --- | ---: | ---: | ---: |
| 1 | 0.96 | 4,354 ms | 221 ms |
| 2 | 0.96 | 4,358 ms | 222 ms |
| 3 | 0.96 | 4,366 ms | 216 ms |
| 4 | 1.05 | 4,343 ms | 225 ms |
| 5 | 1.04 | 4,304 ms | 221 ms |

Their published figure for the same 59 files on the M4 is 3.63 s against 0.20 s.

The same timing with one command per pass (`perfile.mjs`), which keeps per-file times:

| Run | Load | Prettier CLI | Load | Front door |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1.12 | 4,307 ms | 1.11 | 193 ms |
| 2 | 1.11 | 4,246 ms | 1.10 | 185 ms |
| 3 | 1.10 | 4,303 ms | 1.09 | 192 ms |
| 4 | 1.09 | 4,328 ms | 1.41 | 191 ms |
| 5 | 1.41 | 4,289 ms | 1.37 | 187 ms |

The front door totals about 30 ms less when it does not alternate with Node.

A plain bash loop (`prettier --stdin-filepath real/<rel> < file > /dev/null`, `date +%s%N`
around the 59):

| Run | Load | Prettier CLI | Load | Front door |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1.37 | 4,337 ms | 1.20 | 165 ms |
| 2 | 1.26 | 4,320 ms | 1.20 | 164 ms |
| 3 | 1.26 | 4,208 ms | 1.20 | 159 ms |
| 4 | 1.24 | 4,196 ms | 1.20 | 171 ms |
| 5 | 1.22 | 4,283 ms | 1.20 | 158 ms |

Per file, front door, `perfile.mjs` (per-file median over the 5 runs, then across files):
min 1.69 ms (`Fuse/src/transform/index.js`, 141 bytes), median 2.68 ms, max 13.45 ms
(`Fuse/test/fuzzy-search.test.js`, 31 KB, the slowest file in every run). Per run the median was
2.38 to 2.70 ms. Prettier's CLI on the same basis: min 53.8 ms, median 65.5 ms, max 119.5 ms
(`json-server/src/service.ts`).

The floor for starting any process, `/bin/true` with the same arguments and stdin: 52 to 56 ms
for the 59 with `perfile.mjs` (median 0.85 to 0.96 ms a file), 35 to 37 ms in the bash loop.
`/bin/true` is dynamically linked too.

## Start-up

`strace -f` on `Fuse/src/search/index.js` from `/tmp/tmp.XXXXXXXXXX` (7 directories from the
file's folder up to `/`), with `LD_LIBRARY_PATH` unset: 245 syscalls, 165 of them failing.

- 155 `statx`, all ENOENT. For each of the 7 directories it looks for `.git` and `.hg` (the
  `.editorconfig` project root, never found here) and then for 20 Prettier config names
  (`package.json`, `package.yaml`, `.prettierrc*`, `prettier.config.*`). That is 22 per level
  plus one probe call, so the count grows with path depth.
- 14 `openat`: `.gitignore` and `.prettierignore` in the cwd, `.editorconfig` in each of the 7
  directories (all ENOENT), then `/etc/ld.so.cache`, the 3 shared libraries and
  `/proc/self/maps`.
- Dynamic loading: `ld.so` opens and maps `libgcc_s`, `libm` and `libc` (19 `mmap`, 6
  `mprotect`). With this shell's `LD_LIBRARY_PATH=:/usr/local/cuda/lib64` the loader first
  tries 14 paths in the cwd and the CUDA folder (plus 3 `newfstatat` and 1 `mmap`), for 263 in
  all.
- Rust runtime set-up: `poll` on fds 0 to 2, `SIGPIPE` ignored, `/proc/self/maps` read (glibc's
  `pthread_getattr_np`, for the main thread's stack guard), `sigaltstack` and `SIGSEGV`/`SIGBUS` handlers, 2 `getrandom`.
- Work: `getcwd`, reads of stdin, 1 `write` of the output, `exit_group`. No threads, no `clone`.

On the 31 KB file (6 directory levels) it makes 282 calls: 133 `statx` and 47 `brk` as the
heap grows.
