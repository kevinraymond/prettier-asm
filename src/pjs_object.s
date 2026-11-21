# print/object.js: ObjectExpression, ObjectPattern, TSTypeLiteral,
# TSInterfaceBody and TSEnumBody (the Flow bodies do not occur)
.include "pjs.inc"

    .section .rodata
    .balign 8
# path.match(ObjectPattern without decorators, shouldHugTheOnlyParameter)
pob_match_hug: .quad pob_is_undecorated_object_pattern, pob_should_hug_the_only_parameter
# path.match(undefined, name === "typeAnnotation", name === "typeAnnotation",
# shouldHugTheOnlyParameter)
pob_match_type_hug: .quad 0, pob_key_type_annotation, pob_key_type_annotation, pob_should_hug_the_only_parameter
# path.match(ObjectPattern, AssignmentExpression or VariableDeclarator)
pob_match_assign: .quad pob_is_object_pattern, pob_is_assignment_like
# path.match(undefined, TSImportType with key "options")
pob_match_import_options: .quad 0, pob_is_import_type_options
    .text

FUNC pob_is_object_pattern
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectPattern
    sete al
    leave
    ret
ENDF pob_is_object_pattern

FUNC pob_is_undecorated_object_pattern
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectPattern
    jne 9f
    mov rcx, [rdi + N_F6]
    test rcx, rcx
    jz 1f
    cmp qword ptr [rcx], 0
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pob_is_undecorated_object_pattern

FUNC pob_key_type_annotation
    xor eax, eax
    cmp esi, K_typeAnnotation
    sete al
    leave
    ret
ENDF pob_key_type_annotation

FUNC pob_is_import_type_options
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TSImportType
    jne 9f
    cmp esi, K_options
    sete al
9:  leave
    ret
ENDF pob_is_import_type_options

FUNC pob_is_assignment_like
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_AssignmentExpression
    je 1f
    cmp word ptr [rdi + N_TYPE], T_VariableDeclarator
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pob_is_assignment_like

# shouldHugTheOnlyParameter(node, name)
FUNC pob_should_hug_the_only_parameter
    xor eax, eax
    cmp esi, K_params
    je 1f
    cmp esi, K_parameters
    jne 9f
1:  call pjs_should_hug_the_only_function_parameter
9:  leave
    ret
ENDF pob_should_hug_the_only_parameter

# pob_is_ts_signature_ignored(node) -> eax: a TSPropertySignature,
# TSMethodSignature, TSConstructSignatureDeclaration or
# TSCallSignatureDeclaration (or TSIndexSignature when index_ok) with a
# prettier-ignore comment
FUNC pob_is_ts_signature_ignored
    xor eax, eax
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_TSIndexSignature
    jne 1f
    test esi, esi
    jz 9f
    jmp 2f
1:  cmp ecx, T_TSPropertySignature
    je 2f
    cmp ecx, T_TSMethodSignature
    je 2f
    cmp ecx, T_TSConstructSignatureDeclaration
    je 2f
    cmp ecx, T_TSCallSignatureDeclaration
    jne 9f
2:  mov esi, CC_PrettierIgnore
    xor edx, edx
    call has_comment
9:  leave
    ret
ENDF pob_is_ts_signature_ignored

# pjs_print_object(node, args) -> rax doc (printObject)
FUNC pjs_print_object
    PROLOGUE 10
    mov rbx, rdi
    movzx eax, word ptr [rbx + N_TYPE]
    mov esi, K_properties
    cmp eax, T_TSTypeLiteral
    je 1f
    cmp eax, T_TSEnumBody
    je 1f
    cmp eax, T_TSInterfaceBody
    jne 2f
    mov esi, K_body
    jmp 2f
1:  mov esi, K_members
2:  mov edi, N_F0
    xor edx, edx
    call print_map
    mov r12, rax                    # printed members (VEC)
    mov r13, [rbx + N_F0]           # members
    VLEN r14, r13
    call path_parent
    mov [rsp], rax                  # parent
    # shouldBreak
    xor r15d, r15d
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_TSInterfaceBody
    je 6f
    cmp ecx, T_TSEnumBody
    je 6f
    cmp ecx, T_ObjectPattern
    jne 5f
    movzx ecx, word ptr [rax + N_TYPE]
    .irp t, T_FunctionDeclaration, T_FunctionExpression, T_ArrowFunctionExpression, T_ObjectMethod, T_ClassMethod, T_ClassPrivateMethod, T_AssignmentPattern, T_CatchClause
    cmp ecx, \t
    je 7f
    .endr
    xor ecx, ecx
3:  cmp rcx, r14
    jae 7f
    mov rax, [r13 + 8 + rcx*8]
    inc rcx
    TYPE rax, T_ObjectProperty
    jne 3b
    mov rax, [rax + N_F1]
    test rax, rax
    jz 3b
    TYPE rax, T_ObjectPattern
    je 6f
    TYPE rax, T_ArrayPattern
    jne 3b
    jmp 6f
