# src/language-js/utils/index.js and the small utils/*.js files, for the node
# types the babel and babel-ts parsers produce. Predicates take the node in rdi
# and return eax 0 or 1; a node pointer of 0 is undefined. Flow and JSX
# predicates are always false for these types and are not ported.
.include "pjs.inc"

# TYPESET name, types...: name(node) -> eax: node.type is one of the types
.macro TYPESET name, types:vararg
FUNC \name
    xor eax, eax
    test rdi, rdi
    jz 9f
    movzx ecx, word ptr [rdi + N_TYPE]
    .irp t, \types
    cmp ecx, \t
    je 1f
    .endr
    jmp 9f
1:  mov eax, 1
9:  leave
    ret
ENDF \name
.endm

TYPESET pjs_is_export_declaration, T_ExportDefaultDeclaration, T_ExportNamedDeclaration, T_ExportAllDeclaration
TYPESET pjs_is_array_expression, T_ArrayExpression
TYPESET pjs_is_object_expression, T_ObjectExpression
TYPESET pjs_is_numeric_literal, T_NumericLiteral
TYPESET pjs_is_boolean_literal, T_BooleanLiteral
TYPESET pjs_is_string_literal, T_StringLiteral
TYPESET pjs_is_regexp_literal, T_RegExpLiteral
TYPESET pjs_is_literal, T_BooleanLiteral, T_BigIntLiteral, T_DirectiveLiteral, T_NullLiteral, T_NumericLiteral, T_RegExpLiteral, T_StringLiteral
TYPESET pjs_is_single_word_type, T_Identifier, T_ThisExpression, T_Super, T_PrivateName
TYPESET pjs_is_function_or_arrow_expression, T_FunctionExpression, T_ArrowFunctionExpression
TYPESET pjs_is_binaryish, T_BinaryExpression, T_LogicalExpression
TYPESET pjs_is_call_expression, T_CallExpression, T_OptionalCallExpression
TYPESET pjs_is_member_expression, T_MemberExpression, T_OptionalMemberExpression
TYPESET pjs_is_memberish, T_MemberExpression, T_OptionalMemberExpression
TYPESET pjs_is_call_like_expression, T_CallExpression, T_OptionalCallExpression, T_NewExpression, T_ImportExpression
TYPESET pjs_is_object_property, T_ObjectProperty
TYPESET pjs_is_method_type, T_ObjectMethod, T_ClassMethod, T_ClassPrivateMethod
TYPESET pjs_is_object_type, T_TSTypeLiteral, T_TSMappedType
TYPESET pjs_is_union_type, T_TSUnionType
TYPESET pjs_is_intersection_type, T_TSIntersectionType
TYPESET pjs_is_conditional_type, T_TSConditionalType
TYPESET pjs_is_binary_cast_expression, T_TSAsExpression, T_TSSatisfiesExpression
TYPESET pjs_is_simple_type_annotation, T_TSThisType, T_TSLiteralType

# pjs_is_ts_keyword_type(node) -> eax (isTsKeywordType)
FUNC pjs_is_ts_keyword_type
    xor eax, eax
    test rdi, rdi
    jz 9f
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_TSAnyKeyword
    jb 9f
    cmp ecx, T_TSVoidKeyword
    ja 9f
    mov eax, 1
9:  leave
    ret
ENDF pjs_is_ts_keyword_type

# pjs_is_simple_type(node) -> eax (isSimpleType)
FUNC pjs_is_simple_type
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    test rdi, rdi
    jz 9f
    call pjs_is_ts_keyword_type
    test eax, eax
    jnz 9f
    mov rdi, rbx
    call pjs_is_simple_type_annotation
    test eax, eax
    jnz 9f
    cmp word ptr [rbx + N_TYPE], T_TSTypeReference
    jne 9f
    cmp qword ptr [rbx + N_F4], 0
    sete al
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_is_simple_type

# pjs_has_naked_left_side(node) -> eax (hasNakedLeftSide)
FUNC pjs_has_naked_left_side
    movzx ecx, word ptr [rdi + N_TYPE]
    mov eax, 1
    cmp ecx, T_AssignmentExpression
    je 9f
    cmp ecx, T_BinaryExpression
    je 9f
    cmp ecx, T_LogicalExpression
    je 9f
    cmp ecx, T_ConditionalExpression
    je 9f
    cmp ecx, T_CallExpression
    je 9f
    cmp ecx, T_OptionalCallExpression
    je 9f
    cmp ecx, T_MemberExpression
    je 9f
    cmp ecx, T_OptionalMemberExpression
    je 9f
    cmp ecx, T_SequenceExpression
    je 9f
    cmp ecx, T_TaggedTemplateExpression
    je 9f
    cmp ecx, T_TSAsExpression
    je 9f
    cmp ecx, T_TSSatisfiesExpression
    je 9f
    cmp ecx, T_TSNonNullExpression
    je 9f
    xor eax, eax
    cmp ecx, T_UpdateExpression
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_PREFIX
    setz al
9:  leave
    ret
ENDF pjs_has_naked_left_side

