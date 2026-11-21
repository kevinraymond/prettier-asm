# print/assignment.js
.include "pjs.inc"

SDOC sd_space_eq, " ="

    .section .rodata
s_require: .asciz "require"
    .balign 8
# path.match(isAssignment, isAssignmentOrVariableDeclarator, ...) for
# shouldUseChainFormatting; the third predicate depends on isTail
match_chain_not_tail: .quad pas_m_assignment, pas_m_assignment_or_declarator, 0
match_chain_tail: .quad pas_m_assignment, pas_m_assignment_or_declarator, pas_m_not_statement
    .text

# pjs_print_assignment(left_doc, operator_doc, right_offset, right_key) -> rax
# (printAssignment); the node is the path's top
FUNC pjs_print_assignment
    PROLOGUE 4
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    call path_value
    mov rdi, rax
    mov rsi, rbx
    mov edx, r13d
    mov ecx, r14d
    call pas_choose_layout
    mov r15d, eax
    mov edi, eax
    call args_for_layout
    mov rdx, rax
    mov edi, r13d
    mov esi, r14d
    call print_field
    mov r13, rax                    # rightDoc
    mov rdi, rbx
    xor esi, esi
    call doc_group
    mov r14, rax                    # group(leftDoc)
    cmp r15d, AL_BREAK_AFTER_OPERATOR
    je 10f
    cmp r15d, AL_NEVER_BREAK_AFTER_OPERATOR
    je 20f
    cmp r15d, AL_FLUID
    je 30f
    cmp r15d, AL_BREAK_LHS
    je 40f
    cmp r15d, AL_CHAIN
    je 50f
    cmp r15d, AL_CHAIN_TAIL
    je 60f
    cmp r15d, AL_CHAIN_TAIL_ARROW_CHAIN
    je 70f
    mov rax, rbx                    # only-left
    jmp 99f
    # group([group(leftDoc), operator, group(indent([line, rightDoc]))])
10: lea rdi, [rip + d_line]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
    GROUP_RAX
    mov rdi, r14
    mov rsi, r12
    mov rdx, rax
    call doc_array3
    GROUP_RAX
    jmp 99f
    # group([group(leftDoc), operator, " ", rightDoc])
20: DMARK r15
    DPUSH r14
    DPUSH r12
    DPUSHL ps_space
    DPUSH r13
    DARRAY r15
    GROUP_RAX
    jmp 99f
    # group([group(leftDoc), operator, group(indent(line), {id}),
    #   lineSuffixBoundary, indentIfBreak(rightDoc, {groupId})])
30: call doc_group_id_new
    mov [rsp], rax
    lea rdi, [rip + d_line]
    call doc_indent
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp]
    call doc_group_ex
    mov [rsp + 8], rax
    mov rdi, r13
    mov rsi, [rsp]
    xor edx, edx
    call doc_indent_if_break
    mov [rsp + 16], rax
    DMARK r15
    DPUSH r14
    DPUSH r12
    DPUSH [rsp + 8]
    DPUSHL d_line_suffix_boundary
    DPUSH [rsp + 16]
    DARRAY r15
    GROUP_RAX
    jmp 99f
    # group([leftDoc, operator, " ", group(rightDoc)])
40: mov rdi, r13
    xor esi, esi
    call doc_group
    mov r13, rax
    DMARK r15
    DPUSH rbx
    DPUSH r12
    DPUSHL ps_space
    DPUSH r13
    DARRAY r15
    GROUP_RAX
    jmp 99f
    # [group(leftDoc), operator, line, rightDoc]
50: DMARK r15
    DPUSH r14
    DPUSH r12
    DPUSHL d_line
    DPUSH r13
    DARRAY r15
    jmp 99f
    # [group(leftDoc), operator, indent([line, rightDoc])]
60: lea rdi, [rip + d_line]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
    mov rdi, r14
    mov rsi, r12
    mov rdx, rax
    call doc_array3
    jmp 99f
    # [group(leftDoc), operator, rightDoc]
70: mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call doc_array3
99: EPILOGUE
ENDF pjs_print_assignment

