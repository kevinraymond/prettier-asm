// node tests/stage3/printer/ts-mutants.mjs [--only text] [--set "--print-width 40"] [--keep]
//
// Checks that the tests notice broken TypeScript parse and print rules. Each mutant is one edit
// inside one function of src/parse_ts*.s, a TypeScript printer file or the TypeScript comment
// check. The edited copy is written
// to a temporary directory, assembled there and linked with a copy of the objects of build/ (run
// `make` first). src/ and build/ are only read, so nothing needs restoring when a run fails.
//
// Each mutant binary runs on:
//   - tests/harness.mjs on ts-fixtures, real and js-fixtures
//   - the .ts and .js cases of those lists under one more option set (--set, default
//     --print-width 40), against Prettier in process, as sweep.mjs does
//   - ts-cases.mjs under run.mjs's three option sets
// Where Prettier throws, the binary must refuse. A mutant is killed when a case is DIFFERENT, or a
// case the unmutated binary formats identically is refused (the report says which). Exits 1 when a mutant survives that EQUIVALENT does not
// list. --only runs the mutants whose name contains the text; --keep keeps the build directory.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import prettier from "prettier";
import { run, pool, JOBS, ROOT, readCases, filepathOf } from "../../lib.mjs";
import { flagsToOptions } from "../infra/flags.mjs";
import tsCases, { filepath as tsCasesPath } from "./ts-cases.mjs";

const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const only = opt("--only", null);
const extraSet = opt("--set", "--print-width 40").split(" ").filter(Boolean);
const LISTS = ["ts-fixtures", "real", "js-fixtures"];

