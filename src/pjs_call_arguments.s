# print/call-arguments.js
.include "pjs.inc"

SDOC sd_comma_space, ", "

    .data
    .balign 8
# print(selector, {expandFirstArg: true}) and {expandLastArg: true}
pca_args_first: .byte 1, 0, 0, 0, 0, 0, 0, 0
pca_args_last:  .byte 0, 1, 0, 0, 0, 0, 0, 0

    .bss
    .balign 8
g_pca_catch: .quad 0            # innermost ArgExpansionBailout catch frame

    .text

# allArgsBrokenOut() inside pjs_print_call_arguments: r13 printedArguments,
# [rsp + 8] maybeTrailingComma
.macro BROKEN_OUT
    mov rdi, r13
    mov rsi, [rsp + 8]
    call pca_all_args_broken_out
.endm

# pjs_throw_arg_expansion_bailout(): throw new ArgExpansionBailout(). Unwinds
# to the innermost pjs_try_print_call_argument, restoring the path and the
# scratch stack; without one, Prettier would report an error.
FUNC pjs_throw_arg_expansion_bailout
    mov rax, [rip + g_pca_catch]
    test rax, rax
    jz 90f
    mov rcx, [rax]
    mov [rip + g_pca_catch], rcx
    mov rcx, [rax + 32]
    mov [rip + g_path_top], rcx
    mov rcx, [rax + 40]
    mov [rip + g_ss_ptr], rcx
    mov rsp, [rax + 8]
    mov rbp, [rax + 16]
    jmp [rax + 24]
90: REFUSE "printer: ArgExpansionBailout outside call arguments"
ENDF pjs_throw_arg_expansion_bailout

# pjs_try_print_call_argument(index, args) -> rax doc, edx 1 when the print
# threw ArgExpansionBailout (try { print(getCallArgumentSelector(node, index), args) })
FUNC pjs_try_print_call_argument
    PROLOGUE 6
    mov rax, [rip + g_pca_catch]
    mov [rsp], rax
    mov [rsp + 8], rsp
    mov [rsp + 16], rbp
    lea rax, [rip + 1f]
    mov [rsp + 24], rax
    mov rax, [rip + g_path_top]
    mov [rsp + 32], rax
    mov rax, [rip + g_ss_ptr]
    mov [rsp + 40], rax
    mov [rip + g_pca_catch], rsp
    call pjs_print_call_argument
    mov rcx, [rsp]
    mov [rip + g_pca_catch], rcx
    xor edx, edx
    EPILOGUE
1:  xor eax, eax
    mov edx, 1
    EPILOGUE
ENDF pjs_try_print_call_argument

# pjs_print_call_arguments() -> rax doc (printCallArguments); the call is the path's top
FUNC pjs_print_call_arguments
    PROLOGUE 6
    call path_value
    mov rbx, rax
    mov rdi, rbx
    call pjs_get_call_arguments
    mov r12, rax                    # args
    mov r14, [r12]                  # args.length
    test r14, r14
    jnz 1f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    lea rdi, [rip + ps_lparen]
    mov rsi, rax
    lea rdx, [rip + ps_rparen]
    call doc_array3
    jmp 99f
1:  mov rdi, r12
    call pca_is_react_hook_call_with_deps_array
    test eax, eax
    jz 3f
    # ["(", print(), ", ", print(), ..., ")"]
    DMARK r13
    DPUSHL ps_lparen
    xor r15d, r15d
2:  mov rdi, r15
    xor esi, esi
    call pjs_print_call_argument
    DPUSH rax
    inc r15
    cmp r15, r14
    jae 21f
    DPUSHL sd_comma_space
    jmp 2b
21: DPUSHL ps_rparen
    DARRAY r13
    jmp 99f

    # printedArguments
3:  mov qword ptr [rsp], 0          # anyArgEmptyLine
    DMARK r13
    xor r15d, r15d
