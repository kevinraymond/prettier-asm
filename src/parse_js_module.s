# JS import and export declarations (Babel's parseImport and parseExport).
.include "defs.inc"
.include "parse_js.inc"

    .section .rodata
s_default: .ascii "default"
    .text

# jpm_eat_word(kw) -> eax = 1 if the current token is the word kw and was consumed
FUNC jpm_eat_word
    xor eax, eax
    TT_IS J_NAME
    jne 9f
    cmp [rip + g_jt_kw], rdi
    jne 9f
    NEXT
    mov eax, 1
9:  leave
    ret
ENDF jpm_eat_word

# jpm_string() -> rax: StringLiteral from the current token (refuses others)
FUNC jpm_string
    push rbx
    sub rsp, 8
    TT_IS J_STRING
    jne 90f
    NODE T_StringLiteral, [rip + g_jt_start]
    mov rbx, rax
    mov rax, [rip + g_jt_end]
    mov [rbx + N_END], eax
    mov rax, [rip + g_jt_val]
    mov [rbx + N_F0], rax
    mov rax, [rip + g_jt_len]
    mov [rbx + N_F1], rax
    NEXT
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: string expected"
ENDF jpm_string

# jpm_export_name() -> rax: a module export name (string or any word). A string may not hold a
# lone surrogate (a 3-byte ED A0..BF sequence in the cooked WTF-8).
FUNC jpm_export_name
    TT_IS J_STRING
    jne 1f
    call jpm_string
    mov rsi, [rax + N_F0]
    mov rcx, [rax + N_F1]
2:  cmp rcx, 2
    jb 3f
    cmp byte ptr [rsi], 0xED
    jne 21f
    cmp byte ptr [rsi + 1], 0xA0
    jae 90f
21: inc rsi
    dec rcx
    jmp 2b
3:  leave
    ret
90: REFUSE "syntax error: lone surrogate in a module export name"
1:  call js_ident_name
    leave
    ret
ENDF jpm_export_name

# jpm_note_exported(name node): refuses a second export named default
FUNC jpm_note_exported
    push rbx
    sub rsp, 8
    mov rbx, rdi
    cmp word ptr [rbx + N_TYPE], T_StringLiteral
    jne 1f
    cmp qword ptr [rbx + N_F1], 7
    jne 9f
    mov rdi, [rbx + N_F0]
    lea rsi, [rip + s_default]
    mov edx, 7
    call mem_eq
    jmp 2f
1:  mov rdi, rbx
    lea rsi, [rip + s_default]
    mov edx, 7
    call js_node_text_is
2:  test eax, eax
    jz 9f
    call jpm_note_default
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF jpm_note_exported

FUNC jpm_note_default
    cmp qword ptr [rip + g_default_exported], 0
    jne 90f
    mov qword ptr [rip + g_default_exported], 1
    leave
    ret
90: REFUSE "syntax error: more than one default export"
ENDF jpm_note_default

# jpm_attributes(node, slot offset): `with { ... }` or `assert { ... }` after a module source
FUNC jpm_attributes
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    lea rax, [rip + js_empty_vec]
    mov [rbx + r12], rax
    KW_IS KW_WITH
    jne 1f
    cmp qword ptr [rip + g_jt_nl], 0
    je 2f
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '('
    je 9f
    jmp 2f
1:  KW_IS KW_ASSERT
    jne 9f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    or dword ptr [rbx + N_ATTR], NA_DEPRECATED_ASSERT_SYNTAX
2:  NEXT
    EXPECT J_LBRACE
    call ss_mark
    mov r13, rax
3:  TT_IS J_RBRACE
    je 8f
    NODE T_ImportAttribute, [rip + g_jt_start]
    mov r14, rax
    TT_IS J_STRING
    jne 4f
    call jpm_string
    jmp 5f
4:  call js_ident_name
5:  mov [r14 + N_F0], rax
    EXPECT J_COLON
    call jpm_string
    mov [r14 + N_F1], rax
    FINISH r14
    mov rdi, r14
    call ss_push
    TT_IS J_COMMA
    jne 8f
    NEXT
    jmp 3b
