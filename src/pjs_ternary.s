# print/ternary.js: printTernary. Without experimentalTernaries it is
# printTernaryOld. ConditionalExpression and TSConditionalType (JSX mode
# cannot reach it).
.include "pjs.inc"

SDOC sd_q_sp, " ?"
SDOC sd_tab, "\t"

# flag bits (r15d)
.equ F_PT, 1            # isParentTernary
.equ F_IA, 2            # isInAlternate
.equ F_CT, 4            # isConsequentTernary
.equ F_AT, 8            # isAlternateTernary
.equ F_CHAIN, 16        # isInChain
.equ F_BIG, 32          # isBigTabs
.equ F_SAME_ASSIGN, 64  # isOnSameLineAsAssignment
.equ F_SAME_RETURN, 128 # isOnSameLineAsReturn
.equ F_EXTRA, 256       # shouldExtraIndent
.equ F_BCP, 512         # breakClosingParen
.equ F_BREAK, 1024      # shouldBreak
.equ F_TRY, 2048        # tryToParenthesizeAlternate
.equ F_GROUP, 4096      # shouldGroupTestAndConsequent
.equ F_TS, 8192         # isTSConditional
.equ F_IN_TEST, 16384   # isInTest
.equ F_BTCP, 32768      # breakTSClosingParen

# locals
.equ L_PARENT, 0
.equ L_FIRST, 8         # firstNonConditionalParent
.equ L_FILL, 16         # fillTab
.equ L_CCOM, 24         # consequentComments
.equ L_ACOM, 32         # alternateComments array, 0 when empty
.equ L_TEST_ID, 40
.equ L_CONS_ID, 48
.equ L_TC_ID, 56        # testAndConsequentId
.equ L_TESTQ, 64        # printedTestWithQuestionMark
.equ L_CONS, 72         # consequent
.equ L_TC, 80           # printedTestAndConsequent
.equ L_ALT, 88          # printedAlternateWithParens
.equ L_PARTS, 96
.equ L_MARK, 104
.equ L_CONS_OFF, 112    # consequent slot (consequent, trueType)
.equ L_ALT_OFF, 120     # alternate slot (alternate, falseType)
.equ L_CONS_KEY, 128
.equ L_ALT_KEY, 136

# pjs_print_ternary(node, args) -> rax (printTernary)
FUNC pjs_print_ternary
    cmp qword ptr [rip + g_experimental_ternaries], 0
    jne 1f
    call pjs_print_ternary_old
    leave
    ret
1:  call pte_print_experimental
    leave
    ret
ENDF pjs_print_ternary

FUNC pte_print_experimental
    PROLOGUE 18
    mov rbx, rdi
    mov r12, rsi
    xor r15d, r15d
    mov qword ptr [rsp + L_CONS_OFF], N_F1
    mov qword ptr [rsp + L_ALT_OFF], N_F2
    mov qword ptr [rsp + L_CONS_KEY], K_consequent
    mov qword ptr [rsp + L_ALT_KEY], K_alternate
    TYPE rbx, T_TSConditionalType
    jne 1001f
    or r15d, F_TS
    mov qword ptr [rsp + L_CONS_OFF], N_F2
    mov qword ptr [rsp + L_ALT_OFF], N_F3
    mov qword ptr [rsp + L_CONS_KEY], K_trueType
    mov qword ptr [rsp + L_ALT_KEY], K_falseType
1001: call path_parent
    mov [rsp + L_PARENT], rax
    mov r13, rax
    mov ax, [r13 + N_TYPE]
    cmp ax, [rbx + N_TYPE]
    jne 1f
    or r15d, F_PT
    mov rdi, r13
    mov rsi, rbx
    call pto_is_test_of
    test eax, eax
    jz 1002f
    or r15d, F_IN_TEST
1002: mov rax, [rsp + L_ALT_OFF]
    cmp [r13 + rax], rbx
    jne 1f
    or r15d, F_IA
1:  mov rax, [rsp + L_CONS_OFF]
    mov rax, [rbx + rax]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    jne 2f
    or r15d, F_CT
2:  mov rax, [rsp + L_ALT_OFF]
    mov rax, [rbx + rax]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    jne 3f
    or r15d, F_AT
3:  test r15d, F_AT | F_IA
    jz 4f
    or r15d, F_CHAIN
4:  cmp qword ptr [rip + g_use_tabs], 0
    jne 5f
    cmp qword ptr [rip + g_tab_width], 2
    jle 6f
