# print/semicolon.js
.include "pjs.inc"

# pjs_should_print_leading_semicolon() -> eax (shouldPrintLeadingSemicolon) for
# the node at the top of the path
FUNC pjs_should_print_leading_semicolon
    PROLOGUE
    xor eax, eax
    cmp qword ptr [rip + g_semi], 0
    jne 9f
    call path_value
    mov rbx, rax
    xor eax, eax
    TYPE rbx, T_ExpressionStatement
    jne 9f
    call path_key
    mov r12d, eax
    call path_parent
    movzx ecx, word ptr [rax + N_TYPE]
    cmp r12d, K_body
    jne 1f
    cmp ecx, T_Program
    je 2f
    cmp ecx, T_BlockStatement
    je 2f
    cmp ecx, T_StaticBlock
    je 2f
    cmp ecx, T_TSModuleBlock
    je 2f
    jmp 8f
1:  cmp r12d, K_consequent
    jne 8f
    cmp ecx, T_SwitchCase
    jne 8f
2:  lea rdi, [rip + needs_asi_cb]
    xor esi, esi
    mov edx, K_expression
    mov ecx, N_F0
    call path_call
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_should_print_leading_semicolon

FUNC needs_asi_cb
    call expression_needs_asi_protection
    leave
    ret
ENDF needs_asi_cb

# expression_needs_asi_protection() -> eax for the node at the top of the path
FUNC expression_needs_asi_protection
    PROLOGUE
    call path_value
    mov rbx, rax
    mov eax, 1
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_ParenthesizedExpression
    je 9f
    cmp ecx, T_ArrayExpression
    je 9f
    cmp ecx, T_ArrayPattern
    je 9f
    cmp ecx, T_TemplateLiteral
    je 9f
    cmp ecx, T_TemplateElement
    je 9f
    cmp ecx, T_RegExpLiteral
    je 9f
    cmp ecx, T_ArrowFunctionExpression
    jne 1f
    call pjs_should_print_params_without_parens
    test eax, eax
    jz 7f
    jmp 2f
1:  cmp ecx, T_UnaryExpression
    jne 2f
    ATTR rbx, NA_PREFIX
    jz 2f
    mov rax, [rbx + N_F1]
    cmp rax, '+'
    je 7f
    cmp rax, '-'
    je 7f
2:  call pjs_needs_parens
    test eax, eax
    jnz 9f
    mov rdi, rbx
    call pjs_has_naked_left_side
    test eax, eax
    jz 9f
    lea rdi, [rip + needs_asi_cb]
    xor esi, esi
    call pjs_call_left_side
    jmp 9f
7:  mov eax, 1
9:  EPILOGUE
ENDF expression_needs_asi_protection
