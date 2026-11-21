# print/binaryish.js (the pipeline, Angular, Vue and JSX cases do not apply)
.include "pjs.inc"

# pjs_should_inline_logical_expression(node) -> eax (shouldInlineLogicalExpression)
FUNC pjs_should_inline_logical_expression
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_LogicalExpression
    jne 9f
    mov rcx, [rdi + N_F1]           # right
    cmp word ptr [rcx + N_TYPE], T_ObjectExpression
    je 1f
    cmp word ptr [rcx + N_TYPE], T_ArrayExpression
    jne 9f
1:  mov rcx, [rcx + N_F0]           # properties, elements
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 0
    setne al
9:  leave
    ret
ENDF pjs_should_inline_logical_expression

# pjs_print_binaryish_expression(node, args) -> rax (printBinaryishExpression)
FUNC pjs_print_binaryish_expression
    PROLOGUE 4
    mov rbx, rdi
    call path_parent
    mov r12, rax                    # parent
    call path_grandparent
    mov [rsp + 16], rax             # grandparent
    call path_key
    mov r13d, eax
    # isInsideParenthesis
    xor r14d, r14d
    cmp r13d, K_body
    je 1f
    movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_IfStatement
    je 19f
    cmp eax, T_WhileStatement
    je 19f
    cmp eax, T_SwitchStatement
    je 19f
    cmp eax, T_DoWhileStatement
    jne 1f
19: mov r14d, 1
1:  call ss_mark
    mov r15, rax
    xor edi, edi
    mov esi, r14d
    call pbi_print_expressions
    mov rdi, r15
    call ss_to_array_keep
    mov r15, rax                    # parts
    test r14d, r14d
    jnz 98f
    # a callee, a unary argument or a non-computed member object:
    # group([indent([softline, ...parts]), softline])
    mov rdi, r12
    call pjs_is_call_expression
    test eax, eax
    jz 2f
    cmp [r12 + N_F0], rbx
    je 3f
2:  TYPE r12, T_UnaryExpression
    je 3f
    mov rdi, r12
    call pjs_is_member_expression
    test eax, eax
    jz 4f
    ATTR r12, NA_COMPUTED
    jnz 4f
3:  call ss_mark
    mov r13, rax
    DPUSHL d_softline
    mov rdi, r15
    call pbi_push_items
    DARRAY r13
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    GROUP_RAX
    jmp 99f
    # shouldNotIndent
4:  movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_ReturnStatement
    je 90f
    cmp eax, T_ThrowStatement
    je 90f
    cmp eax, T_TemplateLiteral
    je 90f
    cmp eax, T_ArrowFunctionExpression
    jne 41f
    cmp [r12 + N_F2], rbx
    je 90f
41: cmp eax, T_ForStatement
    jne 42f
    cmp [r12 + N_F3], rbx
    jne 90f
42: cmp eax, T_ConditionalExpression
    jne 5f
    mov rdi, [rsp + 16]
    TYPE rdi, T_ReturnStatement
    je 5f
    TYPE rdi, T_ThrowStatement
    je 5f
    call pjs_is_call_expression
    test eax, eax
    jz 90f
    # shouldInlineLogicalExpression and samePrecedenceSubExpression
5:  mov rdi, rbx
    call pjs_should_inline_logical_expression
    mov r14d, eax
    xor r13d, r13d
    mov rdi, [rbx + N_F0]
    call pjs_is_binaryish
    test eax, eax
    jz 51f
    mov rdi, [rbx + N_F2]
    mov rax, [rbx + N_F0]
    mov rsi, [rax + N_F2]
    call pjs_should_flatten
    mov r13d, eax
51: test r14d, r14d
    jz 52f
    test r13d, r13d
    jz 90f
    jmp 6f
    # !shouldInline && shouldIndentIfInlining
52: movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_AssignmentExpression
    je 90f
    cmp eax, T_VariableDeclarator
    je 90f
    cmp eax, T_ClassProperty
    je 90f
    cmp eax, T_ClassPrivateProperty
    je 90f
    cmp eax, T_ObjectProperty
    je 90f
