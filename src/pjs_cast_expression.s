# print/cast-expression.js
.include "pjs.inc"

SDOC sd_as, " as "
SDOC sd_satisfies, " satisfies "

    .text

# pjs_print_binary_cast_expression(node, args) -> rax (printBinaryCastExpression):
# TSAsExpression and TSSatisfiesExpression
FUNC pjs_print_binary_cast_expression
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + N_F0]
    call pjs_check_cast_of_pattern
    PRINT N_F0, K_expression
    mov r12, rax
    PRINT N_F5, K_typeAnnotation
    mov r13, rax
    lea r14, [rip + sd_as]
    TYPE rbx, T_TSAsExpression
    je 1f
    lea r14, [rip + sd_satisfies]
1:  call path_key
    mov r15d, eax
    call path_parent
    mov rbx, rax
    cmp r15d, K_callee
    jne 2f
    mov rdi, rbx
    call pjs_is_call_expression
    test eax, eax
    jnz 5f
2:  cmp r15d, K_object
    jne 3f
    mov rdi, rbx
    call pjs_is_member_expression
    test eax, eax
    jnz 5f
3:  mov rdi, r12
    mov rsi, r14
    mov rdx, r13
    call doc_array3
    jmp 9f
    # group([indent([softline, ...parts]), softline])
5:  DMARK r15
    DPUSHL d_softline
    DPUSH r12
    DPUSH r14
    DPUSH r13
    DARRAY r15
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    GROUP_RAX
9:  EPILOGUE
ENDF pjs_print_binary_cast_expression

# pjs_check_cast_of_pattern(expression): an assignment target `({a} as T) = 1`
# or `({a})! = 1` is an ObjectPattern for babel-ts and stays an
# ObjectExpression for typescript-estree, which Prettier parenthesizes
# differently; refuse it
FUNC pjs_check_cast_of_pattern
    TYPE rdi, T_ObjectPattern
    je 90f
    leave
    ret
90: REFUSE "printer: object pattern in `as`, `satisfies` or `!` (typescript-estree keeps an ObjectExpression)"
ENDF pjs_check_cast_of_pattern
