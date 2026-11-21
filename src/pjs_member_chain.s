# print/member-chain.js
.include "pjs.inc"

# printedNodes record: node, printed, needsParens, hasTrailingEmptyLine
.equ PN_NODE, 0
.equ PN_PRINTED, 8
.equ PN_PARENS, 16
.equ PN_EMPTY, 24
.equ PN_SIZE, 32

# locals of pjs_print_member_chain
.equ L_EXPR_STMT, 0
.equ L_MERGE, 8
.equ L_GROUPS_DOCS, 16      # VEC of printGroup docs (printedGroups)
.equ L_ONE_LINE, 24
.equ L_CUTOFF, 32
.equ L_HAS_COMMENT, 40
.equ L_EMPTY_BEFORE, 48
.equ L_EXPANDED, 56
.equ L_TMP, 64
.equ L_TMP2, 72

SDOC sd_bang, "!"

    .text

# pjs_print_member_chain() -> rax doc (printMemberChain); the call is the path's top
FUNC pjs_print_member_chain
    PROLOGUE 10
    call path_value
    mov r15, rax                    # the root call
    call path_parent
    xor ecx, ecx
    TYPE rax, T_ExpressionStatement
    sete cl
    mov [rsp + L_EXPR_STMT], rcx
    # printedNodes, collected outermost first on the scratch stack
    DMARK r12
    DPUSH r15
    mov rdi, r15
    call pjs_print_optional_token
    mov [rsp + L_TMP], rax
    call pjs_print_function_type_parameters
    mov [rsp + L_TMP2], rax
    call pjs_print_call_arguments
    mov rdi, [rsp + L_TMP]
    mov rsi, [rsp + L_TMP2]
    mov rdx, rax
    call doc_array3
    DPUSH rax
    xor edi, edi
    call ss_push
    xor edi, edi
    call ss_push
    cmp qword ptr [r15 + N_F0], 0
    je 1f
    lea rdi, [rip + pmc_rec]
    xor esi, esi
    mov edx, K_callee
    mov ecx, N_F0
    call path_call
1:  mov rdi, r12
    call ss_to_vec
    mov r13, rax
    mov r12, [r13]
    shr r12, 2                      # n
    mov rdi, r12
    shl rdi, 5
    call alloc
    mov rbx, rax                    # printedNodes, innermost first
    xor ecx, ecx
2:  cmp rcx, r12
    jae 3f
    mov rdx, r12
    sub rdx, rcx
    dec rdx
    shl rdx, 5
    lea rsi, [r13 + 8 + rdx]
    mov rdi, rcx
    shl rdi, 5
    add rdi, rbx
    mov rax, [rsi]
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov rax, [rsi + 16]
    mov [rdi + 16], rax
    mov rax, [rsi + 24]
    mov [rdi + 24], rax
    inc rcx
    jmp 2b

    # groups: (start, end) pairs of printedNodes
3:  mov rdi, r12
    shl rdi, 4
    add rdi, 16
    call alloc
    mov r13, rax
    xor r14d, r14d                  # groups count
    mov r15d, 1                     # i
4:  cmp r15, r12
    jae 6f
    mov rdi, r15
    call pmc_node
    mov [rsp + L_TMP], rax
    TYPE rax, T_TSNonNullExpression
    je 5f
    mov rdi, rax
    call pjs_is_call_expression
    test eax, eax
    jnz 5f
    mov rdi, [rsp + L_TMP]
    call pmc_is_numeric_index
    test eax, eax
    jz 6f
5:  inc r15
    jmp 4b
6:  mov rdi, [rbx + PN_NODE]
    call pjs_is_call_expression
    test eax, eax
    jnz 8f
7:  lea rax, [r15 + 1]
    cmp rax, r12
    jae 8f
    mov rdi, r15
    call pmc_node
    mov rdi, rax
    call pjs_is_memberish
    test eax, eax
    jz 8f
    lea rdi, [r15 + 1]
    call pmc_node
    mov rdi, rax
    call pjs_is_memberish
    test eax, eax
    jz 8f
    inc r15
    jmp 7b
8:  mov qword ptr [r13], 0
    mov [r13 + 8], r15
    mov r14d, 1
    mov [rsp + L_TMP], r15          # currentGroup start
    mov qword ptr [rsp + L_TMP2], 0 # hasSeenCallExpression
