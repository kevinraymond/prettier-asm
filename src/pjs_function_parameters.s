# print/function-parameters.js. The Flow shorthand case and `rest` cannot
# match babel-ts nodes. getReturnTypeNode reads a TS signature's return type
# as typescript-estree's `returnType`, unwrapped, as Prettier's CLI sees it.
.include "pjs.inc"

    .section .rodata
s_module: .asciz "module"
s_exports: .asciz "exports"
    .balign 8
decorated_function_match: .quad pfp_m_arrow_block, pfp_m_decorator_call, pfp_m_decorated_target, pfp_m_single_const
    .text

# pjs_print_function_parameters(expand_arg, print_type_params) -> rax doc
# (printFunctionParameters); the function is the path's top
FUNC pjs_print_function_parameters
    PROLOGUE 4
    mov [rsp], rdi                  # expandArg
    mov qword ptr [rsp + 16], 0     # typeParams
    test esi, esi
    jz 1f
    call pjs_print_function_type_parameters
    mov [rsp + 16], rax
1:  call path_value
    mov rbx, rax
    mov rdi, rbx
    call pjs_get_function_parameters
    mov r12, rax                    # parameters
    cmp qword ptr [r12], 0
    jne 10f
    # [typeParams, "(", printDanglingComments(path, options, { filter }), ")"]
    xor edi, edi
    xor esi, esi
    lea rdx, [rip + pfp_comment_before_paren]
    xor ecx, ecx
    call print_dangling_comments_ex
    mov r13, rax
    DMARK r14
    DPUSH [rsp + 16]
    DPUSHL ps_lparen
    DPUSH r13
    DPUSHL ps_rparen
    DARRAY r14
    jmp 99f

10: call path_parent
    mov rdi, rax
    xor esi, esi
    call pjs_is_test_call
    mov r13d, eax                   # isParametersInTestCall
    mov rdi, rbx
    call pjs_should_hug_the_only_function_parameter
    mov r14d, eax                   # shouldHugParameters
    # printed
    DMARK r15
    xor ecx, ecx
    mov [rsp + 8], rcx              # index
11: mov rsi, [rsp + 8]
    mov rdi, r12
    mov edx, K_params
    xor ecx, ecx
    call print_elem
    DPUSH rax
    mov rax, [rsp + 8]
    inc rax
    cmp rax, [r12]
    jae 15f
    DPUSHL ps_comma
    mov eax, r13d
    or eax, r14d
    jz 12f
    DPUSHL ps_space
    jmp 14f