# pjs_print_assignment_expression(node, args) -> rax
FUNC pjs_print_assignment_expression
    PROLOGUE
    mov rbx, rdi
    PRINT N_F0, K_left
    mov r12, rax
    mov rdi, [rbx + N_F2]
    call pjs_code_doc
    lea rdi, [rip + ps_space]
    mov rsi, rax
    call doc_array2
    mov rdi, r12
    mov rsi, rax
    mov edx, N_F1
    mov ecx, K_right
    call pjs_print_assignment
    EPILOGUE
ENDF pjs_print_assignment_expression

# pjs_print_variable_declarator(node, args) -> rax
FUNC pjs_print_variable_declarator
    PROLOGUE
    PRINT N_F0, K_id
    mov rdi, rax
    lea rsi, [rip + sd_space_eq]
    mov edx, N_F1
    mov ecx, K_init
    call pjs_print_assignment
    EPILOGUE
ENDF pjs_print_variable_declarator

# pjs_is_arrow_function_variable_declarator(node) -> eax
FUNC pjs_is_arrow_function_variable_declarator
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_VariableDeclarator
    jne 9f
    mov rcx, [rdi + N_F1]
    test rcx, rcx
    jz 9f
    cmp word ptr [rcx + N_TYPE], T_ArrowFunctionExpression
    sete al
9:  leave
    ret
ENDF pjs_is_arrow_function_variable_declarator

FUNC pas_m_assignment
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_AssignmentExpression
    sete al
    leave
    ret
ENDF pas_m_assignment

FUNC pas_m_assignment_or_declarator
    mov eax, 1
    cmp word ptr [rdi + N_TYPE], T_AssignmentExpression
    je 9f
    cmp word ptr [rdi + N_TYPE], T_VariableDeclarator
    je 9f
    xor eax, eax
9:  leave
    ret
ENDF pas_m_assignment_or_declarator

FUNC pas_m_not_statement
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ExpressionStatement
    je 9f
    cmp word ptr [rdi + N_TYPE], T_VariableDeclaration
    je 9f
    mov eax, 1
9:  leave
    ret
ENDF pas_m_not_statement

# pas_choose_layout(node, left_doc, right_offset, right_key) -> eax AL_* (chooseLayout)
FUNC pas_choose_layout
    PROLOGUE 2
    mov rbx, rdi
    mov r12, rsi
    mov eax, edx
    mov r13, [rbx + rax]            # rightNode
    mov [rsp], rcx                  # right_key
    mov eax, AL_ONLY_LEFT
    test r13, r13
    jz 99f
    # shouldUseChainFormatting
    xor r14d, r14d                  # isTail
    TYPE r13, T_AssignmentExpression
    je 1f
    mov r14d, 1
1:  lea rdi, [rip + match_chain_not_tail]
    test r14d, r14d
    jz 2f
    lea rdi, [rip + match_chain_tail]
2:  mov esi, 3
    call path_match
    test eax, eax
    jz 5f
    mov eax, AL_CHAIN
    test r14d, r14d
    jz 99f
    mov eax, AL_CHAIN_TAIL
    TYPE r13, T_ArrowFunctionExpression
    jne 99f
    mov rcx, [r13 + N_F2]
    TYPE rcx, T_ArrowFunctionExpression
    jne 99f
    mov eax, AL_CHAIN_TAIL_ARROW_CHAIN
    jmp 99f
    # isHeadOfLongChain, or a leading own-line comment on the right
5:  test r14d, r14d
    jnz 6f
    mov rcx, [r13 + N_F1]
    TYPE rcx, T_AssignmentExpression
    je 7f
6:  mov rdi, r13
    call pjs_has_leading_own_line_comment
    test eax, eax
    jz 8f
7:  mov eax, AL_BREAK_AFTER_OPERATOR
    jmp 99f
8:  TYPE rbx, T_ImportAttribute
    je 81f
    TYPE r13, T_CallExpression
    jne 10f
    mov rdi, [r13 + N_F0]
    lea rsi, [rip + s_require]
    call pjs_ident_is
    test eax, eax
    jz 10f
81: mov eax, AL_NEVER_BREAK_AFTER_OPERATOR
    jmp 99f