8:  EXPECT J_RBRACE
    mov rdi, r13
    call ss_to_vec
    mov [rbx + r12], rax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpm_attributes

# jpm_import() -> rax: ImportDeclaration; the current token is `import`
FUNC jpm_import
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    NODE T_ImportDeclaration, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    lea rax, [rip + js_empty_vec]
    mov [rbx + N_F0], rax
    xor r15d, r15d                      # TypeScript: a default specifier already read (`type`)
    IF_NOT_TS 5f
    mov qword ptr [rbx + N_F3], KD_VALUE
    TT_IS J_STRING
    je 50f
    call ts_tok_is_ident
    test eax, eax
    jz 5f
    call ts_lookahead_char
    cmp eax, '='
    jne 3f
    mov rdi, rbx                        # import x = ...
    xor esi, esi
    xor edx, edx
    call jts_import_equals
    jmp 99f
3:  KW_IS KW_TYPE
    jne 5f
    mov rdi, rbx
    call jpm_type_phase
    mov r15, rax
    call ts_lookahead_char
    cmp eax, '='
    jne 4f
    mov rdi, rbx                        # import type x = require(...)
    mov rsi, r15
    xor edx, edx
    call jts_import_equals
    jmp 99f
4:  test r15, r15
    jnz 10f
    jmp 10f
5:  TT_IS J_STRING
    je 50f
    # import phases: source, defer, module
    TT_IS J_NAME
    jne 10f
    mov rax, [rip + g_jt_kw]
    cmp rax, KW_SOURCE
    je 1f
    cmp rax, KW_DEFER
    je 1f
    cmp rax, KW_MODULE
    jne 10f
1:  call jl_peek
    cmp eax, J_NAME
    jne 2f
    cmp edx, KW_FROM
    jne 90f
    mov rdi, r9
    call jl_next_char
    cmp eax, 'f'
    je 90f
    jmp 10f
2:  cmp eax, J_COMMA
    jne 90f
10: call ss_mark
    mov r12, rax
    xor r13d, r13d                      # 1 after a default specifier
    test r15, r15
    jz 11f
    mov esi, [r15 + N_START]
    NODE T_ImportDefaultSpecifier, rsi
    mov r14, rax
    mov [r14 + N_F0], r15
    FINISH r14
    jmp 12f
11: TT_IS J_NAME
    jne 20f
    NODE T_ImportDefaultSpecifier, [rip + g_jt_start]
    mov r14, rax
    mov edi, 1
    call js_ident
    mov [r14 + N_F0], rax
    FINISH r14
12:
    mov rdi, r14
    call ss_push
    mov r13d, 1
    TT_IS J_COMMA
    jne 40f
    NEXT
20: TT_IS J_STAR
    jne 30f
    NODE T_ImportNamespaceSpecifier, [rip + g_jt_start]
    mov r14, rax
    NEXT
    mov edi, KW_AS
    call jpm_eat_word
    test eax, eax
    jz 91f
    mov edi, 1
    call js_ident
    mov [r14 + N_F0], rax
    FINISH r14
    mov rdi, r14
    call ss_push
    jmp 40f
30: EXPECT J_LBRACE
    xor r13d, r13d
31: TT_IS J_RBRACE
    je 39f
    test r13d, r13d
    jz 32f
    TT_IS J_COLON
    je 91f
    EXPECT J_COMMA
    TT_IS J_RBRACE
    je 39f
32: mov r13d, 1
    NODE T_ImportSpecifier, [rip + g_jt_start]
    mov r14, rax
    IF_NOT_TS 321f
    KW_IS KW_TYPE                       # import { type x }
    jne 322f
    mov rdi, r14
    mov esi, 1
    mov rdx, [rbx + N_F3]
    call jpm_type_only_specifier
    jmp 38f
322: mov qword ptr [r14 + N_F2], KD_VALUE
321: xor r15d, r15d                      # word of the imported name; -1 for a string
    TT_IS J_STRING
    jne 33f
    mov r15, -1
    jmp 34f