4:  mov rdi, r15
    xor esi, esi
    call pjs_print_call_argument
    mov [rsp + 16], rax
    lea rax, [r15 + 1]
    cmp rax, r14
    je 6f
    mov rdi, [r12 + 8 + r15*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 5f
    mov qword ptr [rsp], 1
    DMARK rax
    mov [rsp + 24], rax
    DPUSH [rsp + 16]
    DPUSHL ps_comma
    DPUSHL d_hardline
    DPUSHL d_hardline
    mov rdi, [rsp + 24]
    call ss_to_array
    mov [rsp + 16], rax
    jmp 6f
5:  mov rdi, [rsp + 16]
    lea rsi, [rip + ps_comma]
    lea rdx, [rip + d_line]
    call doc_array3
    mov [rsp + 16], rax
6:  DPUSH [rsp + 16]
    inc r15
    cmp r15, r14
    jb 4b
    mov rdi, r13
    call ss_to_vec
    mov r13, rax                    # printedArguments
    # maybeTrailingComma
    mov qword ptr [rsp + 8], 0
    TYPE rbx, T_ImportExpression
    je 7f
    TYPE rbx, T_TSImportType
    je 7f
    mov edi, 1
    call pjs_should_print_comma
    test eax, eax
    jz 7f
    lea rax, [rip + ps_comma]
    mov [rsp + 8], rax
    # a TSImportType of one string: group(["(", ...printedArguments, ifBreak(maybeTrailingComma), ")"])
7:  TYPE rbx, T_TSImportType
    jne 72f
    cmp r14, 1
    jne 72f
    mov r15, [r12 + 8]
    TYPE r15, T_StringLiteral
    je 73f
    TYPE r15, T_TSLiteralType
    jne 72f
    mov rax, [r15 + N_F0]
    TYPE rax, T_StringLiteral
    jne 72f
73: mov rdi, r15
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 72f
    mov rdi, [rsp + 8]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r15, rax
    DMARK rax
    mov [rsp + 16], rax
    DPUSHL ps_lparen
    DPUSH [r13 + 8]
    DPUSH r15
    DPUSHL ps_rparen
    mov rdi, [rsp + 16]
    call ss_to_array
    GROUP_RAX
    jmp 99f
72: cmp qword ptr [rsp], 0
    jne 80f
    call path_parent
    TYPE rax, T_Decorator
    je 71f
    mov rdi, r12
    call pjs_is_function_composition_args
    test eax, eax
    jnz 80f
71:

    mov rdi, r12
    call pca_should_expand_first_arg
    test eax, eax
    jz 30f
    # tailArgs = printedArguments.slice(1)
    mov rdi, r13
    mov esi, 1
    mov rdx, r14
    call pca_some_will_break
    test eax, eax
    jnz 80f
    xor edi, edi
    lea rsi, [rip + pca_args_first]
    call pjs_try_print_call_argument
    test edx, edx
    jnz 80f
    mov r15, rax                    # firstArg
    mov rdi, r15
    mov esi, 1
    call doc_group
    mov [rsp + 16], rax             # group(firstArg, {shouldBreak: true})
    mov rdi, r15
    call will_break
    test eax, eax
    jz 20f
    DMARK rax
    mov [rsp + 24], rax
    mov rdi, [rsp + 16]
    mov rsi, r13
    call pca_first_state
    DPUSH rax
    BROKEN_OUT
    DPUSH rax
    mov rdi, [rsp + 24]
    call ss_to_array
    jmp 70f
20: DMARK rax
    mov [rsp + 24], rax
    mov rdi, r15
    mov rsi, r13
    call pca_first_state
    DPUSH rax
    mov rdi, [rsp + 16]
    mov rsi, r13
    call pca_first_state
    DPUSH rax
    BROKEN_OUT
    DPUSH rax
    mov rdi, [rsp + 24]
    call ss_to_array
    jmp 75f

30: mov rdi, r12
    mov rsi, r13
    call pca_should_expand_last_arg
    test eax, eax
    jz 50f
    # headArgs = printedArguments.slice(0, -1)
    mov rdi, r13
    xor esi, esi
    lea rdx, [r14 - 1]
    call pca_some_will_break
    test eax, eax
    jnz 80f
    mov rdi, -1
    lea rsi, [rip + pca_args_last]
    call pjs_try_print_call_argument
    test edx, edx
    jnz 80f
    mov r15, rax                    # lastArg
    mov rdi, r15
    mov esi, 1
    call doc_group
    mov [rsp + 16], rax
    mov rdi, r15
    call will_break
    test eax, eax
    jz 40f
    DMARK rax
    mov [rsp + 24], rax
    mov rdi, [rsp + 16]
    mov rsi, r13
    call pca_last_state
    DPUSH rax
    BROKEN_OUT
    DPUSH rax
    mov rdi, [rsp + 24]
    call ss_to_array
    jmp 70f
40: DMARK rax
    mov [rsp + 24], rax
    mov rdi, r15
    mov rsi, r13
    call pca_last_state
    DPUSH rax
    mov rdi, [rsp + 16]
    mov rsi, r13
    call pca_last_state
    DPUSH rax
    BROKEN_OUT
    DPUSH rax
    mov rdi, [rsp + 24]
    call ss_to_array
    jmp 75f

    # ["(", indent([softline, ...printedArguments]), ifBreak(maybeTrailingComma), softline, ")"]
50: DMARK r15
    DPUSHL d_softline
    xor ecx, ecx
51: cmp rcx, r14
    jae 52f
    mov [rsp + 16], rcx
    DPUSH [r13 + 8 + rcx*8]
    mov rcx, [rsp + 16]
    inc rcx
    jmp 51b
52: DARRAY r15
    INDENT_RAX
    mov [rsp + 16], rax
    mov rdi, [rsp + 8]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov [rsp + 24], rax
    DMARK r15
    DPUSHL ps_lparen
    DPUSH [rsp + 16]
    DPUSH [rsp + 24]
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r15
    mov [rsp + 16], rax
    call pjs_is_long_curried_call_expression
    test eax, eax
    jz 53f
    mov rax, [rsp + 16]
    jmp 99f
53: mov rdi, r13
    xor esi, esi
    mov rdx, r14
    call pca_some_will_break
    mov esi, eax
    mov rdi, [rsp + 16]
    call doc_group
    jmp 99f

    # [breakParent, conditionalGroup(states)]
70: mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_conditional_group
    lea rdi, [rip + d_break_parent]
    mov rsi, rax
    call doc_array2
    jmp 99f
    # conditionalGroup(states)
75: mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_conditional_group
    jmp 99f
80: BROKEN_OUT
99: EPILOGUE

ENDF pjs_print_call_arguments

# pca_all_args_broken_out(printedArguments, maybeTrailingComma) -> rax:
# group(["(", indent([line, ...printedArguments]), maybeTrailingComma, line, ")"],
# {shouldBreak: true})
FUNC pca_all_args_broken_out
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    DMARK r13
    DPUSHL d_line
    xor r14d, r14d
1:  cmp r14, [rbx]
    jae 2f
    DPUSH [rbx + 8 + r14*8]
    inc r14
    jmp 1b
2:  DARRAY r13
    INDENT_RAX
    mov r14, rax
    DMARK r13
    DPUSHL ps_lparen
    DPUSH r14
    DPUSH r12
    DPUSHL d_line
    DPUSHL ps_rparen
    DARRAY r13
    GROUP_BREAK_RAX
    EPILOGUE
ENDF pca_all_args_broken_out

# pca_first_state(first_doc, printedArguments) -> rax: ["(", first, ", ", ...tailArgs, ")"]
FUNC pca_first_state
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    DMARK r13
    DPUSHL ps_lparen
    DPUSH rbx
    DPUSHL sd_comma_space
    mov r14d, 1
1:  cmp r14, [r12]
    jae 2f
    DPUSH [r12 + 8 + r14*8]
    inc r14
    jmp 1b
2:  DPUSHL ps_rparen
    DARRAY r13
    EPILOGUE
ENDF pca_first_state

# pca_last_state(last_doc, printedArguments) -> rax: ["(", ...headArgs, last, ")"]
FUNC pca_last_state
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    DMARK r13
    DPUSHL ps_lparen
    mov r15, [r12]
    dec r15
    xor r14d, r14d
1:  cmp r14, r15
    jae 2f
    DPUSH [r12 + 8 + r14*8]
    inc r14
    jmp 1b
2:  DPUSH rbx
    DPUSHL ps_rparen
    DARRAY r13
    EPILOGUE
ENDF pca_last_state

# pca_some_will_break(vec, from, to) -> eax: vec.slice(from, to).some(willBreak)
FUNC pca_some_will_break
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  xor eax, eax
    cmp r12, r13
    jae 9f
    mov rdi, [rbx + 8 + r12*8]
    inc r12
    call will_break
    test eax, eax
    jz 1b
9:  EPILOGUE
ENDF pca_some_will_break

# pca_could_expand_arg(arg, arrow_chain_recursion) -> eax (couldExpandArg)
FUNC pca_could_expand_arg
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ObjectExpression
    je 1f
    cmp eax, T_ArrayExpression
    je 1f
    cmp eax, T_FunctionExpression
    je 7f
    cmp eax, T_TSTypeAssertion
    je 3f
    cmp eax, T_TSAsExpression
    je 3f
    cmp eax, T_TSSatisfiesExpression
    je 3f
    cmp eax, T_ArrowFunctionExpression
    jne 8f
    # an arrow function whose return type is not a type reference (or whose
    # body is a non-empty block) with an expandable body
    mov rax, [rbx + N_F5]
    test rax, rax
    jz 4f
    mov rax, [rax + N_F5]
    test rax, rax
    jz 4f
    TYPE rax, T_TSTypeReference
    jne 4f
    mov rdi, [rbx + N_F2]
    call pca_is_non_empty_block_statement
    test eax, eax
    jz 8f
4:  mov r13, [rbx + N_F2]
    movzx eax, word ptr [r13 + N_TYPE]
    cmp eax, T_BlockStatement
    je 7f
    cmp eax, T_ObjectExpression
    je 7f
    cmp eax, T_ArrayExpression
    je 7f
    cmp eax, T_ArrowFunctionExpression
    jne 2f
    mov rdi, r13
    mov esi, 1
    call pca_could_expand_arg
    test eax, eax
    jnz 7f
    jmp 8f
2:  test r12d, r12d
    jnz 8f
    cmp eax, T_ConditionalExpression
    je 7f
    mov rdi, r13
    call pjs_is_call_expression
    jmp 9f
    # an object or array with entries or comments
1:  mov rax, [rbx + N_F0]
    VLEN rcx, rax
    test rcx, rcx
    jnz 7f
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    jmp 9f
    # a cast of an expandable expression
3:  mov rdi, [rbx + N_F0]
    xor esi, esi
    call pca_could_expand_arg
    jmp 9f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pca_could_expand_arg

# pca_is_non_empty_block_statement(node) -> eax (isNonEmptyBlockStatement)
FUNC pca_is_non_empty_block_statement
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    TYPE rbx, T_BlockStatement
    jne 9f
    mov rcx, [rbx + N_F0]
    VLEN rdx, rcx
1:  test rdx, rdx
    jz 2f
    mov r8, [rcx + rdx*8]
    dec rdx
    TYPE r8, T_EmptyStatement
    je 1b
    mov eax, 1
    jmp 9f
2:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pca_is_non_empty_block_statement

# pca_should_expand_last_arg(args, printedArguments) -> eax (shouldExpandLastArg)
FUNC pca_should_expand_last_arg
    PROLOGUE
    mov rbx, rdi
    mov r14, [rbx]                  # args.length
    mov r12, [rbx + r14*8]          # lastArg
    xor r13d, r13d                  # penultimateArg
    cmp r14, 2
    jb 1f
    mov r13, [rbx + r14*8 - 8]
1:  cmp r14, 1
    jne 2f
    mov rdi, [rsi + 8]
    call pjs_doc_label_bits
    test eax, LB_EMBED
    jz 2f
    test eax, LB_HUG_FALSE
    jz 7f
2:  mov rdi, r12
    mov esi, CC_Leading
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    mov rdi, r12
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    mov rdi, r12
    xor esi, esi
    call pca_could_expand_arg
    test eax, eax
    jz 8f
    test r13, r13
    jz 3f
    mov ax, [r13 + N_TYPE]
    cmp ax, [r12 + N_TYPE]
    je 8f
3:  cmp r14, 2
    jne 4f
    TYPE r13, T_ArrowFunctionExpression
    jne 4f
    TYPE r12, T_ArrayExpression
    je 8f
4:  cmp r14, 1
    jbe 7f
    TYPE r12, T_ArrayExpression
    jne 7f
    mov rdi, r12
    call pjs_is_concisely_printed_array
    test eax, eax
    jnz 8f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pca_should_expand_last_arg

# pca_should_expand_first_arg(args) -> eax (shouldExpandFirstArg)
FUNC pca_should_expand_first_arg
    PROLOGUE
    xor eax, eax
    cmp qword ptr [rdi], 2
    jne 9f
    mov rbx, [rdi + 8]
    mov r12, [rdi + 16]
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    TYPE rbx, T_FunctionExpression
    je 1f
    TYPE rbx, T_ArrowFunctionExpression
    jne 8f
    mov rax, [rbx + N_F2]
    TYPE rax, T_BlockStatement
    jne 8f
1:  movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_FunctionExpression
    je 8f
    cmp eax, T_ArrowFunctionExpression
    je 8f
    cmp eax, T_ConditionalExpression
    je 8f
    mov rdi, r12
    call pca_is_hopefully_short_call_argument
    test eax, eax
    jz 8f
    mov rdi, r12
    xor esi, esi
    call pca_could_expand_arg
    xor eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pca_should_expand_first_arg

# pca_is_hopefully_short_call_argument(node) -> eax (isHopefullyShortCallArgument)
FUNC pca_is_hopefully_short_call_argument
    PROLOGUE
    mov rbx, rdi
1:  TYPE rbx, T_ParenthesizedExpression
    jne 2f
    mov rbx, [rbx + N_F0]
    jmp 1b
2:  mov rdi, rbx
    call pjs_is_binary_cast_expression
    test eax, eax
    jz 21f
    # isSimpleType(typeAnnotation, unwrapped from up to two TSArrayTypes and
    # a one-argument TSTypeReference) && isSimpleCallArgument(expression, 1)
    mov r12, [rbx + N_F5]
    TYPE r12, T_TSArrayType
    jne 11f
    mov r12, [r12 + N_F0]
    TYPE r12, T_TSArrayType
    jne 11f
    mov r12, [r12 + N_F0]
11: TYPE r12, T_TSTypeReference
    jne 12f
    mov rax, [r12 + N_F4]
    test rax, rax
    jz 12f
    mov rax, [rax + N_F0]
    VLEN rcx, rax
    cmp rcx, 1
    jne 12f
    mov r12, [rax + 8]
12: mov rdi, r12
    call pjs_is_simple_type
    test eax, eax
    jz 9f
    mov rdi, [rbx + N_F0]
    mov esi, 1
    call pjs_is_simple_call_argument
    jmp 9f
21: mov rdi, rbx
    call pjs_is_call_like_expression
    test eax, eax
    jz 3f
    mov rdi, rbx
    call pjs_get_call_arguments
    cmp qword ptr [rax], 1
    ja 8f
3:  mov rdi, rbx
    call pjs_is_binaryish
    test eax, eax
    jz 4f
    mov rdi, [rbx + N_F0]
    mov esi, 1
    call pjs_is_simple_call_argument
    test eax, eax
    jz 9f
    mov rdi, [rbx + N_F1]
    mov esi, 1
    call pjs_is_simple_call_argument
    jmp 9f
4:  mov eax, 1
    TYPE rbx, T_RegExpLiteral
    je 9f
    mov rdi, rbx
    mov esi, 2
    call pjs_is_simple_call_argument
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pca_is_hopefully_short_call_argument

# pca_is_react_hook_call_with_deps_array(args) -> eax
FUNC pca_is_react_hook_call_with_deps_array
    PROLOGUE
    mov rbx, rdi
    mov rax, [rbx]
    cmp rax, 2
    jne 1f
    xor esi, esi
    jmp 2f
1:  cmp rax, 3
    jne 8f
    mov rax, [rbx + 8]
    TYPE rax, T_Identifier
    jne 8f
    mov esi, 1
    # isValidHookCallbackAndDepsFormat(args, baseIndex)
2:  mov r12, [rbx + 8 + rsi*8]
    mov r13, [rbx + 16 + rsi*8]
    TYPE r12, T_ArrowFunctionExpression
    jne 8f
    mov rax, [r12 + N_F1]
    VLEN rcx, rax
    test rcx, rcx
    jnz 8f
    mov rax, [r12 + N_F2]
    TYPE rax, T_BlockStatement
    jne 8f
    TYPE r13, T_ArrayExpression
    jne 8f
    xor r14d, r14d
3:  cmp r14, [rbx]
    jae 7f
    mov rdi, [rbx + 8 + r14*8]
    inc r14
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    jmp 3b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pca_is_react_hook_call_with_deps_array
