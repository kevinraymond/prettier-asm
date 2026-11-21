// Checks the harness against stand-in binaries. Usage: node tests/selftest.mjs [list...]
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { ROOT, CASES_DIR } from "./lib.mjs";

const lists = process.argv.slice(2).length ? process.argv.slice(2)
  : fs.readdirSync(CASES_DIR).filter((f) => f.endsWith(".jsonl")).map((f) => f.slice(0, -6)).sort();
const want = {
  "oracle.sh": (c, n) => c.identical === n,
  "fallback.sh": (c, n) => c.fallback + c["oracle-error"] === n && c.fallback > 0,
  "append-byte.sh": (c, n) => c.DIFFERENT === n,
  "crash.sh": (c, n) => c.DIFFERENT === n,
  "hang.sh": (c, n) => c.DIFFERENT === n,
};
let failed = 0;
for (const l of lists) for (const [s, ok] of Object.entries(want)) {
  const extra = s === "hang.sh" ? ["--limit", "4", "--timeout", "300"] : [];
  const r = spawnSync(process.execPath, [path.join(ROOT, "tests/harness.mjs"), path.join(ROOT, "tests/stand-ins", s), l, "--json", ...extra],
    { encoding: "utf8", maxBuffer: 1 << 28 });
  const j = JSON.parse(r.stdout), n = j.cases.length;
  const pass = n > 0 && ok(j.counts, n) && r.status === (j.counts.DIFFERENT ? 1 : 0);
  if (!pass) failed++;
  console.log(`${pass ? "ok  " : "FAIL"} ${l.padEnd(12)} ${s.padEnd(15)} ${n} cases ${JSON.stringify(j.counts)} exit ${r.status}`);
}
const missing = spawnSync(process.execPath, [path.join(ROOT, "tests/harness.mjs"), "/nonexistent/prettier-asm", lists[0]]);
console.log(`${missing.status === 2 ? "ok  " : "FAIL"} missing binary exits ${missing.status}`);
if (missing.status !== 2) failed++;
process.exitCode = failed ? 1 : 0;