33: mov r15, [rip + g_jt_kw]
34: call jpm_export_name
    mov [r14 + N_F0], rax
    mov edi, KW_AS
    call jpm_eat_word
    test eax, eax
    jz 35f
    mov edi, 1
    call js_ident
    mov [r14 + N_F1], rax
    jmp 38f
35: cmp r15, -1
    je 91f
    cmp r15, KW_LET
    je 92f
    mov rdi, r15
    mov esi, 1
    call js_word_check
37: mov rdi, [r14 + N_F0]
    call js_clone
    mov [r14 + N_F1], rax
38: FINISH r14
    mov rdi, r14
    call ss_push
    jmp 31b
39: NEXT
40: mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
    mov edi, KW_FROM
    call jpm_eat_word
    test eax, eax
    jz 91f
50: call jpm_string
    mov [rbx + N_F1], rax
    mov rdi, rbx
    mov esi, N_F2
    call jpm_attributes
    call js_semicolon
    FINISH rbx
    mov rax, rbx
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "import phase or reflection"
91: REFUSE "syntax error: in import"
92: REFUSE "syntax error: let as a lexical binding name"
ENDF jpm_import

# jpm_from(node, required): `from "source"` with attributes, then the semicolon
FUNC jpm_from
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi
    mov edi, KW_FROM
    call jpm_eat_word
    test eax, eax
    jz 1f
    call jpm_string
    mov [rbx + N_F2], rax
    mov rdi, rbx
    mov esi, N_F3
    call jpm_attributes
    jmp 2f
1:  test r12d, r12d
    jnz 90f
2:  call js_semicolon
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: from expected"
ENDF jpm_from

# jpm_export(decorators VEC or 0) -> rax; the current token is `export`. decorators: read before
# `export`, for the class that follows.
FUNC jpm_export
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov [rsp], rdi                      # decorators
    mov qword ptr [rsp + 8], 0          # TypeScript exportKind
    NODE T_ExportNamedDeclaration, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    lea rax, [rip + js_empty_vec]
    mov [rbx + N_F1], rax
    mov [rbx + N_F3], rax
    IF_NOT_TS 9f
    mov qword ptr [rsp + 8], KD_VALUE
    KW_IS KW_IMPORT
    je 100f
    TT_IS J_EQ
    je 101f
    KW_IS KW_AS
    je 102f
    KW_IS KW_TYPE
    jne 9f
    call ts_lookahead_char
    cmp eax, '{'
    je 1f
    cmp eax, '*'
    jne 9f
1:  NEXT                                # export type { ... }, export type *
    mov qword ptr [rsp + 8], KD_TYPE
9:  TT_IS J_STAR
    je 10f
    KW_IS KW_DEFAULT
    je 20f
    TT_IS J_LBRACE
    je 30f
    TT_IS J_AT
    je 40f
    IF_NOT_TS 11f
    call jpm_ts_declaration_start
    test eax, eax
    jnz 42f
    # declarations
11: KW_IS KW_VAR
    je 40f
    KW_IS KW_CONST
    je 40f
    KW_IS KW_FUNCTION
    je 40f
    KW_IS KW_CLASS
    je 41f
    KW_IS KW_LET
    jne 1f
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '['
    je 40f
    cmp eax, '{'
    je 40f
    mov rdi, rdx
    call jps_starts_binding_ident
    test eax, eax
    jnz 40f
    jmp 92f
1:  call jps_is_async_function
    test eax, eax
    jnz 40f
    TT_IS J_NAME
    jne 91f
    # export v from "mod" (exportDefaultFrom) or an error
    jmp 92f
    # export * from, export * as ns from
10: mov r12, [rip + g_jt_start]
    NEXT
    KW_IS KW_AS
    jne 15f
    NODE T_ExportNamespaceSpecifier, r12
    mov r13, rax
    NEXT
    call jpm_export_name
    mov [r13 + N_F0], rax
    FINISH r13
    mov rdi, [r13 + N_F0]
    call jpm_note_exported
    mov rdi, r13
    call js_vec1
    mov [rbx + N_F1], rax
    TT_IS J_COMMA
    je 91f
    mov rdi, rbx
    mov esi, 1
    call jpm_from
    jmp 98f
