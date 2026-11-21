# print/arrow-function.js (no JSX).
.include "pjs.inc"

.equ MAX_CHAIN, 64

# printArrowFunction state, passed to paf_rec as its context
.equ AS_ARGS, 0
.equ AS_CHAIN, 8                # shouldPrintAsChain
.equ AS_BREAK_CHAIN, 16         # shouldBreakChain
.equ AS_BODY_DOC, 24
.equ AS_FUNCTION_BODY, 32
.equ AS_SIGS, 40                # VEC of signature docs (capacity MAX_CHAIN)
.equ AS_COMMENTS, 48            # VEC of trailing comment docs, in rec order
.equ AS_SIZE, 56

SDOC sd_async_sp, "async "
SDOC sd_arrow, " =>"

    .data
    .balign 8
# `args = {}`: an args record that is not undefined, so print("body", args)
# is not cached
paf_empty_args: .quad 0

    .bss
    .balign 8
arrow_line: .quad 0             # [" =>", line]

    .text

# pjs_print_arrow_function(node, args) -> rax doc (printArrowFunction)
FUNC pjs_print_arrow_function
    PROLOGUE 12
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jnz 1f
    lea r12, [rip + paf_empty_args]
1:  cmp qword ptr [rip + arrow_line], 0
    jne 2f
    lea rdi, [rip + sd_arrow]
    lea rsi, [rip + d_line]
    call doc_array2
    mov [rip + arrow_line], rax
2:  mov edi, AS_SIZE
    call alloc
    mov r13, rax                    # state
    mov [r13 + AS_ARGS], r12
    mov edi, (MAX_CHAIN + 1) * 8
    call alloc
    mov [r13 + AS_SIGS], rax
    mov edi, (MAX_CHAIN + 1) * 8
    call alloc
    mov [r13 + AS_COMMENTS], rax
    # shouldPrintAsChain = !args.expandLastArg && body is an arrow
    cmp byte ptr [r12 + ARGS_EXPAND_LAST_ARG], 0
    jne 3f
    mov rax, [rbx + N_F2]
    TYPE rax, T_ArrowFunctionExpression
    jne 3f
    mov qword ptr [r13 + AS_CHAIN], 1
3:  mov rdi, r13
    mov rsi, rbx
    call paf_rec

    # shouldPutBodyOnSameLine
    mov r14, [r13 + AS_FUNCTION_BODY]
    xor r15d, r15d
    mov rdi, r14
    call pjs_has_leading_own_line_comment
    test eax, eax
    jnz 5f
    TYPE r14, T_SequenceExpression
    je 4f
    mov rdi, r14
    mov rsi, [r13 + AS_BODY_DOC]
    call paf_may_break_after_short_prefix
    test eax, eax
    jnz 4f
    cmp qword ptr [r13 + AS_BREAK_CHAIN], 0
    jne 5f
    mov rdi, r14
    call paf_should_add_parens_if_not_break
    test eax, eax
    jz 5f
4:  mov r15d, 1
5:  mov [rsp], r15                  # shouldPutBodyOnSameLine
    # isCallee
    xor r15d, r15d
    call path_key
    cmp eax, K_callee
    jne 6f
    call path_parent
    mov rdi, rax
    call pjs_is_call_like_expression
    mov r15d, eax
6:  mov [rsp + 8], r15              # isCallee
    call doc_group_id_new
    mov [rsp + 16], rax             # chainGroupId
    mov rdi, r13
    call paf_print_signatures
    mov [rsp + 24], rax             # signaturesDoc
    mov qword ptr [rsp + 32], 0     # shouldBreakSignatures
    mov qword ptr [rsp + 40], 0     # shouldIndentSignatures
    mov qword ptr [rsp + 48], 0     # shouldPrintSoftlineInIndent
    cmp qword ptr [r13 + AS_CHAIN], 0
    je 8f
    movzx eax, byte ptr [r12 + ARGS_ASSIGNMENT_LAYOUT]
    or rax, [rsp + 8]
    jz 8f
    mov qword ptr [rsp + 40], 1
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    xor eax, 1
    mov [rsp + 48], rax
    cmp byte ptr [r12 + ARGS_ASSIGNMENT_LAYOUT], AL_CHAIN_TAIL_ARROW_CHAIN
    je 7f
    cmp qword ptr [rsp + 8], 0
    je 8f
    cmp qword ptr [rsp], 0
    jne 8f
