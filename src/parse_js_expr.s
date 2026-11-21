# JS expressions, after Babel's ExpressionParser. The `ref` argument of the jpe_* functions on the
# left spine of an assignment stands for Babel's refExpressionErrors: 1 when a record exists
# (g_err_shorthand, g_err_proto hold positions of `{a = 1}` and a second `__proto__`, or -1),
# 0 when Babel passes none and such syntax is an error at once.
.include "defs.inc"
.include "parse_js.inc"

    .bss
    .balign 8
    .globl g_potential_arrow_at, g_err_shorthand, g_err_proto, g_param_errors, g_err_optparam
g_potential_arrow_at: .quad 0
g_param_errors:       .quad 0   # yield and await expressions and `await` identifiers read so
                                # far outside nested functions; arrow parameters may hold none
g_err_shorthand:      .quad 0
g_err_proto:          .quad 0
g_err_optparam:       .quad 0   # TypeScript: position of `a?` in parentheses (optionalParametersLoc)

    .section .rodata
    .balign 8
    .globl js_empty_vec
js_empty_vec: .quad 0
s_async: .ascii "async"
s_target: .ascii "target"
s_meta: .ascii "meta"
s_proto: .ascii "__proto__"

    .text

FUNC jpe_reset
    mov qword ptr [rip + g_potential_arrow_at], -1
    mov qword ptr [rip + g_err_shorthand], -1
    mov qword ptr [rip + g_err_proto], -1
    mov qword ptr [rip + g_err_optparam], -1
    leave
    ret
ENDF jpe_reset

# jpe_errors_save() -> rax, rdx: the current record; starts a fresh one.
FUNC jpe_errors_save
    mov rax, [rip + g_err_shorthand]
    mov rdx, [rip + g_err_proto]
    mov qword ptr [rip + g_err_shorthand], -1
    mov qword ptr [rip + g_err_proto], -1
    leave
    ret
ENDF jpe_errors_save

# jpe_errors_restore(shorthand, proto)
FUNC jpe_errors_restore
    mov [rip + g_err_shorthand], rdi
    mov [rip + g_err_proto], rsi
    leave
    ret
ENDF jpe_errors_restore

# jpe_errors_check(): Babel's checkExpressionErrors(ref, true)
FUNC jpe_errors_check
    cmp qword ptr [rip + g_err_shorthand], -1
    jne 90f
    cmp qword ptr [rip + g_err_proto], -1
    jne 91f
    leave
    ret
90: REFUSE "syntax error: shorthand property with an initializer outside a pattern"
91: REFUSE "syntax error: duplicate __proto__"
ENDF jpe_errors_check

# js_vec1(node) -> rax: a VEC holding one node
FUNC js_vec1
    push rdi
    sub rsp, 8
    mov edi, 16
    call alloc
    add rsp, 8
    pop rdi
    mov qword ptr [rax], 1
    mov [rax + 8], rdi
    leave
    ret
ENDF js_vec1

# js_is_arrow_at(node, pos) -> eax: Babel's shouldExitDescending
FUNC js_is_arrow_at
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ArrowFunctionExpression
    jne 9f
    mov ecx, [rdi + N_START]
    cmp rcx, rsi
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF js_is_arrow_at

# js_check_word_operand(): after an expression that began with `yield` or `await` read as an
# identifier, Babel reports YieldNotInGeneratorFunction or AwaitNotInAsyncContext when the next
# token, on the same line, starts an expression and is not an ambiguous prefix (+ - ( [ ` / of).
FUNC js_check_word_operand
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    mov rax, [rip + g_jt_type]
    cmp rax, J_NAME
    je 1f
    cmp rax, J_STRING
    je 90f
    cmp rax, J_NUM
    je 90f
    cmp rax, J_BIGINT
    je 90f
    cmp rax, J_PRIVATE
    je 90f
    cmp rax, J_LBRACE
    je 90f
    cmp rax, J_BANG
    je 90f
    cmp rax, J_TILDE
    je 90f
    cmp rax, J_INC
    je 90f
    cmp rax, J_DEC
    je 90f
    jmp 9f
1:  mov rax, [rip + g_jt_kw]
    cmp rax, KW_IN
    je 9f
    cmp rax, KW_INSTANCEOF
    je 9f
    cmp rax, KW_OF
    je 9f
    jmp 90f
9:  leave
    ret
90: REFUSE "syntax error: yield or await outside a generator or async function"
ENDF js_check_word_operand

# ---------------------------------------------------------------- sequence and assignment
# jpe_expression(ref) -> rax: Expression (a SequenceExpression for `a, b`)
FUNC jpe_expression
    push rbx
    push r12
    push r13
    push r14
    mov r13d, edi
    mov r12, [rip + g_jt_start]
    call jpe_maybe_assign
    TT_IS J_COMMA
    jne 9f
    mov rbx, rax
    call ss_mark
    mov r14, rax
    mov rdi, rbx
    call ss_push
1:  TT_IS J_COMMA
    jne 2f
    NEXT
    mov edi, r13d
    call jpe_maybe_assign
    mov rdi, rax
    call ss_push
    jmp 1b
2:  mov rdi, r14
    call ss_to_vec
    mov rbx, rax
    NODE T_SequenceExpression, r12
    mov [rax + N_F0], rbx
    FINISH rax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_expression

# jpe_expression_allow_in() -> rax
FUNC jpe_expression_allow_in
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    xor edi, edi
    call jpe_expression
    mov [rip + g_px], rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpe_expression_allow_in

# jpe_maybe_assign_allow_in() -> rax
FUNC jpe_maybe_assign_allow_in
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    xor edi, edi
    call jpe_maybe_assign
    mov [rip + g_px], rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpe_maybe_assign_allow_in

# jpe_maybe_assign_ref_allow_in(ref) -> rax: with the caller's record when ref is 1
FUNC jpe_maybe_assign_ref_allow_in
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    call jpe_maybe_assign
    mov [rip + g_px], rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpe_maybe_assign_ref_allow_in

# jpe_maybe_assign_disallow_in() -> rax
FUNC jpe_maybe_assign_disallow_in
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_px]
    or qword ptr [rip + g_px], CX_NO_IN
    xor edi, edi
    call jpe_maybe_assign
    mov [rip + g_px], rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpe_maybe_assign_disallow_in

# jpe_maybe_assign(flags) -> rax: AssignmentExpression, YieldExpression or a conditional.
# flags: MA_REF (the caller's error record), MA_PAREN_ITEM (TypeScript's parseParenItem after
# the left side: `x?` and `x: T`), MA_NO_LT (Babel's super.parseMaybeAssign: no TypeScript `<`
# handling at this level).
FUNC jpe_maybe_assign
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov [rsp + 24], rdi
    mov r15d, edi
    and r15d, MA_REF
    call js_enter_depth
    mov r12, [rip + g_jt_start]
    mov qword ptr [rsp + 16], 0
    IF_NOT_TS 1f
    test qword ptr [rsp + 24], MA_NO_LT
    jnz 1f
    TT_IS J_LT
    jne 1f
    mov rdi, [rsp + 24]
    call jts_maybe_assign_lt
    jmp 99f
