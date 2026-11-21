// Checks that the comment tests notice broken code. Each mutant is src/pjs_comments.s with one
// edit (a handler taken out of one of the lists, two neighbors in a list swapped, or one
// condition broken) or src/pjs_comment_print.s with one edit. The mutant is assembled and
// linked with the other objects in build/ (run `make` first) and must give a different
// --debug-comments dump on a case of cases.mjs or ts-cases.mjs, or a different --debug-comment-docs dump on a
// case of print-cases.mjs.
//
//   node tests/stage3/comments/mutants.mjs [--extra-obj file.o]... [--only deletions|swaps|conditions|print]
//
// --extra-obj adds objects to the link (stubs for symbols another file in progress lacks).
// Exits 1 when a deletion or condition mutant survives; surviving swaps are listed, since
// handlers whose conditions never overlap can be swapped without effect.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { run, pool, JOBS, ROOT } from "../../lib.mjs";
import { attachDump, printDump } from "./oracle.mjs";
import jsCases from "./cases.mjs";
import tsCases from "./ts-cases.mjs";
import printCases from "./print-cases.mjs";

const args = process.argv.slice(2);
const extra = [];
let only = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--extra-obj") extra.push(path.resolve(args[++i]));
  else if (args[i] === "--only") only = args[++i];
}

const SRC = path.join(ROOT, "src/pjs_comments.s");
const source = fs.readFileSync(SRC, "utf8");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pjc-mutants-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const PRINT_SRC = path.join(ROOT, "src/pjs_comment_print.s");
const printSource = fs.readFileSync(PRINT_SRC, "utf8");
const objsWithout = (name) => fs.readdirSync(path.join(ROOT, "build")).filter((f) => f.endsWith(".o") && f !== name)
  .map((f) => path.join(ROOT, "build", f));

const cases = [...jsCases, ...tsCases];
const expected = [];
for (const c of cases) expected.push(await attachDump(c.text, c.filepath, c.options));
const printExpected = [];
for (const c of printCases) printExpected.push((await printDump(c.text, c.filepath)).out);

function build(text, name, replaces = "pjs_comments.o") {
  const s = path.join(tmp, `${name}.s`), o = path.join(tmp, `${name}.o`), bin = path.join(tmp, name);
  fs.writeFileSync(s, text);
  execFileSync("as", ["--64", "-I", path.join(ROOT, "src"), "-o", o, s]);
  execFileSync("ld", ["-static", "-o", bin, ...objsWithout(replaces), o, ...extra]);
  return bin;
}

// Cases the unmutated code refuses (TypeScript the parser does not take yet) are left out.
async function killed(bin, print = false, skip = new Set()) {
  const list = print ? printCases : cases, want = print ? printExpected : expected;
  const res = await pool(list, JOBS, async (c, i) => {
    if (skip.has(c.name)) return null;
    const flags = [print ? "--debug-comment-docs" : "--debug-comments", "--stdin-filepath", c.filepath];
    if (c.options?.experimentalTernaries) flags.push("--experimental-ternaries");
    const r = await run(bin, flags, { input: c.text, timeout: 10_000 });
    return r.status !== 0 || r.stdout.toString("utf8") !== want[i] ? c.name : null;
  });
  return res.filter(Boolean);
}
const baseline = build(source, "base");
const skipAttach = new Set(await killed(baseline));
const skipPrint = new Set(await killed(build(printSource, "base-print", "pjs_comment_print.o"), true));
if (skipAttach.size || skipPrint.size)
  console.log(`left out: ${skipAttach.size + skipPrint.size} cases the unmutated code does not match (${[...skipAttach, ...skipPrint].slice(0, 5).join(", ")}${skipAttach.size + skipPrint.size > 5 ? ", ..." : ""})`);

