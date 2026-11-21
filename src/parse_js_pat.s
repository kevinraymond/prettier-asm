# JS patterns: binding atoms, Babel's toAssignable (expression to pattern, in place) and
# checkLVal (assignment and binding targets).
.include "defs.inc"
.include "parse_js.inc"

    .text

# jpp_binding_element() -> rax: a binding atom with an optional `= default`
FUNC jpp_binding_element
    push rbx
    push r12
    mov r12, [rip + g_jt_start]
    call jpp_binding_atom
    mov rbx, rax
    TT_IS J_EQ
    jne 9f
    NODE T_AssignmentPattern, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    NEXT
    call jpe_maybe_assign_allow_in
    mov [rbx + N_F1], rax
    FINISH rbx
9:  mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jpp_binding_element

# jpp_rest_element() -> rax: RestElement at `...` with a binding atom
FUNC jpp_rest_element
    push rbx
    sub rsp, 8
    NODE T_RestElement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call jpp_binding_atom
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpp_rest_element

# jpp_binding_atom() -> rax: Identifier, ArrayPattern or ObjectPattern
FUNC jpp_binding_atom
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rax, [rip + g_jt_type]
    cmp rax, J_LBRACK
    je 10f
    cmp rax, J_LBRACE
    je 20f
    IF_NOT_TS 1f
    KW_IS KW_THIS                       # TypeScript's `this` parameter
    jne 1f
    call js_ident_name
    jmp 99f
1:  mov edi, 1
    call js_ident
    jmp 99f
    # [ ... ]
10: NODE T_ArrayPattern, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call ss_mark
    mov r12, rax
    xor r13d, r13d
11: TT_IS J_RBRACK
    je 18f
    test r13d, r13d
    jz 12f
    EXPECT J_COMMA
    TT_IS J_RBRACK
    je 18f
12: inc r13d
    TT_IS J_COMMA
    jne 13f
    xor edi, edi
    call ss_push
    jmp 11b
13: TT_IS J_ELLIPSIS
    jne 14f
    call jpp_rest_element
    mov rdi, rax
    call ss_push
    mov edi, ']'
    call jpp_comma_after_rest
    jmp 18f
14: call jpp_binding_element
    mov rdi, rax
    call ss_push
    jmp 11b
18: NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    jmp 99f
    # { ... }
20: NODE T_ObjectPattern, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call ss_mark
    mov r12, rax
    xor r13d, r13d
21: TT_IS J_RBRACE
    je 28f
    test r13d, r13d
    jz 22f
    EXPECT J_COMMA
    TT_IS J_RBRACE
    je 28f
22: inc r13d
    TT_IS J_ELLIPSIS
    jne 23f
    NODE T_RestElement, [rip + g_jt_start]
    mov r14, rax
    NEXT
    mov edi, 1
    call js_ident
    mov [r14 + N_F0], rax
    FINISH r14
    mov rdi, r14
    call ss_push
    mov edi, '}'
    call jpp_comma_after_rest
    jmp 28f
23: TT_IS J_PRIVATE
    je 91f
    TT_IS J_AT
    je 92f
    mov r15, [rip + g_jt_start]
    NODE T_ObjectProperty, r15
    mov r14, rax
    xor eax, eax
    TT_IS J_NAME
    jne 231f
    mov rax, [rip + g_jt_kw]
    test rax, rax
    jnz 231f
    mov eax, -1                         # a plain identifier
231: mov [rsp], rax                     # key word: KW_*, 0 not a word, -1 plain
    mov rdi, r14
    call jpe_property_name
    TT_IS J_COLON
    jne 24f
    NEXT
    call jpp_binding_element
    mov [r14 + N_F1], rax
    jmp 27f
24: test dword ptr [r14 + N_ATTR], NA_COMPUTED
    jnz 93f
    mov rax, [rsp]
    test rax, rax
    jz 93f
    cmp rax, -1
    je 25f
    mov rdi, rax
    mov esi, 1
    call js_word_check
25: or dword ptr [r14 + N_ATTR], NA_SHORTHAND
    mov rdi, [r14 + N_F0]
    call js_clone
    mov [r14 + N_F1], rax
    TT_IS J_EQ
    jne 27f
    NODE T_AssignmentPattern, r15
    mov rcx, [r14 + N_F1]
    mov [rax + N_F0], rcx
    mov [r14 + N_F1], rax
    NEXT
    call jpe_maybe_assign_allow_in
    mov rcx, [r14 + N_F1]
    mov [rcx + N_F1], rax
    FINISH rcx
27: FINISH r14
    mov rdi, r14
    call ss_push
    jmp 21b