10: cmp r15, r12
    jae 15f
    mov rdi, r15
    call pmc_node
    mov [rsp + L_HAS_COMMENT], rax  # (scratch) the node
    cmp qword ptr [rsp + L_TMP2], 0
    je 12f
    mov rdi, rax
    call pjs_is_memberish
    test eax, eax
    jz 12f
    mov rdi, [rsp + L_HAS_COMMENT]
    call pmc_is_numeric_index
    test eax, eax
    jnz 14f
    mov rdi, r15
    call pmc_push_group
    mov [rsp + L_TMP], r15
    mov qword ptr [rsp + L_TMP2], 0
12: mov rdi, [rsp + L_HAS_COMMENT]
    TYPE rdi, T_ImportExpression
    je 121f
    call pjs_is_call_expression
    test eax, eax
    jz 13f
121: mov qword ptr [rsp + L_TMP2], 1
13: mov rdi, [rsp + L_HAS_COMMENT]
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    test eax, eax
    jz 14f
    lea rdi, [r15 + 1]
    call pmc_push_group
    lea rax, [r15 + 1]
    mov [rsp + L_TMP], rax
    mov qword ptr [rsp + L_TMP2], 0
14: inc r15
    jmp 10b
15: cmp [rsp + L_TMP], r12
    jae 16f
    mov rdi, r12
    call pmc_push_group

    # shouldMerge
16: mov qword ptr [rsp + L_MERGE], 0
    cmp r14, 2
    jb 20f
    mov rax, [r13 + 16]
    shl rax, 5
    mov rdi, [rbx + rax + PN_NODE]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 20f
    call pmc_should_not_wrap
    mov [rsp + L_MERGE], rax

    # printedGroups, oneLine
20: call ss_mark
    mov [rsp + L_TMP], rax
    xor r15d, r15d
21: cmp r15, r14
    jae 22f
    mov rdi, r15
    call pmc_print_group
    DPUSH rax
    inc r15
    jmp 21b
22: mov rdi, [rsp + L_TMP]
    call ss_to_vec
    mov [rsp + L_GROUPS_DOCS], rax
    mov rdi, rax
    call pmc_vec_to_array
    mov [rsp + L_ONE_LINE], rax
    mov eax, 2
    cmp qword ptr [rsp + L_MERGE], 0
    je 23f
    mov eax, 3
23: mov [rsp + L_CUTOFF], rax

    # nodeHasComment
    mov qword ptr [rsp + L_HAS_COMMENT], 1
    mov r15d, 1
24: lea rax, [r12 - 1]
    cmp r15, rax
    jae 25f
    mov rdi, r15
    call pmc_node
    mov rdi, rax
    mov esi, CC_Leading
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 28f
    inc r15
    jmp 24b
25: xor r15d, r15d
26: lea rax, [r12 - 1]
    cmp r15, rax
    jae 27f
    mov rdi, r15
    call pmc_node
    mov rdi, rax
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 28f
    inc r15
    jmp 26b
27: mov qword ptr [rsp + L_HAS_COMMENT], 0
    mov rax, [rsp + L_CUTOFF]
    cmp rax, r14
    jae 28f
    shl rax, 4
    mov rdi, [r13 + rax]
    call pmc_node
    mov rdi, rax
    mov esi, CC_Leading
    xor edx, edx
    call has_comment
    mov [rsp + L_HAS_COMMENT], rax

    # a single `.`: oneLine
28: cmp [rsp + L_CUTOFF], r14
    jb 30f
    cmp qword ptr [rsp + L_HAS_COMMENT], 0
    jne 30f
    xor r15d, r15d
29: cmp r15, r14
    jae 291f
    mov rax, r15
    shl rax, 4
    mov rax, [r13 + rax + 8]
    shl rax, 5
    cmp qword ptr [rbx + rax - PN_SIZE + PN_EMPTY], 0
    jne 30f
    inc r15
    jmp 29b
291: call pjs_is_long_curried_call_expression
    mov rcx, rax
    mov rax, [rsp + L_ONE_LINE]
    test ecx, ecx
    jnz 99f
    GROUP_RAX
    jmp 99f

    # expanded
30: xor eax, eax
    cmp qword ptr [rsp + L_MERGE], 0
    je 31f
    mov eax, 16
31: mov rax, [r13 + rax + 8]
    mov rdi, rax
    dec rdi
    call pmc_node
    mov r15, rax                    # lastNodeBeforeIndent
    mov qword ptr [rsp + L_EMPTY_BEFORE], 0
    mov rdi, r15
    call pjs_is_call_expression
    test eax, eax
    jnz 32f
    mov rdi, r15
    call pmc_should_insert_empty_line_after
    mov [rsp + L_EMPTY_BEFORE], rax
