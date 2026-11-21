// Tests the test: builds deliberately wrong copies of build/prettier-asm by
// patching the binary, runs run.mjs against each, and checks that every
// mutant is reported DIFFERENT. Exit code 1 if a mutant goes unnoticed.
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const bin = path.join(root, "build/prettier-asm");
const original = fs.readFileSync(bin);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "prettier-asm-mutants-"));

// File offset of a symbol, from nm and the section headers.
function symbolOffset(name) {
  const nm = execFileSync("nm", [bin], { encoding: "utf8", maxBuffer: 1 << 28 });
  const line = nm.split("\n").find((l) => l.endsWith(` ${name}`));
  if (!line) throw new Error(`symbol ${name} not found`);
  const addr = BigInt("0x" + line.split(" ")[0]);
  const readelf = execFileSync("readelf", ["-S", "-W", bin], { encoding: "utf8", maxBuffer: 1 << 28 });
  for (const l of readelf.split("\n")) {
    const m = l.match(/\]\s+(\S+)\s+\S+\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)/);
    if (!m) continue;
    const [, , a, o, s] = m;
    const start = BigInt("0x" + a);
    if (addr >= start && addr < start + BigInt("0x" + s)) {
      return Number(addr - start + BigInt("0x" + o));
    }
  }
  throw new Error(`no section for ${name}`);
}

const mutants = {
  // printWidth 79 instead of 80
  "print-width-79": (buf) => buf.writeBigInt64LE(79n, symbolOffset("g_print_width")),
  // every "null" literal printed as "nul1"
  "null-literal": (buf) => {
    let i = 0;
    let n = 0;
    while ((i = buf.indexOf("null", i)) !== -1) {
      buf.write("nul1", i);
      n++;
    }
    if (n === 0) throw new Error("no null text");
  },
};

let failed = false;
for (const [name, mutate] of Object.entries(mutants)) {
  const buf = Buffer.from(original);
  mutate(buf);
  const file = path.join(dir, name);
  fs.writeFileSync(file, buf, { mode: 0o755 });
  const r = spawnSync(process.execPath, [path.join(root, "tests/stage1/run.mjs")], {
    env: { ...process.env, PRETTIER_ASM_BIN: file },
    encoding: "utf8",
  });
  const total = r.stdout.split("\n").find((l) => l.startsWith("total"));
  const different = Number(total?.trim().split(/\s+/).at(-1));
  const caught = r.status === 1 && different > 0;
  console.log(`${name}: ${total?.replace(/\s+/g, " ")} -> ${caught ? "caught" : "NOT CAUGHT"}`);
  if (!caught) failed = true;
}
fs.rmSync(dir, { recursive: true, force: true });
process.exitCode = failed ? 1 : 0;
