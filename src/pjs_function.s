# print/function.js. A method's value is the method node itself (Babel has no
# FunctionExpression under ObjectMethod, ClassMethod or TSDeclareMethod), so
# isMethodValue never holds in printFunction; typescript-estree's
# MethodDefinition prints its value through printMethodValue, which reads the
# same fields here. Flow's `predicate` does not occur.
.include "pjs.inc"

SDOC sd_async_sp, "async "
SDOC sd_function_sp, "function "
SDOC sd_function_star_sp, "function* "
SDOC sd_return, "return"
SDOC sd_throw, "throw"
SDOC sd_if_break_lparen, "("
SDOC sd_if_break_rparen, ")"

    .text

# pjs_print_function(node, args) -> rax doc (printFunction): FunctionDeclaration,
# FunctionExpression, TSDeclareFunction
FUNC pjs_print_function
    PROLOGUE 2
    mov rbx, rdi
    mov r12, rsi
    xor r14d, r14d                  # expandArg
    TYPE rbx, T_TSDeclareFunction
    je 2f
    test r12, r12
    jz 2f
    cmp byte ptr [r12 + ARGS_EXPAND_LAST_ARG], 0
    je 2f
    call path_parent
    mov r13, rax
    mov rdi, r13
    call pjs_is_call_expression
    test eax, eax
    jz 2f
    mov rdi, r13
    call pjs_get_call_arguments
    cmp qword ptr [rax], 1
    ja 1f
    # every parameter is an Identifier without a type annotation
    mov rcx, [rbx + N_F1]
    xor edx, edx
    test rcx, rcx
    jz 1f
3:  cmp rdx, [rcx]
    jae 1f
    mov rax, [rcx + 8 + rdx*8]
    inc rdx
    TYPE rax, T_Identifier
    jne 2f
    cmp qword ptr [rax + N_F5], 0
    je 3b
    jmp 2f
1:  mov r14d, 1
2:  DMARK r13
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    ATTR rbx, NA_ASYNC
    jz 4f
    DPUSHL sd_async_sp
4:  lea rdi, [rip + sd_function_sp]
    ATTR rbx, NA_GENERATOR
    jz 5f
    lea rdi, [rip + sd_function_star_sp]
5:  call ss_push
    cmp qword ptr [rbx + N_F0], 0
    je 6f
    PRINT N_F0, K_id
    DPUSH rax
6:  mov edi, r14d
    xor esi, esi
    call pjs_print_function_parameters
    mov r14, rax                    # parametersDoc
    call pjs_print_return_type
    mov r15, rax                    # returnTypeDoc
    mov rdi, rbx
    mov rsi, r15
    call pjs_should_group_function_parameters
    test eax, eax
    jz 7f
    mov rdi, r14
    xor esi, esi
    call doc_group
    mov r14, rax
7:  call pjs_print_function_type_parameters
    DPUSH rax
    mov rdi, r14
    mov rsi, r15
    call doc_array2
    GROUP_RAX
    DPUSH rax
    cmp qword ptr [rbx + N_F2], 0
    je 8f
    DPUSHL ps_space
    PRINT N_F2, K_body
    DPUSH rax
    # options.semi && (node.declare || !node.body)
    ATTR rbx, NA_DECLARE
    jz 9f
8:  call pjs_semi_doc
    DPUSH rax
9:  DARRAY r13
    EPILOGUE
ENDF pjs_print_function

# pjs_print_method(node, args) -> rax doc (printMethod)
FUNC pjs_print_method
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rax, [rbx + N_F3]           # kind
    cmp rax, KD_GET
    je 1f
    cmp rax, KD_SET
    je 1f
    ATTR rbx, NA_ASYNC
    jz 2f
    DPUSHL sd_async_sp
    jmp 2f
1:  mov rdi, rax
    call pjs_code_doc
    DPUSH rax
    DPUSHL ps_space
2:  ATTR rbx, NA_GENERATOR
    jz 3f
    DPUSHL ps_star
3:  mov rdi, rbx
    call pjs_print_property_key
    DPUSH rax
    ATTR rbx, NA_OPTIONAL
    jz 4f
    DPUSHL ps_question
4:  call pjs_print_method_value
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_method