1:
    KW_IS KW_YIELD
    jne 1f
    mov qword ptr [rsp + 16], 1         # `yield` as an identifier
    test qword ptr [rip + g_px], CX_YIELD
    jz 1f
    NEXT
    mov rdi, r12
    call jpe_yield
    jmp 99f
1:  test r15d, r15d
    jnz 2f
    call jpe_errors_save
    mov [rsp], rax
    mov [rsp + 8], rdx
2:  TT_IS J_LPAREN
    je 3f
    TT_IS J_NAME
    jne 4f
3:  mov [rip + g_potential_arrow_at], r12
4:  mov edi, 1
    call jpe_maybe_conditional
    mov rbx, rax
    test qword ptr [rsp + 24], MA_PAREN_ITEM
    jz 41f
    IF_NOT_TS 41f
    mov rdi, rbx
    mov rsi, r12
    call jts_paren_item
    mov rbx, rax
41: mov r13, [rip + g_jt_type]
    cmp r13, J_EQ
    je 5f
    cmp r13, J_ADD_EQ
    jb 8f
    cmp r13, J_NULLISH_EQ
    ja 8f
    jmp 6f
5:  mov rdi, rbx
    mov esi, 1
    call jpp_to_assignable
    mov rax, [rip + g_err_shorthand]
    cmp rax, r12
    jl 51f
    mov qword ptr [rip + g_err_shorthand], -1
51: mov rax, [rip + g_err_proto]
    cmp rax, r12
    jl 6f
    mov qword ptr [rip + g_err_proto], -1
6:  NEXT
    xor edi, edi
    call jpe_maybe_assign
    mov r14, rax
    NODE T_AssignmentExpression, r12
    mov [rax + N_F0], rbx
    mov [rax + N_F1], r14
    mov [rax + N_F2], r13
    FINISH rax
    mov r14, rax
    mov rdi, rbx
    mov esi, 2
    call jpp_check_lval
    test r15d, r15d
    jnz 7f
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
7:  mov rax, r14
    jmp 99f
8:  test r15d, r15d
    jnz 9f
    call jpe_errors_check
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
9:  cmp qword ptr [rsp + 16], 0
    je 10f
    call js_check_word_operand
10: mov rax, rbx
99: dec qword ptr [rip + g_js_depth]
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_maybe_assign

# jpe_yield(start) -> rax: `yield` has been consumed
FUNC jpe_yield
    push rbx
    push r12
    test qword ptr [rip + g_px], CX_GEN_PARAMS
    jnz 90f
    inc qword ptr [rip + g_param_errors]
    NODE T_YieldExpression, rdi
    mov rbx, rax
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    xor r12d, r12d
    TT_IS J_STAR
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_DELEGATE
    mov r12d, 1
    jmp 2f
1:  mov rax, [rip + g_jt_type]
    cmp rax, J_SEMI
    je 9f
    cmp rax, J_EOF
    je 9f
    cmp rax, J_RBRACE
    je 9f
    cmp rax, J_RPAREN
    je 9f
    cmp rax, J_RBRACK
    je 9f
    cmp rax, J_COLON
    je 9f
    cmp rax, J_COMMA
    je 9f
2:  xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F0], rax
9:  FINISH rbx
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: yield in parameters"
ENDF jpe_yield

# ---------------------------------------------------------------- conditional and binary
# jpe_maybe_conditional(ref) -> rax
FUNC jpe_maybe_conditional
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_jt_start]
    mov r13, [rip + g_potential_arrow_at]
    call jpe_expr_ops
    mov rbx, rax
    mov rdi, rax
    mov rsi, r13
    call js_is_arrow_at
    test eax, eax
    jnz 9f
    TT_IS J_QUESTION
    jne 9f
    IF_NOT_TS 1f
    test qword ptr [rip + g_ts], TS_ARROW_PARAMS
    jz 1f
    call ts_lookahead_char              # `a?` before , = : ) is an optional parameter
    cmp eax, ','
    je 2f
    cmp eax, '='
    je 2f
    cmp eax, ':'
    je 2f
    cmp eax, ')'
    jne 1f
2:  cmp qword ptr [rip + g_err_optparam], -1
    jne 9f
    mov rax, [rip + g_jt_start]
    mov [rip + g_err_optparam], rax
    jmp 9f
1:  NEXT
    NODE T_ConditionalExpression, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    call jpe_maybe_assign_allow_in
    mov [rbx + N_F1], rax
    EXPECT J_COLON
    xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F2], rax
    FINISH rbx
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_maybe_conditional

# jpe_expr_ops(ref) -> rax
FUNC jpe_expr_ops
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_jt_start]
    mov r13, [rip + g_potential_arrow_at]
    call jpe_unary_or_private
    mov rbx, rax
    mov rdi, rax
    mov rsi, r13
    call js_is_arrow_at
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, -1
    call jpe_expr_op
    mov rbx, rax
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_expr_ops

# jpe_unary_or_private(ref) -> rax: a PrivateName (for `#x in obj`) or a unary expression
FUNC jpe_unary_or_private
    TT_IS J_PRIVATE
    jne 1f
    call jpe_private_name
    leave
    ret
1:  xor esi, esi
    call jpe_maybe_unary
    leave
    ret
ENDF jpe_unary_or_private

# jpe_expr_op(left, left_start, min_prec) -> rax: Babel's parseExprOp
FUNC jpe_expr_op
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  cmp word ptr [rbx + N_TYPE], T_PrivateName
    jne 2f
    KW_IS KW_IN
    jne 90f
    test qword ptr [rip + g_px], CX_NO_IN
    jnz 90f
    cmp r13, 7
    jge 90f
2:  IF_NOT_TS 20f
    cmp r13, 7
    jge 20f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 20f
    TT_IS J_NAME
    jne 20f
    mov edi, T_TSAsExpression
    KW_IS KW_AS
    je 22f
    mov edi, T_TSSatisfiesExpression
    KW_IS KW_SATISFIES
    jne 20f
22: mov rsi, r12
    call js_node
    mov [rax + N_F0], rbx
    mov rbx, rax
    mov rdi, rbx
    call jts_as_type
    mov [rbx + N_F5], rax
    FINISH rbx
    call jl_rescan_lt_gt
    jmp 1b
20: mov r14, [rip + g_jt_type]
    cmp r14, J_NAME
    jne 3f
    mov rax, [rip + g_jt_kw]
    mov r14d, J_IN
    cmp rax, KW_IN
    je 21f
    mov r14d, J_INSTANCEOF
    cmp rax, KW_INSTANCEOF
    jne 9f
    jmp 3f
21: test qword ptr [rip + g_px], CX_NO_IN
    jnz 9f
3:  cmp r14, 0xff
    ja 9f
    lea rax, [rip + ast_binop_prec]
    movzx r15d, byte ptr [rax + r14]
    test r15d, r15d
    jz 9f
    cmp r15, r13
    jle 9f
    cmp r14, J_NULLISH
    jne 4f
    mov r15d, 2                         # ?? binds its right side like &&