15: mov word ptr [rbx + N_TYPE], T_ExportAllDeclaration
    mov edi, KW_FROM
    call jpm_eat_word
    test eax, eax
    jz 91f
    call jpm_string
    mov [rbx + N_F0], rax
    mov rdi, rbx
    mov esi, N_F1
    call jpm_attributes
    mov qword ptr [rbx + N_F2], 0
    call js_semicolon
    jmp 98f
    # export default
20: mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, ','
    je 92f
    mov word ptr [rbx + N_TYPE], T_ExportDefaultDeclaration
    mov qword ptr [rbx + N_F1], 0
    mov qword ptr [rbx + N_F3], 0
    IF_TS 201f
    call jpm_note_default
201: NEXT
    mov r12, [rip + g_jt_start]
    IF_NOT_TS 202f
    KW_IS KW_ABSTRACT                   # export default abstract class
    jne 203f
    call ts_is_lookahead_class
    test eax, eax
    jz 202f
    # typescript-estree reads `abstract` before a line break as an expression
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 96f
    NODE T_ClassDeclaration, r12
    mov r13, rax
    or dword ptr [r13 + N_ATTR], NA_ABSTRACT
    NEXT
    mov rdi, r13
    mov esi, 1
    mov edx, 1
    call jpf_class
    jmp 29f
203: KW_IS KW_INTERFACE                  # export default interface
    jne 202f
    NODE T_TSInterfaceDeclaration, r12
    mov rdi, rax
    xor esi, esi
    call jts_interface
    test rax, rax
    jnz 29f
202: KW_IS KW_FUNCTION
    jne 21f
    NODE T_FunctionDeclaration, r12
    mov r13, rax
    NEXT
    jmp 22f
21: call jps_is_async_function
    test eax, eax
    jz 23f
    NODE T_FunctionDeclaration, r12
    mov r13, rax
    or dword ptr [r13 + N_ATTR], NA_ASYNC
    NEXT
    NEXT
22: mov rdi, r13
    mov esi, 3
    call jpf_function
    jmp 29f
23: KW_IS KW_CLASS
    jne 24f
    NODE T_ClassDeclaration, r12
    mov rdi, rax
    mov esi, 1
    mov edx, 1
    call jpf_class
    jmp 29f
24: TT_IS J_AT
    jne 241f
    call jpd_decorators
    mov r13, rax
    KW_IS KW_CLASS
    jne 93f
    NODE T_ClassDeclaration, [rip + g_jt_start]
    mov rdi, rax
    mov esi, 1
    mov edx, 1
    call jpf_class
    mov rdi, rax
    mov rsi, r13
    call js_take_decorators
    jmp 29f
241: KW_IS KW_CONST
    je 91f
    KW_IS KW_VAR
    je 91f
    KW_IS KW_LET
    jne 25f
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '['
    je 91f
    cmp eax, '{'
    je 91f
    mov rdi, rdx
    call jps_starts_binding_ident
    test eax, eax
    jnz 91f
25: call jpe_maybe_assign_allow_in
    mov r13, rax
    cmp word ptr [r13 + N_TYPE], T_Identifier
    jne 26f
    mov rdi, r13
    lea rsi, [rip + s_from]
    mov edx, 4
    call js_node_text_is
    test eax, eax
    jnz 92f
26: call js_semicolon
    mov rax, r13
29: mov [rbx + N_F0], rax
    cmp word ptr [rax + N_TYPE], T_ClassDeclaration
    jne 98f
    mov rdi, rax
    mov rsi, [rsp]
    call js_take_decorators
    mov qword ptr [rsp], 0
    mov ecx, [rax + N_START]
    cmp ecx, [rbx + N_START]
    jae 98f
    mov [rbx + N_START], ecx
    jmp 98f
    # export { ... }
30: NEXT
    call ss_mark
    mov r12, rax
    xor r13d, r13d                      # bit 0 not first, bit 1 a string local
31: TT_IS J_RBRACE
    je 39f
    test r13d, 1
    jz 32f
    EXPECT J_COMMA
    TT_IS J_RBRACE
    je 39f
