# print/type-parameters.js
.include "pjs.inc"

SDOC sd_lt, "<"
SDOC sd_gt, ">"
SDOC sd_comma_sp, ", "
SDOC sd_const_sp, "const "
SDOC sd_in_sp, "in "
SDOC sd_out_sp, "out "
SDOC sd_extends, " extends"
SDOC sd_eq_sp, " = "

    .section .rodata
    .balign 8
# path.match(not one object type, undefined, name === "typeAnnotation",
# Identifier, isArrowFunctionVariableDeclarator)
ptp_match_arrow_variable:
    .quad ptp_not_single_object_type, 0, ptp_key_type_annotation, ptp_is_identifier
    .quad pjs_is_arrow_function_variable_declarator

    .bss
    .balign 8
ptp_group_ids: .quad 0              # getTypeParametersGroupId's map: node -> group id
ptp_comma_line: .quad 0             # [",", line]

    .text

FUNC ptp_not_single_object_type
    push rbx
    sub rsp, 8
    mov eax, 1
    mov rcx, [rdi + N_F0]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 1
    jne 9f
    mov rdi, [rcx + 8]
    call pjs_is_object_type
    xor eax, 1
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF ptp_not_single_object_type

FUNC ptp_key_type_annotation
    xor eax, eax
    cmp esi, K_typeAnnotation
    sete al
    leave
    ret
ENDF ptp_key_type_annotation

FUNC ptp_is_identifier
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_Identifier
    sete al
    leave
    ret
ENDF ptp_is_identifier

# pjs_get_type_parameters_group_id(node) -> rax (getTypeParametersGroupId)
FUNC pjs_get_type_parameters_group_id
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rip + ptp_group_ids]
    test rdi, rdi
    jnz 1f
    mov edi, 16
    call ptrmap_new
    mov [rip + ptp_group_ids], rax
    mov rdi, rax
1:  mov rsi, rbx
    call ptrmap_get
    test edx, edx
    jnz 9f
    call doc_group_id_new
    mov r12, rax
    mov rdi, [rip + ptp_group_ids]
    mov rsi, rbx
    mov rdx, r12
    call ptrmap_put
    mov rax, r12
9:  EPILOGUE
ENDF pjs_get_type_parameters_group_id

# ptp_filepath_ends_ts() -> eax: /\.ts$/.test(options.filepath)
FUNC ptp_filepath_ends_ts
    xor eax, eax
    mov rdi, [rip + g_filepath]
    test rdi, rdi
    jz 9f
    push rdi
    sub rsp, 8
    call strlen
    add rsp, 8
    pop rdi
    mov rcx, rax
    xor eax, eax
    cmp rcx, 3
    jb 9f
    cmp byte ptr [rdi + rcx - 3], '.'
    jne 9f
    cmp byte ptr [rdi + rcx - 2], 't'
    jne 9f
    cmp byte ptr [rdi + rcx - 1], 's'
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF ptp_filepath_ends_ts

# pjs_print_type_parameters(node, args) -> rax (printTypeParameters with
# paramsKey "params") for a TSTypeParameterDeclaration or
# TSTypeParameterInstantiation at the path's top
FUNC pjs_print_type_parameters
    PROLOGUE 2
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # params
    VLEN r13, r12
    test r13, r13
    jz 10f                          # shouldInline
    lea rdi, [rip + ptp_match_arrow_variable]
    mov esi, 5
    call path_match
    test eax, eax
    jnz 20f                         # isArrowFunctionVariable: not inline
    call path_grandparent
    mov rdi, rax
    xor esi, esi
    call pjs_is_test_call
    test eax, eax
    jnz 10f
    cmp r13, 1
    jne 20f
    mov rdi, [r12 + 8]
    call pjs_should_hug_type
    test eax, eax
    jz 20f
    # ["<", join(", ", path.map(print, "params")), printDanglingCommentsForInline, ">"]