4:  NEXT
    mov rax, [rip + g_jt_start]
    mov [rsp], rax
    xor edi, edi
    call jpe_unary_or_private
    mov rdi, rax
    mov rsi, [rsp]
    mov rdx, r15
    cmp r14, J_EXP
    jne 5f
    dec rdx
5:  call jpe_expr_op
    mov [rsp + 8], rax
    mov edi, T_BinaryExpression
    cmp r14, J_AND2
    je 6f
    cmp r14, J_OR2
    je 6f
    cmp r14, J_NULLISH
    jne 7f
6:  mov edi, T_LogicalExpression
7:  mov rsi, r12
    call js_node
    mov [rax + N_F0], rbx
    mov rcx, [rsp + 8]
    mov [rax + N_F1], rcx
    mov [rax + N_F2], r14
    FINISH rax
    mov rbx, rax
    # ?? cannot mix with || or && without parentheses
    mov rax, [rip + g_jt_type]
    cmp r14, J_NULLISH
    jne 8f
    cmp rax, J_AND2
    je 91f
    cmp rax, J_OR2
    je 91f
    jmp 1b
8:  cmp r14, J_AND2
    je 81f
    cmp r14, J_OR2
    jne 1b
81: cmp rax, J_NULLISH
    je 91f
    jmp 1b
9:  mov rax, rbx
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: private name outside `#x in obj`"
91: REFUSE "syntax error: ?? mixed with || or &&"
ENDF jpe_expr_op

# ---------------------------------------------------------------- unary
# jpe_maybe_unary(ref, saw_unary) -> rax
FUNC jpe_maybe_unary
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r13d, edi
    mov r14d, esi
    mov r12, [rip + g_jt_start]
    IF_NOT_TS 11f
    TT_IS J_LT
    jne 11f
    call jts_type_assertion
    mov rbx, rax
    jmp 99f
11: KW_IS KW_AWAIT
    jne 1f
    test qword ptr [rip + g_px], CX_AWAIT
    jz 1f
    NEXT
    mov rdi, r12
    call jpe_await
    mov rbx, rax
    test r14d, r14d
    jnz 99f
    TT_IS J_EXP
    je 92f
    jmp 99f
    # prefix operators
1:  mov r15, [rip + g_jt_type]
    cmp r15, J_BANG
    je 3f
    cmp r15, J_TILDE
    je 3f
    cmp r15, J_PLUS
    je 3f
    cmp r15, J_MINUS
    je 3f
    cmp r15, J_INC
    je 3f
    cmp r15, J_DEC
    je 3f
    cmp r15, J_NAME
    jne 20f
    mov rax, [rip + g_jt_kw]
    mov r15d, J_TYPEOF
    cmp rax, KW_TYPEOF
    je 3f
    mov r15d, J_VOID
    cmp rax, KW_VOID
    je 3f
    mov r15d, J_DELETE
    cmp rax, KW_DELETE
    je 3f
    cmp rax, KW_THROW
    je 93f
    jmp 20f
3:  mov edi, T_UnaryExpression
    cmp r15, J_INC
    je 31f
    cmp r15, J_DEC
    jne 32f
31: mov edi, T_UpdateExpression
32: mov rsi, r12
    call js_node
    mov rbx, rax
    mov [rbx + N_F1], r15
    or dword ptr [rbx + N_ATTR], NA_PREFIX
    NEXT
    xor edi, edi
    mov esi, 1
    call jpe_maybe_unary
    mov [rbx + N_F0], rax
    test r13d, r13d
    jz 4f
    call jpe_errors_check
4:  FINISH rbx
    cmp r15, J_DELETE
    jne 5f
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_MemberExpression
    je 41f
    cmp word ptr [rax + N_TYPE], T_OptionalMemberExpression
    jne 5f
41: mov rax, [rax + N_F1]
    cmp word ptr [rax + N_TYPE], T_PrivateName
    je 94f
5:  cmp word ptr [rbx + N_TYPE], T_UpdateExpression
    jne 6f
    mov rdi, [rbx + N_F0]
    xor esi, esi
    call jpp_check_lval
    jmp 99f
6:  test r14d, r14d
    jnz 99f
    TT_IS J_EXP
    je 92f
    jmp 99f
    # postfix
20: xor eax, eax
    KW_IS KW_AWAIT
    sete al
    mov [rsp], rax                      # `await` as an identifier
    mov edi, r13d
    call jpe_expr_subscripts
    mov rbx, rax
    test r13d, r13d
    jz 21f
    cmp qword ptr [rip + g_err_shorthand], -1
    jne 99f
    cmp qword ptr [rip + g_err_proto], -1
    jne 99f
21: mov r15, [rip + g_jt_type]
    cmp r15, J_INC
    je 22f
    cmp r15, J_DEC
    jne 98f
22: cmp qword ptr [rip + g_jt_nl], 0
    jne 98f
    NODE T_UpdateExpression, r12
    mov [rax + N_F0], rbx
    mov [rax + N_F1], r15
    mov rbx, rax
    NEXT
    FINISH rbx
    mov rdi, [rbx + N_F0]
    xor esi, esi
    call jpp_check_lval
    jmp 21b
98: cmp qword ptr [rsp], 0
    je 99f
    call js_check_word_operand
99: mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
92: REFUSE "syntax error: unary operator before **"
93: REFUSE "throw expression"
94: REFUSE "syntax error: delete of a private field"
ENDF jpe_maybe_unary

# jpe_await(start) -> rax: `await` has been consumed
FUNC jpe_await
    push rbx
    sub rsp, 8
    test qword ptr [rip + g_px], CX_GEN_PARAMS
    jnz 90f
    inc qword ptr [rip + g_param_errors]
    NODE T_AwaitExpression, rdi
    mov rbx, rax
    TT_IS J_STAR
    je 91f
    xor edi, edi
    mov esi, 1
    call jpe_maybe_unary
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: await in parameters"
91: REFUSE "syntax error: await*"
ENDF jpe_await

# ---------------------------------------------------------------- subscripts
# jpe_expr_subscripts(ref) -> rax
FUNC jpe_expr_subscripts
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_jt_start]
    mov r13, [rip + g_potential_arrow_at]
    call jpe_expr_atom
    mov rbx, rax
    mov rdi, rax
    mov rsi, r13
    call js_is_arrow_at
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call jpe_subscripts
    mov rbx, rax
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_expr_subscripts

# js_at_possible_async_arrow(base) -> eax: Babel's atPossibleAsyncArrow
FUNC js_at_possible_async_arrow
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 9f
    mov ecx, [rbx + N_END]
    cmp rcx, [rip + g_jt_last_end]
    jne 9f
    mov ecx, [rbx + N_START]
    cmp rcx, [rip + g_potential_arrow_at]
    jne 9f
    call js_can_insert_semicolon
    test eax, eax
    jnz 8f
    mov rdi, rbx
    lea rsi, [rip + s_async]
    mov edx, 5
    call js_node_text_is
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_at_possible_async_arrow

# jpe_subscripts(base, start, no_calls) -> rax: member access, calls, tagged templates and
# optional chains after base.
FUNC jpe_subscripts
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d                      # bit 0: in an optional chain; bit 1: maybe async arrow
    mov rdi, rbx
    call js_at_possible_async_arrow
    test eax, eax
    jz 1f
    or r14d, 2
