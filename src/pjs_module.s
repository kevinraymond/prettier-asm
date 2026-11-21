# print/module.js. Import phases do not occur (the parser refuses them).
.include "pjs.inc"

SDOC sd_import, "import"
SDOC sd_export, "export"
SDOC sd_default_sp, " default"
SDOC sd_star_sp, " *"
SDOC sd_from_sp, " from"
SDOC sd_comma_sp, ", "
SDOC sd_as_sp, " as "
SDOC sd_with_open, " with {"
SDOC sd_assert_open, " assert {"

    .section .rodata
s_from: .ascii "from"
s_assert: .ascii "assert"
s_with: .ascii "with"

    .bss
    .balign 8
comma_line: .quad 0             # [",", line]

    .text

# pjs_print_import_declaration(node, args) -> rax (printImportDeclaration)
FUNC pjs_print_import_declaration
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_import
    mov rdi, [rbx + N_F3]           # importKind
    mov esi, 1
    call pjs_print_import_or_export_kind
    DPUSH rax
    mov rdi, rbx
    mov rsi, [rbx + N_F0]
    call pmo_print_module_specifiers
    DPUSH rax
    mov rdi, rbx
    call pmo_print_module_source
    DPUSH rax
    mov rdi, rbx
    call pmo_print_import_attributes
    DPUSH rax
    call pjs_semi_doc
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_import_declaration

# pjs_print_export_declaration(node, args) -> rax (printExportDeclaration)
FUNC pjs_print_export_declaration
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_decorators_before_export
    DPUSH rax
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    DPUSHL sd_export
    TYPE rbx, T_ExportDefaultDeclaration
    jne 1f
    DPUSHL sd_default_sp
1:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 2f
    DPUSHL ps_space
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
    mov rdi, rbx
    call pjs_needs_hardline_after_dangling_comment
    test eax, eax
    jz 2f
    DPUSHL d_hardline
    # declaration: ExportDefaultDeclaration and ExportNamedDeclaration keep it in F0
2:  TYPE rbx, T_ExportAllDeclaration
    je 4f
    cmp qword ptr [rbx + N_F0], 0
    je 3f
    DPUSHL ps_space
    PRINT N_F0, K_declaration
    DPUSH rax
    jmp 6f
    # printExportKind: exportKind is F4 in ExportNamedDeclaration
3:  mov rdi, [rbx + N_F4]
    mov esi, 1
    call pjs_print_import_or_export_kind
    DPUSH rax
    mov rdi, rbx
    mov rsi, [rbx + N_F1]
    call pmo_print_module_specifiers
    DPUSH rax
    jmp 5f
    # exportKind is F2 in ExportAllDeclaration
4:  mov rdi, [rbx + N_F2]
    mov esi, 1
    call pjs_print_import_or_export_kind
    DPUSH rax
    DPUSHL sd_star_sp
5:  mov rdi, rbx
    call pmo_print_module_source
    DPUSH rax
    mov rdi, rbx
    call pmo_print_import_attributes
    DPUSH rax
    # printSemicolonAfterExportDeclaration
6:  cmp qword ptr [rip + g_semi], 0
    je 9f
    TYPE rbx, T_ExportAllDeclaration
    je 8f
    mov rax, [rbx + N_F0]
    test rax, rax
    jz 8f
    TYPE rbx, T_ExportDefaultDeclaration
    jne 9f
    TYPE rax, T_ClassDeclaration
    je 9f
    TYPE rax, T_FunctionDeclaration
    je 9f
    TYPE rax, T_TSInterfaceDeclaration
    je 9f
    TYPE rax, T_TSDeclareFunction
    je 9f
8:  DPUSHL ps_semi
9:  DARRAY r12
    EPILOGUE
ENDF pjs_print_export_declaration

# pmo_source(node) -> rax: node.source, or 0
FUNC pmo_source
    xor eax, eax
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_ImportDeclaration
    je 1f
    cmp ecx, T_ExportNamedDeclaration
    je 2f
    cmp ecx, T_ExportAllDeclaration
    jne 9f
    mov rax, [rdi + N_F0]
    jmp 9f