// [name, file, function, old text, new text]: the old text must occur once in the function.
const MUTANTS = [
  // printer: print/typescript.js
  ["type assertion: always the plain group", "pjs_typescript.s", "pts_type_assertion",
    "    TYPE rax, T_ObjectExpression\n    je 5f", "    TYPE rax, T_ObjectExpression\n    jmp 5f"],
  ["type operator: unique printed as keyof", "pjs_typescript.s", "pts_type_operator",
    "    lea rdi, [rip + sd_unique]", "    lea rdi, [rip + sd_keyof]"],
  ["property signature: readonly dropped", "pjs_typescript.s", "pts_property_signature",
    "    jz 1f\n    DPUSHL sd_readonly_sp", "    jmp 1f\n    DPUSHL sd_readonly_sp"],
  ["index signature: static dropped in a class", "pjs_typescript.s", "pts_index_signature",
    "    ATTR rbx, NA_STATIC\n    jz 3f", "    ATTR rbx, NA_STATIC\n    jmp 3f"],
  ["index signature: no trailing comma for several parameters", "pjs_typescript.s", "pts_index_signature",
    "    cmp rcx, 1\n    jbe 1f", "    cmp rcx, 1\n    jmp 1f"],
  ["method signature: get printed as set", "pjs_typescript.s", "pts_method_signature",
    "    DPUSHL sd_get_sp", "    DPUSHL sd_set_sp"],
  ["method signature: return type not grouped", "pjs_typescript.s", "pts_method_signature",
    "    mov rdi, r14\n    xor esi, esi\n    call doc_group\n    DPUSH rax", "    DPUSH r14"],
  ["module declaration: nested body printed as a declaration", "pjs_typescript.s", "pts_module_declaration",
    "    TYPE rax, T_TSModuleDeclaration\n    jne 1f", "    TYPE rax, T_TSModuleDeclaration\n    jmp 1f"],
  ["module declaration: body not grouped", "pjs_typescript.s", "pts_module_declaration",
    "    PRINT N_F1, K_body\n    GROUP_RAX", "    PRINT N_F1, K_body"],
  // printer: print/type-annotation.js
  ["first token: constructor type gets `:`", "pjs_type_annotation.s", "pta_first_token",
    "    cmp ecx, T_TSConstructorType\n    je 1f", "    cmp ecx, T_TSConstructorType\n    je 8f"],
  ["annotation property: no space before a commented annotation", "pjs_type_annotation.s", "pjs_print_type_annotation_property",
    "    call has_comment\n    test eax, eax\n    jz 5f", "    call has_comment\n    test eax, eax\n    jmp 5f"],
  ["named tuple member: optional dropped", "pjs_type_annotation.s", "pjs_print_named_tuple_member",
    "    jz 1f\n    DPUSHL ps_question", "    jmp 1f\n    DPUSHL ps_question"],
  ["type predicate: asserts dropped", "pjs_type_annotation.s", "pjs_print_type_predicate",
    "    jz 1f\n    DPUSHL sd_asserts", "    jmp 1f\n    DPUSHL sd_asserts"],
  ["shouldHugType: null replaced by undefined", "pjs_type_annotation.s", "pjs_should_hug_type",
    "    cmp edx, T_TSNullKeyword\n    je 5b", "    cmp edx, T_TSUndefinedKeyword\n    je 5b"],
  ["intersection: second object type indented", "pjs_type_annotation.s", "pjs_print_intersection_type",
    "    cmp r14, 1\n    jbe 7f", "    cmp r14, 1\n    jb 7f"],
  ["intersection: operator position inverted", "pjs_type_annotation.s", "pjs_print_intersection_type",
    "4:  cmp qword ptr [rip + g_operator_position], OP_START\n    je 5f",
    "4:  cmp qword ptr [rip + g_operator_position], OP_START\n    jne 5f"],
  ["union: indented in a type assertion", "pjs_type_annotation.s", "pjs_print_union_type",
    "    cmp eax, T_TSTypeAssertion\n    je 2f", "    cmp eax, T_TSTypeAssertion\n    nop"],
  ["union: no start line", "pjs_type_annotation.s", "pjs_print_union_type",
    "    lea r14, [rip + d_line]\n4:", "    nop\n4:"],
  ["union: no parentheses in a tuple", "pjs_type_annotation.s", "pjs_print_union_type",
    "    cmp rcx, 1\n    jbe 7f", "    cmp rcx, 1\n    jmp 7f"],
  ["union member: align 4", "pjs_type_annotation.s", "pta_union_member",
    "    mov edi, 2\n", "    mov edi, 4\n"],
  // printer: print/type-parameters.js
  ["type parameters: .ts check fails", "pjs_type_parameters.s", "ptp_filepath_ends_ts",
    "    cmp byte ptr [rdi + rcx - 1], 's'", "    cmp byte ptr [rdi + rcx - 1], 'x'"],
  ["type parameters: trailing comma on instantiations", "pjs_type_parameters.s", "pjs_print_type_parameters",
    "    TYPE rbx, T_TSTypeParameterInstantiation\n    je 23f", "    TYPE rbx, T_TSTypeParameterInstantiation\n    nop"],
  ["type parameter: default without ` = `", "pjs_type_parameters.s", "pjs_print_type_parameter",
    "    DPUSHL sd_eq_sp\n    PRINT N_F2, K_default", "    PRINT N_F2, K_default"],
  ["inline dangling comments: no hardline after a line comment", "pjs_type_parameters.s", "ptp_print_dangling_comments_for_inline",
    "    test r12d, r12d\n    jz 9f", "    test r12d, r12d\n    jmp 9f"],
  // printer: print/mapped-type.js
  ["mapped type: -readonly printed as +readonly", "pjs_mapped_type.s", "pjs_print_typescript_mapped_type",
    "    lea rdi, [rip + sd_minus_readonly]", "    lea rdi, [rip + sd_plus_readonly]"],
  ["mapped type: no ifBreak(\";\")", "pjs_mapped_type.s", "pjs_print_typescript_mapped_type",
    "    cmp qword ptr [rip + g_semi], 0\n    je 8f", "    cmp qword ptr [rip + g_semi], 0\n    jmp 8f"],
  ["mapped type: objectWrap preserve ignored", "pjs_mapped_type.s", "pjs_print_typescript_mapped_type",
    "    mov r15d, eax\n1:", "    xor r15d, r15d\n1:"],
  // printer: print/interface.js, enum.js, cast-expression.js, decorators.js
  ["interface: shouldIndentOnlyHeritageClauses always false", "pjs_interface.s", "pjs_print_interface",
    "    xor eax, 1\n    mov r15d, eax", "    xor eax, eax\n    mov r15d, eax"],
  ["interface: several extends not indented", "pjs_interface.s", "pjs_print_interface",
    "    cmp r13, 1\n    je 2f", "    cmp r13, 1\n    jmp 2f"],
  ["cast: no group as a member object", "pjs_cast_expression.s", "pjs_print_binary_cast_expression",
    "2:  cmp r15d, K_object\n    jne 3f", "2:  cmp r15d, K_object\n    jmp 3f"],
  ["decorators: class declaration not broken", "pjs_decorators.s", "pjs_print_decorators",
    "    TYPE rbx, T_ClassDeclaration\n    je 2f", "    TYPE rbx, T_ClassDeclaration\n    nop"],
  ["class member decorators: line for hardline", "pjs_decorators.s", "pjs_print_class_member_decorators",
    "    lea rsi, [rip + d_hardline]", "    lea rsi, [rip + d_line]"],
  // parser
  ["parser: readonly accepted on any type", "parse_ts.s", "jts_type_operator",
    "    cmp word ptr [rax + N_TYPE], T_TSArrayType\n    jne 90f", "    cmp word ptr [rax + N_TYPE], T_TSArrayType\n    nop"],
  ["parser: union with a leading `|` and one member unwrapped", "parse_ts.s", "jts_union_or_intersection",
    "    test r15d, r15d\n    jnz 7f", "    test r15d, r15d\n    nop"],
  ["parser: `[` after a line break continues an array type", "parse_ts.s", "jts_array_type",
    "1:  cmp qword ptr [rip + g_jt_nl], 0\n    jne 9f", "1:  cmp qword ptr [rip + g_jt_nl], 0\n    nop"],
  ["parser: mapped type `?` lost", "parse_ts.s", "jts_mapped_type",
    "    mov qword ptr [rbx + N_F4], 1", "    mov qword ptr [rbx + N_F4], 0"],
  ["parser: named tuple member `?` lost", "parse_ts.s", "jts_tuple_element",
    "    test r15d, 2\n    jz 71f", "    test r15d, 2\n    jmp 71f"],
  ["parser: string enum member names not read", "parse_ts_decl.s", "jts_enum_member",
    "    TT_IS J_STRING\n    jne 1f", "    TT_IS J_STRING\n    jmp 1f"],
  ["parser: declare global read as a namespace", "parse_ts_decl.s", "jts_ambient_module",
    "    mov qword ptr [rbx + N_F3], KD_GLOBAL", "    mov qword ptr [rbx + N_F3], KD_NAMESPACE"],
  ["parser: `asserts x` without asserts", "parse_ts.s", "jts_type_or_predicate_annotation",
    "    mov [r12 + N_F0], rax\n    or dword ptr [r12 + N_ATTR], NA_ASSERTS\n    FINISH r12\n    mov [rbx + N_F5], r12\n    jmp 8f\n5:",
    "    mov [r12 + N_F0], rax\n    FINISH r12\n    mov [rbx + N_F5], r12\n    jmp 8f\n5:"],
  ["parser: infer constraint kept before `?`", "parse_ts.s", "jts_infer_constraint",
    "    TT_IS J_QUESTION\n    jne 9f", "    TT_IS J_QUESTION\n    jmp 9f"],
  ["parser: `(a?:` not a function type start", "parse_ts.s", "jts_unambiguous_function_type",
    "    TT_IS J_QUESTION\n    je 9f", "    TT_IS J_QUESTION\n    nop"],
  ["parser: private read as protected", "parse_ts.s", "jts_modifiers",
    "    mov eax, KD_PRIVATE", "    mov eax, KD_PROTECTED"],
  ["parser: optional property signature loses `?`", "parse_ts.s", "jts_property_or_method_signature",
    "    or dword ptr [rbx + N_ATTR], NA_OPTIONAL", "    nop"],
  ["parser: definite `!` lost", "parse_ts_decl.s", "jts_var_id",
    "    or dword ptr [rbx + N_ATTR], NA_DEFINITE", "    nop"],
  ["parser: decorated parameters allowed in class expressions", "parse_ts.s", "jts_check_param_decorators",
    "    cmp r12d, T_ClassDeclaration\n    jne 90f", "    cmp r12d, T_ClassDeclaration\n    nop"],
  ["parser: decorated `this` allowed", "parse_ts.s", "jts_check_param_decorators",
    "    call ts_is_this_param\n    test eax, eax\n    jnz 90f", "    call ts_is_this_param\n    test eax, eax\n    nop"],
  ["comments: superclass instantiation before implements not refused", "pjs_comment_print.s", "pjs_check_ts_comments",
    "    cmp rcx, [r13 + CM_FOLL]\n    jne 97f", "    cmp rcx, [r13 + CM_FOLL]\n    nop"],
  ["parser: declare not set on a variable in jts_try_declare", "parse_ts_decl.s", "jts_try_declare",
    "    or dword ptr [rax + N_ATTR], NA_DECLARE\n    jmp 89f", "    jmp 89f"],
];