1:  IF_NOT_TS 109f
    cmp qword ptr [rip + g_jt_nl], 0    # x!
    jne 101f
    TT_IS J_BANG
    jne 101f
    NEXT
    NODE T_TSNonNullExpression, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    FINISH rbx
    and r14d, ~2
    jmp 1b
101: xor r15d, r15d                     # ?.< : an optional call with type arguments
    TT_IS J_QDOT
    jne 102f
    call ts_lookahead_char
    cmp eax, '<'
    jne 102f
    test r13d, r13d
    jnz 99f
    or r14d, 1
    mov r15d, 1
    NEXT
102: TT_IS J_LT
    je 103f
    TT_IS J_SHL
    jne 109f
103: mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov eax, r14d
    and eax, 1
    shl eax, 1
    or edx, eax
    shl r15d, 2
    or edx, r15d
    call jts_subscript_lt
    test rax, rax
    jnz 104f
    test r15d, r15d
    jnz 99f
    jmp 109f
104: mov rbx, rax
    and r14d, ~2
    test edx, edx
    jnz 99f
    jmp 1b
109: TT_IS J_TEMPLATE
    jne 2f
    test r14d, 1
    jnz 90f
    NODE T_TaggedTemplateExpression, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    mov edi, 1
    call jpe_template
    mov [rbx + N_F1], rax
    FINISH rbx
    and r14d, ~2
    jmp 1b
2:  xor r15d, r15d                      # this subscript is optional
    TT_IS J_QDOT
    jne 3f
    test r13d, r13d
    jnz 91f
    or r14d, 1
    mov r15d, 1
    NEXT
3:  test r13d, r13d
    jnz 10f
    TT_IS J_LPAREN
    jne 10f
    # call
    NEXT
    mov edi, T_CallExpression
    test r14d, 1
    jz 4f
    mov edi, T_OptionalCallExpression
4:  mov rsi, r12
    call js_node
    mov [rax + N_F0], rbx
    mov [rsp + 16], rax                 # call node
    test r15d, r15d
    jz 41f
    or dword ptr [rax + N_ATTR], NA_OPTIONAL
41: test r14d, 2
    jz 5f
    test r15d, r15d
    jnz 5f
    # possible async arrow: one record for all arguments
    call jpe_errors_save
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rax, [rip + g_param_errors]
    mov [rsp + 24], rax
    mov edi, 1
    call jpe_call_args
    mov [rsp + 32], rdx                 # `a?` position
    mov rcx, [rsp + 16]
    mov [rcx + N_F1], rax
    FINISH rcx
    mov qword ptr [rsp + 24 + 16], 0    # return type
    IF_NOT_TS 43f
    TT_IS J_COLON
    jne 43f
    mov rdi, -1
    mov esi, 1
    call jts_type_annotation
    mov [rsp + 24 + 16], rax
    TT_IS J_ARROW
    jne 94f
    jmp 44f
43: TT_IS J_ARROW
    jne 42f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 42f
44: mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    mov rax, [rsp + 24]
    cmp rax, [rip + g_param_errors]
    jne 93f
    NEXT
    mov rax, [rsp + 16]
    mov rdi, r12
    mov rsi, [rax + N_F1]
    mov edx, 1
    call jpf_arrow
    mov rbx, rax
    mov rax, [rsp + 24 + 16]
    mov [rbx + N_F5], rax
    jmp 99f
42: call jpe_errors_check
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    IF_NOT_TS 6f
    cmp qword ptr [rsp + 32], -1
    jne 95f
    mov rax, [rsp + 16]
    mov rdi, [rax + N_F1]
    call jts_check_type_casts
    jmp 6f
5:  xor edi, edi
    call jpe_call_args
    mov rcx, [rsp + 16]
    mov [rcx + N_F1], rax
    FINISH rcx
6:  mov rbx, [rsp + 16]
    and r14d, ~2
    jmp 1b
    # member
10: TT_IS J_LBRACK
    jne 11f
    NEXT
    mov r15d, r15d
    or r15d, 2                          # computed
    jmp 12f
11: test r15d, r15d
    jnz 12f
    TT_IS J_DOT
    jne 99f
    NEXT
12: mov edi, T_MemberExpression
    test r14d, 1
    jz 13f
    mov edi, T_OptionalMemberExpression
13: mov rsi, r12
    call js_node
    mov [rax + N_F0], rbx
    mov rbx, rax
    test r15d, 1
    jz 14f
    or dword ptr [rbx + N_ATTR], NA_OPTIONAL
14: test r15d, 2
    jz 15f
    or dword ptr [rbx + N_ATTR], NA_COMPUTED
    call jpe_expression_allow_in
    mov [rbx + N_F1], rax
    EXPECT J_RBRACK
    jmp 17f
15: TT_IS J_PRIVATE
    jne 16f
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_Super
    je 92f
    call jpe_private_name
    mov [rbx + N_F1], rax
    jmp 17f
16: call js_ident_name
    mov [rbx + N_F1], rax
17: FINISH rbx
    and r14d, ~2
    jmp 1b
99: mov rax, rbx
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: tagged template in an optional chain"
91: REFUSE "syntax error: optional chain in new"
92: REFUSE "syntax error: super with a private name"
93: REFUSE "syntax error: yield or await in arrow parameters"
94: REFUSE "syntax error: => expected"
95: REFUSE "syntax error: optional parameter in call arguments"
ENDF jpe_subscripts

# jpe_call_args(ref) -> rax = VEC: arguments after `(`, consumes `)`. In TypeScript, with ref the
# position of an optional-parameter `a?` (or -1) is returned in rdx for the async arrow caller to
# judge; without ref such an argument, and a type annotation, are refused here.
FUNC jpe_call_args
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r13d, edi
    mov r14, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    mov rax, [rip + g_err_optparam]
    mov [rsp], rax
    mov qword ptr [rip + g_err_optparam], -1
    TS_SAVE [rsp + 8]
    or qword ptr [rip + g_ts], TS_ARROW_PARAMS
    call ss_mark
    mov r12, rax
    xor ebx, ebx                        # items so far
1:  TT_IS J_RPAREN
    je 8f
    test ebx, ebx
    jz 2f
    EXPECT J_COMMA
    TT_IS J_RPAREN
    je 8f
2:  inc ebx
    TT_IS J_ELLIPSIS
    jne 3f
    mov r15, [rip + g_jt_start]
    mov edi, r13d
    call jpe_spread
    IF_NOT_TS 4f
    mov rdi, rax
    mov rsi, r15
    call jts_paren_item
    jmp 4f
3:  TT_IS J_QUESTION
    je 90f
    mov edi, r13d
    or edi, MA_PAREN_ITEM
    call jpe_maybe_assign
4:  mov rdi, rax
    call ss_push
    jmp 1b
8:  NEXT
    mov [rip + g_px], r14
    mov rdi, r12
    call ss_to_vec
    mov rbx, rax
    TS_RESTORE TS_ARROW_PARAMS, [rsp + 8]
    mov r15, [rip + g_err_optparam]
    mov rax, [rsp]
    mov [rip + g_err_optparam], rax
    test r13d, r13d
    jnz 9f
    IF_NOT_TS 9f
    cmp r15, -1
    jne 91f
    mov rdi, rbx
    call jts_check_type_casts