# pjs_get_left_side(node) -> rax (getLeftSide) for a node with a naked left
# side; edx its key, ecx its index (-1 unless expressions[0]), r8 the array.
FUNC pjs_get_left_side
    mov ecx, -1
    xor r8d, r8d
    movzx eax, word ptr [rdi + N_TYPE]
    cmp eax, T_SequenceExpression
    je 5f
    mov edx, K_left
    cmp eax, T_AssignmentExpression
    je 8f
    cmp eax, T_BinaryExpression
    je 8f
    cmp eax, T_LogicalExpression
    je 8f
    mov edx, K_test
    cmp eax, T_ConditionalExpression
    je 8f
    mov edx, K_object
    cmp eax, T_MemberExpression
    je 8f
    cmp eax, T_OptionalMemberExpression
    je 8f
    mov edx, K_callee
    cmp eax, T_CallExpression
    je 8f
    cmp eax, T_OptionalCallExpression
    je 8f
    cmp eax, T_NewExpression
    je 8f
    mov edx, K_tag
    cmp eax, T_TaggedTemplateExpression
    je 8f
    mov edx, K_argument
    cmp eax, T_UpdateExpression
    je 8f
    cmp eax, T_UnaryExpression
    je 8f
    cmp eax, T_AwaitExpression
    je 8f
    cmp eax, T_SpreadElement
    je 8f
    mov edx, K_expression
    cmp eax, T_ParenthesizedExpression
    je 8f
    cmp eax, T_TSAsExpression
    je 8f
    cmp eax, T_TSSatisfiesExpression
    je 8f
    cmp eax, T_TSNonNullExpression
    je 8f
    cmp eax, T_TSTypeAssertion
    je 8f
    cmp eax, T_TSInstantiationExpression
    je 8f
    cmp eax, T_ExpressionStatement
    je 8f
    REFUSE "printer: getLeftSide of a node without a left side"
5:  mov r8, [rdi + N_F0]
    mov rax, [r8 + 8]
    mov edx, K_expressions
    xor ecx, ecx
    leave
    ret
8:  mov rax, [rdi + N_F0]
    leave
    ret
ENDF pjs_get_left_side

# pjs_call_left_side(fn, ctx) -> rax: path.call(fn, ...getLeftSidePathName(node))
# for the node at the top of the path; fn(ctx, child, index).
FUNC pjs_call_left_side
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call path_value
    mov rdi, rax
    call pjs_get_left_side
    mov r13, rax
    mov r14d, ecx
    mov rdi, rax
    mov esi, edx
    mov edx, ecx
    mov rcx, r8
    call path_push
    mov rdi, r12
    mov rsi, r13
    movsxd rdx, r14d
    call rbx
    mov rbx, rax
    call path_pop
    mov rax, rbx
    EPILOGUE
ENDF pjs_call_left_side

# pjs_is_nullish_coalescing(node) -> eax
FUNC pjs_is_nullish_coalescing
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_LogicalExpression
    jne 9f
    cmp qword ptr [rdi + N_F2], J_NULLISH
    sete al
9:  leave
    ret
ENDF pjs_is_nullish_coalescing

# pjs_is_signed_numeric_literal(node) -> eax
FUNC pjs_is_signed_numeric_literal
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_UnaryExpression
    jne 9f
    mov rcx, [rdi + N_F1]
    cmp rcx, '+'
    je 1f
    cmp rcx, '-'
    jne 9f
1:  mov rcx, [rdi + N_F0]
    cmp word ptr [rcx + N_TYPE], T_NumericLiteral
    sete al
9:  leave
    ret
ENDF pjs_is_signed_numeric_literal

# pjs_is_function_or_arrow_expression_with_body(node) -> eax
FUNC pjs_is_function_or_arrow_expression_with_body
    mov eax, 1
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_FunctionExpression
    je 9f
    xor eax, eax
    cmp ecx, T_ArrowFunctionExpression
    jne 9f
    mov rcx, [rdi + N_F2]
    cmp word ptr [rcx + N_TYPE], T_BlockStatement
    sete al
9:  leave
    ret
ENDF pjs_is_function_or_arrow_expression_with_body

# pjs_is_method(node) -> eax (isMethod): kind "get" or "set" (Babel has no
# "init" kind)
FUNC pjs_is_method
    xor eax, eax
    call pjs_is_method_type
    test eax, eax
    jz 9f
    xor eax, eax
    mov rcx, [rdi + N_F3]
    cmp rcx, KD_GET
    je 1f
    cmp rcx, KD_SET
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pjs_is_method

# pjs_ident_name(node) -> rax ptr, rdx len: an Identifier's name (F7 is its
# length when the range takes in `?` or a type annotation, F0 is 1 + its offset
# when the range starts at modifiers); another node's source text
FUNC pjs_ident_name
    mov eax, [rdi + N_START]
    mov edx, [rdi + N_END]
    sub edx, eax
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 2f
    mov rcx, [rdi + N_F7]
    test rcx, rcx
    jz 1f
    mov edx, ecx
1:  mov rcx, [rdi + N_F0]
    test rcx, rcx
    jz 2f
    lea eax, [rcx - 1]
2:  add rax, [rip + g_text]
    leave
    ret
ENDF pjs_ident_name

# pjs_name_eq(node, ptr, len) -> eax: the node's name (pjs_ident_name) is the string
FUNC pjs_name_eq
    push rbx
    push r12
    mov rbx, rsi
    mov r12, rdx
    call pjs_ident_name
    mov rdi, rax
    xor eax, eax
    cmp rdx, r12
    jne 9f
    mov rsi, rbx
    call mem_eq
9:  pop r12
    pop rbx
    leave
    ret
ENDF pjs_name_eq

