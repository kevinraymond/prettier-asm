# print/ternary-old.js for ConditionalExpression and TSConditionalType (JSX
# mode cannot happen: JSX is refused by the parser)
.include "pjs.inc"

SDOC sd_q, "? "
SDOC sd_c, ": "
SDOC sd_lp, "("
SDOC sd_rp, ")"

# locals of pjs_print_ternary_old
.equ TO_PREV, 0                 # previousParent, then the ss mark
.equ TO_FIRST, 8                # firstNonConditionalParent
.equ TO_MARK, 16                # ss mark, then the printed test
.equ TO_PART, 24                # part, then parts
.equ TO_EXTRA, 32               # shouldExtraIndent
.equ TO_BREAK_PAREN, 40         # breakClosingParen
.equ TO_CONS, 48                # consequent slot offset (consequent, trueType)
.equ TO_ALT, 56                 # alternate slot offset (alternate, falseType)
.equ TO_CONS_KEY, 64
.equ TO_ALT_KEY, 72

# pjs_print_ternary_old(node, args) -> rax (printTernaryOld) for
# ConditionalExpression and TSConditionalType
FUNC pjs_print_ternary_old
    PROLOGUE 10
    mov rbx, rdi
    mov qword ptr [rsp + TO_CONS], N_F1
    mov qword ptr [rsp + TO_ALT], N_F2
    mov qword ptr [rsp + TO_CONS_KEY], K_consequent
    mov qword ptr [rsp + TO_ALT_KEY], K_alternate
    TYPE rbx, T_ConditionalExpression
    je 101f
    mov qword ptr [rsp + TO_CONS], N_F2
    mov qword ptr [rsp + TO_ALT], N_F3
    mov qword ptr [rsp + TO_CONS_KEY], K_trueType
    mov qword ptr [rsp + TO_ALT_KEY], K_falseType
101: call path_parent
    mov r12, rax                    # parent
    # isParentTest, forceNoIndent
    xor r13d, r13d
    xor r14d, r14d
    mov ax, [r12 + N_TYPE]
    cmp ax, [rbx + N_TYPE]
    jne 1f
    mov rdi, r12
    mov rsi, rbx
    call pto_is_test_of
    mov r13d, eax                   # isParentTest
    mov r14d, r13d
    xor r14d, 1                     # forceNoIndent
    # firstNonConditionalParent
1:  xor r15d, r15d                  # i
    xor ecx, ecx                    # currentParent
2:  mov rax, rbx
    test rcx, rcx
    jz 3f
    mov rax, rcx
3:  mov [rsp + TO_PREV], rax        # previousParent
    mov rdi, r15
    inc r15
    call path_parent_node
    mov rcx, rax
    test rcx, rcx
    jz 4f
    mov ax, [rcx + N_TYPE]
    cmp ax, [rbx + N_TYPE]
    jne 4f
    push rcx
    push rcx
    mov rdi, rcx
    mov rsi, [rsp + 16 + TO_PREV]
    call pto_is_test_of
    pop rcx
    pop rcx
    test eax, eax
    jz 2b
4:  test rcx, rcx
    jnz 5f
    mov rcx, r12
5:  mov [rsp + TO_FIRST], rcx       # firstNonConditionalParent
    # part = [line, "? ", ifBreak("", "(")?, branch(consequent), ifBreak("", ")")?,
    #   line, ": ", branch(alternate)]
    call ss_mark
    mov [rsp + TO_MARK], rax
    DPUSHL d_line
    DPUSHL sd_q
    mov rax, [rsp + TO_CONS]
    mov rax, [rbx + rax]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    jne 6f
    xor edi, edi
    lea rsi, [rip + sd_lp]
    xor edx, edx
    call doc_if_break
    DPUSH rax
6:  mov rdi, [rsp + TO_CONS]
    mov rsi, [rsp + TO_CONS_KEY]
    xor edx, edx
    call print_field
    mov rdi, rax
    call pto_branch
    DPUSH rax
    mov rax, [rsp + TO_CONS]
    mov rax, [rbx + rax]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    jne 7f
    xor edi, edi
    lea rsi, [rip + sd_rp]
    xor edx, edx
    call doc_if_break
    DPUSH rax