5:  or r15d, F_BIG
    # firstNonConditionalParent
6:  xor r14d, r14d                  # i
    xor ecx, ecx                    # currentParent
7:  mov rax, rbx
    test rcx, rcx
    jz 8f
    mov rax, rcx
8:  mov [rsp + L_MARK], rax         # previousParent
    mov rdi, r14
    inc r14
    call path_parent_node
    mov rcx, rax
    test rcx, rcx
    jz 9f
    mov ax, [rcx + N_TYPE]
    cmp ax, [rbx + N_TYPE]
    jne 9f
    push rcx
    push rcx
    mov rdi, rcx
    mov rsi, [rsp + 16 + L_MARK]
    call pto_is_test_of
    pop rcx
    pop rcx
    test eax, eax
    jz 7b
9:  test rcx, rcx
    jnz 10f
    mov rcx, r13
10: mov [rsp + L_FIRST], rcx
    # isOnSameLineAsAssignment
    test r12, r12
    jz 12f
    movzx eax, byte ptr [r12 + ARGS_ASSIGNMENT_LAYOUT]
    test eax, eax
    jz 12f
    cmp eax, AL_BREAK_AFTER_OPERATOR
    je 12f
    movzx eax, word ptr [r13 + N_TYPE]
    cmp eax, T_AssignmentExpression
    je 11f
    cmp eax, T_VariableDeclarator
    je 11f
    cmp eax, T_ClassProperty
    je 11f
    cmp eax, T_ClassPrivateProperty
    je 11f
    cmp eax, T_ObjectProperty
    jne 12f
11: or r15d, F_SAME_ASSIGN
    # isOnSameLineAsReturn
12: TYPE r13, T_ReturnStatement
    je 13f
    TYPE r13, T_ThrowStatement
    jne 14f
13: test r15d, F_CT | F_AT
    jnz 14f
    or r15d, F_SAME_RETURN
14: call pte_should_extra_indent
    test eax, eax
    jz 141f
    or r15d, F_EXTRA
141: test r15d, F_TS
    jz 15f
    call pjs_needs_parens
    test eax, eax
    jz 15f
    or r15d, F_BTCP
    # breakClosingParen: a non-computed member parent
15: mov rdi, r13
    call pjs_is_member_expression
    test eax, eax
    jz 16f
    ATTR r13, NA_COMPUTED
    jnz 16f
    or r15d, F_BCP
    # fillTab
16: mov qword ptr [rsp + L_FILL], 0
    test r15d, F_BIG
    jz 18f
    lea rax, [rip + sd_tab]
    cmp qword ptr [rip + g_use_tabs], 0
    jne 17f
    mov r14, [rip + g_tab_width]
    dec r14
    mov rdi, r14
    call alloc
    mov rdi, rax
    mov rcx, r14
    mov al, ' '
    push rdi
    sub rsp, 8
    rep stosb
    add rsp, 8
    pop rdi
    mov rsi, r14
    call doc_str
17: mov [rsp + L_FILL], rax
    # shouldBreak
18: test r15d, F_CT | F_AT
    jnz 19f
    mov rdi, [rbx + N_F0]
    call pte_has_multiline_block_comment
    test eax, eax
    jnz 19f
    mov rdi, [rbx + N_F1]
    call pte_has_multiline_block_comment
    test eax, eax
    jnz 19f
    mov rdi, [rbx + N_F2]
    call pte_has_multiline_block_comment
    test eax, eax
    jnz 19f
    test r15d, F_TS
    jz 20f
    mov rdi, [rbx + N_F3]
    call pte_has_multiline_block_comment
    test eax, eax
    jz 20f
19: or r15d, F_BREAK
    # tryToParenthesizeAlternate
20: test r15d, F_CHAIN | F_PT | F_TS
    jnz 21f
    mov rdi, [rbx + N_F1]
    call pjs_is_lone_short_argument
    test eax, eax
    jz 21f
    mov rdi, [rbx + N_F0]
    mov esi, 3
    call pjs_is_simple_expression_by_node_count
    test eax, eax
    jz 21f
    or r15d, F_TRY
    # shouldGroupTestAndConsequent
21: test r15d, F_CHAIN | F_IA | F_TRY
    jnz 22f
    test r15d, F_TS
    jz 211f
    test r15d, F_PT
    jz 22f
    jmp 23f
