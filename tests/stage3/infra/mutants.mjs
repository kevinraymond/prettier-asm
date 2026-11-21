// node tests/stage3/infra/mutants.mjs
//
// Builds binaries with one deliberate bug each (the objects of build/, with
// the mutated file assembled again) and checks that the stage 3 infra tests
// report every one of them.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { ROOT } from "../../lib.mjs";

const MUTANTS = [
  ["fits: a line costs no width", "docprint.s", "    add r10, 16\n    dec r13\n    jmp 10b", "    add r10, 16\n    jmp 10b"],
  ["fits: mustBeFlat ignored", "docprint.s", "    cmp qword ptr [rsp + 64], 0     # must_be_flat (7th slot: see below)\n    jne 80f", "    nop"],
  ["fits: trim gives no width back", "docprint.s", "4:  add r13, rax\n    jmp 10b", "4:  jmp 10b"],
  ["fits: rest commands not read", "docprint.s", "    cmp r12, r11\n    jbe 81f", "    jmp 81f"],
  ["fill: pair check skipped", "docprint.s", "    mov rsi, [rsp + 16]\n    test eax, eax\n    jz 5f", "    mov rsi, [rsp + 16]\n    jmp 5f"],
  ["generateInd: tabs for trailing aligns", "docprint.s", "    mov r12, [rbx + IND_TC]\n    inc r12", "    xor r12d, r12d\n    inc r12"],
  ["cleanDoc: nested group kept", "docutils.s", "    cmp rcx, [rbx + G_EXPANDED]\n    jne 98f\n    jmp 99f", "    jmp 98f"],
  ["cleanDoc: strings not concatenated", "docutils.s", "    mov rax, [rip + g_ss_ptr]\n    cmp rax, r12\n    jbe 54f", "    jmp 54f"],
  ["stripTrailingHardline: newlines kept", "docutils.s", "    cmp al, 10\n    je 53f\n    cmp al, 13", "    cmp al, 13"],
  ["propagateBreaks: break not marked propagated", "doc.s", "    or byte ptr [rax + G_FLAGS], GF_BREAK | GF_PROPAGATED", "    or byte ptr [rax + G_FLAGS], GF_BREAK"],
  ["skipNewline: U+2028 not a line break", "text.s", "3:  cmp edx, 0xE2\n    jne 9f", "3:  jmp 9f"],
  ["path.match: arrays not skipped", "path.s", "    test dword ptr [r13 + PE_FLAGS], PEF_ARRAY\n    jz 3f\n    sub r13, PE_SIZE", "    nop"],
];

const TESTS = [
  ["doc-eval", ["--lists", "js-fixtures", "--limit", "300", "--options", "3"]],
  ["util-eval", ["--random", "800", "--harvest", "0"]],
  ["text-eval", ["--texts", "120"]],
  ["path-eval", []],
];

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "asm-mutants-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const objs = fs.readdirSync(path.join(ROOT, "build")).filter((f) => f.endsWith(".o"));
let caught = 0;
for (const [name, file, from, to] of MUTANTS) {
  const src = fs.readFileSync(path.join(ROOT, "src", file), "utf8");
  if (src.split(from).length !== 2) {
    console.log(`MUTANT NOT APPLIED (pattern not found once): ${name}`);
    continue;
  }
  const dir = path.join(tmp, name.replace(/\W+/g, "-"));
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, file), src.replace(from, to));
  fs.copyFileSync(path.join(ROOT, "src/defs.inc"), path.join(dir, "defs.inc"));
  const obj = path.join(dir, file.replace(/\.s$/, ".o"));
  execFileSync("as", ["--64", "-I", path.join(ROOT, "src"), "-o", obj, path.join(dir, file)]);
  const bin = path.join(dir, "prettier-asm");
  execFileSync("ld", ["-static", "-o", bin, obj,
    ...objs.filter((o) => o !== path.basename(obj)).map((o) => path.join(ROOT, "build", o))]);
  const failed = [];
  for (const [test, args] of TESTS) {
    const r = spawnSync(process.execPath, [path.join(ROOT, "tests/stage3/infra", test + ".mjs"), bin, ...args], { encoding: "utf8" });
    if (r.status !== 0) failed.push(test);
  }
  if (failed.length) caught++;
  console.log(`${failed.length ? "caught" : "MISSED"}: ${name}${failed.length ? " (by " + failed.join(", ") + ")" : ""}`);
}
console.log(`mutants: ${caught} of ${MUTANTS.length} caught`);
process.exit(caught === MUTANTS.length ? 0 : 1);