9:  mov rax, rbx
    mov rdx, r15
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "partial application"
91: REFUSE "syntax error: optional parameter in arguments"
ENDF jpe_call_args

# jpe_spread(ref) -> rax: SpreadElement at `...`
FUNC jpe_spread
    push rbx
    push r12
    mov r12d, edi
    NODE T_SpreadElement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    mov edi, r12d
    call jpe_maybe_assign_ref_allow_in
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_spread

# jpe_private_name() -> rax: PrivateName from the current J_PRIVATE token
FUNC jpe_private_name
    push rbx
    push r12
    NODE T_PrivateName, [rip + g_jt_start]
    mov rbx, rax
    mov rsi, [rip + g_jt_start]
    inc rsi
    mov edi, T_Identifier
    call js_node
    mov rcx, [rip + g_jt_end]
    mov [rax + N_END], ecx
    mov [rbx + N_F0], rax
    NEXT
    FINISH rbx
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_private_name

# ---------------------------------------------------------------- atoms
# jpe_expr_atom(ref) -> rax
FUNC jpe_expr_atom
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r13d, edi
    mov r12, [rip + g_jt_start]
    mov rax, [rip + g_jt_type]
    cmp rax, J_NAME
    je 10f
    cmp rax, J_NUM
    je 30f
    cmp rax, J_STRING
    je 31f
    cmp rax, J_LPAREN
    je 40f
    cmp rax, J_LBRACK
    je 41f
    cmp rax, J_LBRACE
    je 42f
    cmp rax, J_TEMPLATE
    je 43f
    cmp rax, J_SLASH
    je 44f
    cmp rax, J_DIV_EQ
    je 44f
    cmp rax, J_BIGINT
    je 32f
    cmp rax, J_PRIVATE
    je 90f
    cmp rax, J_AT
    je 91f
    cmp rax, J_LT
    je 92f
    cmp rax, J_PERCENT
    je 89f
    jmp 98f

10: mov rax, [rip + g_jt_kw]
    cmp rax, KW_THIS
    je 11f
    cmp rax, KW_NULL
    je 12f
    cmp rax, KW_TRUE
    je 13f
    cmp rax, KW_FALSE
    je 14f
    cmp rax, KW_FUNCTION
    je 15f
    cmp rax, KW_NEW
    je 16f
    cmp rax, KW_CLASS
    je 17f
    cmp rax, KW_SUPER
    je 18f
    cmp rax, KW_IMPORT
    je 19f
    cmp rax, KW_DO
    je 93f
    cmp rax, KW_MODULE
    je 20f
    jmp 21f

11: mov edi, T_ThisExpression
    jmp 29f
12: mov edi, T_NullLiteral
    jmp 29f
13: mov ebx, 1
    jmp 141f
14: xor ebx, ebx
141: NODE T_BooleanLiteral, r12
    mov [rax + N_F0], rbx
    jmp 28f
15: NODE T_FunctionExpression, r12
    mov rbx, rax
    NEXT
    TT_IS J_DOT
    je 94f
    mov rdi, rbx
    xor esi, esi
    call jpf_function
    mov rbx, rax
    jmp 99f
16: call jpe_new
    mov rbx, rax
    jmp 99f
17: NODE T_ClassExpression, r12
    mov rdi, rax
    xor esi, esi
    mov edx, 1
    call jpf_class
    mov rbx, rax
    jmp 99f
18: NODE T_Super, r12
    mov rbx, rax
    NEXT
    FINISH rbx
    TT_IS J_LPAREN
    je 181f
    TT_IS J_LBRACK
    je 181f
    TT_IS J_DOT
    jne 95f
181: mov rax, rbx
    jmp 99f
19: call jpe_import
    mov rbx, rax
    jmp 99f
20: mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 21f
    cmp eax, '{'
    je 96f
    # identifier, async function, arrow
21: xor r14d, r14d                      # can be an arrow
    cmp r12, [rip + g_potential_arrow_at]
    sete r14b
    xor r15d, r15d
    KW_IS KW_ASYNC
    sete r15b
    xor edi, edi
    call js_ident
    mov rbx, rax
    test r15d, r15d
    jz 25f
    call js_can_insert_semicolon
    test eax, eax
    jnz 25f
    KW_IS KW_FUNCTION
    jne 22f
    NEXT
    NODE T_FunctionExpression, r12
    mov rbx, rax
    or dword ptr [rbx + N_ATTR], NA_ASYNC
    mov rdi, rbx
    xor esi, esi
    call jpf_function
    mov rbx, rax
    jmp 99f
22: KW_IS KW_DO
    je 93f
    TT_IS J_NAME
    jne 25f
    mov rax, [rip + g_jt_kw]
    test rax, rax
    jz 23f
    cmp rax, KW_LAST_RESERVED
    jbe 25f
23: mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '='
    jne 99f
    # async x => ...
    mov edi, 1
    call js_ident
    mov rbx, rax
    cmp qword ptr [rip + g_jt_nl], 0
    jne 97f
    EXPECT J_ARROW
    mov rdi, rbx
    call js_vec1
    mov rdi, r12
    mov rsi, rax
    mov edx, 1
    call jpf_arrow
    mov rbx, rax
    jmp 99f
25: test r14d, r14d
    jz 99f
    TT_IS J_ARROW
    jne 99f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 99f
    NEXT
    mov rdi, rbx
    call js_vec1
    mov rdi, r12
    mov rsi, rax
    xor edx, edx
    call jpf_arrow
    mov rbx, rax
    jmp 99f

29: mov rsi, r12
    call js_node
28: mov rbx, rax
    mov rax, [rip + g_jt_end]
    mov [rbx + N_END], eax
    NEXT
    jmp 99f
30: mov edi, T_NumericLiteral
    jmp 29b
31: NODE T_StringLiteral, r12
    mov rcx, [rip + g_jt_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_jt_len]
    mov [rax + N_F1], rcx
    jmp 28b
32: NODE T_BigIntLiteral, r12
    mov rcx, [rip + g_jt_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_jt_len]
    mov [rax + N_F1], rcx
    jmp 28b
40: xor edi, edi
    cmp r12, [rip + g_potential_arrow_at]
    sete dil
    call jpe_paren
    mov rbx, rax
    jmp 99f
41: mov edi, r13d
    call jpe_array
    mov rbx, rax
    jmp 99f
42: mov edi, r13d
    call jpe_object
    mov rbx, rax
    jmp 99f
43: xor edi, edi
    call jpe_template
    mov rbx, rax
    jmp 99f
44: call jl_regex
    NODE T_RegExpLiteral, r12
    mov rcx, [rip + g_jt_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_jt_len]
    mov [rax + N_F1], rcx
    mov rcx, [rip + g_text]
    add rcx, [rip + g_jt_raw_start]
    mov [rax + N_F2], rcx
    mov rcx, [rip + g_jt_raw_end]
    sub rcx, [rip + g_jt_raw_start]
    mov [rax + N_F3], rcx
    jmp 28b