211: test r15d, F_PT
    jz 23f
    mov rdi, [rbx + N_F0]
    mov esi, 1
    call pjs_is_simple_expression_by_node_count
    test eax, eax
    jz 23f
22: or r15d, F_GROUP

    # consequentComments
23: mov qword ptr [rsp + L_CCOM], 0
    test r15d, F_TS
    jz 231f
    call pte_ts_check_dangling
    mov qword ptr [rsp + L_ACOM], 0
    jmp 28f
231: test r15d, F_CT
    jnz 24f
    mov rdi, [rbx + N_F1]
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 24f
    mov rdi, [rbx + N_F1]
    mov esi, K_consequent
    call pte_dangling_of
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    mov [rsp + L_CCOM], rax
    # alternateComments
24: DMARK r14
    xor r13d, r13d                  # count
    mov rdi, [rbx + N_F0]
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 25f
    mov rdi, [rbx + N_F0]
    mov esi, K_test
    call pte_dangling_of
    DPUSH rax
    inc r13d
25: test r15d, F_AT
    jnz 26f
    mov rdi, [rbx + N_F2]
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 26f
    mov rdi, [rbx + N_F2]
    mov esi, K_alternate
    call pte_dangling_of
    DPUSH rax
    inc r13d
26: mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 27f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
    inc r13d
27: DARRAY r14
    mov qword ptr [rsp + L_ACOM], 0
    test r13d, r13d
    jz 28f
    mov [rsp + L_ACOM], rax

28: call doc_group_id_new
    mov [rsp + L_TEST_ID], rax
    call doc_group_id_new
    mov [rsp + L_CONS_ID], rax
    call doc_group_id_new
    mov [rsp + L_TC_ID], rax
    test r15d, F_TS
    jz 281f
    call pte_ts_printed_test
    jmp 29f
281: # printedTest = [wrapInParens(print("test")), test is a ternary ? breakParent : ""]
    PRINT N_F0, K_test
    mov rdi, rax
    call pte_wrap_in_parens
    mov r14, rax
    DMARK r13
    DPUSH r14
    mov rax, [rbx + N_F0]
    TYPE rax, T_ConditionalExpression
    jne 282f
    DPUSHL d_break_parent
282: DARRAY r13
29: mov rdi, rax
    lea rsi, [rip + sd_q_sp]
    call doc_array2
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp + L_TEST_ID]
    call doc_group_ex
    mov [rsp + L_TESTQ], rax
    # consequent = indent([isConsequentTernary ? hardline : line, consequentComments, print(consequent)])
    mov rdi, [rsp + L_CONS_OFF]
    mov rsi, [rsp + L_CONS_KEY]
    xor edx, edx
    call print_field
    mov r14, rax
    DMARK r13
    lea rdi, [rip + d_line]
    test r15d, F_CT
    jz 30f
    lea rdi, [rip + d_hardline]
30: call ss_push
    DPUSH [rsp + L_CCOM]
    DPUSH r14
    DARRAY r13
    INDENT_RAX
    mov [rsp + L_CONS], rax
    # printedTestAndConsequent
    test r15d, F_GROUP
    jnz 31f
    mov rdi, [rsp + L_TESTQ]
    mov rsi, [rsp + L_CONS]
    call doc_array2
    jmp 33f
31: mov r14, [rsp + L_CONS]
    test r15d, F_CHAIN
    jnz 32f
    mov rdi, [rsp + L_CONS]
    xor esi, esi
    mov rdx, [rsp + L_CONS_ID]
    call doc_group_ex
    mov rdi, [rsp + L_CONS]
    mov rsi, rax
    mov rdx, [rsp + L_TEST_ID]
    call doc_if_break
    mov r14, rax
32: mov rdi, [rsp + L_TESTQ]
    mov rsi, r14
    call doc_array2
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp + L_TC_ID]
    call doc_group_ex
33: mov [rsp + L_TC], rax
    # printedAlternateWithParens
    mov rdi, [rsp + L_ALT_OFF]
    mov rsi, [rsp + L_ALT_KEY]
    xor edx, edx
    call print_field
    mov r14, rax
    test r15d, F_TRY
    jz 34f
    mov rdi, r14
    call pte_wrap_in_parens
    mov rdi, rax
    call doc_dedent
    mov rdi, r14
    mov rsi, rax
    mov rdx, [rsp + L_TC_ID]
    call doc_if_break
    mov r14, rax