1:  mov rax, [rdi + N_F1]
    jmp 9f
2:  mov rax, [rdi + N_F2]
9:  leave
    ret
ENDF pmo_source

# pmo_source_slot(node) -> eax: the field offset of node.source
FUNC pmo_source_slot
    mov eax, N_F0
    cmp word ptr [rdi + N_TYPE], T_ImportDeclaration
    jne 1f
    mov eax, N_F1
1:  cmp word ptr [rdi + N_TYPE], T_ExportNamedDeclaration
    jne 2f
    mov eax, N_F2
2:  leave
    ret
ENDF pmo_source_slot

# pmo_attributes_slot(node) -> eax: the field offset of node.attributes
FUNC pmo_attributes_slot
    mov eax, N_F1
    cmp word ptr [rdi + N_TYPE], T_ImportDeclaration
    jne 1f
    mov eax, N_F2
1:  cmp word ptr [rdi + N_TYPE], T_ExportNamedDeclaration
    jne 2f
    mov eax, N_F3
2:  leave
    ret
ENDF pmo_attributes_slot

# pmo_comment_end_at(pos) -> rax: the end of the comment holding text[pos], or 0
FUNC pmo_comment_end_at
    xor eax, eax
    mov rcx, [rip + g_comments]
    test rcx, rcx
    jz 9f
    xor edx, edx
1:  cmp edx, [rcx]
    jae 9f
    mov r8, [rcx + 8 + rdx*8]
    inc edx
    mov r9d, [r8 + CM_START]
    cmp rdi, r9
    jb 1b
    mov r9d, [r8 + CM_END]
    cmp rdi, r9
    jae 1b
    mov eax, r9d
9:  leave
    ret
ENDF pmo_comment_end_at

# pmo_comment_start_at(pos) -> rax: the start of the comment holding
# text[pos], or -1
FUNC pmo_comment_start_at
    mov rax, -1
    mov rcx, [rip + g_comments]
    test rcx, rcx
    jz 9f
    xor edx, edx
1:  cmp edx, [rcx]
    jae 9f
    mov r8, [rcx + 8 + rdx*8]
    inc edx
    mov r9d, [r8 + CM_START]
    cmp rdi, r9
    jb 1b
    mov r10d, [r8 + CM_END]
    cmp rdi, r10
    jae 1b
    mov eax, r9d
9:  leave
    ret
ENDF pmo_comment_start_at

# pmo_text_is(pos, end, str, len) -> eax: getTextWithoutComments(start, end)
# has `str` at pos: the bytes match, lie before end and outside comments
FUNC pmo_text_is
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    lea rax, [rbx + r14]
    cmp rax, r12
    ja 8f
    mov rdi, [rip + g_text]
    add rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call mem_eq
    test eax, eax
    jz 8f
    xor r15d, r15d
1:  cmp r15, r14
    jae 7f
    lea rdi, [rbx + r15]
    call pmo_comment_end_at
    test rax, rax
    jnz 8f
    inc r15
    jmp 1b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pmo_text_is

# pmo_should_print_specifiers(node) -> eax (shouldPrintSpecifiers)
FUNC pmo_should_print_specifiers
    PROLOGUE
    mov rbx, rdi
    mov eax, 1
    TYPE rbx, T_ImportDeclaration
    jne 9f
    mov rdx, [rbx + N_F0]
    VLEN rcx, rdx
    test rcx, rcx
    jnz 9f
    cmp qword ptr [rbx + N_F3], KD_TYPE  # importKind === "type"
    je 9f
    # getTextWithoutComments(node start, source start).trimEnd().endsWith("from")
    mov r12d, [rbx + N_START]
    mov rax, [rbx + N_F1]
    mov r13d, [rax + N_START]       # end of the text
    mov r14, r13
1:  cmp r14, r12
    jbe 5f
    lea rdi, [r14 - 1]
    call pmo_comment_start_at
    cmp rax, -1
    je 2f
    cmp rax, r12
    jbe 8f                          # the text starts inside a comment
    mov r14, rax
    jmp 1b