99: mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
91: call jpd_decorators
    mov rbx, rax
    KW_IS KW_CLASS
    jne 911f
    NODE T_ClassExpression, [rip + g_jt_start]
    mov rdi, rax
    xor esi, esi
    mov edx, 1
    call jpf_class
    mov rdi, rax
    mov rsi, rbx
    call js_take_decorators
    mov rbx, rax
    jmp 99b
92: IF_NOT_TS 921f
    REFUSE "syntax error: unexpected <"
921: REFUSE "JSX"
89: REFUSE "V8 intrinsic"
90: REFUSE "syntax error: private name outside `#x in obj`"
911: REFUSE "syntax error: decorators before something other than a class"
93: REFUSE "do expression"
94: REFUSE "function.sent"
95: REFUSE "syntax error: super"
96: REFUSE "module expression"
97: REFUSE "syntax error: line break before =>"
98: REFUSE "syntax error: unexpected token"
ENDF jpe_expr_atom

# jpe_import() -> rax: import(...), import.meta
FUNC jpe_import
    push rbx
    push r12
    push r13
    push r14
    NODE T_ImportExpression, [rip + g_jt_start]
    mov rbx, rax
    mov r12, [rip + g_jt_start]
    mov r13, [rip + g_jt_end]
    NEXT
    TT_IS J_DOT
    jne 2f
    NEXT
    lea rdi, [rip + s_meta]
    mov esi, 4
    call js_tok_text_is
    test eax, eax
    jz 91f
    cmp qword ptr [rip + g_js_script], 0
    jne 92f
    mov word ptr [rbx + N_TYPE], T_MetaProperty
    NODE T_Identifier, r12
    mov [rax + N_END], r13d
    mov [rbx + N_F0], rax
    call js_ident_name
    mov [rbx + N_F1], rax
    FINISH rbx
    jmp 9f
2:  TT_IS J_LPAREN
    jne 90f
    NEXT
    mov r14, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F0], rax
    TT_IS J_COMMA
    jne 3f
    NEXT
    TT_IS J_RPAREN
    je 3f
    xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F1], rax
    TT_IS J_COMMA
    jne 3f
    NEXT
    TT_IS J_RPAREN
    jne 93f
3:  mov [rip + g_px], r14
    EXPECT J_RPAREN
    FINISH rbx
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: import"
91: REFUSE "import phase or reflection"
92: REFUSE "syntax error: import.meta outside a module"
93: REFUSE "syntax error: import() with more than two arguments"
ENDF jpe_import

# jpe_new() -> rax: NewExpression or new.target
FUNC jpe_new
    push rbx
    push r12
    push r13
    push r14
    NODE T_NewExpression, [rip + g_jt_start]
    mov rbx, rax
    mov r12, [rip + g_jt_start]
    mov r13, [rip + g_jt_end]
    NEXT
    TT_IS J_DOT
    jne 2f
    NEXT
    lea rdi, [rip + s_target]
    mov esi, 6
    call js_tok_text_is
    test eax, eax
    jz 90f
    mov word ptr [rbx + N_TYPE], T_MetaProperty
    NODE T_Identifier, r12
    mov [rax + N_END], r13d
    mov [rbx + N_F0], rax
    call js_ident_name
    mov [rbx + N_F1], rax
    FINISH rbx
    jmp 9f
2:  KW_IS KW_IMPORT
    je 90f
    mov r14, [rip + g_jt_start]
    xor edi, edi
    call jpe_expr_atom
    mov rdi, rax
    mov rsi, r14
    mov edx, 1
    call jpe_subscripts
    mov [rbx + N_F0], rax
    cmp word ptr [rax + N_TYPE], T_TSInstantiationExpression
    jne 1f
    mov rcx, [rax + N_F4]
    mov [rbx + N_F4], rcx
    mov rcx, [rax + N_F0]
    mov [rbx + N_F0], rcx
1:  lea rax, [rip + js_empty_vec]
    mov [rbx + N_F1], rax
    TT_IS J_LPAREN
    jne 3f
    NEXT
    xor edi, edi
    call jpe_call_args
    mov [rbx + N_F1], rax
3:  FINISH rbx
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: new"
ENDF jpe_new

# jpe_paren(can_be_arrow) -> rax: ParenthesizedExpression, or an arrow function
FUNC jpe_paren
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov r15d, edi
    mov r12, [rip + g_jt_start]
    NEXT
    mov rax, [rip + g_err_optparam]
    mov [rsp + 56], rax
    mov qword ptr [rip + g_err_optparam], -1
    TS_SAVE [rsp + 64]
    or qword ptr [rip + g_ts], TS_ARROW_PARAMS
    call jpe_errors_save
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rax, [rip + g_px]
    mov [rsp + 16], rax
    and qword ptr [rip + g_px], ~CX_NO_IN
    mov rax, [rip + g_jt_start]
    mov [rsp + 24], rax                 # inner start
    mov qword ptr [rsp + 32], 0         # bit 0 trailing comma, bit 1 rest element
    mov rax, [rip + g_param_errors]
    mov [rsp + 48], rax
    call ss_mark
    mov r13, rax
    xor ebx, ebx                        # items
1:  TT_IS J_RPAREN
    je 5f
    test ebx, ebx
    jz 2f
    EXPECT J_COMMA
    TT_IS J_RPAREN
    jne 2f
    or qword ptr [rsp + 32], 1
    jmp 5f
2:  inc ebx
    TT_IS J_ELLIPSIS
    jne 3f
    or qword ptr [rsp + 32], 2
    NODE T_RestElement, [rip + g_jt_start]
    mov r14, rax
    NEXT
    call jpp_binding_atom
    mov [r14 + N_F0], rax
    FINISH r14
    IF_NOT_TS 21f
    mov rdi, r14
    mov esi, [r14 + N_START]
    call jts_paren_item
    mov r14, rax
21: mov rdi, r14
    call ss_push
    TT_IS J_COMMA
    jne 5f
    mov rdi, [rip + g_jt_end]           # `(...a,)`: RestTrailingComma, allowed for an arrow
    call jl_next_char
    cmp eax, ')'
    jne 91f
    NEXT
    or qword ptr [rsp + 32], 1
    jmp 5f
3:  mov edi, MA_REF | MA_PAREN_ITEM
    call jpe_maybe_assign
    mov rdi, rax
    call ss_push
    jmp 1b
5:  mov rax, [rip + g_jt_last_end]
    mov [rsp + 40], rax                 # inner end
    EXPECT J_RPAREN
    TS_RESTORE TS_ARROW_PARAMS, [rsp + 64]
    mov rax, [rsp + 16]
    mov [rip + g_px], rax
    mov rdi, r13
    call ss_to_vec
    mov r14, rax
    mov qword ptr [rsp + 72], 0         # return type
    test r15d, r15d
    jz 6f
    IF_NOT_TS 51f
    TT_IS J_COLON
    jne 51f
    xor ebx, ebx                        # TypeScript's shouldParseArrow: every item assignable
52: cmp rbx, [r14]
    jae 53f
    mov rdi, [r14 + 8 + rbx*8]
    mov esi, 1
    call js_is_assignable
    test eax, eax
    jz 54f
    inc rbx
    jmp 52b