34: mov [rsp + L_ALT], r14

    # parts
    DMARK r13
    DPUSH [rsp + L_TC]
    cmp qword ptr [rsp + L_ACOM], 0
    je 35f
    lea rdi, [rip + d_hardline]
    mov rsi, [rsp + L_ACOM]
    call doc_array2
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    DPUSH rax
    jmp 38f
35: test r15d, F_AT
    jz 36f
    DPUSHL d_hardline
    jmp 38f
36: test r15d, F_TRY
    jz 37f
    lea rdi, [rip + d_line]
    lea rsi, [rip + ps_space]
    mov rdx, [rsp + L_TC_ID]
    call doc_if_break
    DPUSH rax
    jmp 38f
37: DPUSHL d_line
38: DPUSHL ps_colon
    test r15d, F_AT
    jnz 39f
    test r15d, F_BIG
    jnz 40f
39: DPUSHL ps_space
    jmp 43f
40: test r15d, F_GROUP
    jz 42f
    mov rdi, [rsp + L_FILL]
    test r15d, F_CHAIN | F_TRY
    jz 41f
    lea rdi, [rip + ps_space]
41: lea rsi, [rip + ps_space]
    xor edx, edx
    call doc_if_break
    mov rdi, [rsp + L_FILL]
    mov rsi, rax
    mov rdx, [rsp + L_TC_ID]
    call doc_if_break
    DPUSH rax
    jmp 43f
42: mov rdi, [rsp + L_FILL]
    lea rsi, [rip + ps_space]
    xor edx, edx
    call doc_if_break
    DPUSH rax
43: test r15d, F_AT
    jz 44f
    DPUSH [rsp + L_ALT]
    jmp 45f
44: mov rdi, [rsp + L_ALT]
    call doc_indent
    GROUP_RAX
    DPUSH rax
45: test r15d, F_BCP
    jz 46f
    test r15d, F_EXTRA
    jnz 46f
    DPUSHL d_softline
46: test r15d, F_BREAK
    jz 47f
    DPUSHL d_break_parent