# pjs_ident_is(node, cstr) -> eax: node is an Identifier named cstr
FUNC pjs_ident_is
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    test rbx, rbx
    jz 9f
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 9f
    mov rdi, r12
    call strlen
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    call pjs_name_eq
9:  pop r12
    pop rbx
    leave
    ret
ENDF pjs_ident_is

# pjs_ident_in(node, list) -> eax: node is an Identifier named one of the
# strings in a 0-terminated list of cstr pointers
FUNC pjs_ident_in
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
1:  mov rsi, [r12]
    xor eax, eax
    test rsi, rsi
    jz 9f
    mov rdi, rbx
    call pjs_ident_is
    test eax, eax
    jnz 9f
    add r12, 8
    jmp 1b
9:  pop r12
    pop rbx
    leave
    ret
ENDF pjs_ident_in

    .section .rodata
s_async: .asciz "async"
s_inject: .asciz "inject"
s_fake_async: .asciz "fakeAsync"
s_wait_for_async: .asciz "waitForAsync"
s_before_each: .asciz "beforeEach"
s_before_all: .asciz "beforeAll"
s_after_each: .asciz "afterEach"
s_after_all: .asciz "afterAll"
    .balign 8
angular_wrappers: .quad s_async, s_inject, s_fake_async, s_wait_for_async, 0
unit_test_setup: .quad s_before_each, s_before_all, s_after_each, s_after_all, 0
.macro TCP p
    .pushsection .rodata.str, "a"
.Ltcp\@: .asciz "\p"
    .popsection
    .quad .Ltcp\@
.endm
test_call_callee_patterns:
    .irp p, "it", "it.only", "it.skip", "describe", "describe.only", "describe.skip", "test", "test.only", "test.skip", "test.step", "test.describe", "test.describe.only", "test.describe.parallel", "test.describe.parallel.only", "test.describe.serial", "test.describe.serial.only", "skip", "xit", "xdescribe", "xtest", "fit", "fdescribe", "ftest"
    TCP \p
    .endr
    .quad 0
    .text

# pjs_is_angular_test_wrapper(node) -> eax
FUNC pjs_is_angular_test_wrapper
    xor eax, eax
    call pjs_is_call_expression
    test eax, eax
    jz 9f
    mov rdi, [rdi + N_F0]
    lea rsi, [rip + angular_wrappers]
    call pjs_ident_in
9:  leave
    ret
ENDF pjs_is_angular_test_wrapper

# pjs_is_unit_test_setup_identifier(node) -> eax
FUNC pjs_is_unit_test_setup_identifier
    lea rsi, [rip + unit_test_setup]
    call pjs_ident_in
    leave
    ret
ENDF pjs_is_unit_test_setup_identifier

# node_matches_path(node, cstr) -> eax (isNodeMatchesNameOrPath): "a.b.c"
# matches the member chain a.b.c, without computed or optional links
FUNC node_matches_path
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    mov r13, rax                    # end of the current name
1:  mov r14, r13                    # start of the current name
2:  test r14, r14
    jz 3f
    cmp byte ptr [r12 + r14 - 1], '.'
    je 4f
    dec r14
    jmp 2b
    # the first name: an Identifier
3:  xor eax, eax
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 9f
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call pjs_name_eq
    jmp 9f
    # a later name: a non-computed, non-optional member with that property
4:  xor eax, eax
    cmp word ptr [rbx + N_TYPE], T_MemberExpression
    jne 9f
    test dword ptr [rbx + N_ATTR], NA_COMPUTED | NA_OPTIONAL
    jnz 9f
    mov rdi, [rbx + N_F1]
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 9f
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call pjs_name_eq
    test eax, eax
    jz 9f
    mov rbx, [rbx + N_F0]
    lea r13, [r14 - 1]
    jmp 1b
9:  EPILOGUE
ENDF node_matches_path

# pjs_is_test_call_callee(node) -> eax
FUNC pjs_is_test_call_callee
    push rbx
    push r12
    mov rbx, rdi
    lea r12, [rip + test_call_callee_patterns]
1:  mov rsi, [r12]
    xor eax, eax
    test rsi, rsi
    jz 9f
    mov rdi, rbx
    call node_matches_path
    test eax, eax
    jnz 9f
    add r12, 8
    jmp 1b
9:  pop r12
    pop rbx
    leave
    ret
ENDF pjs_is_test_call_callee

# pjs_is_test_call(node, parent) -> eax (isTestCall); either may be 0
FUNC pjs_is_test_call
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    test rbx, rbx
    jz 9f
    cmp word ptr [rbx + N_TYPE], T_CallExpression
    jne 9f
    mov r13, [rbx + N_F1]           # arguments
    VLEN r14, r13
    cmp r14, 1
    jne 20f
    mov rdi, rbx
    call pjs_is_angular_test_wrapper
    test eax, eax
    jz 10f
    mov rdi, r12
    xor esi, esi
    call pjs_is_test_call
    test eax, eax
    jz 10f
    mov rdi, [r13 + 8]
    call pjs_is_function_or_arrow_expression
    jmp 9f
10: mov rdi, [rbx + N_F0]
    call pjs_is_unit_test_setup_identifier
    test eax, eax
    jz 8f
    mov rdi, [r13 + 8]
    call pjs_is_angular_test_wrapper
    jmp 9f
20: cmp r14, 2
    je 21f
    cmp r14, 3
    jne 8f
21: mov rdi, [r13 + 8]
    test rdi, rdi
    jz 8f
    cmp word ptr [rdi + N_TYPE], T_TemplateLiteral
    je 22f
    cmp word ptr [rdi + N_TYPE], T_StringLiteral
    jne 8f