10: mov edi, N_F0
    mov esi, K_params
    xor edx, edx
    call print_map
    lea rdi, [rip + sd_comma_sp]
    mov rsi, rax
    call doc_join
    mov r14, rax
    mov rdi, rbx
    call ptp_print_dangling_comments_for_inline
    mov r15, rax
    DMARK r12
    DPUSHL sd_lt
    DPUSH r14
    DPUSH r15
    DPUSHL sd_gt
    DARRAY r12
    jmp 99f
    # trailingComma
20: xor r15d, r15d
    TYPE rbx, T_TSTypeParameterInstantiation
    je 23f
    # shouldForceTrailingComma: one parameter without a constraint, the parent
    # an arrow function, and a file name not ending in ".ts"
    cmp r13, 1
    jne 22f
    mov rax, [r12 + 8]
    cmp qword ptr [rax + N_F1], 0
    jne 22f
    call path_parent
    TYPE rax, T_ArrowFunctionExpression
    jne 22f
    call ptp_filepath_ends_ts
    test eax, eax
    jnz 22f
    lea r15, [rip + ps_comma]
    jmp 23f
22: xor edi, edi
    call pjs_should_print_comma
    test eax, eax
    jz 23f
    lea rdi, [rip + ps_comma]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r15, rax
    # group(["<", indent([softline, join([",", line], printed)]), trailingComma,
    # softline, ">"], {id: getTypeParametersGroupId(node)})
23: mov rax, [rip + ptp_comma_line]
    test rax, rax
    jnz 24f
    lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array2
    mov [rip + ptp_comma_line], rax
24: mov [rsp], rax
    mov edi, N_F0
    mov esi, K_params
    xor edx, edx
    call print_map
    mov rdi, [rsp]
    mov rsi, rax
    call doc_join
    lea rdi, [rip + d_softline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov r14, rax
    DMARK r12
    DPUSHL sd_lt
    DPUSH r14
    DPUSH r15
    DPUSHL d_softline
    DPUSHL sd_gt
    DARRAY r12
    mov r14, rax
    mov rdi, rbx
    call pjs_get_type_parameters_group_id
    mov rdi, r14
    xor esi, esi
    mov rdx, rax
    call doc_group_ex
99: EPILOGUE
ENDF pjs_print_type_parameters

# ptp_print_dangling_comments_for_inline(node) -> rax (printDanglingCommentsForInline)
FUNC ptp_print_dangling_comments_for_inline
    PROLOGUE
    mov rbx, rdi
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 8f
    mov rdi, rbx
    mov esi, CC_Line
    xor edx, edx
    call has_comment
    mov r12d, eax                   # !hasOnlyBlockComments
    mov rdi, rbx
    mov esi, r12d
    call print_dangling_comments
    test r12d, r12d
    jz 9f
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF ptp_print_dangling_comments_for_inline

# pjs_print_type_parameter(node, args) -> rax (printTypeParameter)
FUNC pjs_print_type_parameter
    PROLOGUE 2
    mov rbx, rdi
    DMARK r12
    ATTR rbx, NA_CONST
    jz 1f
    DPUSHL sd_const_sp
1:  ATTR rbx, NA_IN
    jz 2f
    DPUSHL sd_in_sp
2:  ATTR rbx, NA_OUT
    jz 3f
    DPUSHL sd_out_sp
3:  PRINT N_F0, K_name
    DPUSH rax
    cmp qword ptr [rbx + N_F1], 0
    je 4f
    # " extends", group(indent(line), {id}), lineSuffixBoundary,
    # indentIfBreak(print("constraint"), {groupId})
    call doc_group_id_new
    mov r13, rax
    DPUSHL sd_extends
    lea rdi, [rip + d_line]
    call doc_indent
    mov rdi, rax
    xor esi, esi
    mov rdx, r13
    call doc_group_ex
    DPUSH rax
    DPUSHL d_line_suffix_boundary
    PRINT N_F1, K_constraint
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    call doc_indent_if_break
    DPUSH rax
4:  cmp qword ptr [rbx + N_F2], 0
    je 5f
    DPUSHL sd_eq_sp
    PRINT N_F2, K_default
    DPUSH rax
5:  DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_type_parameter