32: call ss_mark
    mov [rsp + L_TMP], rax
    mov rax, [rsp + L_GROUPS_DOCS]
    DPUSH [rax + 8]
    mov r15d, 1
    cmp qword ptr [rsp + L_MERGE], 0
    je 33f
    mov rax, [rsp + L_GROUPS_DOCS]
    DPUSH [rax + 16]
    mov r15d, 2
33: cmp qword ptr [rsp + L_EMPTY_BEFORE], 0
    je 34f
    DPUSHL d_hardline
    # printIndentedGroup(groups.slice(r15))
34: cmp r15, r14
    jae 36f
    call ss_mark
    mov [rsp + L_TMP2], rax
    DPUSHL d_hardline
35: mov rax, [rsp + L_GROUPS_DOCS]
    DPUSH [rax + 8 + r15*8]
    inc r15
    cmp r15, r14
    jae 351f
    DPUSHL d_hardline
    jmp 35b
351: mov rdi, [rsp + L_TMP2]
    call ss_to_array
    INDENT_RAX
    DPUSH rax
36: mov rdi, [rsp + L_TMP]
    call ss_to_array
    mov [rsp + L_EXPANDED], rax

    # one line or expanded
    cmp qword ptr [rsp + L_HAS_COMMENT], 0
    jne 50f
    call pmc_calls_not_simple
    test eax, eax
    jnz 50f
    xor r15d, r15d
37: lea rax, [r14 - 1]
    cmp r15, rax
    jae 38f
    mov rax, [rsp + L_GROUPS_DOCS]
    mov rdi, [rax + 8 + r15*8]
    call will_break
    test eax, eax
    jnz 50f
    inc r15
    jmp 37b
38: call pmc_last_group_will_break_and_other_calls_have_function_arguments
    test eax, eax
    jnz 50f
    # [willBreak(oneLine) || emptyLine ? breakParent : "", conditionalGroup([oneLine, expanded])]
    mov rdi, [rsp + L_ONE_LINE]
    mov rsi, [rsp + L_EXPANDED]
    call doc_array2
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_conditional_group
    mov r15, rax
    xor r12d, r12d
    cmp qword ptr [rsp + L_EMPTY_BEFORE], 0
    jne 39f
    mov rdi, [rsp + L_ONE_LINE]
    call will_break
    test eax, eax
    jz 40f
39: lea r12, [rip + d_break_parent]
40: mov rdi, r12
    mov rsi, r15
    call doc_array2
    jmp 60f
50: mov rax, [rsp + L_EXPANDED]
    GROUP_RAX
60: mov rsi, rax
    mov edi, LB_MEMBER_CHAIN
    call doc_label
99: EPILOGUE

# pmc_node(i) -> rax: printedNodes[i].node (rbx is printedNodes)
pmc_node:
    shl rdi, 5
    mov rax, [rbx + rdi + PN_NODE]
    ret

# pmc_push_group(end): groups.push(printedNodes[currentGroupStart .. end))
pmc_push_group:
    mov rax, r14
    shl rax, 4
    mov rcx, [rsp + 8 + L_TMP]
    mov [r13 + rax], rcx
    mov [r13 + rax + 8], rdi
    inc r14
    ret

# pmc_should_not_wrap() -> rax (shouldNotWrap)
pmc_should_not_wrap:
    sub rsp, 8
    mov rdi, [r13 + 16]             # groups[1][0]
    call pmc_node
    xor r8d, r8d
    test dword ptr [rax + N_ATTR], NA_COMPUTED
    setnz r8b                       # hasComputed
    mov rax, [r13 + 8]
    cmp rax, 1
    jne 3f
    mov rdi, [rbx + PN_NODE]
    TYPE rdi, T_ThisExpression
    je 7f
    TYPE rdi, T_Identifier
    jne 8f
    push r8
    push rdi
    call pmc_is_factory
    pop rdi
    pop r8
    test eax, eax
    jnz 7f
    test r8, r8
    jnz 7f
    cmp qword ptr [rsp + 16 + L_EXPR_STMT], 0
    je 8f
    mov eax, [rdi + N_END]
    sub eax, [rdi + N_START]
    cmp rax, [rip + g_tab_width]
    jbe 7f
    jmp 8f
3:  lea rdi, [rax - 1]
    call pmc_node
    mov rdi, rax
    push r8
    push rdi
    call pjs_is_member_expression
    pop rdi
    pop r8
    test eax, eax
    jz 8f
    mov rdi, [rdi + N_F1]
    TYPE rdi, T_Identifier
    jne 8f
    test r8, r8
    jnz 7f
    call pmc_is_factory
    jmp 9f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    ret