22: mov rdi, [rbx + N_F0]
    call pjs_is_test_call_callee
    test eax, eax
    jz 8f
    cmp r14, 3
    jne 23f
    mov rdi, [r13 + 24]
    test rdi, rdi
    jz 23f
    cmp word ptr [rdi + N_TYPE], T_NumericLiteral
    jne 8f
23: mov r15, [r13 + 16]             # args[1]
    test r15, r15
    jz 8f
    mov rdi, r15
    cmp r14, 2
    jne 24f
    call pjs_is_function_or_arrow_expression
    jmp 25f
24: call pjs_is_function_or_arrow_expression_with_body
    test eax, eax
    jz 25f
    mov rdi, [r15 + N_F1]
    VLEN rax, rdi
    cmp rax, 1
    setbe al
    movzx eax, al
25: test eax, eax
    jnz 9f
    mov rdi, r15
    call pjs_is_angular_test_wrapper
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_is_test_call

# pjs_comment_newline_after(comment) -> eax: hasNewline(text, locEnd(comment))
FUNC pjs_comment_newline_after
    mov edi, [rdi + CM_END]
    xor esi, esi
    call has_newline
    leave
    ret
ENDF pjs_comment_newline_after

# pjs_has_leading_own_line_comment(node) -> eax (hasLeadingOwnLineComment)
FUNC pjs_has_leading_own_line_comment
    mov esi, CC_Leading
    lea rdx, [rip + pjs_comment_newline_after]
    call has_comment
    leave
    ret
ENDF pjs_has_leading_own_line_comment

# pjs_template_literal_has_newlines(template) -> eax (templateLiteralHasNewLines)
FUNC pjs_template_literal_has_newlines
    push rbx
    push r12
    mov rbx, [rdi + N_F0]           # quasis
    xor r12d, r12d
1:  xor eax, eax
    cmp r12, [rbx]
    jae 9f
    mov rax, [rbx + 8 + r12*8]
    inc r12
    mov edi, [rax + N_START]
    mov esi, [rax + N_END]
    call has_newline_in_range
    test eax, eax
    jz 1b
9:  pop r12
    pop rbx
    leave
    ret
ENDF pjs_template_literal_has_newlines

# pjs_is_template_on_its_own_line(node) -> eax (isTemplateOnItsOwnLine)
FUNC pjs_is_template_on_its_own_line
    push rbx
    sub rsp, 8
    mov rbx, rdi
    cmp word ptr [rbx + N_TYPE], T_TemplateLiteral
    je 1f
    xor eax, eax
    cmp word ptr [rbx + N_TYPE], T_TaggedTemplateExpression
    jne 9f
    mov rdi, [rbx + N_F1]
1:  call pjs_template_literal_has_newlines
    test eax, eax
    jz 9f
    mov edi, [rbx + N_START]
    mov esi, 1
    call has_newline
    xor eax, 1
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_is_template_on_its_own_line

# pjs_needs_hardline_after_dangling_comment(node) -> eax
FUNC pjs_needs_hardline_after_dangling_comment
    xor eax, eax
    cmp qword ptr [rdi + N_COMMENTS], 0
    je 9f
    mov esi, CC_Dangling
    xor edx, edx
    call get_comments
    mov rcx, [rax]
    test rcx, rcx
    jz 8f
    mov rax, [rax + rcx*8]
    cmp byte ptr [rax + CM_TYPE], CT_BLOCK
    setne al
    movzx eax, al
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF pjs_needs_hardline_after_dangling_comment

# pjs_get_call_arguments(node) -> rax VEC (getCallArguments)
FUNC pjs_get_call_arguments
    push rbx
    sub rsp, 8
    mov rbx, rdi
    cmp word ptr [rbx + N_TYPE], T_ImportExpression
    je 2f
    cmp word ptr [rbx + N_TYPE], T_TSImportType
    je 2f
    mov rax, [rbx + N_F1]
    test rax, rax
    jnz 9f
    lea rax, [rip + js_empty_vec]
    jmp 9f
    # [source (argument for TSImportType, the same slot), options?]
2:  mov edi, 24
    call alloc
    mov rcx, [rbx + N_F0]
    mov [rax + 8], rcx
    mov qword ptr [rax], 1
    mov rcx, [rbx + N_F1]
    test rcx, rcx
    jz 9f
    mov [rax + 16], rcx
    mov qword ptr [rax], 2
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_get_call_arguments

# pjs_get_function_parameters(node) -> rax VEC (getFunctionParameters)
FUNC pjs_get_function_parameters
    mov rax, [rdi + N_F1]
    test rax, rax
    jnz 1f
    lea rax, [rip + js_empty_vec]
1:  leave
    ret
ENDF pjs_get_function_parameters

# pjs_has_rest_parameter(node) -> eax
FUNC pjs_has_rest_parameter
    mov rcx, [rdi + N_F1]
    xor eax, eax
    test rcx, rcx
    jz 9f
    mov rdx, [rcx]
    test rdx, rdx
    jz 9f
    mov rcx, [rcx + rdx*8]
    cmp word ptr [rcx + N_TYPE], T_RestElement
    sete al
9:  leave
    ret
ENDF pjs_has_rest_parameter

# pjs_iterate_function_parameters_path(fn, ctx): path.each(fn, "params") for
# the function at the top of the path; fn(ctx, param, index)
FUNC pjs_iterate_function_parameters_path
    mov edx, K_params
    mov ecx, N_F1
    call path_each
    leave
    ret