28: NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
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
90: REFUSE "syntax error: element after a rest element"
91: REFUSE "private name in a pattern (destructuring private)"
92: REFUSE "decorators"
93: REFUSE "syntax error: in object pattern"
ENDF jpp_binding_atom

# jpp_comma_after_rest(close char): after a rest element only the closing token may follow, or
# a comma and then it (Babel reports RestTrailingComma, which Prettier allows); the comma is
# consumed
FUNC jpp_comma_after_rest
    push rbx
    sub rsp, 8
    mov ebx, edi
    TT_IS J_COMMA
    jne 1f
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, ebx
    jne 90f
    NEXT
1:  cmp [rip + g_jt_type], rbx
    jne 90f
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: element after a rest element"
ENDF jpp_comma_after_rest

# js_unparen(node) -> rax: the expression inside any ParenthesizedExpression wrappers
FUNC js_unparen
    mov rax, rdi
1:  cmp word ptr [rax + N_TYPE], T_ParenthesizedExpression
    jne 9f
    mov rax, [rax + N_F0]
    jmp 1b
9:  leave
    ret
ENDF js_unparen

# jpp_to_assignable(node, is_lhs): Babel's toAssignable. is_lhs is 0 for arrow parameters.
FUNC jpp_to_assignable
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ParenthesizedExpression
    jne 10f
    test r12d, r12d
    jz 90f
    mov rdi, rbx
    call js_unparen
    mov rdi, rax
    movzx eax, word ptr [rax + N_TYPE]
    cmp eax, T_Identifier
    je 99f
    cmp eax, T_MemberExpression
    je 99f
    cmp eax, T_OptionalMemberExpression
    je 99f
    call js_is_ts_cast
    test eax, eax
    jnz 11f
    jmp 90f
10: mov rdi, rbx
    call js_is_ts_cast
    test eax, eax
    jz 12f
    test r12d, r12d
    jz 93f
    mov rdi, rbx
11: mov rdi, [rdi + N_F0]               # a TypeScript cast: its expression
    mov esi, r12d
    call jpp_to_assignable
    jmp 99f
12: movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ObjectExpression
    je 20f
    cmp eax, T_ArrayExpression
    je 30f
    cmp eax, T_AssignmentExpression
    je 40f
    jmp 99f
    # object
20: mov word ptr [rbx + N_TYPE], T_ObjectPattern
    mov r13, [rbx + N_F0]
    xor r14d, r14d
21: cmp r14, [r13]
    jae 99f
    mov r15, [r13 + 8 + r14*8]
    movzx eax, word ptr [r15 + N_TYPE]
    cmp eax, T_ObjectMethod
    je 91f
    cmp eax, T_SpreadElement
    jne 22f
    mov word ptr [r15 + N_TYPE], T_RestElement
    mov rdi, [r15 + N_F0]
    xor esi, esi
    call jpp_check_to_rest
    mov rdi, [r15 + N_F0]
    mov esi, r12d
    call jpp_to_assignable
    jmp 23f
22: cmp eax, T_ObjectProperty
    jne 23f
    mov rdi, [r15 + N_F1]
    mov esi, r12d
    call jpp_to_assignable
23: inc r14
    jmp 21b
    # array
30: mov word ptr [rbx + N_TYPE], T_ArrayPattern
    mov rdi, [rbx + N_F0]
    mov esi, r12d
    call jpp_to_assignable_list
    jmp 99f
    # a = b
40: cmp qword ptr [rbx + N_F2], J_EQ
    jne 92f
    test r12d, r12d
    jnz 41f
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_TSTypeCastExpression
    jne 41f
    mov rdi, rax
    call js_type_cast_to_param
    mov [rbx + N_F0], rax
41:
    mov word ptr [rbx + N_TYPE], T_AssignmentPattern
    mov qword ptr [rbx + N_F2], 0
    mov rdi, [rbx + N_F0]
    mov esi, r12d
    call jpp_to_assignable
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: invalid parenthesized pattern"
91: REFUSE "syntax error: method in a pattern"
92: REFUSE "syntax error: compound assignment in a pattern"
93: REFUSE "syntax error: type cast in a parameter"
ENDF jpp_to_assignable

# js_is_ts_cast(node) -> eax: TSAsExpression, TSSatisfiesExpression, TSTypeAssertion or
# TSNonNullExpression
FUNC js_is_ts_cast
    xor eax, eax
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_TSAsExpression
    je 1f
    cmp ecx, T_TSSatisfiesExpression
    je 1f
    cmp ecx, T_TSTypeAssertion
    je 1f
    cmp ecx, T_TSNonNullExpression
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF js_is_ts_cast