6:  mov ecx, [r15 + DA_COUNT]
    xor eax, eax
    test ecx, ecx
    jz 99f
    # headParts: up to the first group, or the first part
    xor edx, edx
7:  cmp edx, ecx
    jae 71f
    mov rax, [r15 + DA_ITEMS + rdx*8]
    test rax, rax
    jz 72f
    cmp byte ptr [rax], DK_GROUP
    je 73f
72: inc edx
    jmp 7b
71: xor edx, edx                    # no group: one part
73: inc edx
    mov r14d, edx                   # headParts length
    call ss_mark
    mov r13, rax
    xor ebx, ebx
8:  cmp ebx, r14d
    jae 81f
    mov rdi, [r15 + DA_ITEMS + rbx*8]
    call ss_push
    inc ebx
    jmp 8b
81: call ss_mark
    mov r12, rax
82: cmp ebx, [r15 + DA_COUNT]
    jae 83f
    mov rdi, [r15 + DA_ITEMS + rbx*8]
    call ss_push
    inc ebx
    jmp 82b
83: mov rdi, r12
    call ss_to_array_keep
    INDENT_RAX
    DPUSH rax
    mov rdi, r13
    call ss_to_array_keep
    mov rbx, rax
    call doc_group_id_new
    mov rdi, rbx
    xor esi, esi
    mov rdx, rax
    call doc_group_ex
    jmp 99f
90: mov rax, r15
    GROUP_RAX
    jmp 99f
98: mov rax, r15
99: EPILOGUE
ENDF pjs_print_binaryish_expression

# pbi_push_items(array): push the array doc's items on the scratch stack
FUNC pbi_push_items
    push rbx
    push r12
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12d, [rbx + DA_COUNT]
    jae 9f
    mov rdi, [rbx + DA_ITEMS + r12*8]
    call ss_push
    inc r12d
    jmp 1b
9:  pop r12
    pop rbx
    leave
    ret
ENDF pbi_push_items

# pbi_print_expressions(is_nested, is_inside_parenthesis)
# (printBinaryishExpressions) for the node at the top of the path: pushes the
# parts on the scratch stack
FUNC pbi_print_expressions
    PROLOGUE 6
    mov [rsp], rdi                  # isNested
    mov [rsp + 8], rsi              # isInsideParenthesis
    call path_value
    mov rbx, rax
    mov rdi, rbx
    call pjs_is_binaryish
    test eax, eax
    jnz 1f
    xor edi, edi
    call main_print_here
    GROUP_RAX
    DPUSH rax
    jmp 99f
1:  call ss_mark
    mov [rsp + 16], rax             # where this node's parts start
    # flatten operators of the same precedence on the left
    mov rdi, [rbx + N_F0]
    call pjs_is_binaryish
    test eax, eax
    jz 2f
    mov rdi, [rbx + N_F2]
    mov rax, [rbx + N_F0]
    mov rsi, [rax + N_F2]
    call pjs_should_flatten
    test eax, eax
    jz 2f
    mov rdi, [rbx + N_F0]
    mov esi, K_left
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov edi, 1
    mov rsi, [rsp + 8]
    call pbi_print_expressions
    call path_pop
    jmp 3f
2:  PRINT N_F0, K_left
    GROUP_RAX
    DPUSH rax
3:  mov rdi, rbx
    call pjs_should_inline_logical_expression
    mov r12d, eax                   # shouldInline
    # commentBeforeOperator
    mov rdi, [rbx + N_F1]
    mov esi, CC_Leading
    lea rdx, [rip + is_type_cast_comment]
    call has_comment
    xor r13d, r13d
    test eax, eax
    jnz 4f
    mov rdi, [rbx + N_F1]
    call pjs_has_leading_own_line_comment
    mov r13d, eax
4:  mov [rsp + 32], r13             # commentBeforeOperator
    mov rdi, [rbx + N_F2]
    call pjs_code_doc
    mov r14, rax                    # operator
    test r12d, r12d
    jz 10f
    # [operator, hasLeadingOwnLineComment(right) ? indent([line, print("right"), ""])
    #   : [" ", print("right"), ""]]
    PRINT N_F1, K_right
    mov r15, rax
    mov rdi, [rbx + N_F1]
    call pjs_has_leading_own_line_comment
    test eax, eax
    jz 5f
    lea rdi, [rip + d_line]
    mov rsi, r15
    call doc_array2
    INDENT_RAX
    jmp 6f