ENDF pjs_iterate_function_parameters_path

# pjs_iterate_call_arguments_path(fn, ctx): iterateCallArgumentsPath for the
# call at the top of the path; fn(ctx, argument, index)
FUNC pjs_iterate_call_arguments_path
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call path_value
    mov r13, rax
    mov r14d, K_argument
    cmp word ptr [r13 + N_TYPE], T_TSImportType
    je 1f
    mov r14d, K_source
    cmp word ptr [r13 + N_TYPE], T_ImportExpression
    je 1f
    mov rdi, rbx
    mov rsi, r12
    mov edx, K_arguments
    mov ecx, N_F1
    call path_each
    jmp 9f
1:  mov rdi, [r13 + N_F0]
    mov esi, r14d
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    mov rsi, [r13 + N_F0]
    xor edx, edx
    call rbx
    call path_pop
    mov rsi, [r13 + N_F1]
    test rsi, rsi
    jz 9f
    mov rdi, rsi
    mov esi, K_options
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    mov rsi, [r13 + N_F1]
    mov edx, 1
    call rbx
    call path_pop
9:  EPILOGUE
ENDF pjs_iterate_call_arguments_path

# pjs_print_call_argument(index, args) -> rax: print(getCallArgumentSelector(node,
# index), args) for the call at the top of the path; a negative index counts
# from the end
FUNC pjs_print_call_argument
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    call path_value
    mov r13, rax
    cmp word ptr [r13 + N_TYPE], T_ImportExpression
    je 5f
    cmp word ptr [r13 + N_TYPE], T_TSImportType
    je 5f
    mov rdi, [r13 + N_F1]
    VLEN rcx, rdi
    test rbx, rbx
    jns 1f
    add rbx, rcx
1:  test rbx, rbx
    js 90f
    cmp rbx, rcx
    jae 90f
    mov rsi, rbx
    mov edx, K_arguments
    mov rcx, r12
    call print_elem
    jmp 9f
    # ImportExpression: [source, options?]
5:  xor ecx, ecx
    cmp qword ptr [r13 + N_F1], 0
    setne cl
    inc ecx                         # argument count
    test rbx, rbx
    jns 6f
    add rbx, rcx
6:  test rbx, rbx
    jz 7f
    cmp rbx, 1
    jne 90f
    cmp ecx, 2
    jne 90f
    mov edi, N_F1
    mov esi, K_options
    mov rdx, r12
    call print_field
    jmp 9f
7:  mov esi, K_source
    cmp word ptr [r13 + N_TYPE], T_TSImportType
    jne 71f
    mov esi, K_argument
71: mov edi, N_F0
    mov rdx, r12
    call print_field
9:  EPILOGUE
90: REFUSE "printer: Invalid argument index"
ENDF pjs_print_call_argument

# pjs_is_function_composition_args(vec) -> eax (isFunctionCompositionArgs)
FUNC pjs_is_function_composition_args
    PROLOGUE
    mov rbx, rdi
    VLEN r12, rbx
    xor eax, eax
    cmp r12, 1
    jbe 9f
    xor r13d, r13d                  # index
    xor r14d, r14d                  # count
1:  xor eax, eax
    cmp r13, r12
    jae 9f
    mov r15, [rbx + 8 + r13*8]
    inc r13
    mov rdi, r15
    call pjs_is_function_or_arrow_expression
    test eax, eax
    jz 2f
    inc r14
    cmp r14, 1
    jbe 1b
    mov eax, 1
    jmp 9f
2:  mov rdi, r15
    call pjs_is_call_expression
    test eax, eax
    jz 1b
    mov rdi, r15
    call pjs_get_call_arguments
    mov rcx, rax
    xor edx, edx
3:  cmp rdx, [rcx]
    jae 1b
    mov rdi, [rcx + 8 + rdx*8]
    inc rdx
    push rcx
    push rdx
    call pjs_is_function_or_arrow_expression
    pop rdx
    pop rcx
    test eax, eax
    jz 3b
9:  EPILOGUE
ENDF pjs_is_function_composition_args

# pjs_is_long_curried_call_expression() -> eax (isLongCurriedCallExpression)
FUNC pjs_is_long_curried_call_expression
    PROLOGUE
    xor eax, eax
    call path_key
    cmp eax, K_callee
    jne 8f
    call path_value
    mov rbx, rax
    call path_parent
    mov r12, rax
    mov rdi, rbx
    call pjs_is_call_expression
    test eax, eax
    jz 8f
    mov rdi, r12
    call pjs_is_call_expression
    test eax, eax
    jz 8f
    mov rdi, [r12 + N_F1]
    VLEN rcx, rdi
    test rcx, rcx
    jz 8f
    mov rdi, [rbx + N_F1]
    VLEN rdx, rdi
    xor eax, eax
    cmp rdx, rcx
    seta al
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_is_long_curried_call_expression

# pjs_is_simple_call_argument(node, depth) -> eax (isSimpleCallArgument)
FUNC pjs_is_simple_call_argument
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    test r12, r12
    jle 9f
    lea r13, [r12 - 1]              # depth of a child
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_TSNonNullExpression
    jne 10f
    mov rdi, [rbx + N_F0]
    mov rsi, r12
    call pjs_is_simple_call_argument
    jmp 9f