32: or r13d, 1
    NODE T_ExportSpecifier, [rip + g_jt_start]
    mov r14, rax
    IF_NOT_TS 321f
    KW_IS KW_TYPE                       # export { type x }
    jne 322f
    mov rdi, r14
    xor esi, esi
    mov rdx, [rsp + 8]
    call jpm_type_only_specifier
    mov rdi, [r14 + N_F1]
    call jpm_note_exported
    FINISH r14
    mov rdi, r14
    call ss_push
    jmp 31b
322: mov qword ptr [r14 + N_F2], KD_VALUE
321: TT_IS J_STRING
    jne 33f
    or r13d, 2
33: TT_IS J_NAME
    jne 331f
    mov rax, [rip + g_jt_kw]
    test rax, rax
    jz 331f
    cmp rax, KW_LAST_RESERVED
    ja 331f
    or r13d, 4                          # a keyword as local name
331: call jpm_export_name
    mov [r14 + N_F0], rax
    mov edi, KW_AS
    call jpm_eat_word
    test eax, eax
    jz 34f
    call jpm_export_name
    jmp 35f
34: mov rdi, [r14 + N_F0]
    call js_clone
35: mov [r14 + N_F1], rax
    mov rdi, rax
    call jpm_note_exported
    FINISH r14
    mov rdi, r14
    call ss_push
    jmp 31b
39: NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F1], rax
    KW_IS KW_FROM
    je 391f
    test r13d, 6
    jnz 94f
391: mov rdi, rbx
    xor esi, esi
    call jpm_from
    jmp 98f
40: mov edi, 1
    call jps_statement
    jmp 29b
41: NODE T_ClassDeclaration, [rip + g_jt_start]
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    call jpf_class
    jmp 29b
    # TypeScript declarations: declare, abstract, enum, module, namespace, interface, type
42: mov rdi, rbx
    lea rsi, [rsp + 8]
    call jpm_ts_export_declaration
    jmp 29b
    # export import x = ..., export = x, export as namespace x
100: NEXT
    mov qword ptr [rbx + N_F3], KD_VALUE
    xor r12d, r12d
    KW_IS KW_TYPE
    jne 1001f
    call ts_lookahead_char
    cmp eax, '='
    je 1001f
    mov rdi, rbx
    call jpm_type_phase
    mov r12, rax
1001: mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    call jts_import_equals
    jmp 990f
101: NEXT
    mov word ptr [rbx + N_TYPE], T_TSExportAssignment
    call jpe_expression_allow_in
    mov [rbx + N_F0], rax
    mov qword ptr [rbx + N_F1], 0
    mov qword ptr [rbx + N_F3], 0
    call js_semicolon
    jmp 989f
102: NEXT
    KW_IS KW_NAMESPACE
    jne 91f
    NEXT
    mov word ptr [rbx + N_TYPE], T_TSNamespaceExportDeclaration
    xor edi, edi
    call js_ident
    mov [rbx + N_F0], rax
    mov qword ptr [rbx + N_F1], 0
    mov qword ptr [rbx + N_F3], 0
    call js_semicolon
    jmp 989f
98: cmp qword ptr [rsp], 0
    jne 93f
    mov rax, [rsp + 8]                  # exportKind: F4, F1 or F2 by the node type
    cmp word ptr [rbx + N_TYPE], T_ExportNamedDeclaration
    jne 981f
    mov [rbx + N_F4], rax
981: cmp word ptr [rbx + N_TYPE], T_ExportDefaultDeclaration
    jne 982f
    mov [rbx + N_F1], rax
982: cmp word ptr [rbx + N_TYPE], T_ExportAllDeclaration
    jne 989f
    mov [rbx + N_F2], rax
989: FINISH rbx
    mov rax, rbx
990: add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
91: REFUSE "syntax error: in export"
92: REFUSE "syntax error: export (or the exportDefaultFrom proposal)"
93: REFUSE "syntax error: decorators on an export that is not a class"
94: REFUSE "syntax error: export of a string or keyword without from"
96: REFUSE "typescript-estree parses `export default abstract` before a line break as an expression"
ENDF jpm_export