5:  cmp qword ptr [rip + g_object_wrap], OW_PRESERVE
    jne 7f
    test r14, r14
    jz 7f
    mov rax, [r13 + 8]
    mov edi, [rbx + N_START]
    mov esi, [rax + N_START]
    call has_newline_in_range
    mov r15d, eax
    jmp 7f
6:  mov r15d, 1
7:  mov [rsp + 8], r15              # shouldBreak
    # separator: ifBreak(semi, ";") for TSInterfaceBody and TSTypeLiteral, else ","
    lea rax, [rip + ps_comma]
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_TSInterfaceBody
    je 8f
    cmp ecx, T_TSTypeLiteral
    jne 9f
8:  call pjs_semi_doc
    mov rdi, rax
    lea rsi, [rip + ps_semi]
    xor edx, edx
    call doc_if_break
9:  mov [rsp + 48], rax             # separator
    test r14, r14
    jnz 20f
    # no members
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 10f
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    lea rdi, [rip + ps_lbrace]
    lea rsi, [rip + ps_rbrace]
    mov rdx, rax
    call doc_array3
    jmp 99f
10: DMARK r15
    DPUSHL ps_lbrace
    mov rdi, rbx
    mov esi, 1
    call print_dangling_comments
    DPUSH rax
    DPUSHL d_softline
    DPUSHL ps_rbrace
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    DARRAY r15
    GROUP_RAX
    mov [rsp + 16], rax             # content
    jmp 40f
    # props: [...separatorParts, group(printed)]
20: lea rax, [rip + d_line]
    cmp qword ptr [rip + g_bracket_spacing], 0
    jne 21f
    lea rax, [rip + d_softline]
21: mov [rsp + 24], rax             # line or softline
    DMARK rax
    mov [rsp + 32], rax             # indent parts
    DPUSH [rsp + 24]
    xor r15d, r15d                  # index
    mov qword ptr [rsp + 40], 0     # separatorParts: bit 0 separator, bit 1 line, bit 2 hardline
22: cmp r15, r14
    jae 25f
    DMARK rax
    mov [rsp + 16], rax
    mov rax, [rsp + 40]
    test eax, 1
    jz 221f
    DPUSH [rsp + 48]
221: mov rax, [rsp + 40]
    test eax, 2
    jz 222f
    DPUSHL d_line
222: mov rax, [rsp + 40]
    test eax, 4
    jz 23f
    DPUSHL d_hardline
23: mov rdi, [r12 + 8 + r15*8]
    xor esi, esi
    call doc_group
    DPUSH rax
    mov rdi, [rsp + 16]
    call ss_to_array
    DPUSH rax
    mov qword ptr [rsp + 40], 3
    mov rdi, [r13 + 8 + r15*8]
    xor esi, esi
    call pob_is_ts_signature_ignored
    test eax, eax
    jz 24f
    mov qword ptr [rsp + 40], 2
24: mov rdi, [r13 + 8 + r15*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 241f
    or qword ptr [rsp + 40], 4
241: inc r15
    jmp 22b
25: mov rdi, [rsp + 32]
    call ss_to_array
    INDENT_RAX
    mov r15, rax
    # ifBreak(canHaveTrailingSeparator && (separator !== "," || shouldPrintComma) ? separator : "")
    xor edi, edi
    mov rax, [r13 + r14*8]          # last member
    TYPE rax, T_RestElement
    je 26f
    mov rdi, rax
    mov esi, 1
    call pob_is_ts_signature_ignored
    xor edi, edi
    test eax, eax
    jnz 26f
    lea rdi, [rip + pob_match_import_options]
    mov esi, 2
    call path_match
    xor edi, edi
    test eax, eax
    jnz 26f
    mov rdi, [rsp + 48]
    lea rax, [rip + ps_comma]
    cmp rdi, rax
    jne 26f
    xor edi, edi
    call pjs_should_print_comma
    xor edi, edi
    test eax, eax
    jz 26f
    lea rdi, [rip + ps_comma]
26: xor esi, esi
    xor edx, edx
    call doc_if_break
    mov [rsp + 16], rax
    DMARK rax
    mov [rsp + 32], rax
    DPUSHL ps_lbrace
    DPUSH r15
    DPUSH [rsp + 16]
    DPUSH [rsp + 24]
    DPUSHL ps_rbrace
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    mov rdi, [rsp + 32]
    call ss_to_array
    mov [rsp + 16], rax             # content
    # return content without a group when printAssignment or the hugged
    # parameter supplies it
40: lea rdi, [rip + pob_match_hug]
    mov esi, 2
    call path_match
    test eax, eax
    jnz 45f
    mov rdi, rbx
    call pjs_is_object_type
    test eax, eax
    jz 41f
    lea rdi, [rip + pob_match_type_hug]
    mov esi, 4
    call path_match
    test eax, eax
    jnz 45f
41: cmp qword ptr [rsp + 8], 0
    jne 42f
    lea rdi, [rip + pob_match_assign]
    mov esi, 2
    call path_match
    test eax, eax
    jnz 45f
42: mov rdi, [rsp + 16]
    mov rsi, [rsp + 8]
    call doc_group
    jmp 99f
45: mov rax, [rsp + 16]
99: EPILOGUE
ENDF pjs_print_object