53: lea rdi, [rip + jts_arrow_return_type]
    call js_try
    cmp edx, TRY_OK
    jne 54f
    mov [rsp + 72], rax
    jmp 55f
54: mov rbx, [r14]
    jmp 6f
51: TT_IS J_ARROW
    jne 6f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 6f
55: mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    mov rax, [rsp + 56]
    mov [rip + g_err_optparam], rax
    mov rax, [rsp + 48]
    cmp rax, [rip + g_param_errors]
    jne 92f
    NEXT
    mov rdi, r12
    mov rsi, r14
    xor edx, edx
    call jpf_arrow
    mov rcx, [rsp + 72]
    mov [rax + N_F5], rcx
    jmp 99f
6:  IF_NOT_TS 61f
    cmp qword ptr [rip + g_err_optparam], -1
    jne 93f
    mov rdi, r14
    call jts_check_type_casts
61: mov rax, [rsp + 56]
    mov [rip + g_err_optparam], rax
    test ebx, ebx
    jz 90f
    cmp qword ptr [rsp + 32], 0
    jne 90f
    call jpe_errors_check
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    mov r15, [r14 + 8]
    cmp ebx, 1
    je 7f
    NODE T_SequenceExpression, [rsp + 24]
    mov [rax + N_F0], r14
    mov rcx, [rsp + 40]
    mov [rax + N_END], ecx
    mov r15, rax
7:  NODE T_ParenthesizedExpression, r12
    mov [rax + N_F0], r15
    FINISH rax
99: add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: in parentheses"
91: REFUSE "syntax error: comma after a rest element"
92: REFUSE "syntax error: yield or await in arrow parameters"
93: REFUSE "syntax error: optional parameter in parentheses"
ENDF jpe_paren

# jpe_array(ref) -> rax: ArrayExpression at `[`
FUNC jpe_array
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r13d, edi
    mov r15, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    NODE T_ArrayExpression, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call ss_mark
    mov r12, rax
    xor r14d, r14d                      # items
1:  TT_IS J_RBRACK
    je 8f
    test r14d, r14d
    jz 2f
    EXPECT J_COMMA
    TT_IS J_RBRACK
    je 8f
2:  inc r14d
    TT_IS J_COMMA
    jne 3f
    xor eax, eax                        # hole
    jmp 5f
3:  TT_IS J_ELLIPSIS
    jne 4f
    mov rax, [rip + g_jt_start]
    mov [rsp], rax
    mov edi, r13d
    call jpe_spread
    IF_NOT_TS 5f
    mov rdi, rax
    mov rsi, [rsp]
    call jts_paren_item
    jmp 5f
4:  mov edi, r13d
    or edi, MA_PAREN_ITEM
    call jpe_maybe_assign
5:  mov rdi, rax
    call ss_push
    jmp 1b
8:  NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
    IF_NOT_TS 81f
    mov rdi, rax
    call jts_check_type_casts
81: FINISH rbx
    mov [rip + g_px], r15
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpe_array

# jpe_object(ref) -> rax: ObjectExpression at `{`
FUNC jpe_object
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r13d, edi
    mov r15, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    NODE T_ObjectExpression, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call ss_mark
    mov r12, rax
    xor r14d, r14d                      # bit 0: not first; bit 1: saw __proto__
1:  TT_IS J_RBRACE
    je 8f
    test r14d, 1
    jz 2f
    EXPECT J_COMMA
    TT_IS J_RBRACE
    je 8f
2:  or r14d, 1
    mov edi, r13d
    call jpe_property
    mov [rsp], rax
    mov rdi, rax
    call ss_push
    # checkProto
    mov rdi, [rsp]
    call js_is_proto_prop
    test eax, eax
    jz 1b
    test r14d, 2
    jz 3f
    test r13d, r13d
    jz 90f
    cmp qword ptr [rip + g_err_proto], -1
    jne 1b
    mov rax, [rsp]
    mov rax, [rax + N_F0]
    mov eax, [rax + N_START]
    mov [rip + g_err_proto], rax
    jmp 1b
3:  or r14d, 2
    jmp 1b
8:  NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
    FINISH rbx
    mov [rip + g_px], r15
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: duplicate __proto__"
ENDF jpe_object

# js_is_proto_prop(prop) -> eax: a non-shorthand, non-computed ObjectProperty whose key is
# __proto__ (identifier or string value)
FUNC js_is_proto_prop
    push rbx
    sub rsp, 8
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectProperty
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_COMPUTED | NA_SHORTHAND
    jnz 9f
    mov rbx, [rdi + N_F0]
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 1f
    mov rdi, rbx
    lea rsi, [rip + s_proto]
    mov edx, 9
    call js_node_text_is
    jmp 9f
1:  cmp word ptr [rbx + N_TYPE], T_StringLiteral
    jne 9f
    cmp qword ptr [rbx + N_F1], 9
    jne 8f
    mov rdi, [rbx + N_F0]
    lea rsi, [rip + s_proto]
    mov edx, 9
    call mem_eq
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_is_proto_prop

# jpe_property_name(prop): sets prop.key (F0) and computed. Private names are refused here;
# classes read them before calling.
FUNC jpe_property_name
    push rbx
    push r12
    mov rbx, rdi
    mov rax, [rip + g_jt_type]
    cmp rax, J_LBRACK
    je 1f
    cmp rax, J_NAME
    je 2f
    cmp rax, J_STRING
    je 3f
    cmp rax, J_NUM
    je 4f
    cmp rax, J_BIGINT
    je 5f
    cmp rax, J_PRIVATE
    je 90f
    REFUSE "syntax error: property name expected"
90: REFUSE "private name in an object or pattern (destructuring private)"
1:  or dword ptr [rbx + N_ATTR], NA_COMPUTED
    NEXT
    call jpe_maybe_assign_allow_in
    mov [rbx + N_F0], rax
    EXPECT J_RBRACK
    jmp 9f
2:  and dword ptr [rbx + N_ATTR], ~NA_COMPUTED
    call js_ident_name
    mov [rbx + N_F0], rax
    jmp 9f
3:  and dword ptr [rbx + N_ATTR], ~NA_COMPUTED
    NODE T_StringLiteral, [rip + g_jt_start]
    mov rcx, [rip + g_jt_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_jt_len]
    mov [rax + N_F1], rcx
    jmp 6f
4:  and dword ptr [rbx + N_ATTR], ~NA_COMPUTED
    NODE T_NumericLiteral, [rip + g_jt_start]
    jmp 6f
5:  and dword ptr [rbx + N_ATTR], ~NA_COMPUTED
    NODE T_BigIntLiteral, [rip + g_jt_start]
    mov rcx, [rip + g_jt_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_jt_len]
    mov [rax + N_F1], rcx
6:  mov rcx, [rip + g_jt_end]
    mov [rax + N_END], ecx
    mov [rbx + N_F0], rax
    NEXT
9:  pop r12
    pop rbx
    leave
    ret
ENDF jpe_property_name