2:  mov rdi, [rip + g_text]
    mov rsi, r14
    call cp_before
    mov r15, rdx
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jz 5f
    sub r14, r15
    jmp 1b
5:  lea rdi, [r14 - 4]
    xor eax, eax
    cmp r14, 4
    jb 9f
    cmp rdi, r12
    jl 9f
    mov rsi, r13
    lea rdx, [rip + s_from]
    mov ecx, 4
    call pmo_text_is
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pmo_should_print_specifiers

# pmo_print_module_source(node) -> rax (printModuleSource)
FUNC pmo_print_module_source
    PROLOGUE
    mov rbx, rdi
    call pmo_source
    test rax, rax
    jz 9f
    DMARK r12
    mov rdi, rbx
    call pmo_should_print_specifiers
    test eax, eax
    jz 1f
    DPUSHL sd_from_sp
1:  DPUSHL ps_space
    mov rdi, rbx
    call pmo_source_slot
    mov edi, eax
    mov esi, K_source
    xor edx, edx
    call print_field
    DPUSH rax
    DARRAY r12
9:  EPILOGUE
ENDF pmo_print_module_source

# pmo_vec_alloc(count) -> rax: a VEC of count zero items
FUNC pmo_vec_alloc
    push rdi
    sub rsp, 8
    lea rdi, [rdi*8 + 8]
    call alloc
    add rsp, 8
    pop rdi
    leave
    ret
ENDF pmo_vec_alloc

# pmo_print_module_specifiers(node, specifiers) -> rax (printModuleSpecifiers)
FUNC pmo_print_module_specifiers
    PROLOGUE 4
    mov rbx, rdi
    mov r12, rsi
    call pmo_should_print_specifiers
    xor ecx, ecx
    test eax, eax
    jz 99f
    VLEN r13, r12
    test r13, r13
    jnz 1f
    lea rdi, [rip + ps_space]
    lea rsi, [rip + ps_empty_braces]
    call doc_array2
    jmp 99f
    # print each specifier into the standalone or the grouped list
1:  mov rdi, r13
    call pmo_vec_alloc
    mov r14, rax                    # standalone VEC
    mov rdi, r13
    call pmo_vec_alloc
    mov r15, rax                    # grouped VEC
    xor ebx, ebx
2:  cmp rbx, r13
    jae 4f
    mov rdi, r12
    mov rsi, rbx
    mov edx, K_specifiers
    xor ecx, ecx
    call print_elem
    mov rcx, [r12 + 8 + rbx*8]
    movzx ecx, word ptr [rcx + N_TYPE]
    mov rdx, r15
    cmp ecx, T_ExportSpecifier
    je 3f
    cmp ecx, T_ImportSpecifier
    je 3f
    mov rdx, r14
3:  mov rcx, [rdx]
    mov [rdx + 8 + rcx*8], rax
    inc qword ptr [rdx]
    inc rbx
    jmp 2b
4:  DMARK rbx
    DPUSHL ps_space
    lea rdi, [rip + sd_comma_sp]
    mov rsi, r14
    call doc_join
    DPUSH rax
    cmp qword ptr [r15], 0
    je 90f
    cmp qword ptr [r14], 0
    je 5f
    DPUSHL sd_comma_sp
    # canBreak
5:  cmp qword ptr [r15], 1
    ja 6f
    cmp qword ptr [r14], 0
    jne 6f
    xor ecx, ecx
51: cmp rcx, r13
    jae 7f
    mov rdi, [r12 + 8 + rcx*8]
    inc rcx
    mov [rsp], rcx
    xor esi, esi
    xor edx, edx
    call has_comment
    mov rcx, [rsp]
    test eax, eax
    jz 51b
    # group(["{", indent([line, join([",", line], grouped)]), ifBreak(","), line, "}"])
6:  lea rax, [rip + d_line]
    cmp qword ptr [rip + g_bracket_spacing], 0
    jne 61f
    lea rax, [rip + d_softline]