12: mov rax, [rsp + 8]
    mov rdi, [r12 + 8 + rax*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 13f
    DPUSHL d_hardline
    DPUSHL d_hardline
    jmp 14f
13: DPUSHL d_line
14: inc qword ptr [rsp + 8]
    jmp 11b
15: DARRAYK r15
    mov r15, rax                    # printed (array)

    cmp qword ptr [rsp], 0
    je 20f
    call pfp_is_decorated_function
    test eax, eax
    jnz 20f
    # group([removeLines(typeParams), "(", removeLines(printed), ")"])
    mov rdi, [rsp + 16]
    call will_break
    test eax, eax
    jnz 151f
    mov rdi, r15
    call will_break
    test eax, eax
    jz 16f
151: call pjs_throw_arg_expansion_bailout   # throw new ArgExpansionBailout()
16: mov rdi, [rsp + 16]
    call remove_lines
    mov [rsp + 24], rax
    mov rdi, r15
    call remove_lines
    mov r15, rax
    DMARK r14
    DPUSH [rsp + 24]
    DPUSHL ps_lparen
    DPUSH r15
    DPUSHL ps_rparen
    DARRAY r14
    GROUP_RAX
    jmp 99f

    # hugged without parameter decorators, or in a test call:
    # [typeParams, "(", ...printed, ")"]
20: test r14d, r14d
    jz 21f
    mov rdi, r12
    call pfp_has_parameter_decorator
    test eax, eax
    jz 22f
21: test r13d, r13d
    jz 30f
22: DMARK r14
    DPUSH [rsp + 16]
    DPUSHL ps_lparen
    DPUSH r15
    DPUSHL ps_rparen
    DARRAY r14
    jmp 99f

    # ["(", indent([softline, ...printed]), ifBreak(","), softline, ")"]
30: lea rdi, [rip + d_softline]
    mov rsi, r15
    call doc_array2
    INDENT_RAX
    mov r13, rax
    xor r14d, r14d
    mov rdi, rbx
    call pjs_has_rest_parameter
    test eax, eax
    jnz 31f
    mov edi, 1
    call pjs_should_print_comma
    test eax, eax
    jz 31f
    lea r14, [rip + ps_comma]
31: mov rdi, r14
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r14, rax
    DMARK r15
    DPUSH [rsp + 16]
    DPUSHL ps_lparen
    DPUSH r13
    DPUSH r14
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r15
99: EPILOGUE
ENDF pjs_print_function_parameters

# pfp_has_parameter_decorator(parameters) -> eax: some parameter has decorators
FUNC pfp_has_parameter_decorator
    xor eax, eax
    mov rcx, [rdi]
1:  test rcx, rcx
    jz 9f
    mov rdx, [rdi + rcx*8]
    dec rcx
    movzx r8d, word ptr [rdx + N_TYPE]
    cmp r8d, T_Identifier
    je 2f
    cmp r8d, T_TSParameterProperty
    je 2f
    cmp r8d, T_ObjectPattern
    je 2f
    cmp r8d, T_ArrayPattern
    je 2f
    cmp r8d, T_AssignmentPattern
    je 2f
    cmp r8d, T_RestElement
    jne 1b
2:  mov rdx, [rdx + N_F6]
    test rdx, rdx
    jz 1b
    cmp qword ptr [rdx], 0
    je 1b
    mov eax, 1
9:  leave
    ret
ENDF pfp_has_parameter_decorator

# pfp_comment_before_paren(ctx, comment) -> eax:
# getNextNonSpaceNonCommentCharacter(text, locEnd(comment)) === ")"
FUNC pfp_comment_before_paren
    mov edi, [rsi + CM_END]
    call next_nonspace_noncomment_char
    xor ecx, ecx
    cmp rax, ')'
    sete cl
    mov eax, ecx
    leave
    ret
ENDF pfp_comment_before_paren

# pfp_is_decorated_function() -> eax (isDecoratedFunction)
FUNC pfp_is_decorated_function
    lea rdi, [rip + decorated_function_match]
    mov esi, 4
    call path_match
    leave
    ret
ENDF pfp_is_decorated_function

# node.type === "ArrowFunctionExpression" && node.body.type === "BlockStatement"
FUNC pfp_m_arrow_block
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ArrowFunctionExpression
    jne 9f
    mov rcx, [rdi + N_F2]
    cmp word ptr [rcx + N_TYPE], T_BlockStatement
    sete al
9:  leave
    ret
ENDF pfp_m_arrow_block

# a call with this one argument whose callee is a call of a decorator: an
# Identifier or a non-computed `a.b` of Identifiers
FUNC pfp_m_decorator_call
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_CallExpression
    jne 9f
    cmp esi, K_arguments
    jne 9f
    mov rcx, [rdi + N_F1]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 1
    jne 9f
    mov rcx, [rdi + N_F0]
    cmp word ptr [rcx + N_TYPE], T_CallExpression
    jne 9f
    mov rcx, [rcx + N_F0]           # decorator
    cmp word ptr [rcx + N_TYPE], T_Identifier
    je 8f
    cmp word ptr [rcx + N_TYPE], T_MemberExpression
    jne 9f
    test dword ptr [rcx + N_ATTR], NA_COMPUTED
    jnz 9f
    mov rdx, [rcx + N_F0]
    cmp word ptr [rdx + N_TYPE], T_Identifier
    jne 9f
    mov rdx, [rcx + N_F1]
    cmp word ptr [rdx + N_TYPE], T_Identifier
    jne 9f
8:  mov eax, 1
9:  leave
    ret
ENDF pfp_m_decorator_call

# the init of a declarator, an export default declaration, the expression of
# `export =`, or the right of `module.exports = ...`
FUNC pfp_m_decorated_target
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov eax, 1
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_VariableDeclarator
    jne 1f
    cmp esi, K_init
    je 9f
    jmp 8f
1:  cmp ecx, T_ExportDefaultDeclaration
    jne 11f
    cmp esi, K_declaration
    je 9f
    jmp 8f
11: cmp ecx, T_TSExportAssignment
    jne 2f
    cmp esi, K_expression
    je 9f
    jmp 8f
2:  cmp ecx, T_AssignmentExpression
    jne 8f
    cmp esi, K_right
    jne 8f
    mov rbx, [rbx + N_F0]           # left
    cmp word ptr [rbx + N_TYPE], T_MemberExpression
    jne 8f
    mov rdi, [rbx + N_F0]
    lea rsi, [rip + s_module]
    call pjs_ident_is
    test eax, eax
    jz 9f
    mov rdi, [rbx + N_F1]
    lea rsi, [rip + s_exports]
    call pjs_ident_is
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pfp_m_decorated_target

# node.type !== "VariableDeclaration" || (node.kind === "const" &&
# node.declarations.length === 1)
FUNC pfp_m_single_const
    mov eax, 1
    cmp word ptr [rdi + N_TYPE], T_VariableDeclaration
    jne 9f
    xor eax, eax
    cmp qword ptr [rdi + N_F1], KD_CONST
    jne 9f
    mov rcx, [rdi + N_F0]
    cmp qword ptr [rcx], 1
    sete al
9:  leave
    ret
ENDF pfp_m_single_const

# pjs_should_hug_the_only_function_parameter(function) -> eax
# (shouldHugTheOnlyFunctionParameter); function may be 0
FUNC pjs_should_hug_the_only_function_parameter
    push rbx
    sub rsp, 8
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov rcx, [rdi + N_F1]
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 1
    jne 9f
    mov rbx, [rcx + 8]
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp ecx, T_ObjectPattern
    je 7f
    cmp ecx, T_ArrayPattern
    je 7f
    cmp ecx, T_Identifier
    jne 3f
    mov rax, [rbx + N_F5]
    test rax, rax
    jz 8f
    cmp word ptr [rax + N_TYPE], T_TSTypeAnnotation
    jne 8f
    mov rdi, [rax + N_F5]
    call pjs_is_object_type
    jmp 9f
3:  cmp ecx, T_AssignmentPattern
    jne 8f
    mov rax, [rbx + N_F0]
    movzx ecx, word ptr [rax + N_TYPE]
    cmp ecx, T_ObjectPattern
    je 1f
    cmp ecx, T_ArrayPattern
    jne 8f
1:  mov rax, [rbx + N_F1]
    movzx ecx, word ptr [rax + N_TYPE]
    cmp ecx, T_Identifier
    je 7f
    cmp ecx, T_ObjectExpression
    je 2f
    cmp ecx, T_ArrayExpression
    jne 8f
2:  mov rax, [rax + N_F0]           # properties, elements
    VLEN rcx, rax
    test rcx, rcx
    jnz 8f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_should_hug_the_only_function_parameter

# pjs_get_return_type_node(function) -> rax (getReturnTypeNode): F5 (returnType,
# or a TS signature's typeAnnotation, which typescript-estree calls returnType),
# unwrapped from its TSTypeAnnotation; 0 for none
FUNC pjs_get_return_type_node
    mov rax, [rdi + N_F5]
    test rax, rax
    jz 9f
    cmp word ptr [rax + N_TYPE], T_TSTypeAnnotation
    jne 9f
    mov rax, [rax + N_F5]
9:  leave
    ret
ENDF pjs_get_return_type_node

# pjs_should_group_function_parameters(function, return_type_doc) -> eax
# (shouldGroupFunctionParameters)
FUNC pjs_should_group_function_parameters
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call pjs_get_return_type_node
    mov r13, rax
    test r13, r13
    jz 8f
    mov rax, [rbx + N_F4]           # typeParameters
    test rax, rax
    jz 2f
    mov rax, [rax + N_F0]           # params
    VLEN rcx, rax
    cmp rcx, 1
    ja 8f
    jb 2f
    mov rax, [rax + 8]
    cmp qword ptr [rax + N_F1], 0   # constraint
    jne 8f
    cmp qword ptr [rax + N_F2], 0   # default
    jne 8f
2:  mov rdi, rbx
    call pjs_get_function_parameters
    cmp qword ptr [rax], 1
    jne 8f
    mov rdi, r13
    call pjs_is_object_type
    test eax, eax
    jnz 9f
    mov rdi, r12
    call will_break
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_should_group_function_parameters

# pjs_should_break_function_parameters(function) -> eax
# (shouldBreakFunctionParameters): more than one parameter, one of them a
# TSParameterProperty
FUNC pjs_should_break_function_parameters
    push rbx
    sub rsp, 8
    call pjs_get_function_parameters
    mov rcx, [rax]
    xor edx, edx
    cmp rcx, 1
    jbe 9f
1:  mov r8, [rax + rcx*8]
    cmp word ptr [r8 + N_TYPE], T_TSParameterProperty
    je 8f
    dec rcx
    jnz 1b
    jmp 9f
8:  mov edx, 1
9:  mov eax, edx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_should_break_function_parameters