# js_key_is_word(prop, kw) -> eax: the key is a non-computed Identifier from the word kw
# (the token that was read as the key had that keyword id: stored by jpe_property in r?)
# jpe_property(ref) -> rax: one property of an object literal
FUNC jpe_property
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r13d, edi
    TT_IS J_ELLIPSIS
    jne 1f
    mov edi, r13d
    call jpe_spread
    jmp 99f
1:  TT_IS J_AT
    je 91f
    mov r12, [rip + g_jt_start]
    NODE T_ObjectProperty, r12
    mov rbx, rax
    xor r14d, r14d                      # bit 0 generator, bit 1 async, bit 2 accessor
    TT_IS J_STAR
    jne 2f
    NEXT
    or r14d, 1
2:  mov r15, [rip + g_jt_kw]            # word of the key token
    TT_IS J_NAME
    je 21f
    xor r15d, r15d
21: mov rax, [rip + g_jt_type]
    mov [rsp], rax
    mov rdi, rbx
    call jpe_property_name
    test r14d, 1
    jnz 5f
    cmp qword ptr [rsp], J_NAME
    jne 5f
    test dword ptr [rbx + N_ATTR], NA_COMPUTED
    jnz 5f
    # maybeAsyncOrAccessorProp: a property name, `[` or `*` follows
    mov rax, [rip + g_jt_type]
    cmp rax, J_NAME
    je 3f
    cmp rax, J_STRING
    je 3f
    cmp rax, J_NUM
    je 3f
    cmp rax, J_BIGINT
    je 3f
    cmp rax, J_PRIVATE
    je 3f
    cmp rax, J_LBRACK
    je 3f
    cmp rax, J_STAR
    jne 5f
3:  cmp r15, KW_ASYNC
    jne 4f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 4f
    or r14d, 2
    TT_IS J_STAR
    jne 31f
    NEXT
    or r14d, 1
31: TT_IS J_PRIVATE
    je 90f
    mov rdi, rbx
    call jpe_property_name
    jmp 5f
4:  cmp r15, KW_GET
    je 41f
    cmp r15, KW_SET
    jne 5f
41: or r14d, 4
    mov qword ptr [rbx + N_F3], KD_GET
    cmp r15, KW_GET
    je 42f
    mov qword ptr [rbx + N_F3], KD_SET
42: TT_IS J_STAR
    je 92f
    TT_IS J_PRIVATE
    je 90f
    mov rdi, rbx
    call jpe_property_name
    # method or property
5:  IF_NOT_TS 50f
    mov edi, 1                          # TP_CONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
50: test r14d, 4
    jnz 6f
    test r14d, 3
    jnz 7f
    TT_IS J_LPAREN
    je 7f
    jmp 10f
6:  mov word ptr [rbx + N_TYPE], T_ObjectMethod
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call jpf_method
    mov rdi, rbx
    call jpf_check_accessor_params
    jmp 98f
7:  mov word ptr [rbx + N_TYPE], T_ObjectMethod
    mov qword ptr [rbx + N_F3], KD_METHOD
    or dword ptr [rbx + N_ATTR], NA_METHOD
    mov esi, r14d
    and esi, 1
    mov edx, r14d
    shr edx, 1
    and edx, 1
    mov rdi, rbx
    call jpf_method
    jmp 98f
    # ObjectProperty
10: cmp qword ptr [rbx + N_F4], 0
    jne 93f
    TT_IS J_COLON
    jne 11f
    NEXT
    mov edi, r13d
    call jpe_maybe_assign_ref_allow_in
    mov [rbx + N_F1], rax
    FINISH rbx
    jmp 98f
11: test dword ptr [rbx + N_ATTR], NA_COMPUTED
    jnz 93f
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_Identifier
    jne 93f
    # shorthand: the key must be a valid identifier reference
    mov rdi, r15
    xor esi, esi
    call js_word_check
12: or dword ptr [rbx + N_ATTR], NA_SHORTHAND
    mov rdi, [rbx + N_F0]
    call js_clone
    mov r14, rax
    TT_IS J_EQ
    jne 13f
    test r13d, r13d
    jz 95f
    cmp qword ptr [rip + g_err_shorthand], -1
    jne 121f
    mov rax, [rip + g_jt_start]
    mov [rip + g_err_shorthand], rax
121: NODE T_AssignmentPattern, r12
    mov [rax + N_F0], r14
    mov r14, rax
    NEXT
    call jpe_maybe_assign_allow_in
    mov [r14 + N_F1], rax
    FINISH r14
13: mov [rbx + N_F1], r14
    FINISH rbx
98: mov rax, rbx
99: add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: private name in an object literal"
91: REFUSE "decorators"
92: REFUSE "syntax error: generator accessor"
93: REFUSE "syntax error: in object literal"
95: REFUSE "syntax error: shorthand property with an initializer outside a pattern"
ENDF jpe_property

# ---------------------------------------------------------------- templates
# jpe_template(tagged) -> rax: TemplateLiteral at the current J_TEMPLATE token
FUNC jpe_template
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    NODE T_TemplateLiteral, [rip + g_jt_start]
    mov rbx, rax
    mov r15, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    call ss_mark
    mov r12, rax                        # quasi, expression, quasi, ...
1:  TT_IS J_TEMPLATE
    jne 90f
    NODE T_TemplateElement, [rip + g_jt_raw_start]
    mov r13, rax
    mov rax, [rip + g_jt_raw_end]
    mov [r13 + N_END], eax
    mov rax, [rip + g_jt_val]
    mov [r13 + N_F0], rax
    mov rax, [rip + g_jt_len]
    mov [r13 + N_F1], rax
    mov r14, [rip + g_jt_flags]
    and r14d, 1
    jz 2f
    or dword ptr [r13 + N_ATTR], NA_TAIL
2:  mov rdi, r13
    call ss_push
    NEXT
    test r14d, r14d
    jnz 5f
    test qword ptr [rip + g_ts], TS_IN_TYPE
    jz 3f
    call jts_type
    jmp 4f
3:  xor edi, edi
    call jpe_expression
4:  mov rdi, rax
    call ss_push
    TT_IS J_RBRACE
    jne 90f
    call jl_template_continue
    jmp 1b
    # split the alternating list
5:  mov r13, [rip + g_ss_ptr]
    sub r13, r12
    shr r13, 3                          # items: 2n+1
    lea rdi, [r13 + 1]
    shr rdi, 1
    lea rdi, [rdi*8 + 8]
    call alloc
    mov r14, rax                        # quasis
    mov rdi, r13
    shr rdi, 1
    lea rdi, [rdi*8 + 8]
    call alloc                          # expressions
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
6:  cmp rcx, r13
    jae 7f
    mov r9, [r12 + rcx*8]
    test ecx, 1
    jnz 61f
    mov [r14 + 8 + rdx*8], r9
    inc rdx
    jmp 62f
61: mov [rax + 8 + r8*8], r9
    inc r8
62: inc rcx
    jmp 6b
7:  mov [r14], rdx
    mov [rax], r8
    mov [rbx + N_F0], r14
    mov [rbx + N_F1], rax
    mov [rip + g_ss_ptr], r12
    FINISH rbx
    mov [rip + g_px], r15
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: in template literal"
ENDF jpe_template
