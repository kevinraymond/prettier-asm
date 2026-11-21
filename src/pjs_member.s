# print/member.js
.include "pjs.inc"

# pjs_doc_label_bits(doc) -> rax: doc.label as LB_* bits, 0 when doc is not a label
FUNC pjs_doc_label_bits
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp byte ptr [rdi], DK_LABEL
    jne 9f
    mov rax, [rdi + DL_LABEL]
9:  leave
    ret
ENDF pjs_doc_label_bits

# pjs_print_member_expression(node, args) -> rax doc (printMemberExpression)
FUNC pjs_print_member_expression
    PROLOGUE 2
    mov rbx, rdi
    PRINT N_F0, K_object
    mov r12, rax                    # objectDoc
    call pjs_print_member_lookup
    mov r13, rax                    # lookupDoc
    lea rdi, [rip + pme_not_non_null]
    xor esi, esi
    call path_find_ancestor
    mov r14, rax                    # firstNonChainElementWrapperParent
    # firstNonMemberParent: New, or an assignment whose left is not an Identifier
    lea rdi, [rip + pme_not_member]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 1f
    TYPE rax, T_NewExpression
    je 7f
    TYPE rax, T_AssignmentExpression
    jne 1f
    mov rcx, [rax + N_F0]
    TYPE rcx, T_Identifier
    jne 7f
1:  ATTR rbx, NA_COMPUTED
    jnz 7f
    mov rax, [rbx + N_F0]
    TYPE rax, T_Identifier
    jne 2f
    mov rax, [rbx + N_F1]
    TYPE rax, T_Identifier
    jne 2f
    mov rdi, r14
    call pjs_is_member_expression
    test eax, eax
    jz 7f
2:  TYPE r14, T_AssignmentExpression
    je 3f
    TYPE r14, T_VariableDeclarator
    jne 6f
    # isCallExpressionWithArguments(node.object)
3:  mov r15, [rbx + N_F0]
    TYPE r15, T_TSNonNullExpression
    jne 31f
    mov r15, [r15 + N_F0]
31: mov rdi, r15
    call pjs_is_call_expression
    test eax, eax
    jz 4f
    mov rdi, r15
    call pjs_get_call_arguments
    cmp qword ptr [rax], 0
    jne 7f
4:  mov rdi, r12
    call pjs_doc_label_bits
    test eax, LB_MEMBER_CHAIN
    jnz 7f
    # group(indent([softline, lookupDoc]))
6:  lea rdi, [rip + d_softline]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
    GROUP_RAX
    mov r13, rax
7:  mov rdi, r12
    mov rsi, r13
    call doc_array2
    mov r13, rax
    mov rdi, r12
    call pjs_doc_label_bits
    mov rdi, rax
    mov rsi, r13
    call doc_label_or
    EPILOGUE
ENDF pjs_print_member_expression

FUNC pme_not_member
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_TSNonNullExpression
    je 9f
    mov rdi, rsi
    call pjs_is_member_expression
    xor eax, 1
9:  leave
    ret
ENDF pme_not_member

FUNC pme_not_non_null
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_TSNonNullExpression
    setne al
    leave
    ret
ENDF pme_not_non_null

# pjs_print_member_lookup() -> rax doc (printMemberLookup); the member
# expression is the path's top
FUNC pjs_print_member_lookup
    PROLOGUE
    call path_value
    mov rbx, rax
    PRINT N_F1, K_property
    mov r12, rax                    # property
    mov rdi, rbx
    call pjs_print_optional_token
    mov r13, rax                    # optional
    DMARK r14
    DPUSH r13
    ATTR rbx, NA_COMPUTED
    jnz 1f
    DPUSHL ps_dot
    DPUSH r12
    DARRAY r14
    jmp 9f
1:  DPUSHL ps_lbracket
    mov rax, [rbx + N_F1]
    test rax, rax
    jz 2f
    TYPE rax, T_NumericLiteral
    je 2f
    lea rdi, [rip + d_softline]
    mov rsi, r12
    call doc_array2
    INDENT_RAX
    DPUSH rax
    DPUSHL d_softline
    DPUSHL ps_rbracket
    DARRAY r14
    GROUP_RAX
    jmp 9f
2:  DPUSH r12
    DPUSHL ps_rbracket
    DARRAY r14
9:  EPILOGUE
ENDF pjs_print_member_lookup