# pmc_print_group(k) -> rax (printGroup of groups[k])
pmc_print_group:
    push r12
    push r15
    sub rsp, 8
    mov rax, rdi
    shl rax, 4
    mov r12, [r13 + rax]            # start
    mov r15, [r13 + rax + 8]        # end
    call ss_mark
    mov [rsp], rax
    mov rax, r15
    shl rax, 5
    cmp qword ptr [rbx + rax - PN_SIZE + PN_PARENS], 0
    je 1f
    DPUSHL ps_lparen
1:  cmp r12, r15
    jae 2f
    mov rax, r12
    shl rax, 5
    DPUSH [rbx + rax + PN_PRINTED]
    inc r12
    jmp 1b
2:  mov rax, r15
    shl rax, 5
    cmp qword ptr [rbx + rax - PN_SIZE + PN_PARENS], 0
    je 3f
    DPUSHL ps_rparen
3:  mov rdi, [rsp]
    call ss_to_array
    add rsp, 8
    pop r15
    pop r12
    ret

# pmc_calls_not_simple() -> eax: callExpressions.length > 2 and some call has
# an argument that is not simple
pmc_calls_not_simple:
    push r12
    push r14
    push r15
    xor r14d, r14d                  # calls
    xor r15d, r15d
1:  cmp r15, r12
    jae 2f
    mov rdi, r15
    call pmc_node
    mov rdi, rax
    call pjs_is_call_expression
    add r14, rax
    inc r15
    jmp 1b
2:  xor eax, eax
    cmp r14, 2
    jbe 9f
    xor r15d, r15d
3:  xor eax, eax
    cmp r15, r12
    jae 9f
    mov rdi, r15
    inc r15
    call pmc_node
    mov r14, rax
    mov rdi, rax
    call pjs_is_call_expression
    test eax, eax
    jz 3b
    mov r14, [r14 + N_F1]
    VLEN rcx, r14
    xor edx, edx
4:  cmp rdx, rcx
    jae 3b
    push rcx
    push rdx
    mov rdi, [r14 + 8 + rdx*8]
    mov esi, 2
    call pjs_is_simple_call_argument
    pop rdx
    pop rcx
    inc rdx
    test eax, eax
    jnz 4b
    mov eax, 1
9:  pop r15
    pop r14
    pop r12
    ret

# pmc_last_group_will_break_and_other_calls_have_function_arguments() -> eax
pmc_last_group_will_break_and_other_calls_have_function_arguments:
    push r12
    push r14
    push r15
    mov rax, r14
    shl rax, 4
    mov rdi, [r13 + rax - 8]
    dec rdi
    call pmc_node
    mov rdi, rax
    call pjs_is_call_expression
    test eax, eax
    jz 9f
    mov rax, [rsp + 32 + L_GROUPS_DOCS]
    mov rdi, [rax + r14*8]
    call will_break
    test eax, eax
    jz 9f
    # the last call expression is left out
    xor r14d, r14d                  # index of the last call + 1
    xor r15d, r15d
1:  cmp r15, r12
    jae 2f
    mov rdi, r15
    inc r15
    call pmc_node
    mov rdi, rax
    call pjs_is_call_expression
    test eax, eax
    jz 1b
    mov r14, r15
    jmp 1b
2:  xor r15d, r15d
3:  xor eax, eax
    lea rcx, [r14 - 1]
    cmp r15, rcx
    jae 9f
    mov rdi, r15
    inc r15
    call pmc_node
    mov r12, rax
    mov rdi, rax
    call pjs_is_call_expression
    test eax, eax
    jz 3b
    mov r12, [r12 + N_F1]
    VLEN rcx, r12
    xor edx, edx
4:  cmp rdx, rcx
    jae 3b
    push rcx
    push rdx
    mov rdi, [r12 + 8 + rdx*8]
    call pjs_is_function_or_arrow_expression
    pop rdx
    pop rcx
    inc rdx
    test eax, eax
    jz 4b
9:  pop r15
    pop r14
    pop r12
    ret
ENDF pjs_print_member_chain

# pmc_is_numeric_index(node) -> eax: a computed member with a numeric literal property
FUNC pmc_is_numeric_index
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call pjs_is_member_expression
    test eax, eax
    jz 9f
    xor eax, eax
    test dword ptr [rbx + N_ATTR], NA_COMPUTED
    jz 9f
    mov rcx, [rbx + N_F1]
    TYPE rcx, T_NumericLiteral
    sete al
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pmc_is_numeric_index

