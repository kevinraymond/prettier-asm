// Checks that run.mjs reports broken parsers: builds mutated copies of the parser and expects
// DIFFERENT cases from each.
//   node tests/stage3/parser/mutants.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { ROOT } from "../../lib.mjs";

const mutants = [
  {
    name: "* binds like + (precedence swapped)",
    file: "parse_js_expr.s",
    from: "    movzx r15d, byte ptr [rax + r14]\n",
    to: "    movzx r15d, byte ptr [rax + r14]\n    cmp r14, J_STAR\n    jne .Lmut1\n    mov r15d, 9\n.Lmut1:\n    cmp r14, J_PLUS\n    jne .Lmut2\n    mov r15d, 10\n.Lmut2:\n",
  },
  {
    name: "parenthesized flag dropped",
    file: "parse_js_post.s",
    from: "    or dword ptr [rbx + N_ATTR], NA_PARENTHESIZED\n",
    to: "",
  },
  {
    name: "statement end one byte short",
    file: "parse_js.s",
    from: "    NODE T_ExpressionStatement, r12\n    mov [rax + N_F0], rbx\n    mov rbx, rax\n    call js_semicolon\n    FINISH rbx\n",
    to: "    NODE T_ExpressionStatement, r12\n    mov [rax + N_F0], rbx\n    mov rbx, rax\n    call js_semicolon\n    FINISH rbx\n    dec dword ptr [rbx + N_END]\n",
  },
  {
    name: "line comments lose their last byte",
    file: "parse_js_lex.s",
    from: "41: mov edi, CT_LINE\n    mov rsi, r14\n    mov rdx, rbx\n",
    to: "41: mov edi, CT_LINE\n    mov rsi, r14\n    lea rdx, [rbx - 1]\n",
  },
  {
    name: "TypeScript: parenthesized types kept (postprocess step dropped)",
    file: "parse_js_post.s",
    from: "    cmp eax, T_TSParenthesizedType\n    je 30f\n",
    to: "",
  },
  {
    name: "TypeScript: generic calls never tried (f<T>(x) read as comparisons)",
    file: "parse_ts.s",
    from: "FUNC jts_subscript_lt_try\n    ENTER5 8\n",
    to: "FUNC jts_subscript_lt_try\n    ENTER5 8\n    call js_abort\n",
  },
  {
    name: "cover grammar errors accepted ({a = 1} as an expression)",
    file: "parse_js_expr.s",
    from: "FUNC jpe_errors_check\n    cmp qword ptr [rip + g_err_shorthand], -1\n",
    to: "FUNC jpe_errors_check\n    leave\n    ret\n    cmp qword ptr [rip + g_err_shorthand], -1\n",
  },
];

const work = fs.mkdtempSync(path.join(os.tmpdir(), "js-mutants-"));
let failures = 0;
for (const m of mutants) {
  const dir = path.join(work, m.name.replace(/\W+/g, "-"));
  fs.cpSync(path.join(ROOT, "src"), path.join(dir, "src"), { recursive: true });
  fs.cpSync(path.join(ROOT, "tests/stage3/parser"), path.join(dir, "tests/stage3/parser"), { recursive: true });
  const f = path.join(dir, "src", m.file);
  const text = fs.readFileSync(f, "utf8");
  if (!text.includes(m.from)) { console.log(`MUTANT NOT APPLIED: ${m.name}`); failures++; continue; }
  fs.writeFileSync(f, text.replace(m.from, m.to));
  const b = spawnSync("sh", [path.join(dir, "tests/stage3/parser/build.sh")], { encoding: "utf8" });
  if (b.status !== 0) { console.log(`MUTANT DID NOT BUILD: ${m.name}\n${b.stderr}`); failures++; continue; }
  const r = spawnSync(process.execPath, [path.join(ROOT, "tests/stage3/parser/run.mjs"), "--quiet",
    "--bin", path.join(dir, "build/js-parse"), "real", path.join(ROOT, "tests/stage3/parser/cases.mjs")], { encoding: "utf8" });
  const counts = [...r.stdout.matchAll(/DIFFERENT (\d+)/g)].map((x) => Number(x[1]));
  const total = counts.reduce((a, b) => a + b, 0);
  console.log(`${total > 0 ? "caught" : "MISSED"}  ${m.name}: ${total} DIFFERENT`);
  if (total === 0) failures++;
}
fs.rmSync(work, { recursive: true, force: true });
process.exit(failures ? 1 : 0);