7:  mov qword ptr [rsp + 32], 1
8:  mov rdi, r13
    mov rsi, [rsp]
    call paf_print_body
    mov [rsp + 56], rax             # bodyDoc

    # group([group(signatures, {shouldBreak, id}), " =>", body, ifBreak(softline, "")])
    mov rax, [rsp + 24]
    cmp qword ptr [rsp + 40], 0
    je 10f
    DMARK r14
    cmp qword ptr [rsp + 48], 0
    je 9f
    DPUSHL d_softline
9:  DPUSH [rsp + 24]
    DARRAY r14
    INDENT_RAX
10: mov rdi, rax
    xor esi, esi
    cmp qword ptr [rsp + 32], 0
    je 11f
    mov esi, GF_BREAK
11: mov rdx, [rsp + 16]
    call doc_group_ex
    mov r15, rax
    DMARK r14
    DPUSH r15
    DPUSHL sd_arrow
    cmp qword ptr [r13 + AS_CHAIN], 0
    je 12f
    mov rdi, [rsp + 56]
    mov rsi, [rsp + 16]
    xor edx, edx
    call doc_indent_if_break
    DPUSH rax
    cmp qword ptr [rsp + 8], 0
    je 13f
    lea rdi, [rip + d_softline]
    xor esi, esi
    mov rdx, [rsp + 16]
    call doc_if_break
    DPUSH rax
    jmp 13f
12: mov rax, [rsp + 56]
    GROUP_RAX
    DPUSH rax
13: DARRAY r14
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_arrow_function

# paf_rec(state, node, index) -> rax: the `rec` closure for the arrow at the
# top of the path
FUNC paf_rec
    PROLOGUE
    mov r13, rdi
    mov rbx, rsi
    mov rdi, r13
    call paf_print_signature
    mov r14, rax                    # signatureDoc
    mov r12, [r13 + AS_SIGS]
    mov rcx, [r12]
    cmp rcx, MAX_CHAIN
    jae 90f
    test rcx, rcx
    jz 2f
    mov rdi, rbx
    call print_comments_separately
    mov r15, rdx                    # trailing
    test ecx, ecx
    jnz 1f
    xor eax, eax
    xor r15d, r15d
1:  mov rdi, rax
    mov rsi, r14
    call doc_array2
    mov r14, rax
    mov rcx, [r13 + AS_COMMENTS]
    mov rdx, [rcx]
    mov [rcx + 8 + rdx*8], r15
    inc qword ptr [rcx]
    mov rcx, [r12]
2:  mov [r12 + 8 + rcx*8], r14
    inc qword ptr [r12]
    cmp qword ptr [r13 + AS_CHAIN], 0
    je 4f
    # shouldBreakChain ||= (returnType && parameters.length > 0) ||
    # typeParameters || some parameter is not an Identifier
    cmp qword ptr [rbx + N_F4], 0
    jne 31f
    mov rcx, [rbx + N_F1]
    xor edx, edx
    test rcx, rcx
    jz 4f
    cmp qword ptr [rbx + N_F5], 0
    je 3f
    cmp qword ptr [rcx], 0
    je 3f
31: mov qword ptr [r13 + AS_BREAK_CHAIN], 1
    jmp 4f
3:  cmp rdx, [rcx]
    jae 4f
    mov rax, [rcx + 8 + rdx*8]
    inc rdx
    TYPE rax, T_Identifier
    je 3b
    mov qword ptr [r13 + AS_BREAK_CHAIN], 1
4:  mov rax, [rbx + N_F2]
    cmp qword ptr [r13 + AS_CHAIN], 0
    je 5f
    TYPE rax, T_ArrowFunctionExpression
    jne 5f
    lea rdi, [rip + paf_rec]
    mov rsi, r13
    mov edx, K_body
    mov ecx, N_F2
    call path_call
    jmp 9f
5:  mov [r13 + AS_FUNCTION_BODY], rax
    mov edi, N_F2
    mov esi, K_body
    mov rdx, [r13 + AS_ARGS]
    call print_field
    mov [r13 + AS_BODY_DOC], rax
9:  EPILOGUE
90: REFUSE "printer: arrow chain longer than 64"
ENDF paf_rec

# paf_print_signature(state) -> rax (printArrowFunctionSignature) for the arrow
# at the top of the path
FUNC paf_print_signature
    PROLOGUE
    mov r13, rdi
    call path_value
    mov rbx, rax
    DMARK r12
    ATTR rbx, NA_ASYNC
    jz 1f
    DPUSHL sd_async_sp