# pjs_print_method_value() -> rax doc (printMethodValue) for the method at the
# top of the path: [typeParams, group([parametersDoc, returnTypeDoc]),
# body ? [" ", print("body")] : semi]
FUNC pjs_print_method_value
    PROLOGUE
    call path_value
    mov rbx, rax
    xor edi, edi
    xor esi, esi
    call pjs_print_function_parameters
    mov r12, rax                    # parametersDoc
    call pjs_print_return_type
    mov r13, rax                    # returnTypeDoc
    mov rdi, rbx
    call pjs_should_break_function_parameters
    test eax, eax
    jz 1f
    mov rdi, r12
    mov esi, 1
    call doc_group
    mov r12, rax
    jmp 2f
1:  mov rdi, rbx
    mov rsi, r13
    call pjs_should_group_function_parameters
    test eax, eax
    jz 2f
    mov rdi, r12
    xor esi, esi
    call doc_group
    mov r12, rax
2:  DMARK r14
    call pjs_print_function_type_parameters
    DPUSH rax
    mov rdi, r12
    mov rsi, r13
    call doc_array2
    GROUP_RAX
    DPUSH rax
    cmp qword ptr [rbx + N_F2], 0
    je 3f
    DPUSHL ps_space
    PRINT N_F2, K_body
    DPUSH rax
    jmp 4f
3:  call pjs_semi_doc
    DPUSH rax
4:  DARRAY r14
    EPILOGUE
ENDF pjs_print_method_value

# pjs_print_return_type() -> rax (printReturnType) for the node at the path's
# top: printTypeAnnotationProperty(path, print, "returnType")
FUNC pjs_print_return_type
    mov edi, N_F5
    mov esi, K_returnType
    call pjs_print_type_annotation_property
    leave
    ret
ENDF pjs_print_return_type

# pjs_should_print_params_without_parens() -> eax (shouldPrintParamsWithoutParens)
FUNC pjs_should_print_params_without_parens
    PROLOGUE
    xor eax, eax
    cmp qword ptr [rip + g_arrow_parens], AP_AVOID
    jne 9f
    call path_value
    mov rbx, rax
    # canPrintParamsWithoutParens
    mov rcx, [rbx + N_F1]
    xor eax, eax
    test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 1
    jne 9f
    mov r12, [rcx + 8]
    cmp qword ptr [rbx + N_F4], 0   # typeParameters
    jne 8f
    cmp qword ptr [rbx + N_F5], 0   # returnType
    jne 8f
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    TYPE r12, T_Identifier
    jne 8f
    cmp qword ptr [r12 + N_F5], 0   # typeAnnotation
    jne 8f
    ATTR r12, NA_OPTIONAL
    jnz 8f
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    call has_comment
    xor eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_should_print_params_without_parens

# pjs_print_return_statement(node, args) -> rax: ["return", printReturnOrThrowArgument]
FUNC pjs_print_return_statement
    lea rsi, [rip + sd_return]
    call pfn_print_return_or_throw
    leave
    ret
ENDF pjs_print_return_statement

# pjs_print_throw_statement(node, args) -> rax: ["throw", printReturnOrThrowArgument]
FUNC pjs_print_throw_statement
    lea rsi, [rip + sd_throw]
    call pfn_print_return_or_throw
    leave
    ret
ENDF pjs_print_throw_statement

# pfn_print_return_or_throw(node, keyword_doc) -> rax:
# [keyword, printReturnOrThrowArgument(path, options, print)]
FUNC pfn_print_return_or_throw
    PROLOGUE
    mov rbx, rdi
    mov r13, rsi
    DMARK r12
    mov r14, [rbx + N_F0]           # argument
    test r14, r14
    jz 5f
    PRINT N_F0, K_argument
    mov r15, rax
    mov rdi, r14
    call pfn_return_argument_has_leading_comment
    test eax, eax
    jz 2f
    # ["(", indent([hardline, argumentDoc]), hardline, ")"]
    lea rdi, [rip + d_hardline]
    mov rsi, r15
    call doc_array2
    INDENT_RAX
    mov r15, rax
    DMARK r14
    DPUSHL ps_lparen
    DPUSH r15
    DPUSHL d_hardline
    DPUSHL ps_rparen
    DARRAY r14
    mov r15, rax
    jmp 4f