10: mov rdi, r12
    call can_break
    mov r15d, eax                   # canBreakLeftDoc
    mov rdi, rbx
    call pas_is_complex_destructuring
    test eax, eax
    jnz 11f
    mov rdi, rbx
    call pas_has_complex_type_annotation
    test eax, eax
    jnz 11f
    test r15d, r15d
    jz 12f
    mov rdi, rbx
    call pjs_is_arrow_function_variable_declarator
    test eax, eax
    jz 12f
11: mov eax, AL_BREAK_LHS
    jmp 99f
12: mov rdi, rbx
    mov rsi, r12
    call pas_has_short_key
    mov r14d, eax                   # hasShortKey
    # path.call(() => shouldBreakAfterOperator(...), rightPropertyName)
    mov rdi, r13
    mov rsi, [rsp]
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov edi, r14d
    call pas_should_break_after_operator
    mov [rsp + 8], rax
    call path_pop
    mov eax, AL_BREAK_AFTER_OPERATOR
    cmp qword ptr [rsp + 8], 0
    jne 99f
    mov rdi, rbx
    call pas_is_complex_type_alias_params
    mov ecx, eax
    mov eax, AL_BREAK_LHS
    test ecx, ecx
    jnz 99f
    mov eax, AL_FLUID
    test r15d, r15d
    jnz 99f
    mov eax, AL_NEVER_BREAK_AFTER_OPERATOR
    test r14d, r14d
    jnz 99f
    movzx ecx, word ptr [r13 + N_TYPE]
    cmp ecx, T_TemplateLiteral
    je 99f
    cmp ecx, T_TaggedTemplateExpression
    je 99f
    cmp ecx, T_BooleanLiteral
    je 99f
    cmp ecx, T_NumericLiteral
    je 99f
    cmp ecx, T_ClassExpression
    je 99f
    mov eax, AL_FLUID
99: EPILOGUE
ENDF pas_choose_layout

# pas_should_break_after_operator(has_short_key) -> eax
# (shouldBreakAfterOperator) for the right side at the top of the path
FUNC pas_should_break_after_operator
    PROLOGUE
    mov r14d, edi
    call path_value
    mov rbx, rax
    mov rdi, rbx
    call pjs_is_binaryish
    test eax, eax
    jz 1f
    mov rdi, rbx
    call pjs_should_inline_logical_expression
    test eax, eax
    jz 7f
1:  movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_SequenceExpression
    je 7f
    cmp eax, T_ClassExpression
    jne 12f
    mov rdi, rbx
    call pjs_get_decorators
    test rax, rax
    jz 8f
    jmp 7f
12: cmp eax, T_TSConditionalType
    jne 13f
    cmp qword ptr [rip + g_experimental_ternaries], 0
    jne 7f
    mov rdi, rbx
    call pas_should_break_before_conditional_type
    test eax, eax
    jnz 7f
    jmp 2f
13: cmp eax, T_ConditionalExpression
    jne 2f
    cmp qword ptr [rip + g_experimental_ternaries], 0
    je 11f
    # experimentalTernaries: a consequent or alternate ternary
    mov eax, 1
    mov rcx, [rbx + N_F1]
    cmp word ptr [rcx + N_TYPE], T_ConditionalExpression
    je 9f
    mov rcx, [rbx + N_F2]
    cmp word ptr [rcx + N_TYPE], T_ConditionalExpression
    sete al
    movzx eax, al
    jmp 9f
11: mov r12, [rbx + N_F0]           # test
    mov rdi, r12
    call pjs_is_binaryish
    test eax, eax
    jz 9f
    mov rdi, r12
    call pjs_should_inline_logical_expression
    xor eax, 1
    jmp 9f
2:  test r14d, r14d
    jnz 8f
    # skip unary, await and yield (with an argument) wrappers, and non-null assertions
    xor r12d, r12d                  # entries pushed
3:  movzx eax, word ptr [rbx + N_TYPE]
    mov r13d, K_expression
    cmp eax, T_TSNonNullExpression
    je 4f
    mov r13d, K_argument
    cmp eax, T_UnaryExpression
    je 4f
    cmp eax, T_AwaitExpression
    je 4f
    cmp eax, T_YieldExpression
    jne 5f
    cmp qword ptr [rbx + N_F0], 0
    je 5f