61: mov [rsp + 8], rax
    mov rax, [rip + comma_line]
    test rax, rax
    jnz 62f
    lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array2
    mov [rip + comma_line], rax
62: mov rdi, rax
    mov rsi, r15
    call doc_join
    mov rdi, [rsp + 8]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov [rsp + 16], rax
    xor edi, edi
    call pjs_should_print_comma
    xor edi, edi
    test eax, eax
    jz 63f
    lea rdi, [rip + ps_comma]
63: xor esi, esi
    xor edx, edx
    call doc_if_break
    mov [rsp + 24], rax
    DMARK r12
    DPUSHL ps_lbrace
    DPUSH [rsp + 16]
    DPUSH [rsp + 24]
    DPUSH [rsp + 8]
    DPUSHL ps_rbrace
    DARRAY r12
    GROUP_RAX
    DPUSH rax
    jmp 90f
    # ["{", " ", ...grouped, " ", "}"]
7:  DMARK r12
    DPUSHL ps_lbrace
    cmp qword ptr [rip + g_bracket_spacing], 0
    je 71f
    DPUSHL ps_space
71: DPUSH [r15 + 8]
    cmp qword ptr [rip + g_bracket_spacing], 0
    je 72f
    DPUSHL ps_space
72: DPUSHL ps_rbrace
    DARRAY r12
    DPUSH rax
90: DARRAY rbx
99: EPILOGUE
ENDF pmo_print_module_specifiers

# pmo_import_attributes_keyword(node) -> eax: 0 undefined, 1 "with", 2 "assert"
# (getImportAttributesKeyword)
FUNC pmo_import_attributes_keyword
    PROLOGUE
    mov rbx, rdi
    mov eax, 2
    ATTR rbx, NA_DEPRECATED_ASSERT_SYNTAX
    jnz 9f
    call pmo_source
    mov r12d, [rax + N_END]         # start
    mov r13d, [rbx + N_END]         # end
    mov rdi, rbx
    call pmo_attributes_slot
    mov r15, [rbx + rax]            # attributes
    test r15, r15
    jz 1f
    cmp qword ptr [r15], 0
    je 1f
    mov rax, [r15 + 8]
    mov r13d, [rax + N_START]
    # trimStart over the text with comments blanked
1:  cmp r12, r13
    jae 5f
    mov rdi, r12
    call pmo_comment_end_at
    test rax, rax
    jz 2f
    mov r12, rax
    jmp 1b
2:  mov rdi, [rip + g_text]
    mov rsi, r12
    call utf8_decode
    mov r14, rdx
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jz 5f
    add r12, r14
    jmp 1b
5:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + s_assert]
    mov ecx, 6
    call pmo_text_is
    test eax, eax
    jz 6f
    mov eax, 2
    jmp 9f
6:  mov rdi, r12
    mov rsi, r13
    lea rdx, [rip + s_with]
    mov ecx, 4
    call pmo_text_is
    test eax, eax
    jnz 9f
    VLEN rax, r15
    test rax, rax
    setnz al
    movzx eax, al
9:  EPILOGUE
ENDF pmo_import_attributes_keyword

# pmo_print_import_attributes(node) -> rax (printImportAttributes)
FUNC pmo_print_import_attributes
    PROLOGUE
    mov rbx, rdi
    call pmo_source
    test rax, rax
    jz 9f
    mov rdi, rbx
    call pmo_import_attributes_keyword
    test eax, eax
    jz 8f
    mov r14d, eax
    DMARK r12
    lea rdi, [rip + sd_with_open]
    cmp r14d, 2
    jne 1f
    lea rdi, [rip + sd_assert_open]
1:  call ss_push
    mov rdi, rbx
    call pmo_attributes_slot
    mov r13d, eax
    mov rdx, [rbx + r13]
    VLEN rcx, rdx
    test rcx, rcx
    jz 4f
    cmp qword ptr [rip + g_bracket_spacing], 0
    je 2f
    DPUSHL ps_space