1:  call pjs_should_print_params_without_parens
    test eax, eax
    jz 2f
    mov rdi, [rbx + N_F1]
    xor esi, esi
    mov edx, K_params
    xor ecx, ecx
    call print_elem
    DPUSH rax
    jmp 4f
2:  mov rax, [r13 + AS_ARGS]
    movzx r14d, byte ptr [rax + ARGS_EXPAND_LAST_ARG]
    or r14b, [rax + ARGS_EXPAND_FIRST_ARG]
    call pjs_print_return_type
    mov r15, rax                    # returnTypeDoc
    test r14d, r14d
    jz 3f
    # group(removeLines(returnTypeDoc)); a break throws ArgExpansionBailout
    mov rdi, r15
    call will_break
    test eax, eax
    jz 21f
    call pjs_throw_arg_expansion_bailout
21: mov rdi, r15
    call remove_lines
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov r15, rax
3:  mov edi, r14d
    mov esi, 1
    call pjs_print_function_parameters
    mov rdi, rax
    mov rsi, r15
    call doc_array2
    GROUP_RAX
    DPUSH rax
    # dangling comments before `=>`
4:  xor edi, edi
    xor esi, esi
    lea rdx, [rip + paf_comment_before_arrow]
    xor ecx, ecx
    call print_dangling_comments_ex
    test rax, rax
    jz 5f
    mov r14, rax
    DPUSHL ps_space
    DPUSH r14
5:  DARRAY r12
    EPILOGUE
ENDF paf_print_signature

# paf_comment_before_arrow(ctx, comment) -> eax: the next non-space,
# non-comment text after the comment is "=>"
FUNC paf_comment_before_arrow
    mov edi, [rsi + CM_END]
    call next_nonspace_noncomment_index
    mov r8, IDX_FALSE
    cmp rax, r8
    je 8f
    lea rcx, [rax + 2]
    cmp rcx, [rip + g_text_len]
    ja 8f
    mov rcx, [rip + g_text]
    cmp byte ptr [rcx + rax], '='
    jne 8f
    cmp byte ptr [rcx + rax + 1], '>'
    jne 8f
    mov eax, 1
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF paf_comment_before_arrow

# paf_should_add_parens_if_not_break(node) -> eax (shouldAddParensIfNotBreak)
FUNC paf_should_add_parens_if_not_break
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ConditionalExpression
    jne 9f
    lea rsi, [rip + paf_is_object_expression]
    xor edx, edx
    call pjs_starts_with_no_lookahead_token
    xor eax, 1
9:  leave
    ret
ENDF paf_should_add_parens_if_not_break

FUNC paf_is_object_expression
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_ObjectExpression
    sete al
    leave
    ret
ENDF paf_is_object_expression

# paf_may_break_after_short_prefix(functionBody, bodyDoc) -> eax
FUNC paf_may_break_after_short_prefix
    push rbx
    push r12
    mov rbx, rdi
    mov eax, 1
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_ArrayExpression
    je 9f
    cmp ecx, T_ObjectExpression
    je 9f
    cmp ecx, T_ArrowFunctionExpression
    je 9f
    cmp ecx, T_BlockStatement
    je 9f
    # bodyDoc.label?.hug !== false && (bodyDoc.label?.embed || isTemplateOnItsOwnLine)
    xor r12d, r12d                  # label bits
    test rsi, rsi
    jz 1f
    cmp byte ptr [rsi], DK_LABEL
    jne 1f
    mov r12, [rsi + DL_LABEL]
1:  xor eax, eax
    test r12, LB_HUG_FALSE
    jnz 9f
    mov eax, 1
    test r12, LB_EMBED
    jnz 9f
    mov rdi, rbx
    call pjs_is_template_on_its_own_line
9:  pop r12
    pop rbx
    leave
    ret
ENDF paf_may_break_after_short_prefix

# paf_join_signatures(vec, from) -> rax: join([" =>", line], vec.slice(from))
FUNC paf_join_signatures
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [rbx]
    sub rdi, r12
    lea rdi, [rdi*8 + 8]
    call alloc
    mov rcx, [rbx]
    sub rcx, r12
    mov [rax], rcx
    xor edx, edx
1:  cmp rdx, rcx
    jae 2f
    lea r8, [rdx + r12]
    mov r8, [rbx + 8 + r8*8]
    mov [rax + 8 + rdx*8], r8
    inc rdx
    jmp 1b
2:  mov rdi, [rip + arrow_line]
    mov rsi, rax
    call doc_join
    pop r12
    pop rbx
    leave
    ret
ENDF paf_join_signatures