5:  lea rdi, [rip + ps_space]
    mov rsi, r15
    call doc_array2
6:  mov rdi, r14
    mov rsi, rax
    call doc_array2
    mov r15, rax                    # right
    jmp 20f
10: PRINT N_F1, K_right
    mov r15, rax                    # rightContent
    cmp qword ptr [rip + g_operator_position], OP_START
    jne 11f
    # [line, comment, operator, " ", rightContent, ""]; the comment is taken
    # out of rightContent (splice), which Prettier does in place
    mov qword ptr [rsp + 40], 0
    test r13d, r13d
    jz 13f
    test r15, r15
    jz 13f
    mov rax, r15
    cmp byte ptr [rax], DK_ARRAY
    je 12f
    cmp byte ptr [rax], DK_LABEL
    jne 13f
    mov rax, [rax + D_CONTENTS]
    test rax, rax
    jz 90f
    cmp byte ptr [rax], DK_ARRAY
    jne 90f
12: mov ecx, [rax + DA_COUNT]
    test ecx, ecx
    jz 13f
    mov rdx, [rax + DA_ITEMS]
    mov [rsp + 40], rdx
    dec ecx
    mov [rax + DA_COUNT], ecx
    xor edx, edx
14: cmp edx, ecx
    jae 13f
    mov r8, [rax + DA_ITEMS + 8 + rdx*8]
    mov [rax + DA_ITEMS + rdx*8], r8
    inc edx
    jmp 14b
13: call ss_mark
    mov [rsp + 24], rax
    DPUSHL d_line
    DPUSH [rsp + 40]
    DPUSH r14
    DPUSHL ps_space
    DPUSH r15
    mov rdi, [rsp + 24]
    call ss_to_array
    mov r15, rax
    jmp 20f
    # ["", operator, line, rightContent, ""]
11: mov rdi, r14
    lea rsi, [rip + d_line]
    mov rdx, r15
    call doc_array3
    mov r15, rax
    # shouldGroup
20: mov rdi, [rbx + N_F0]
    mov esi, CC_Trailing | CC_Line
    xor edx, edx
    call has_comment
    mov r13d, eax                   # shouldBreak
    test eax, eax
    jnz 21f
    cmp qword ptr [rsp + 8], 0
    je 22f
    TYPE rbx, T_LogicalExpression
    je 23f
22: call path_parent
    mov cx, [rbx + N_TYPE]
    cmp cx, [rax + N_TYPE]
    je 23f
    mov rax, [rbx + N_F0]
    cmp cx, [rax + N_TYPE]
    je 23f
    mov rax, [rbx + N_F1]
    cmp cx, [rax + N_TYPE]
    je 23f
21: mov rdi, r15
    mov esi, r13d
    call doc_group
    mov r15, rax
23: cmp qword ptr [rip + g_operator_position], OP_START
    jne 24f
    xor edi, edi
    mov eax, r12d
    or rax, [rsp + 32]
    jz 25f
    lea rdi, [rip + ps_space]
25: call ss_push
    jmp 26f
24: DPUSHL ps_space
26: DPUSH r15
    # nested binaries print their own comments
    cmp qword ptr [rsp], 0
    je 99f
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jz 99f
    mov rdi, [rsp + 16]
    call ss_to_array_keep
    mov rsi, rax
    mov rdi, rbx
    call print_comments
    mov rdi, rax
    call clean_doc
    test rax, rax
    jz 30f
    cmp byte ptr [rax], DK_FILL
    jne 27f
    mov rax, [rax + FILL_PARTS]
    jmp 28f
27: cmp byte ptr [rax], DK_ARRAY
    jne 30f
28: mov rdi, rax
    call pbi_push_items
    jmp 99f
30: DPUSH rax
99: EPILOGUE
90: REFUSE "printer: comment before the operator in a label without an array"
ENDF pbi_print_expressions
