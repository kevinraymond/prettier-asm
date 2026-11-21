// Tests the tests: builds copies of the binary with one config rule broken in
// the source, runs run.mjs (hand cases) and fuzz.mjs against each, and checks
// that every mutant shows DIFFERENT. Exit 1 if a mutant goes unnoticed.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const here = path.dirname(fileURLToPath(import.meta.url));

// [name, file, text to replace, replacement]
const mutants = [
  ["negation-ignored", "src/ignore.s",
    "    mov r15d, 1\n    inc rbx\n    dec r12", "    mov r15d, 0\n    inc rbx\n    dec r12"],
  ["parents-not-tested", "src/ignore.s",
    "    test r13, r13\n    jz 2f\n    mov rdi, rbx\n    lea rsi, [r13 + 1]", "    jmp 2f\n    mov rdi, rbx\n    lea rsi, [r13 + 1]"],
  ["editorconfig-root-ignored", "src/editorconfig.s",
    "    cmp ecx, 0x65757274             # \"true\"\n    jne 9f\n    mov eax, 1", "    cmp ecx, 0x65757274             # \"true\"\n    jne 9f\n    mov eax, 0"],
  ["star-globstar-zero", "src/glob.s",
    "    cmp byte ptr [rdi + rsi - 1], '*'\n    jne 61f", "    cmp byte ptr [rdi + rsi - 1], '*'\n    jmp 61f"],
  ["config-beats-cli", "src/options.s",
    "    cmp byte ptr [rax + rdi], 0\n    jne 1f", "    cmp byte ptr [rax + rdi], 0\n    jmp 2f\n2:"],
  ["package-json-without-key-counts", "src/config.s",
    "    test rax, rax\n    jz 8f\n    movzx ecx, byte ptr [rax + CV_TYPE]", "    test rax, rax\n    jz 99f\n    movzx ecx, byte ptr [rax + CV_TYPE]"],
];

const work = fs.mkdtempSync(path.join(os.tmpdir(), "prettier-asm-config-mutants-"));
let failed = false;
for (const [name, file, from, to] of mutants) {
  const dir = path.join(work, name);
  fs.mkdirSync(dir);
  fs.cpSync(path.join(ROOT, "src"), path.join(dir, "src"), { recursive: true });
  fs.copyFileSync(path.join(ROOT, "Makefile"), path.join(dir, "Makefile"));
  const p = path.join(dir, file);
  const text = fs.readFileSync(p, "utf8");
  if (text.split(from).length !== 2) {
    console.log(`${name}: the text to mutate is not in ${file} exactly once`);
    failed = true;
    continue;
  }
  fs.writeFileSync(p, text.replace(from, to));
  const make = spawnSync("make", ["-s", "-C", dir], { encoding: "utf8" });
  if (make.status !== 0) {
    console.log(`${name}: build failed\n${make.stderr.slice(0, 500)}`);
    failed = true;
    continue;
  }
  const bin = path.join(dir, "build/prettier-asm");
  let different = 0;
  for (const script of [["run.mjs", "--random", "0", "--quiet"], ["fuzz.mjs", "--n", "40"]]) {
    const r = spawnSync(process.execPath, [path.join(here, script[0]), "--bin", bin, ...script.slice(1)], { encoding: "utf8" });
    const total = r.stdout.split("\n").find((l) => l.startsWith("total"));
    different += Number(total?.match(/DIFFERENT (\d+)/)?.[1] ?? 0);
  }
  console.log(`${name.padEnd(34)} DIFFERENT ${different}${different ? "" : "   NOT CAUGHT"}`);
  if (!different) failed = true;
}
fs.rmSync(work, { recursive: true, force: true });
process.exit(failed ? 1 : 0);