// Mutants no input can tell apart from the original, with the reason. Reported, not failed.
const EQUIVALENT = new Map([
  ["index signature: no trailing comma for several parameters",
    "dead code: the parser reads one parameter, as Babel's tsTryParseIndexSignature does, and refuses a second"],
  ["method signature: return type not grouped",
    "each doc a return type prints to keeps its lines inside groups of its own, so the extra group changes no break"],
  ["module declaration: body not grouped",
    "a TSModuleBlock prints as `{}` or with hardlines only, so the group changes no break"],
  ["parser: readonly accepted on any type",
    "the refusal is Babel's error; Prettier's typescript parser takes `readonly T` for any T and prints what the mutant prints"],
  ["parser: union with a leading `|` and one member unwrapped",
    "the postprocess (parse_js_post.s, as Prettier's) replaces a one-member union by its member, so the tree is the same"],
  ["parser: declare not set on a variable in jts_try_declare",
    "jts_expression_statement, the only caller, sets NA_DECLARE on what jts_try_declare returns"],
]);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ts-mutants-"));
if (!argv.includes("--keep")) process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
// A copy of the objects, so a `make` running meanwhile cannot mix two builds.
const objDir = path.join(tmp, "objs");
fs.mkdirSync(objDir);
for (const f of fs.readdirSync(path.join(ROOT, "build")).filter((f) => f.endsWith(".o")))
  fs.copyFileSync(path.join(ROOT, "build", f), path.join(objDir, f));