10: cmp eax, T_RegExpLiteral
    jne 1f
    mov rdi, [rbx + N_F0]
    mov rsi, [rbx + N_F1]
    call str_width
    cmp rax, 5
    setbe al
    movzx eax, al
    jmp 9f
1:  mov rdi, rbx
    call pjs_is_literal
    test eax, eax
    jnz 9f
    mov rdi, rbx
    call pjs_is_single_word_type
    test eax, eax
    jnz 9f
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_TemplateLiteral
    je 20f
    cmp eax, T_ObjectExpression
    je 30f
    cmp eax, T_ArrayExpression
    je 40f
    mov rdi, rbx
    call pjs_is_call_like_expression
    test eax, eax
    jnz 50f
    mov rdi, rbx
    call pjs_is_member_expression
    test eax, eax
    jnz 60f
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_UpdateExpression
    je 70f
    cmp eax, T_UnaryExpression
    jne 8f
    mov rax, [rbx + N_F1]
    cmp rax, '!'
    je 70f
    cmp rax, '-'
    je 70f
    cmp rax, '+'
    je 70f
    cmp rax, '~'
    jne 8f
70: mov rdi, [rbx + N_F0]
    mov rsi, r12
    call pjs_is_simple_call_argument
    jmp 9f
    # TemplateLiteral: no quasi has a newline, every expression is simple
20: mov r14, [rbx + N_F0]
    xor r15d, r15d
21: cmp r15, [r14]
    jae 22f
    mov rax, [r14 + 8 + r15*8]
    inc r15
    mov edi, [rax + N_START]
    mov esi, [rax + N_END]
    call has_newline_in_range
    test eax, eax
    jnz 8f
    jmp 21b
22: mov r14, [rbx + N_F1]
    jmp 41f
    # ObjectExpression: every property is a non-computed ObjectProperty,
    # shorthand or with a simple value
30: mov r14, [rbx + N_F0]
    xor r15d, r15d
31: cmp r15, [r14]
    jae 80f
    mov rax, [r14 + 8 + r15*8]
    inc r15
    cmp word ptr [rax + N_TYPE], T_ObjectProperty
    jne 8f
    test dword ptr [rax + N_ATTR], NA_COMPUTED
    jnz 8f
    test dword ptr [rax + N_ATTR], NA_SHORTHAND
    jnz 31b
    mov rdi, [rax + N_F1]
    mov rsi, r13
    call pjs_is_simple_call_argument
    test eax, eax
    jz 8f
    jmp 31b
    # ArrayExpression: holes or simple elements
40: mov r14, [rbx + N_F0]
41: xor r15d, r15d
    test r14, r14
    jz 80f
42: cmp r15, [r14]
    jae 80f
    mov rdi, [r14 + 8 + r15*8]
    inc r15
    test rdi, rdi
    jz 42b
    mov rsi, r13
    call pjs_is_simple_call_argument
    test eax, eax
    jz 8f
    jmp 42b
    # call-like: an import(), or a simple callee; at most depth simple arguments
50: cmp word ptr [rbx + N_TYPE], T_ImportExpression
    je 51f
    mov rdi, [rbx + N_F0]
    mov rsi, r12
    call pjs_is_simple_call_argument
    test eax, eax
    jz 8f
51: mov rdi, rbx
    call pjs_get_call_arguments
    mov r14, rax
    cmp [r14], r12
    jg 8f
    jmp 41b
60: mov rdi, [rbx + N_F0]
    mov rsi, r12
    call pjs_is_simple_call_argument
    test eax, eax
    jz 9f
    mov rdi, [rbx + N_F1]
    mov rsi, r12
    call pjs_is_simple_call_argument
    jmp 9f
80: mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_is_simple_call_argument

# pjs_should_print_comma(level) -> eax (shouldPrintComma): level 0 "es5", 1 "all"
FUNC pjs_should_print_comma
    mov rcx, [rip + g_trailing_comma]
    xor eax, eax
    cmp rcx, TC_ALL
    je 1f
    cmp rcx, TC_ES5
    jne 9f
    test edi, edi
    jnz 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pjs_should_print_comma

# pjs_starts_with_no_lookahead_token(node, pred, ctx) -> eax
# (startsWithNoLookaheadToken); pred(ctx, leftmost_node) -> eax
FUNC pjs_starts_with_no_lookahead_token
1:  movzx eax, word ptr [rdi + N_TYPE]
    cmp eax, T_BinaryExpression
    je 2f
    cmp eax, T_LogicalExpression
    je 2f
    cmp eax, T_AssignmentExpression
    je 2f
    cmp eax, T_MemberExpression
    je 2f
    cmp eax, T_OptionalMemberExpression
    je 2f
    cmp eax, T_ConditionalExpression
    je 2f
    cmp eax, T_TaggedTemplateExpression
    je 3f
    cmp eax, T_CallExpression
    je 3f
    cmp eax, T_OptionalCallExpression
    je 3f
    cmp eax, T_UpdateExpression
    je 4f
    cmp eax, T_SequenceExpression
    je 5f
    cmp eax, T_TSAsExpression
    je 2f
    cmp eax, T_TSSatisfiesExpression
    je 2f
    cmp eax, T_TSNonNullExpression
    je 2f
    mov rax, rsi
    mov rsi, rdi
    mov rdi, rdx
    call rax
    leave
    ret
2:  mov rdi, [rdi + N_F0]
    jmp 1b
3:  mov rdi, [rdi + N_F0]
    cmp word ptr [rdi + N_TYPE], T_FunctionExpression
    jne 1b
    xor eax, eax
    leave
    ret