# pmc_is_factory(identifier) -> eax: /^[A-Z]|^[$_]+$/ on the name
FUNC pmc_is_factory
    mov rsi, [rip + g_text]
    mov ecx, [rdi + N_START]
    mov edx, [rdi + N_END]
    mov eax, 1
    movzx r8d, byte ptr [rsi + rcx]
    cmp r8d, 'A'
    jb 1f
    cmp r8d, 'Z'
    jbe 9f
1:  cmp ecx, edx
    jae 9f
    movzx r8d, byte ptr [rsi + rcx]
    inc ecx
    cmp r8d, '$'
    je 1b
    cmp r8d, '_'
    je 1b
    xor eax, eax
9:  leave
    ret
ENDF pmc_is_factory

# pmc_should_insert_empty_line_after(node) -> eax (shouldInsertEmptyLineAfter)
FUNC pmc_should_insert_empty_line_after
    push rbx
    push r12
    mov rbx, rdi
    mov edi, [rbx + N_END]
    call next_nonspace_noncomment_index
    mov r12, rax
    mov r8, IDX_FALSE
    cmp rax, r8
    je 2f
    mov rdi, rax
    call char_at
    cmp eax, ')'
    jne 2f
    lea rdi, [r12 + 1]
    call is_next_line_empty
    jmp 9f
2:  mov rdi, rbx
    call pjs_is_next_line_empty
9:  pop r12
    pop rbx
    leave
    ret
ENDF pmc_should_insert_empty_line_after

# pmc_vec_to_array(vec) -> rax: an array doc of the VEC's docs
FUNC pmc_vec_to_array
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    call ss_mark
    mov r12, rax
    xor r13d, r13d
1:  cmp r13, [rbx]
    jae 2f
    DPUSH [rbx + 8 + r13*8]
    inc r13
    jmp 1b
2:  mov rdi, r12
    call ss_to_array
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pmc_vec_to_array

# pmc_rec(ctx, node, index): rec of printMemberChain for the node at the top of the path
FUNC pmc_rec
    PROLOGUE 2
    call path_value
    mov rbx, rax
    mov rdi, rbx
    call pjs_is_call_expression
    test eax, eax
    jz 10f
    mov rdi, [rbx + N_F0]
    call pjs_is_memberish
    test eax, eax
    jnz 1f
    mov rdi, [rbx + N_F0]
    call pjs_is_call_expression
    test eax, eax
    jz 10f
    # a call in the chain
1:  mov rdi, rbx
    call pmc_should_insert_empty_line_after
    mov r12, rax                    # hasTrailingEmptyLine
    mov rdi, rbx
    call pjs_print_optional_token
    mov [rsp], rax
    call pjs_print_function_type_parameters
    mov [rsp + 8], rax
    call pjs_print_call_arguments
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, rax
    call doc_array3
    mov rdi, rbx
    mov rsi, rax
    call print_comments
    mov r13, rax
    xor esi, esi
    test r12, r12
    jz 2f
    lea rsi, [rip + d_hardline]
2:  mov rdi, r13
    call doc_array2
    mov r13, rax
    DPUSH rbx
    DPUSH r13
    xor edi, edi
    call ss_push
    DPUSH r12
    lea rdi, [rip + pmc_rec]
    xor esi, esi
    mov edx, K_callee
    mov ecx, N_F0
    call path_call
    jmp 99f
10: mov rdi, rbx
    call pjs_is_memberish
    test eax, eax
    jz 20f
    call pjs_needs_parens
    mov r12, rax
    call pjs_print_member_lookup
    mov rdi, rbx
    mov rsi, rax
    call print_comments
    mov r13, rax
    DPUSH rbx
    DPUSH r13
    DPUSH r12
    xor edi, edi
    call ss_push
    lea rdi, [rip + pmc_rec]
    xor esi, esi
    mov edx, K_object
    mov ecx, N_F0
    call path_call
    jmp 99f
20: TYPE rbx, T_TSNonNullExpression
    jne 21f
    mov rdi, rbx
    lea rsi, [rip + sd_bang]
    call print_comments
    mov r13, rax
    DPUSH rbx
    DPUSH r13
    xor edi, edi
    call ss_push
    xor edi, edi
    call ss_push
    lea rdi, [rip + pmc_rec]
    xor esi, esi
    mov edx, K_expression
    mov ecx, N_F0
    call path_call
    jmp 99f
21: xor edi, edi
    call main_print_here
    mov r13, rax
    DPUSH rbx
    DPUSH r13
    xor edi, edi
    call ss_push
    xor edi, edi
    call ss_push
99: EPILOGUE
ENDF pmc_rec