2:  mov rdi, r14
    call pjs_is_binaryish
    test eax, eax
    jnz 21f
    cmp qword ptr [rip + g_experimental_ternaries], 0
    je 4f
    cmp word ptr [r14 + N_TYPE], T_ConditionalExpression
    jne 4f
    mov rax, [r14 + N_F1]
    cmp word ptr [rax + N_TYPE], T_ConditionalExpression
    je 21f
    mov rax, [r14 + N_F2]
    cmp word ptr [rax + N_TYPE], T_ConditionalExpression
    jne 4f
21:
    # group([ifBreak("("), indent([softline, argumentDoc]), softline, ifBreak(")")])
    lea rdi, [rip + d_softline]
    mov rsi, r15
    call doc_array2
    INDENT_RAX
    mov r15, rax
    DMARK r14
    lea rdi, [rip + sd_if_break_lparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DPUSH r15
    DPUSHL d_softline
    lea rdi, [rip + sd_if_break_rparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DARRAY r14
    GROUP_RAX
    mov r15, rax
4:  lea rdi, [rip + ps_space]
    mov rsi, r15
    call doc_array2
    DPUSH rax
    # semi and dangling comments
5:  call pjs_semi_doc
    mov r15, rax                    # semi
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    mov r14d, eax                   # hasDanglingComments
    xor ecx, ecx                    # shouldPrintSemiBeforeComments
    test r15, r15
    jz 6f
    test r14d, r14d
    jz 6f
    mov rdi, rbx
    mov esi, CC_Last | CC_Line
    xor edx, edx
    call has_comment
    mov ecx, eax
6:  push rcx
    push rcx
    test ecx, ecx
    jz 7f
    DPUSH r15
7:  test r14d, r14d
    jz 8f
    DPUSHL ps_space
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
8:  pop rcx
    pop rcx
    test ecx, ecx
    jnz 9f
    DPUSH r15
9:  DARRAY r12
    mov rdi, r13
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pfn_print_return_or_throw

# pfn_comment_has_newline(comment) -> eax: hasNewlineInRange(text, locStart, locEnd)
FUNC pfn_comment_has_newline
    mov esi, [rdi + CM_END]
    mov edi, [rdi + CM_START]
    call has_newline_in_range
    leave
    ret
ENDF pfn_comment_has_newline

# pfn_get_left_side(node) -> rax: getLeftSide for any node, 0 for undefined
FUNC pfn_get_left_side
    xor eax, eax
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_SequenceExpression
    je 1f
    cmp ecx, T_TemplateLiteral
    je 2f
    .irp t, T_AssignmentExpression, T_BinaryExpression, T_LogicalExpression, T_AssignmentPattern, T_ConditionalExpression, T_CallExpression, T_OptionalCallExpression, T_NewExpression, T_MemberExpression, T_OptionalMemberExpression, T_TaggedTemplateExpression, T_UnaryExpression, T_UpdateExpression, T_AwaitExpression, T_YieldExpression, T_SpreadElement, T_RestElement, T_ParenthesizedExpression
    cmp ecx, \t
    je 3f
    .endr
    jmp 9f
1:  mov rcx, [rdi + N_F0]
    jmp 4f
2:  mov rcx, [rdi + N_F1]
4:  test rcx, rcx
    jz 9f
    cmp qword ptr [rcx], 0
    je 9f
    mov rax, [rcx + 8]
    jmp 9f
3:  mov rax, [rdi + N_F0]
9:  leave
    ret
ENDF pfn_get_left_side

# pfn_return_argument_has_leading_comment(argument) -> eax
# (returnArgumentHasLeadingComment)
FUNC pfn_return_argument_has_leading_comment
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call pjs_has_leading_own_line_comment
    test eax, eax
    jnz 9f
    mov rdi, rbx
    mov esi, CC_Leading
    lea rdx, [rip + pfn_comment_has_newline]
    call has_comment
    test eax, eax
    jnz 9f
    mov rdi, rbx
    call pjs_has_naked_left_side
    test eax, eax
    jz 9f
1:  mov rdi, rbx
    call pfn_get_left_side
    test rax, rax
    jz 9f
    mov rbx, rax
    mov rdi, rax
    call pjs_has_leading_own_line_comment
    test eax, eax
    jz 1b
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pfn_return_argument_has_leading_comment