4:  xor eax, eax
    test dword ptr [rdi + N_ATTR], NA_PREFIX
    jnz 9f
    mov rdi, [rdi + N_F0]
    jmp 1b
5:  mov rdi, [rdi + N_F0]
    mov rdi, [rdi + 8]
    jmp 1b
9:  leave
    ret
ENDF pjs_starts_with_no_lookahead_token

# pjs_is_node_same(ctx, node) -> eax: node === ctx, the usual predicate
FUNC pjs_is_node_same
    xor eax, eax
    cmp rdi, rsi
    sete al
    leave
    ret
ENDF pjs_is_node_same

# pjs_get_precedence(op) -> eax (getPrecedence); -1 for an operator without one
FUNC pjs_get_precedence
    mov eax, -1
    cmp edi, J_NULLISH
    jne 1f
    mov eax, 1
    jmp 9f
1:  cmp edi, J_OR2
    jne 2f
    mov eax, 2
    jmp 9f
2:  cmp edi, J_AND2
    jne 3f
    mov eax, 3
    jmp 9f
3:  cmp edi, '|'
    jne 4f
    mov eax, 4
    jmp 9f
4:  cmp edi, '^'
    jne 5f
    mov eax, 5
    jmp 9f
5:  cmp edi, '&'
    jne 6f
    mov eax, 6
    jmp 9f
6:  mov eax, 7
    cmp edi, J_EQ2
    je 9f
    cmp edi, J_EQ3
    je 9f
    cmp edi, J_NE
    je 9f
    cmp edi, J_NE2
    je 9f
    mov eax, 8
    cmp edi, '<'
    je 9f
    cmp edi, '>'
    je 9f
    cmp edi, J_LE
    je 9f
    cmp edi, J_GE
    je 9f
    cmp edi, J_IN
    je 9f
    cmp edi, J_INSTANCEOF
    je 9f
    mov eax, 9
    cmp edi, J_SHR
    je 9f
    cmp edi, J_SHL
    je 9f
    cmp edi, J_USHR
    je 9f
    mov eax, 10
    cmp edi, '+'
    je 9f
    cmp edi, '-'
    je 9f
    mov eax, 11
    cmp edi, '*'
    je 9f
    cmp edi, '/'
    je 9f
    cmp edi, '%'
    je 9f
    mov eax, 12
    cmp edi, J_EXP
    je 9f
    mov eax, -1
9:  leave
    ret
ENDF pjs_get_precedence

# is_equality_op(op), is_multiplicative_op(op), is_bitshift_op(op) -> eax
FUNC is_equality_op
    xor eax, eax
    cmp edi, J_EQ2
    je 1f
    cmp edi, J_EQ3
    je 1f
    cmp edi, J_NE
    je 1f
    cmp edi, J_NE2
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF is_equality_op

FUNC is_multiplicative_op
    xor eax, eax
    cmp edi, '*'
    je 1f
    cmp edi, '/'
    je 1f
    cmp edi, '%'
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF is_multiplicative_op

FUNC is_bitshift_op
    xor eax, eax
    cmp edi, J_SHR
    je 1f
    cmp edi, J_USHR
    je 1f
    cmp edi, J_SHL
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF is_bitshift_op

# pjs_should_flatten(parent_op, node_op) -> eax (shouldFlatten)
FUNC pjs_should_flatten
    PROLOGUE
    mov ebx, edi
    mov r12d, esi
    call pjs_get_precedence
    mov r13d, eax
    mov edi, r12d
    call pjs_get_precedence
    cmp eax, r13d
    jne 8f
    cmp ebx, J_EXP
    je 8f
    mov edi, ebx
    call is_equality_op
    mov r13d, eax
    mov edi, r12d
    call is_equality_op
    and eax, r13d
    jnz 8f
    mov edi, ebx
    call is_multiplicative_op
    mov r13d, eax                   # parent multiplicative
    mov edi, r12d
    call is_multiplicative_op
    mov r14d, eax                   # node multiplicative
    cmp r12d, '%'
    jne 1f
    test r13d, r13d
    jnz 8f
1:  cmp ebx, '%'
    jne 2f
    test r14d, r14d
    jnz 8f
2:  cmp ebx, r12d
    je 3f
    test r13d, r14d
    jnz 8f
3:  mov edi, ebx
    call is_bitshift_op
    mov r13d, eax
    mov edi, r12d
    call is_bitshift_op
    and eax, r13d
    jnz 8f
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_should_flatten

# pjs_is_bitwise_operator(op) -> eax
FUNC pjs_is_bitwise_operator
    call is_bitshift_op
    test eax, eax
    jnz 9f
    cmp edi, '|'
    je 1f
    cmp edi, '^'
    je 1f
    cmp edi, '&'
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pjs_is_bitwise_operator

# pjs_is_next_line_empty(node) -> eax (isNextLineEmpty)
FUNC pjs_is_next_line_empty
    mov edi, [rdi + N_END]
    call is_next_line_empty
    leave
    ret
ENDF pjs_is_next_line_empty

# pjs_raw(node) -> rax ptr, rdx len: the node's source text (getRaw: extra.raw)
FUNC pjs_raw
    mov eax, [rdi + N_START]
    mov edx, [rdi + N_END]
    sub edx, eax
    add rax, [rip + g_text]
    leave
    ret
ENDF pjs_raw