# paf_print_signatures(state) -> rax (printArrowFunctionSignatures)
FUNC paf_print_signatures
    PROLOGUE
    mov r13, rdi
    mov rbx, [r13 + AS_SIGS]
    cmp qword ptr [rbx], 1
    jne 1f
    mov rax, [rbx + 8]
    jmp 99f
1:  xor r15d, r15d
    cmp qword ptr [r13 + AS_BREAK_CHAIN], 0
    je 2f
    mov r15d, GF_BREAK
2:  call path_key
    mov r12d, eax
    call path_parent
    mov r14, rax
    mov rdi, r14
    call pjs_is_call_like_expression
    test eax, eax
    jz 3f
    cmp r12d, K_callee
    jne 4f
    jmp 6f
3:  mov rdi, r14
    call pjs_is_binaryish
    test eax, eax
    jz 5f
    # group([sigs[0], " =>", indent([line, join([" =>", line], sigs.slice(1))])])
4:  mov rdi, rbx
    mov esi, 1
    call paf_join_signatures
    lea rdi, [rip + d_line]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov rdi, [rbx + 8]
    lea rsi, [rip + sd_arrow]
    mov rdx, rax
    call doc_array3
    jmp 8f
5:  mov rax, [r13 + AS_ARGS]
    cmp byte ptr [rax + ARGS_ASSIGNMENT_LAYOUT], 0
    jne 6f
    mov rdi, rbx
    xor esi, esi
    call paf_join_signatures
    INDENT_RAX
    jmp 8f
6:  mov rdi, rbx
    xor esi, esi
    call paf_join_signatures
8:  mov rdi, rax
    mov esi, r15d
    xor edx, edx
    call doc_group_ex
99: EPILOGUE
ENDF paf_print_signatures

# paf_print_body(state, shouldPutBodyOnSameLine) -> rax (printArrowFunctionBody)
FUNC paf_print_body
    PROLOGUE 2
    mov r13, rdi
    mov [rsp], rsi
    call path_value
    mov rbx, rax
    mov r12, [r13 + AS_ARGS]
    # bodyComments: the trailing comments in reverse rec order (unshift)
    DMARK r14
    mov rcx, [r13 + AS_COMMENTS]
    mov rdx, [rcx]
1:  test rdx, rdx
    jz 2f
    mov rdi, [rcx + rdx*8]
    call ss_push
    dec rdx
    jmp 1b
2:  DARRAY r14
    mov r14, rax                    # bodyComments
    # trailingComma
    xor r15d, r15d
    cmp byte ptr [r12 + ARGS_EXPAND_LAST_ARG], 0
    je 3f
    mov edi, 1
    call pjs_should_print_comma
    test eax, eax
    jz 3f
    lea rdi, [rip + ps_comma]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r15, rax
3:  mov [rsp + 8], r15              # trailingComma
    # trailingSpace
    xor r15d, r15d
    cmp byte ptr [r12 + ARGS_EXPAND_LAST_ARG], 0
    je 4f
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 4f
    lea r15, [rip + d_softline]
4:  mov rbx, [r13 + AS_BODY_DOC]
    cmp qword ptr [rsp], 0
    je 20f
    mov rdi, [r13 + AS_FUNCTION_BODY]
    call paf_should_add_parens_if_not_break
    test eax, eax
    jz 10f
    # [" ", group([ifBreak("", "("), indent([softline, body]), ifBreak("", ")"),
    #  trailingComma, trailingSpace]), bodyComments]
    lea rdi, [rip + d_softline]
    mov rsi, rbx
    call doc_array2
    INDENT_RAX
    mov rbx, rax
    DMARK r12
    xor edi, edi
    lea rsi, [rip + ps_lparen]
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DPUSH rbx
    xor edi, edi
    lea rsi, [rip + ps_rparen]
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DPUSH [rsp + 8]
    DPUSH r15
    DARRAY r12
    GROUP_RAX
    mov rbx, rax
    # [" ", body, bodyComments]
10: lea rdi, [rip + ps_space]
    mov rsi, rbx
    mov rdx, r14
    call doc_array3
    jmp 99f
    # [indent([line, body, bodyComments]), trailingComma, trailingSpace]
20: lea rdi, [rip + d_line]
    mov rsi, rbx
    mov rdx, r14
    call doc_array3
    INDENT_RAX
    mov rdi, rax
    mov rsi, [rsp + 8]
    mov rdx, r15
    call doc_array3
99: EPILOGUE
ENDF paf_print_body