# js_type_cast_to_param(cast) -> rax: typeCastToParameter: the expression of a
# TSTypeCastExpression with its type annotation, its range grown to take it in
FUNC js_type_cast_to_param
    push rbx
    sub rsp, 8
    mov rbx, [rdi + N_F0]
    mov rax, [rdi + N_F5]
    mov [rbx + N_F5], rax
    mov rdi, rbx
    mov esi, [rax + N_END]
    call js_extend_end
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF js_type_cast_to_param

# jpp_to_assignable_list(vec, is_lhs): array elements or arrow parameters
FUNC jpp_to_assignable_list
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    xor r13d, r13d
1:  cmp r13, [rbx]
    jae 9f
    mov r14, [rbx + 8 + r13*8]
    test r14, r14
    jz 3f
    cmp word ptr [r14 + N_TYPE], T_TSTypeCastExpression
    jne 11f
    mov rdi, r14
    call js_type_cast_to_param
    mov r14, rax
    mov [rbx + 8 + r13*8], rax
11: cmp word ptr [r14 + N_TYPE], T_SpreadElement
    jne 2f
    mov word ptr [r14 + N_TYPE], T_RestElement
    mov rdi, [r14 + N_F0]
    mov esi, 1
    call jpp_check_to_rest
    mov rdi, [r14 + N_F0]
    mov esi, r12d
    call jpp_to_assignable
    jmp 3f
2:  mov rdi, r14
    mov esi, r12d
    call jpp_to_assignable
3:  inc r13
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpp_to_assignable_list

# jpp_check_to_rest(node, allow_pattern): Babel's checkToRestConversion
FUNC jpp_check_to_rest
    sub rsp, 16
    mov [rsp], esi
1:  call js_unparen
    mov rdi, rax
    push rdi
    sub rsp, 8
    call js_is_ts_cast
    add rsp, 8
    pop rdi
    test eax, eax
    jz 2f
    mov rdi, [rdi + N_F0]
    mov dword ptr [rsp], 0
    jmp 1b
2:  movzx eax, word ptr [rdi + N_TYPE]
    cmp eax, T_Identifier
    je 9f
    cmp eax, T_MemberExpression
    je 9f
    cmp dword ptr [rsp], 0
    je 90f
    cmp eax, T_ArrayExpression
    je 9f
    cmp eax, T_ObjectExpression
    je 9f
    jmp 90f
9:  leave
    ret
90: REFUSE "syntax error: invalid rest element"
ENDF jpp_check_to_rest

# jpp_check_lval(node, flags): Babel's checkLVal. flags: 1 a binding (parameters), 2 the
# unparenthesized left side of an assignment (where TypeScript casts other than `!` are invalid).
FUNC jpp_check_lval
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_Identifier
    je 99f
    cmp eax, T_TSNonNullExpression
    je 40f
    cmp eax, T_TSParameterProperty
    je 40f
    cmp eax, T_TSAsExpression
    je 41f
    cmp eax, T_TSSatisfiesExpression
    je 41f
    cmp eax, T_TSTypeAssertion
    je 41f
    cmp eax, T_MemberExpression
    je 10f
    cmp eax, T_OptionalMemberExpression
    je 91f
    cmp eax, T_ParenthesizedExpression
    je 20f
    cmp eax, T_AssignmentPattern
    je 21f
    cmp eax, T_RestElement
    je 21f
    cmp eax, T_ObjectProperty
    je 22f
    cmp eax, T_ArrayPattern
    je 30f
    cmp eax, T_ObjectPattern
    je 30f
    jmp 90f
10: test r12d, 1
    jnz 90f
    jmp 99f
41: cmp r12d, 2
    je 90f
40: mov rdi, [rbx + N_F0]               # expression, parameter
    jmp 23f
20: mov rdi, [rbx + N_F0]               # (expression)
    jmp 23f
21: mov rdi, [rbx + N_F0]               # left, argument
    jmp 23f
22: mov rdi, [rbx + N_F1]               # value
23: mov esi, r12d
    and esi, 1
    call jpp_check_lval
    jmp 99f
30: mov r13, [rbx + N_F0]
    xor r14d, r14d
31: cmp r14, [r13]
    jae 99f
    mov rdi, [r13 + 8 + r14*8]
    inc r14
    test rdi, rdi
    jz 31b
    mov esi, r12d
    and esi, 1
    call jpp_check_lval
    jmp 31b
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: invalid assignment target"
91: REFUSE "optional chain as an assignment target"
ENDF jpp_check_lval