# pjs_vec_last(vec) -> rax: the last element, or 0 for an empty or 0 VEC
FUNC pjs_vec_last
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov rcx, [rdi]
    test rcx, rcx
    jz 9f
    mov rax, [rdi + rcx*8]
9:  leave
    ret
ENDF pjs_vec_last

# pjs_utf16_len(ptr, len) -> rax: String#length of UTF-8 text
FUNC pjs_utf16_len
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    movzx edx, byte ptr [rdi + rcx]
    inc rcx
    mov r8d, edx
    and r8d, 0xC0
    cmp r8d, 0x80
    je 1b
    inc rax
    cmp edx, 0xF0
    jb 1b
    inc rax
    jmp 1b
9:  leave
    ret
ENDF pjs_utf16_len

# pjs_is_lone_short_argument(node) -> eax (isLoneShortArgument with the
# options' printWidth); `len <= printWidth * 0.25` is `4 * len <= printWidth`
FUNC pjs_is_lone_short_argument
    PROLOGUE
    mov rbx, rdi
    mov r12, [rip + g_print_width]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ThisExpression
    je 7f
    cmp eax, T_Identifier
    jne 1f
    mov eax, [rbx + N_END]
    sub eax, [rbx + N_START]
    jmp 50f
1:  mov rdi, rbx
    call pjs_is_signed_numeric_literal
    test eax, eax
    jz 2f
    mov rdi, [rbx + N_F0]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jz 7f
2:  movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_RegExpLiteral
    jne 3f
    mov rdi, [rbx + N_F0]
    mov rsi, [rbx + N_F1]
    test rsi, rsi
    jz 3f                           # an empty pattern is falsy
    call pjs_utf16_len
    jmp 50f
3:  cmp eax, T_StringLiteral
    jne 4f
    mov rdi, rbx
    call pjs_raw
    mov rdi, rax
    mov rsi, rdx
    call print_string
    mov rdi, rax
    mov rsi, rdx
    call pjs_utf16_len
    jmp 50f
4:  cmp eax, T_TemplateLiteral
    jne 5f
    mov rax, [rbx + N_F1]
    VLEN rcx, rax
    test rcx, rcx
    jnz 8f
    mov rax, [rbx + N_F0]
    mov r13, [rax + 8]
    mov edi, [r13 + N_START]
    mov esi, [r13 + N_END]
    call has_newline_in_range
    test eax, eax
    jnz 8f
    mov rdi, [rip + g_text]
    mov eax, [r13 + N_START]
    add rdi, rax
    mov esi, [r13 + N_END]
    sub esi, [r13 + N_START]
    call pjs_utf16_len
    jmp 50f
5:  cmp eax, T_UnaryExpression
    jne 6f
    # isLoneShortArgument(node.argument, { printWidth }): printString without
    # singleQuote
    mov r13, [rip + g_single_quote]
    mov qword ptr [rip + g_single_quote], 0
    mov rdi, [rbx + N_F0]
    call pjs_is_lone_short_argument
    mov [rip + g_single_quote], r13
    jmp 9f
6:  cmp eax, T_CallExpression
    jne 65f
    mov rax, [rbx + N_F1]
    VLEN rcx, rax
    test rcx, rcx
    jnz 65f
    mov rax, [rbx + N_F0]
    TYPE rax, T_Identifier
    jne 65f
    mov ecx, [rax + N_END]
    sub ecx, [rax + N_START]
    lea rcx, [rcx*4 + 8]
    cmp rcx, r12
    jbe 7f
    jmp 8f
65: mov rdi, rbx
    call pjs_is_literal
    jmp 9f
50: shl rax, 2
    cmp rax, r12
    jbe 7f
8:  xor eax, eax
    jmp 9f
7:  mov eax, 1
9:  EPILOGUE
ENDF pjs_is_lone_short_argument

# pjs_is_simple_expression_by_node_count(node, max) -> eax
# (isSimpleExpressionByNodeCount): getExpressionInnerNodeCount(node, max) <= max
FUNC pjs_is_simple_expression_by_node_count
    push rbx
    sub rsp, 8
    mov rbx, rsi
    call pu_inner_node_count
    xor ecx, ecx
    cmp rax, rbx
    setle cl
    mov eax, ecx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_is_simple_expression_by_node_count

# pu_inner_node_count(node, max) -> rax (getExpressionInnerNodeCount): the
# nodes held in single-node fields, recursively; stops once above max
FUNC pu_inner_node_count
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi                    # maxCount
    xor r13d, r13d                  # count
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_type_fields]
    mov r14, [rcx + rax*8]
    # skip the props
1:  movzx eax, byte ptr [r14]
    inc r14
    test eax, eax
    jz 3f
    inc r14
2:  cmp byte ptr [r14], 0
    lea r14, [r14 + 1]
    jne 2b
    jmp 1b
    # the children
3:  movzx eax, byte ptr [r14]
    test eax, eax
    jz 9f
    movzx r15d, byte ptr [r14 + 1]
    add r14, 2
4:  cmp byte ptr [r14], 0
    lea r14, [r14 + 1]
    jne 4b
    cmp eax, FK_NODE
    jne 3b
    mov rdi, [rbx + r15]
    test rdi, rdi
    jz 3b
    inc r13
    mov rsi, r12
    sub rsi, r13
    call pu_inner_node_count
    add r13, rax
    cmp r13, r12
    jle 3b
9:  mov rax, r13
    EPILOGUE
ENDF pu_inner_node_count