// The handler lists: [listName, [line index of each entry]]
const lines = source.split("\n");
const lists = [];
let cur = null;
lines.forEach((l, i) => {
  const m = /^(pjs_handlers_\w+):$/.exec(l);
  if (m) { cur = { name: m[1], entries: [] }; lists.push(cur); return; }
  if (!cur) return;
  if (/^\s+\.quad 0$/.test(l)) { cur = null; return; }
  if (/^\s+\.quad pjc_handle_\w+$/.test(l)) cur.entries.push(i);
});

const mutants = [];
if (!only || only === "deletions")
  for (const list of lists) for (const i of list.entries) {
    const ls = [...lines]; ls.splice(i, 1);
    mutants.push({ kind: "deletion", name: `${list.name}: drop ${lines[i].trim().slice(6)}`, text: ls.join("\n") });
  }
if (!only || only === "swaps")
  for (const list of lists) for (let k = 0; k + 1 < list.entries.length; k++) {
    const a = list.entries[k], b = list.entries[k + 1];
    const ls = [...lines]; [ls[a], ls[b]] = [ls[b], ls[a]];
    mutants.push({ kind: "swap", name: `${list.name}: swap ${lines[a].trim().slice(6)} / ${lines[b].trim().slice(6)}`, text: ls.join("\n") });
  }