const objs = fs.readdirSync(objDir).map((f) => path.join(objDir, f));

function build(name, file, text) {
  const dir = path.join(tmp, name);
  fs.mkdirSync(dir);
  const s = path.join(dir, file), o = path.join(dir, file.replace(/\.s$/, ".o")), bin = path.join(dir, "prettier-asm");
  fs.writeFileSync(s, text);
  execFileSync("as", ["--64", "-I", path.join(ROOT, "src"), "-o", o, s]);
  execFileSync("ld", ["-static", "-o", bin, o, ...objs.filter((x) => path.basename(x) !== path.basename(o))]);
  return bin;
}

const sources = new Map();
const src = (file) => sources.get(file) ?? (sources.set(file, fs.readFileSync(path.join(ROOT, "src", file), "utf8")), sources.get(file));
// -> the mutated file text; throws when the old text does not occur once in the function
function mutate([name, file, fn, from, to]) {
  const text = src(file);
  const start = text.indexOf(`FUNC ${fn}\n`), end = text.indexOf(`ENDF ${fn}\n`, start);
  if (start < 0 || end < 0) throw new Error(`${file}: no function ${fn}`);
  const body = text.slice(start, end);
  if (body.split(from).length !== 2) throw new Error(`${name}: the old text does not occur once in ${fn}`);
  return text.slice(0, start) + body.replace(from, to) + text.slice(end);
}
const selected = MUTANTS.map((m, i) => [i, m]).filter(([, m]) => !only || m[0].includes(only));
const texts = new Map(selected.map(([i, m]) => [i, mutate(m)]));