2:  mov edi, r13d
    mov esi, K_attributes
    xor edx, edx
    call print_map
    lea rdi, [rip + sd_comma_sp]
    mov rsi, rax
    call doc_join
    DPUSH rax
    cmp qword ptr [rip + g_bracket_spacing], 0
    je 4f
    DPUSHL ps_space
4:  DPUSHL ps_rbrace
    DARRAY r12
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pmo_print_import_attributes

# pjs_print_module_specifier(node, args) -> rax (printModuleSpecifier)
FUNC pjs_print_module_specifier
    PROLOGUE
    mov rbx, rdi
    xor r12d, r12d                  # left
    xor r13d, r13d                  # right
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ImportSpecifier
    je 10f
    cmp eax, T_ExportSpecifier
    je 20f
    cmp eax, T_ImportDefaultSpecifier
    je 30f
    lea r12, [rip + ps_star]
    cmp eax, T_ImportNamespaceSpecifier
    je 30f
    cmp eax, T_ExportNamespaceSpecifier
    je 40f
    REFUSE "printer: printModuleSpecifier"
    # ImportSpecifier: imported as local
10: PRINT N_F0, K_imported
    mov r12, rax
    call pmo_is_shorthand
    test eax, eax
    jnz 50f
    PRINT N_F1, K_local
    mov r13, rax
    jmp 50f
    # ExportSpecifier: local as exported
20: PRINT N_F0, K_local
    mov r12, rax
    call pmo_is_shorthand
    test eax, eax
    jnz 50f
    PRINT N_F1, K_exported
    mov r13, rax
    jmp 50f
30: PRINT N_F0, K_local
    mov r13, rax
    jmp 50f
40: PRINT N_F0, K_exported
    mov r13, rax
50: DMARK r14
    # printImportOrExportKind(importKind or exportKind, false): F2 of
    # ImportSpecifier and ExportSpecifier; the other specifiers have none
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ImportSpecifier
    je 52f
    cmp eax, T_ExportSpecifier
    jne 53f
52: mov rdi, [rbx + N_F2]
    xor esi, esi
    call pjs_print_import_or_export_kind
    DPUSH rax
53: DPUSH r12
    test r12, r12
    jz 51f
    test r13, r13
    jz 51f
    DPUSHL sd_as_sp
51: DPUSH r13
    DARRAY r14
    EPILOGUE
ENDF pjs_print_module_specifier

# pmo_is_shorthand() -> eax (isShorthandSpecifier) for the Import or
# ExportSpecifier at the top of the path: both sides the same Identifier or
# StringLiteral at the same location
FUNC pmo_is_shorthand
    call path_value
    mov rcx, [rax + N_F0]
    mov rdx, [rax + N_F1]
    xor eax, eax
    test rcx, rcx
    jz 9f
    test rdx, rdx
    jz 9f
    movzx r8d, word ptr [rcx + N_TYPE]
    cmp r8w, [rdx + N_TYPE]
    jne 9f
    cmp r8d, T_Identifier
    je 1f
    cmp r8d, T_StringLiteral
    jne 9f
1:  mov r8d, [rcx + N_START]
    cmp r8d, [rdx + N_START]
    jne 9f
    mov r8d, [rcx + N_END]
    cmp r8d, [rdx + N_END]
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF pmo_is_shorthand

SDOC sd_kind_type_after, "type "
SDOC sd_kind_typeof_after, "typeof "
SDOC sd_kind_type_before, " type"
SDOC sd_kind_typeof_before, " typeof"

# pjs_print_import_or_export_kind(kind, space_before) -> rax
# (printImportOrExportKind): "" for no kind or "value"
FUNC pjs_print_import_or_export_kind
    xor eax, eax
    cmp rdi, KD_TYPE
    je 1f
    cmp rdi, KD_TYPEOF
    je 2f
    leave
    ret
1:  lea rax, [rip + sd_kind_type_before]
    lea rcx, [rip + sd_kind_type_after]
    jmp 3f
2:  lea rax, [rip + sd_kind_typeof_before]
    lea rcx, [rip + sd_kind_typeof_after]
3:  test esi, esi
    cmovz rax, rcx
    leave
    ret
ENDF pjs_print_import_or_export_kind