// Conditions: [function, old text, new text]; the old text must occur once in that function.
const CONDITIONS = [
  ["pjc_handle_if_statement_comments", "    cmp eax, ')'\n    jne 1f", "    cmp eax, '('\n    jne 1f"],
  ["pjc_handle_if_statement_comments", "    jl 2f", "    jg 2f"],
  ["pjc_handle_if_statement_comments", "2:  TYPE r13, T_BlockStatement\n    jne 3f", "2:  TYPE r13, T_BlockStatement\n    jmp 3f"],
  ["pjc_handle_if_statement_comments", "    jnz 4f\n    TRAIL r13", "    jz 4f\n    TRAIL r13"],
  ["pjc_handle_if_statement_comments", "6:  TYPE r14, T_IfStatement", "6:  TYPE r14, T_WhileStatement"],
  ["pjc_handle_if_statement_comments", "61: cmp r14, [r12 + N_F1]", "61: cmp r14, [r12 + N_F2]"],
  ["pjc_handle_while_comments", "2:  cmp r14, [r12 + N_F1]", "2:  cmp r14, [r12 + N_F0]"],
  ["pjc_handle_try_statement_comments", "    test r13, r13\n    jz 2f", "    test r13, r13\n    jmp 2f"],
  ["pjc_handle_try_statement_comments", "4:  TYPE r14, T_CatchClause", "4:  TYPE r14, T_TryStatement"],
  ["pjc_handle_conditional_expression_comments", "    jz 8f                               # on the preceding node's line", "    jz 1f"],
  ["pjc_handle_conditional_expression_comments", "    cmp r14, [r12 + N_F2]", "    cmp r14, [r12 + N_F1]"],
  ["pjc_handle_conditional_expression_comments", "    test eax, eax\n    jz 3f\n2:", "    test eax, eax\n    jmp 3f\n2:"],
  ["pjc_handle_last_function_arg_comments", "    cmp eax, T_RestElement\n    je 1f", "    cmp eax, T_RestElement\n    je 2f"],
  ["pjc_handle_last_function_arg_comments", "    cmp eax, T_AssignmentPattern\n    je 1f", "    cmp eax, T_AssignmentPattern\n    je 2f"],
  ["pjc_handle_last_function_arg_comments", "    cmp eax, T_ObjectPattern\n    je 1f", "    cmp eax, T_ObjectPattern\n    je 2f"],
  ["pjc_handle_last_function_arg_comments", "    cmp eax, T_ArrayPattern\n    je 1f", "    cmp eax, T_ArrayPattern\n    je 2f"],
  ["pjc_handle_last_function_arg_comments", "2:  cmp byte ptr [rbx + CM_TYPE], CT_BLOCK\n    je 8f", "2:  cmp byte ptr [rbx + CM_TYPE], CT_BLOCK\n    jne 8f"],
  ["pjc_handle_last_function_arg_comments", "    cmp eax, T_ObjectMethod\n    jne 8f", "    cmp eax, T_ObjectMethod\n    jmp 8f"],
  ["pjc_handle_last_function_arg_comments", "    cmp rax, rcx\n    jne 8f", "    cmp rax, rcx\n    je 8f"],
  ["pjc_is_real_function_like", "    cmp eax, T_ClassMethod\n    je 1f", "    cmp eax, T_ClassPrivateMethod\n    je 1f"],
  ["pjc_is_real_function_like", "    cmp eax, T_ArrowFunctionExpression\n    je 1f", "    cmp eax, T_ArrowFunctionExpression\n    jmp 1f"],
  ["pjc_handle_class_comments", "    cmp r13, [r12 + N_F0]\n    je 31f", "    cmp r13, [r12 + N_F2]\n    je 31f"],
  ["pjc_handle_class_comments", "    cmp r14, rax\n    jne 3f", "    cmp r14, rax\n    jmp 3f"],
  ["pjc_handle_only_comments", "3:  test r15, r15\n    jz 4f", "3:  test r15, r15\n    jnz 4f"],
  ["pjc_handle_only_comments", "    mov rdi, [r12 + N_F1]\n    call pjc_vec_len\n    test rax, rax\n    jnz 8f", "    mov rdi, [r12 + N_F1]\n    call pjc_vec_len\n    test rax, rax\n    nop"],
  ["pjc_handle_module_specifiers_comments", "    call has_newline\n    test eax, eax\n    jz 8f", "    call has_newline\n    test eax, eax\n    nop"],
  ["pjc_handle_module_specifiers_comments", "    cmp eax, T_ExportSpecifier\n    jne 2f", "    cmp eax, T_ExportSpecifier\n    jmp 2f"],
  ["pjc_handle_module_specifiers_comments", "3:  cmp ecx, T_ExportSpecifier", "3:  cmp ecx, T_ImportSpecifier"],
  ["pjc_handle_call_expression_comments", "    cmp r13, [r12 + N_F0]", "    cmp r13, [r12 + N_F1]"],
  ["pjc_handle_call_expression_comments", "    cmp qword ptr [rax], 0\n    je 8f", "    cmp qword ptr [rax], 1\n    je 8f"],
  ["pjc_handle_variable_declarator_comments", "    cmp eax, T_TaggedTemplateExpression\n    je 2f", "    cmp eax, T_TaggedTemplateExpression\n    je 8f"],
  ["pjc_handle_variable_declarator_comments", "    cmp eax, T_TemplateLiteral\n    je 2f", "    cmp eax, T_TemplateLiteral\n    je 8f"],
  ["pjc_handle_variable_declarator_comments", "    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK\n    jne 8f", "    cmp byte ptr [rbx + CM_TYPE], CT_LINE\n    jne 8f"],
  ["pjc_handle_variable_declarator_comments", "    cmp eax, T_AssignmentExpression\n    je 1f", "    cmp eax, T_AssignmentPattern\n    je 1f"],
  ["pjc_handle_switch_default_case_comments", "    cmp qword ptr [r12 + N_F0], 0       # test\n    jne 8f", "    cmp qword ptr [r12 + N_F0], 0       # test\n    nop"],
  ["pjc_handle_switch_default_case_comments", "    call pjs_is_line_comment\n    test eax, eax\n    jz 1f", "    call pjs_is_line_comment\n    test eax, eax\n    jnz 1f"],
  ["pjc_handle_switch_default_case_comments", "    cmp r14, [rax + 8]\n    jne 8f", "    cmp r14, [rax + 8]\n    nop"],
  ["pjc_handle_last_binary_operator_operand", "    test r14, r14\n    jnz 8f", "    test r14, r14\n    jz 8f"],
  ["pjc_handle_last_binary_operator_operand", "    cmp eax, T_BinaryExpression\n    jne 8f", "    cmp eax, T_BinaryExpression\n    jmp 8f"],
  ["pjc_handle_last_binary_operator_operand", "    call has_newline_in_range\n    test eax, eax\n    jnz 8f", "    call has_newline_in_range\n    test eax, eax\n    nop"],
  ["pjc_handle_last_binary_operator_operand", "    call pjc_is_single_line_comment\n    test eax, eax\n    jz 8f", "    call pjc_is_single_line_comment\n    test eax, eax\n    nop"],
  ["pjc_handle_object_property_assignment", "    ATTR r12, NA_SHORTHAND\n    jz 8f", "    ATTR r12, NA_SHORTHAND\n    jnz 8f"],
  ["pjc_handle_comment_in_empty_parens", "    call pjs_get_call_arguments\n    cmp qword ptr [rax], 0\n    je 3f", "    call pjs_get_call_arguments\n    cmp qword ptr [rax], 0\n    jne 3f"],
  ["pjc_handle_comment_in_empty_parens", "    call pjs_get_function_parameters\n    cmp qword ptr [rax], 0\n    je 3f", "    call pjs_get_function_parameters\n    cmp qword ptr [rax], 0\n    jne 3f"],
  ["pjc_handle_comment_after_arrow_params", "    cmp word ptr [rcx + rax], 0x3e3d    # \"=>\"", "    cmp word ptr [rcx + rax], 0x3d3e"],
  ["pjc_handle_function_name_comments", "    cmp eax, T_ClassMethod\n    je 1f", "    cmp eax, T_ClassMethod\n    je 8f"],
  ["pjc_handle_function_name_comments", "    cmp eax, T_ObjectMethod\n    jne 8f", "    cmp eax, T_ObjectMethod\n    jmp 8f"],
  ["pjc_handle_function_name_comments", "    cmp eax, T_FunctionExpression\n    je 1f", "    cmp eax, T_FunctionExpression\n    je 8f"],
  ["pjc_handle_break_and_continue_statement_comments", "1:  cmp qword ptr [r12 + N_F0], 0       # label\n    jne 8f", "1:  cmp qword ptr [r12 + N_F0], 0       # label\n    nop"],
  ["pjc_handle_break_and_continue_statement_comments", "    cmp eax, T_ContinueStatement\n    je 1f", "    cmp eax, T_ContinueStatement\n    je 8f"],
  ["pjc_handle_for_comments", "    cmp eax, T_ForInStatement\n    je 1f", "    cmp eax, T_ForInStatement\n    je 8f"],
  ["pjc_add_block_statement_first_comment", "    cmp word ptr [rax + N_TYPE], T_EmptyStatement\n    je 1b", "    cmp word ptr [rax + N_TYPE], T_EmptyStatement\n    nop"],
  ["pjc_add_block_or_not_comment", "    cmp word ptr [rdi + N_TYPE], T_BlockStatement\n    jne 1f", "    cmp word ptr [rdi + N_TYPE], T_BlockStatement\n    jmp 1f"],
  ["pjc_is_single_line_comment", "    call has_newline_in_range\n    xor eax, 1", "    call has_newline_in_range\n    mov eax, 1"],
  ["pjs_is_line_comment", "    cmp byte ptr [rdi + CM_TYPE], CT_INTERPRETER\n    jne 9f", "    cmp byte ptr [rdi + CM_TYPE], CT_INTERPRETER\n    jmp 9f"],
];
if (!only || only === "conditions")
  for (const [fn, a, b] of CONDITIONS) {
    const start = source.indexOf(`FUNC ${fn}\n`), end = source.indexOf(`ENDF ${fn}\n`, start);
    if (start < 0 || end < 0) throw new Error(`no function ${fn}`);
    const body = source.slice(start, end);
    if (body.split(a).length !== 2) throw new Error(`${fn}: ${JSON.stringify(a)} does not occur once`);
    mutants.push({ kind: "condition", name: `${fn}: ${JSON.stringify(a)} -> ${JSON.stringify(b)}`,
      text: source.slice(0, start) + body.replace(a, b) + source.slice(end) });
  }