47: DARRAY r13
    mov r14, rax                    # parts

    # result
    test r15d, F_SAME_ASSIGN
    jz 50f
    test r15d, F_BREAK
    jnz 51f
    mov rax, r14
    GROUP_RAX
    lea rdi, [rip + d_softline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    GROUP_RAX
    jmp 99f
50: test r15d, F_SAME_RETURN
    jz 52f
51: mov rax, r14
    INDENT_RAX
    GROUP_RAX
    jmp 99f
52: test r15d, F_EXTRA
    jnz 521f
    test r15d, F_TS
    jz 53f
    test r15d, F_IN_TEST
    jz 53f
521: lea rdi, [rip + d_softline]
    mov rsi, r14
    call doc_array2
    INDENT_RAX
    xor esi, esi
    test r15d, F_BTCP
    jz 522f
    lea rsi, [rip + d_softline]
522: mov rdi, rax
    call doc_array2
    GROUP_RAX
    jmp 99f
53: mov rax, r14
    mov rcx, [rsp + L_PARENT]
    cmp rcx, [rsp + L_FIRST]
    jne 99f
    GROUP_RAX
99: EPILOGUE
ENDF pte_print_experimental

SDOC sd_extends, "extends"

# pte_ts_printed_test() -> rax: printedTest of a TSConditionalType (the path's
# top): [print("checkType"), " ", "extends", " ", extendsType a conditional or
# mapped type ? print("extendsType") : group(wrapInParens(print("extendsType")))]
FUNC pte_ts_printed_test
    PROLOGUE
    call path_value
    mov rbx, rax
    DMARK r12
    PRINT N_F0, K_checkType
    DPUSH rax
    DPUSHL ps_space
    DPUSHL sd_extends
    DPUSHL ps_space
    PRINT N_F1, K_extendsType
    mov r13, rax
    mov rax, [rbx + N_F1]
    TYPE rax, T_TSConditionalType
    je 1f
    TYPE rax, T_TSMappedType
    je 1f
    mov rdi, r13
    call pte_wrap_in_parens
    GROUP_RAX
    mov r13, rax
1:  DPUSH r13
    DARRAY r12
    EPILOGUE
ENDF pte_ts_printed_test

# pte_ts_check_dangling(): for a TSConditionalType (the path's top) Prettier
# reads dangling comments through the "consequent", "test" and "alternate"
# keys, which it does not have; a dangling comment on trueType, falseType or
# the node is not ported
FUNC pte_ts_check_dangling
    PROLOGUE
    call path_value
    mov rbx, rax
    mov rax, [rbx + N_F2]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    je 1f
    mov rdi, rax
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 90f
1:  mov rax, [rbx + N_F3]
    mov cx, [rax + N_TYPE]
    cmp cx, [rbx + N_TYPE]
    je 2f
    mov rdi, rax
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 90f
2:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 90f
    EPILOGUE
90: REFUSE "printer: dangling comment in a TSConditionalType with experimentalTernaries"
ENDF pte_ts_check_dangling

# pte_wrap_in_parens(doc) -> rax: [ifBreak("("), indent([softline, doc]), softline, ifBreak(")")]
FUNC pte_wrap_in_parens
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    lea rdi, [rip + ps_lparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    lea rdi, [rip + d_softline]
    mov rsi, rbx
    call doc_array2
    INDENT_RAX
    DPUSH rax
    DPUSHL d_softline
    lea rdi, [rip + ps_rparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pte_wrap_in_parens

# pte_dangling_of(child, key) -> rax: path.call(p => printDanglingComments(p), key)
FUNC pte_dangling_of
    PROLOGUE
    mov rbx, rdi
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    mov rbx, rax
    call path_pop
    mov rax, rbx
    EPILOGUE
ENDF pte_dangling_of

# pte_has_multiline_block_comment(node) -> eax: a block comment of the node
# spans lines (hasMultilineBlockComments for one node)
FUNC pte_has_multiline_block_comment
    PROLOGUE
    mov rbx, [rdi + N_COMMENTS]
    xor eax, eax
    test rbx, rbx
    jz 9f
    xor r12d, r12d
1:  xor eax, eax
    cmp r12d, [rbx]
    jae 9f
    mov r13, [rbx + 8 + r12*8]
    inc r12d
    cmp byte ptr [r13 + CM_TYPE], CT_BLOCK
    jne 1b
    mov edi, [r13 + CM_START]
    mov esi, [r13 + CM_END]
    call has_newline_in_range
    test eax, eax
    jz 1b
9:  EPILOGUE
ENDF pte_has_multiline_block_comment

# pte_should_extra_indent() -> eax (shouldExtraIndentForConditionalExpression)
FUNC pte_should_extra_indent
    PROLOGUE
    call path_value
    mov rbx, rax                    # node
    mov r12, rax                    # child
    xor eax, eax
    TYPE rbx, T_ConditionalExpression
    jne 9f
    xor r13d, r13d                  # ancestorCount
1:  mov rdi, r13
    call path_parent_node
    test rax, rax
    jz 90f
    mov r14, rax
    mov rdi, r14
    call pjs_is_call_expression
    test eax, eax
    jz 2f
    cmp [r14 + N_F0], r12           # callee
    je 3f
2:  mov rdi, r14
    call pjs_is_member_expression
    test eax, eax
    jnz 21f
    TYPE r14, T_TSNonNullExpression
    jne 4f
21: cmp [r14 + N_F0], r12           # object, expression
    jne 4f
3:  mov r12, r14
    inc r13
    jmp 1b
    # reached the chain root
4:  TYPE r14, T_NewExpression
    je 41f
    mov rdi, r14
    call pjs_is_binary_cast_expression
    test eax, eax
    jz 5f
41: cmp [r14 + N_F0], r12           # callee, expression
    jne 5f
    lea rdi, [r13 + 1]
    call path_parent_node
    test rax, rax
    jz 90f
    mov r12, r14
    mov r14, rax
5:  xor eax, eax
    cmp r12, rbx
    je 9f
    movzx ecx, word ptr [r14 + N_TYPE]
    mov rdx, [r14 + N_F1]           # right, init
    cmp ecx, T_AssignmentExpression
    je 6f
    cmp ecx, T_VariableDeclarator
    je 6f
    mov rdx, [r14 + N_F0]           # argument
    cmp ecx, T_ReturnStatement
    je 6f
    cmp ecx, T_ThrowStatement
    je 6f
    cmp ecx, T_UnaryExpression
    je 6f
    cmp ecx, T_YieldExpression
    je 6f
    cmp ecx, T_AwaitExpression
    jne 9f
6:  cmp rdx, r12
    sete al
9:  EPILOGUE
90: REFUSE "printer: shouldExtraIndentForConditionalExpression past the root"
ENDF pte_should_extra_indent