4:  mov rbx, [rbx + N_F0]
    mov rdi, rbx
    mov esi, r13d
    mov edx, -1
    xor ecx, ecx
    call path_push
    inc r12
    jmp 3b
5:  mov r13d, 1
    TYPE rbx, T_StringLiteral
    je 6f
    xor edi, edi
    call pas_is_poorly_breakable_member_or_call_chain
    mov r13d, eax
6:  test r12, r12
    jz 61f
    call path_pop
    dec r12
    jmp 6b
61: mov eax, r13d
    jmp 9f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pas_should_break_after_operator

# pas_is_poorly_breakable_member_or_call_chain(deep) -> eax for the node at
# the top of the path (isPoorlyBreakableMemberOrCallChain)
FUNC pas_is_poorly_breakable_member_or_call_chain
    PROLOGUE
    mov r12d, edi
    call path_value
    mov rbx, rax
    TYPE rbx, T_TSNonNullExpression
    jne 10f
    mov rdi, [rbx + N_F0]
    mov esi, K_expression
    jmp 6f
10: mov rdi, rbx
    call pjs_is_call_expression
    test eax, eax
    jz 5f
    mov rdi, rbx
    xor esi, esi
    call pjs_print_call_expression
    test rax, rax
    jz 1f
    cmp byte ptr [rax], DK_LABEL
    jne 1f
    test qword ptr [rax + DL_LABEL], LB_MEMBER_CHAIN
    jnz 8f
1:  mov rdi, rbx
    call pjs_get_call_arguments
    mov rcx, [rax]
    test rcx, rcx
    jz 2f
    cmp rcx, 1
    jne 8f
    mov rdi, [rax + 8]
    call pjs_is_lone_short_argument
    test eax, eax
    jz 8f
2:  call pas_is_call_expression_with_complex_type_arguments
    test eax, eax
    jnz 8f
    mov rdi, [rbx + N_F0]
    mov esi, K_callee
    jmp 6f
5:  mov rdi, rbx
    call pjs_is_member_expression
    test eax, eax
    jz 7f
    mov rdi, [rbx + N_F0]
    mov esi, K_object
6:  mov edx, -1
    xor ecx, ecx
    call path_push
    mov edi, 1
    call pas_is_poorly_breakable_member_or_call_chain
    mov rbx, rax
    call path_pop
    mov eax, ebx
    jmp 9f
7:  xor eax, eax
    test r12d, r12d
    jz 9f
    TYPE rbx, T_Identifier
    je 71f
    TYPE rbx, T_ThisExpression
    jne 9f
71: mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pas_is_poorly_breakable_member_or_call_chain

# pas_is_complex_destructuring(node) -> eax (isComplexDestructuring)
FUNC pas_is_complex_destructuring
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_AssignmentExpression
    je 1f
    cmp word ptr [rdi + N_TYPE], T_VariableDeclarator
    jne 9f
1:  mov rcx, [rdi + N_F0]           # left, id
    cmp word ptr [rcx + N_TYPE], T_ObjectPattern
    jne 9f
    mov rcx, [rcx + N_F0]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 2
    jbe 9f
    xor edx, edx
2:  cmp rdx, [rcx]
    jae 9f
    mov r8, [rcx + 8 + rdx*8]
    inc rdx
    cmp word ptr [r8 + N_TYPE], T_ObjectProperty
    jne 2b
    test dword ptr [r8 + N_ATTR], NA_SHORTHAND
    jz 3f
    mov r8, [r8 + N_F1]
    test r8, r8
    jz 2b
    cmp word ptr [r8 + N_TYPE], T_AssignmentPattern
    jne 2b
3:  mov eax, 1
9:  leave
    ret
ENDF pas_is_complex_destructuring

# pas_has_short_key(node, key_doc) -> eax (isObjectPropertyWithShortKey)
FUNC pas_has_short_key
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectProperty
    jne 9f
    mov rdi, rsi
    call clean_doc
    test rax, rax
    jz 1f
    cmp byte ptr [rax], DK_STR
    jne 8f
    mov rcx, [rax + DS_WIDTH]
    jmp 2f
1:  xor ecx, ecx
2:  mov rdx, [rip + g_tab_width]
    add rdx, 3
    xor eax, eax
    cmp rcx, rdx
    setl al
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF pas_has_short_key