// The extra option set and ts-cases.mjs: Prettier's output, computed once.
const sweepCases = [];
for (const list of LISTS) for (const c of readCases(list)) {
  const fp = filepathOf(c);
  if (!/\.(js|mjs|cjs|ts|mts|cts)$/.test(fp ?? "")) continue;
  const base = c.args.filter((a, i) => a !== "--stdin-filepath" && c.args[i - 1] !== "--stdin-filepath");
  const flags = [...base.filter((a, i) => !(extraSet.includes(a) || extraSet.includes(base[i - 1]) && base[i - 1].startsWith("--"))), ...extraSet];
  let expected = null;
  try { expected = await prettier.format(c.stdin, { filepath: fp, ...flagsToOptions(flags) }); } catch {}
  sweepCases.push({ name: `${list}/${c.name} ${extraSet.join(" ")}`, args: ["--stdin-filepath", fp, ...flags], input: c.stdin, expected });
}
for (const c of tsCases) {
  const [code, flags = []] = Array.isArray(c) ? c : [c];
  for (const extra of [[], ["--print-width", "40"], ["--no-semi"]]) {
    const all = [...flags, ...extra];
    let expected = null;
    try { expected = await prettier.format(code, { filepath: tsCasesPath, ...flagsToOptions(all) }); } catch {}
    sweepCases.push({ name: `ts-cases ${JSON.stringify(code).slice(0, 60)} ${all.join(" ")}`, args: ["--stdin-filepath", tsCasesPath, ...all], input: code, expected });
  }
}

// -> Map name -> "identical" | "refused" | "DIFFERENT" (harness classes folded the same way)
async function evaluate(bin) {
  const res = new Map();
  for (const list of LISTS) {
    const r = spawnSync(process.execPath, [path.join(ROOT, "tests/harness.mjs"), bin, list, "--json"], { encoding: "utf8", maxBuffer: 1 << 28 });
    const j = JSON.parse(r.stdout);
    for (const c of j.cases) res.set(`${list}/${c.name}`, c.class === "DIFFERENT" ? "DIFFERENT" : c.class === "identical" ? "identical" : "refused");
  }
  const out = await pool(sweepCases, JOBS, async (c) => {
    const r = await run(bin, c.args, { input: c.input, timeout: 10_000 });
    if (r.status === 3) return c.expected === null ? "identical" : "refused";
    return r.status === 0 && r.stdout.toString("utf8") === c.expected ? "identical" : "DIFFERENT";
  });
  sweepCases.forEach((c, i) => res.set(c.name, out[i]));
  return res;
}

const baseBin = path.join(tmp, "base");
execFileSync("ld", ["-static", "-o", baseBin, ...objs]);
const baseline = await evaluate(baseBin);
const baseDifferent = [...baseline].filter(([, k]) => k === "DIFFERENT").map(([n]) => n);
if (baseDifferent.length) {
  console.log(`the unmutated binary is DIFFERENT on ${baseDifferent.length} cases (${baseDifferent.slice(0, 3).join(", ")}); fix those first`);
  process.exit(1);
}
console.log(`${baseline.size} cases per mutant (${[...baseline.values()].filter((k) => k === "identical").length} identical before mutation)`);

let survived = 0, killed = 0, failed = false;
for (const [i, [name, file]] of selected) {
  const bin = build(`m${i}`, file, texts.get(i));
  const res = await evaluate(bin);
  const different = [], refused = [];
  for (const [n, k] of res) {
    if (k === "DIFFERENT") different.push(n);
    else if (k === "refused" && baseline.get(n) === "identical") refused.push(n);
  }
  if (different.length || refused.length) {
    killed++;
    const by = different.length ? `${different.length} DIFFERENT, first ${different[0]}` : `refusals only: ${refused.length}, first ${refused[0]}`;
    console.log(`killed: ${name} (${by})`);
  } else {
    survived++;
    const eq = EQUIVALENT.get(name);
    console.log(`SURVIVED: ${name}${eq ? ` (equivalent: ${eq})` : ""}${argv.includes("--keep") ? ` (${bin})` : ""}`);
    if (!eq) failed = true;
  }
}
console.log(`ts mutants: ${killed} of ${killed + survived} killed`);
process.exit(failed ? 1 : 0);