7:  DPUSHL d_line
    DPUSHL sd_c
    mov rdi, [rsp + TO_ALT]
    mov rsi, [rsp + TO_ALT_KEY]
    xor edx, edx
    call print_field
    mov rdi, rax
    call pto_branch
    DPUSH rax
    mov rdi, [rsp + TO_MARK]
    call ss_to_array
    mov [rsp + TO_PART], rax        # part
    # parts = [part], or aligned when this is the consequent of a parent
    mov cx, [r12 + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    jne 9f
    mov rcx, [rsp + TO_ALT]
    cmp [r12 + rcx], rbx
    je 9f
    test r13d, r13d
    jnz 9f
    cmp qword ptr [rip + g_use_tabs], 0
    je 8f
    mov rdi, rax
    call doc_indent
    mov rdi, rax
    call doc_dedent
    jmp 81f
8:  mov rdi, [rip + g_tab_width]
    sub rdi, 2
    jns 82f
    xor edi, edi
82: mov rsi, rax
    call doc_align_n
81: mov [rsp + TO_PART], rax
9:  # shouldBreak: a multiline block comment on consequent, alternate or a test
    xor r15d, r15d
    mov rax, [rsp + TO_CONS]
    mov rdi, [rbx + rax]
    xor esi, esi
    lea rdx, [rip + pto_multiline_block_comment]
    call has_comment
    or r15d, eax
    mov rax, [rsp + TO_ALT]
    mov rdi, [rbx + rax]
    xor esi, esi
    lea rdx, [rip + pto_multiline_block_comment]
    call has_comment
    or r15d, eax
    mov rdi, [rbx + N_F0]
    xor esi, esi
    lea rdx, [rip + pto_multiline_block_comment]
    call has_comment
    or r15d, eax
    TYPE rbx, T_TSConditionalType
    jne 91f
    mov rdi, [rbx + N_F1]
    xor esi, esi
    lea rdx, [rip + pto_multiline_block_comment]
    call has_comment
    or r15d, eax
    # breakClosingParen and shouldExtraIndent
91: call pto_should_extra_indent
    mov [rsp + TO_EXTRA], rax
    xor eax, eax
    mov rdi, r12
    call pjs_is_member_expression
    test eax, eax
    jz 10f
    ATTR r12, NA_COMPUTED
    setz al
    movzx eax, al
10: mov [rsp + TO_BREAK_PAREN], rax # breakClosingParen
    # [printTernaryTest, forceNoIndent ? parts : indent(parts), softline?]
    call pto_print_ternary_test
    mov [rsp + TO_MARK], rax        # printed test
    mov rdi, [rsp + TO_PART]
    xor esi, esi
    call doc_array2                 # parts
    test r14d, r14d
    jnz 12f
    INDENT_RAX
12: mov [rsp + TO_PART], rax
    call ss_mark
    mov [rsp + TO_PREV], rax
    DPUSH [rsp + TO_MARK]
    DPUSH [rsp + TO_PART]
    TYPE rbx, T_ConditionalExpression
    jne 13f
    cmp qword ptr [rsp + TO_BREAK_PAREN], 0
    je 13f
    cmp qword ptr [rsp + TO_EXTRA], 0
    jne 13f
    DPUSHL d_softline
13: mov rdi, [rsp + TO_PREV]
    call ss_to_array
    # maybeGroup
    cmp r12, [rsp + TO_FIRST]
    jne 14f
    mov rdi, rax
    mov esi, r15d
    call doc_group
    jmp 15f
14: test r15d, r15d
    jz 15f
    mov rdi, rax
    lea rsi, [rip + d_break_parent]
    call doc_array2
15: test r13d, r13d
    jnz 16f
    cmp qword ptr [rsp + TO_EXTRA], 0
    je 99f
    # group([indent([softline, result]), softline])
16: lea rdi, [rip + d_softline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    GROUP_RAX
99: EPILOGUE
ENDF pjs_print_ternary_old

# pto_is_test_of(parent, node) -> eax: node is the parent's test (checkType or
# extendsType for TSConditionalType)
FUNC pto_is_test_of
    mov eax, 1
    cmp [rdi + N_F0], rsi
    je 9f
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TSConditionalType
    jne 9f
    cmp [rdi + N_F1], rsi
    sete al
9:  leave
    ret
ENDF pto_is_test_of

SDOC sd_extends, "extends"

# pto_print_ternary_test() -> rax (printTernaryTest) for the node at the path's top
FUNC pto_print_ternary_test
    PROLOGUE
    call path_value
    mov rbx, rax
    call path_parent
    mov r12, rax
    TYPE rbx, T_ConditionalExpression
    jne 1f
    PRINT N_F0, K_test
    mov r13, rax
    mov r14d, N_F2                  # alternate
    jmp 2f
    # [print("checkType"), " ", "extends", " ", print("extendsType")]
1:  DMARK r14
    PRINT N_F0, K_checkType
    DPUSH rax
    DPUSHL ps_space
    DPUSHL sd_extends
    DPUSHL ps_space
    PRINT N_F1, K_extendsType
    DPUSH rax
    DARRAY r14
    mov r13, rax
    mov r14d, N_F3                  # falseType
2:  mov ax, [r12 + N_TYPE]
    cmp ax, [rbx + N_TYPE]
    jne 8f
    cmp [r12 + r14], rbx
    jne 8f
    mov rsi, r13
    mov edi, 2
    call doc_align_n
    jmp 9f
8:  mov rax, r13
9:  EPILOGUE
ENDF pto_print_ternary_test

# pto_branch(doc) -> rax: useTabs ? indent(doc) : align(2, doc)
FUNC pto_branch
    cmp qword ptr [rip + g_use_tabs], 0
    je 1f
    call doc_indent
    leave
    ret
1:  mov rsi, rdi
    mov edi, 2
    call doc_align_n
    leave
    ret
ENDF pto_branch

# pto_multiline_block_comment(comment) -> eax: isBlockComment(comment) &&
# hasNewlineInRange(text, locStart(comment), locEnd(comment))
FUNC pto_multiline_block_comment
    xor eax, eax
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    jne 9f
    mov esi, [rdi + CM_END]
    mov edi, [rdi + CM_START]
    call has_newline_in_range
9:  leave
    ret
ENDF pto_multiline_block_comment

# pto_should_extra_indent() -> eax (shouldExtraIndentForConditionalExpression)
FUNC pto_should_extra_indent
    PROLOGUE
    call path_value
    mov rbx, rax                    # node
    mov r12, rax                    # child
    TYPE rbx, T_ConditionalExpression
    jne 8f
    xor r13d, r13d                  # ancestorCount
1:  mov rdi, r13
    call path_parent_node
    mov r14, rax
    test r14, r14
    jz 8f
    mov rdi, r14
    call pjs_is_call_expression
    test eax, eax
    jnz 2f
    mov rdi, r14
    call pjs_is_member_expression
    test eax, eax
    jnz 2f
    TYPE r14, T_TSNonNullExpression
    jne 3f
2:  cmp [r14 + N_F0], r12          # callee, object, expression
    jne 3f
    mov r12, r14
    inc r13
    jmp 1b
3:  TYPE r14, T_NewExpression
    je 31f
    mov rdi, r14
    call pjs_is_binary_cast_expression
    test eax, eax
    jz 4f
31: cmp [r14 + N_F0], r12          # callee, expression
    jne 4f
    lea rdi, [r13 + 1]
    call path_parent_node
    mov r12, r14
    mov r14, rax                    # parent
    test r14, r14
    jz 8f
4:  cmp r12, rbx
    je 8f
    movzx eax, word ptr [r14 + N_TYPE]
    mov rcx, [r14 + N_F1]
    cmp eax, T_AssignmentExpression
    je 5f
    cmp eax, T_VariableDeclarator
    je 5f
    mov rcx, [r14 + N_F0]
    cmp eax, T_ReturnStatement
    je 5f
    cmp eax, T_ThrowStatement
    je 5f
    cmp eax, T_UnaryExpression
    je 5f
    cmp eax, T_YieldExpression
    je 5f
    cmp eax, T_AwaitExpression
    jne 8f
5:  xor eax, eax
    cmp rcx, r12
    sete al
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pto_should_extra_indent