# jpm_type_phase(node) -> rax: TypeScript's parseMaybeImportPhase at `import type`: when `type`
# is the phase it is consumed and importKind (F3) becomes type (0 returned); otherwise `type` is
# returned as the default import's Identifier.
FUNC jpm_type_phase
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call ts_lookahead_char
    cmp eax, '='
    je 8f                               # import type = ...: not a phase
    call jl_peek
    cmp eax, J_NAME
    jne 2f
    cmp edx, KW_FROM
    jne 3f
    mov rdi, r9                         # `type from`: a phase when `from` follows again
    call jl_next_char
    cmp eax, 'f'
    je 3f
    jmp 4f
2:  cmp eax, J_COMMA
    je 4f
3:  NEXT
    mov qword ptr [rbx + N_F3], KD_TYPE
8:  xor eax, eax
    jmp 9f
4:  call js_ident_name
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF jpm_type_phase

# jpm_type_only_specifier(specifier, is_import, kind): parseTypeOnlyImportExportSpecifier at a
# specifier starting with the word `type`. kind: the declaration's importKind or exportKind.
# Import specifiers have imported F0 and local F1, export specifiers local F0 and exported F1;
# the specifier's kind goes in F2.
FUNC jpm_type_only_specifier
    ENTER5 24
    mov rbx, rdi
    mov r12d, esi
    mov [rsp], rdx
    mov [rip + g_spec_is_import], r12
    call js_ident_name                  # `type`
    mov r13, rax                        # leftOfAs
    xor r14d, r14d                      # rightOfAs
    xor r15d, r15d                      # bit 0 hasTypeSpecifier, bit 1 cannot parse `as`
    KW_IS KW_AS
    jne 5f
    call js_ident_name                  # firstAs
    mov [rsp + 8], rax
    KW_IS KW_AS
    jne 3f
    call js_ident_name                  # secondAs
    mov [rsp + 16], rax
    or r15d, 2
    TT_IS J_NAME
    jne 2f
    or r15d, 1                          # type as as x
    mov r13, [rsp + 8]
    call jpm_specifier_name
    mov r14, rax
    jmp 8f
2:  mov r14, [rsp + 16]                 # type as as
    jmp 8f
3:  TT_IS J_NAME
    jne 4f
    or r15d, 2                          # type as x
    call jpm_specifier_name
    mov r14, rax
    jmp 8f
4:  or r15d, 1                          # type as
    mov r13, [rsp + 8]
    jmp 8f
5:  TT_IS J_NAME
    jne 8f
    or r15d, 1                          # type x
    test r12d, r12d
    jz 7f
    call js_ident_name
    mov r13, rax
    jmp 8f
7:  call jpm_export_name
    mov r13, rax
8:  test r15d, 1
    jz 81f
    cmp qword ptr [rsp], KD_TYPE
    je 90f
81: mov [rbx + N_F0], r13
    mov [rbx + N_F1], r14
    mov rax, KD_VALUE
    test r15d, 1
    jz 82f
    mov rax, KD_TYPE
82: mov [rbx + N_F2], rax
    test r15d, 2
    jnz 83f
    KW_IS KW_AS
    jne 83f
    NEXT
    call jpm_specifier_name
    mov [rbx + N_F1], rax
83: cmp qword ptr [rbx + N_F1], 0
    jne 84f
    mov rdi, [rbx + N_F0]
    call js_clone
    mov [rbx + N_F1], rax
84: FINISH rbx
    LEAVE5 24
90: REFUSE "syntax error: type modifier in a type-only import or export"
ENDF jpm_type_only_specifier

    .bss
    .balign 8
g_spec_is_import: .quad 0
    .text

# jpm_specifier_name() -> rax: after `as`: an Identifier for an import, a module export name for an
# export (jpm_type_only_specifier sets which)
FUNC jpm_specifier_name
    cmp qword ptr [rip + g_spec_is_import], 0
    je 1f
    mov edi, 1
    call js_ident
    leave
    ret
1:  call jpm_export_name
    leave
    ret
ENDF jpm_specifier_name

