# print/call-expression.js
.include "pjs.inc"

SDOC sd_new, "new "
SDOC sd_import, "import"
SDOC sd_comma_space, ", "

    .section .rodata
s_require: .asciz "require"
s_define: .asciz "define"
    .text

# pjs_print_call_expression(node, args) -> rax doc (printCallExpression)
FUNC pjs_print_call_expression
    PROLOGUE 2
    mov rbx, rdi
    mov rdi, rbx
    call pjs_print_optional_token
    mov r13, rax                    # optional
    mov rdi, rbx
    call pjs_get_call_arguments
    mov r14, rax                    # args
    xor r15d, r15d                  # isTemplateLiteralSingleArg
    cmp qword ptr [r14], 1
    jne 1f
    mov rdi, [r14 + 8]
    call pjs_is_template_on_its_own_line
    mov r15d, eax
    test eax, eax
    jnz 2f
1:  call pce_is_commonjs_or_amd_module_definition
    test eax, eax
    jnz 2f
    call path_parent
    mov rdi, rbx
    mov rsi, rax
    call pjs_is_test_call
    test eax, eax
    jz 10f
    # the arguments printed one by one, joined by ", "
2:  DMARK r12
    xor ecx, ecx
    mov [rsp], rcx
3:  mov rcx, [rsp]
    cmp rcx, [r14]
    jae 4f
    mov rdi, rcx
    xor esi, esi
    call pjs_print_call_argument
    DPUSH rax
    inc qword ptr [rsp]
    jmp 3b
4:  mov rdi, r12
    call ss_to_vec
    mov r12, rax                    # printed
    test r15d, r15d
    jz 5f
    mov rdi, [r12 + 8]
    call pjs_doc_label_bits
    test eax, LB_EMBED
    jnz 10f
5:  lea rdi, [rip + sd_comma_space]
    mov rsi, r12
    call doc_join
    mov r12, rax
    DMARK r15
    TYPE rbx, T_NewExpression
    jne 6f
    DPUSHL sd_new
6:  call pce_print_callee
    DPUSH rax
    DPUSH r13
    call pjs_print_function_type_parameters
    DPUSH rax
    DPUSHL ps_lparen
    DPUSH r12
    DPUSHL ps_rparen
    DARRAY r15
    jmp 99f

    # member chain
10: TYPE rbx, T_ImportExpression
    je 20f
    TYPE rbx, T_NewExpression
    je 20f
    mov rdi, [rbx + N_F0]
    call pjs_is_memberish
    test eax, eax
    jz 20f
    lea rdi, [rip + pce_needs_parens_cb]
    xor esi, esi
    mov edx, K_callee
    mov ecx, N_F0
    call path_call
    test eax, eax
    jnz 20f
    call pjs_print_member_chain
    jmp 99f

20: DMARK r15
    TYPE rbx, T_NewExpression
    jne 21f
    DPUSHL sd_new
21: call pce_print_callee
    DPUSH rax
    DPUSH r13
    call pjs_print_function_type_parameters
    DPUSH rax
    call pjs_print_call_arguments
    DPUSH rax
    DARRAY r15
    TYPE rbx, T_ImportExpression
    je 22f
    mov r12, rax
    mov rdi, [rbx + N_F0]
    call pjs_is_call_expression
    mov ecx, eax
    mov rax, r12
    test ecx, ecx
    jz 99f
22: GROUP_RAX
99: EPILOGUE
ENDF pjs_print_call_expression

FUNC pce_needs_parens_cb
    call pjs_needs_parens
    leave
    ret
ENDF pce_needs_parens_cb

# pce_print_callee() -> rax (printCallee)
FUNC pce_print_callee
    call path_value
    TYPE rax, T_ImportExpression
    jne 1f
    lea rax, [rip + sd_import]
    leave
    ret
1:  PRINT N_F0, K_callee
    leave
    ret
ENDF pce_print_callee

# pce_is_commonjs_or_amd_module_definition() -> eax (isCommonsJsOrAmdModuleDefinition)
FUNC pce_is_commonjs_or_amd_module_definition
    PROLOGUE
    call path_value
    mov rbx, rax
    TYPE rbx, T_CallExpression
    jne 8f
    ATTR rbx, NA_OPTIONAL
    jnz 8f
    mov r12, [rbx + N_F0]
    TYPE r12, T_Identifier
    jne 8f
    mov rdi, rbx
    call pjs_get_call_arguments
    mov r13, rax
    mov r14, [r13]                  # args.length
    mov rdi, r12
    lea rsi, [rip + s_require]
    call pjs_ident_is
    test eax, eax
    jz 2f
    cmp r14, 1
    ja 7f
    jne 8f
    mov rdi, [r13 + 8]
    call pjs_is_string_literal
    jmp 9f
2:  mov rdi, r12
    lea rsi, [rip + s_define]
    call pjs_ident_is
    test eax, eax
    jz 8f
    call path_parent
    TYPE rax, T_ExpressionStatement
    jne 8f
    cmp r14, 1
    je 7f
    cmp r14, 2
    jne 3f
    mov rax, [r13 + 8]
    TYPE rax, T_ArrayExpression
    je 7f
    jmp 8f
3:  cmp r14, 3
    jne 8f
    mov rdi, [r13 + 8]
    call pjs_is_string_literal
    test eax, eax
    jz 8f
    mov rax, [r13 + 16]
    TYPE rax, T_ArrayExpression
    je 7f
8:  xor eax, eax
    jmp 9f
7:  mov eax, 1
9:  EPILOGUE
ENDF pce_is_commonjs_or_amd_module_definition