# pas_is_complex_type_alias_params(node) -> eax (isComplexTypeAliasParams):
# a TSTypeAliasDeclaration with more than one type parameter, one of them with
# a constraint or default
FUNC pas_is_complex_type_alias_params
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TSTypeAliasDeclaration
    jne 9f
    mov rcx, [rdi + N_F4]
    test rcx, rcx
    jz 9f
    mov rcx, [rcx + N_F0]
    VLEN rdx, rcx
    cmp rdx, 1
    jbe 9f
1:  mov r8, [rcx + rdx*8]
    cmp qword ptr [r8 + N_F1], 0    # constraint
    jne 8f
    cmp qword ptr [r8 + N_F2], 0    # default
    jne 8f
    dec rdx
    jnz 1b
    jmp 9f
8:  mov eax, 1
9:  leave
    ret
ENDF pas_is_complex_type_alias_params

# pas_type_reference_params(node) -> rax: (node.typeParameters)?.params of a
# TSTypeReference (getTypeParametersFromTypeReference), 0 otherwise
FUNC pas_type_reference_params
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp word ptr [rdi + N_TYPE], T_TSTypeReference
    jne 9f
    mov rax, [rdi + N_F4]
    test rax, rax
    jz 9f
    mov rax, [rax + N_F0]
9:  leave
    ret
ENDF pas_type_reference_params

# pas_has_complex_type_annotation(node) -> eax (hasComplexTypeAnnotation)
FUNC pas_has_complex_type_annotation
    push rbx
    push r12
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_VariableDeclarator
    jne 9f
    mov rcx, [rdi + N_F0]
    mov rcx, [rcx + N_F5]           # id.typeAnnotation
    test rcx, rcx
    jz 9f
    mov rdi, [rcx + N_F5]
    call pas_type_reference_params
    mov rbx, rax
    VLEN r12, rbx
    xor eax, eax
    cmp r12, 1
    jbe 9f
1:  mov rdi, [rbx + r12*8]
    TYPE rdi, T_TSConditionalType
    je 8f
    call pas_type_reference_params
    VLEN rcx, rax
    test rcx, rcx
    jnz 8f
    dec r12
    jnz 1b
    xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  pop r12
    pop rbx
    leave
    ret
ENDF pas_has_complex_type_annotation

# pas_should_break_before_conditional_type(node) -> eax
# (shouldBreakBeforeConditionalType): checkType or extendsType is generic
FUNC pas_should_break_before_conditional_type
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx + N_F0]
    call pas_is_generic
    test eax, eax
    jnz 9f
    mov rdi, [rbx + N_F1]
    call pas_is_generic
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pas_should_break_before_conditional_type

# pas_is_generic(node) -> eax: a TSFunctionType or TSTypeReference with type parameters
FUNC pas_is_generic
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TSFunctionType
    je 1f
    cmp word ptr [rdi + N_TYPE], T_TSTypeReference
    jne 9f
1:  cmp qword ptr [rdi + N_F4], 0
    setne al
9:  leave
    ret
ENDF pas_is_generic

# pas_is_call_expression_with_complex_type_arguments() -> eax
# (isCallExpressionWithComplexTypeArguments) for the call at the path's top
FUNC pas_is_call_expression_with_complex_type_arguments
    push rbx
    sub rsp, 8
    call path_value
    xor ecx, ecx
    mov rax, [rax + N_F4]
    test rax, rax
    jz 8f
    mov rbx, [rax + N_F0]
    VLEN rcx, rbx
    test rcx, rcx
    jz 8f
    cmp rcx, 1
    ja 7f
    mov rdi, [rbx + 8]
    movzx eax, word ptr [rdi + N_TYPE]
    cmp eax, T_TSUnionType
    je 7f
    cmp eax, T_TSIntersectionType
    je 7f
    cmp eax, T_TSTypeLiteral
    je 7f
    PRINT N_F4, K_typeParameters
    mov rdi, rax
    call will_break
    test eax, eax
    jnz 7f
8:  xor eax, eax
    jmp 9f
7:  mov eax, 1
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pas_is_call_expression_with_complex_type_arguments