// printComment: [old text, new text], each occurring once in pjs_comment_print.s
const PRINT = [
  ["    call trim_end_bytes\n    mov rdi, r12\n    mov rsi, rax", "    mov eax, [rbx + CM_END]\n    mov rdi, r12\n    mov rsi, rax"],
  ["    call pjs_is_line_comment\n    test eax, eax\n    jz 1f", "    cmp byte ptr [rbx + CM_TYPE], CT_LINE\n    jne 1f"],
  ["    call is_indentable_block_comment\n    test eax, eax\n    jz 2f", "    call is_indentable_block_comment\n    jmp 2f"],
  ["    lea rdx, [rip + d_literalline]", "    lea rdx, [rip + d_hardline]"],
  ["    sub esi, 4\n", "    sub esi, 3\n"],
];
if (!only || only === "print")
  for (const [a, b] of PRINT) {
    if (printSource.split(a).length !== 2) throw new Error(`pjs_comment_print.s: ${JSON.stringify(a)} does not occur once`);
    mutants.push({ kind: "print", name: `pjs_comment_print.s: ${JSON.stringify(a)} -> ${JSON.stringify(b)}`,
      text: printSource.replace(a, b), replaces: "pjs_comment_print.o" });
  }

// Mutants no JS input can tell apart, with the reason. They are reported but do not fail.
const EQUIVALENT = new Map([
  ["pjs_handlers_own_line: drop pjc_handle_break_and_continue_statement_comments",
    "a comment inside a break or continue without a label is on the keyword's line: a line break ends the statement (ASI)"],
  ["pjs_handlers_end_of_line: drop pjc_handle_break_and_continue_statement_comments", "the same"],
  ["pjs_handlers_own_line: drop pjc_handle_nested_conditional_expression_comments",
    "handleConditionalExpressionComments, earlier in the list, takes every own-line comment this one would"],
  ["pjs_handlers_remaining: drop pjc_handle_object_property_assignment",
    "Babel's shorthand value spans the key, so the comment's enclosing node is the AssignmentPattern, and the default puts it where the handler would"],
  ["pjs_handlers_remaining: drop pjc_handle_method_name_comments",
    "for a remaining comment after a TSDeclareMethod's key the next character is `(`, so the tie-break makes it trailing on the key too; the decorator branch needs a line or own-line comment, which is never remaining inside a class"],
  ["pjc_handle_object_property_assignment: \"    ATTR r12, NA_SHORTHAND\\n    jz 8f\" -> \"    ATTR r12, NA_SHORTHAND\\n    jnz 8f\"", "the same"],
  ["pjs_is_line_comment: \"    cmp byte ptr [rdi + CM_TYPE], CT_INTERPRETER\\n    jne 9f\" -> \"    cmp byte ptr [rdi + CM_TYPE], CT_INTERPRETER\\n    jmp 9f\"",
    "a hashbang is never inside an if, switch case or unary expression, where the handlers ask"],
]);

let failed = false;
const survivors = { deletion: [], swap: [], condition: [], print: [] };
let n = 0;
for (const m of mutants) {
  const bin = build(m.text, `m${n++}`, m.replaces);
  const k = await killed(bin, m.kind === "print", m.kind === "print" ? skipPrint : skipAttach);
  if (!k.length) survivors[m.kind].push(m.name);
  else if (process.env.VERBOSE) console.log(`killed ${m.name} by ${k.slice(0, 3).join(", ")}`);
}
for (const kind of ["deletion", "swap", "condition", "print"]) {
  const total = mutants.filter((m) => m.kind === kind).length;
  console.log(`${kind}: ${total - survivors[kind].length} of ${total} killed`);
  for (const s of survivors[kind]) console.log(`  survived: ${s}${EQUIVALENT.has(s) ? ` (equivalent: ${EQUIVALENT.get(s)})` : ""}`);
  if (kind !== "swap" && survivors[kind].some((s) => !EQUIVALENT.has(s))) failed = true;
}
process.exit(failed ? 1 : 0);