# jpm_ts_declaration_start() -> eax: tsIsDeclarationStart: abstract, declare, enum, module,
# namespace, interface or type
FUNC jpm_ts_declaration_start
    xor eax, eax
    TT_IS J_NAME
    jne 9f
    mov rcx, [rip + g_jt_kw]
    cmp rcx, KW_ABSTRACT
    je 8f
    cmp rcx, KW_DECLARE
    je 8f
    cmp rcx, KW_ENUM
    je 8f
    cmp rcx, KW_MODULE
    je 8f
    cmp rcx, KW_NAMESPACE
    je 8f
    cmp rcx, KW_INTERFACE
    je 8f
    cmp rcx, KW_TYPE
    jne 9f
8:  mov eax, 1
9:  leave
    ret
ENDF jpm_ts_declaration_start

# jpm_ts_modifier_line_break(): after `export` (or `export declare`), typescript-estree rejects
# abstract, declare, type, interface, namespace and module followed by a line break; Babel reads
# some of them as an expression
FUNC jpm_ts_modifier_line_break
    TT_IS J_NAME
    jne 9f
    mov rcx, [rip + g_jt_kw]
    cmp rcx, KW_ABSTRACT
    je 1f
    cmp rcx, KW_DECLARE
    je 1f
    cmp rcx, KW_TYPE
    je 1f
    cmp rcx, KW_INTERFACE
    je 1f
    cmp rcx, KW_NAMESPACE
    je 1f
    cmp rcx, KW_MODULE
    jne 9f
1:  mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 90f
9:  leave
    ret
90: REFUSE "rejected by Prettier's typescript parser: a line break after a modifier following `export`"
ENDF jpm_ts_modifier_line_break

# jpm_ts_export_declaration(export node, exportKind slot) -> rax: TypeScript's
# parseExportDeclaration for a declaration starting with one of jpm_ts_declaration_start's words
FUNC jpm_ts_export_declaration
    ENTER5 24
    mov rbx, rdi
    mov r12, rsi
    TS_SAVE [rsp]
    mov r13, [rip + g_jt_start]         # start
    xor r14d, r14d                      # declare
    call jpm_ts_modifier_line_break
    KW_IS KW_DECLARE
    jne 2f
    or qword ptr [rip + g_ts], TS_AMBIENT
    NEXT
    mov r14d, 1
    call jpm_ts_modifier_line_break
    KW_IS KW_DECLARE
    je 90f
    call jpm_ts_declaration_start
    test eax, eax
    jnz 2f
    KW_IS KW_VAR
    je 2f
    KW_IS KW_CONST
    je 2f
    KW_IS KW_FUNCTION
    je 2f
    KW_IS KW_CLASS
    je 2f
    KW_IS KW_LET
    je 2f
    call jps_is_async_function
    test eax, eax
    jz 90f
2:  xor eax, eax
    call ts_tok_is_ident
    test eax, eax
    jz 3f
    NODE T_TSModuleDeclaration, [rip + g_jt_start]
    mov rdi, rax
    mov rsi, [rip + g_jt_kw]
    mov edx, 1
    xor ecx, ecx
    call jts_declaration
    test rax, rax
    jnz 5f
3:  KW_IS KW_CLASS
    jne 4f
    NODE T_ClassDeclaration, [rip + g_jt_start]
    mov rdi, rax
    mov esi, 1
    xor edx, edx
    call jpf_class
    jmp 5f
4:  mov edi, 1
    call jps_statement
5:  mov r15, rax
    movzx eax, word ptr [r15 + N_TYPE]
    cmp eax, T_TSInterfaceDeclaration
    je 6f
    cmp eax, T_TSTypeAliasDeclaration
    je 6f
    test r14d, r14d
    jz 7f
6:  mov qword ptr [r12], KD_TYPE
7:  test r14d, r14d
    jz 8f
    cmp word ptr [r15 + N_TYPE], T_TSImportEqualsDeclaration
    je 8f
    mov [r15 + N_START], r13d
    or dword ptr [r15 + N_ATTR], NA_DECLARE
8:  TS_RESTORE TS_AMBIENT, [rsp]
    mov rax, r15
    LEAVE5 24
90: REFUSE "syntax error: export declare must be followed by an ambient declaration"
ENDF jpm_ts_export_declaration

    .section .rodata
s_from: .ascii "from"
