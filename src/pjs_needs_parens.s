# needs-parens.js for the node types of the babel and babel-ts parsers. The
# Flow, JSX, Angular, pipeline and bind cases cannot match them and are left out.
.include "pjs.inc"

    .section .rodata
s_let: .asciz "let"
s_async: .asciz "async"
s_placeholder: .asciz "PRETTIER_HTML_PLACEHOLDER_"
s_await: .asciz "await"
s_interface: .asciz "interface"
s_module: .asciz "module"
s_using: .asciz "using"
s_yield: .asciz "yield"
s_component: .asciz "component"
s_hook: .asciz "hook"
s_type: .asciz "type"
    .balign 8
cast_words: .quad s_await, s_interface, s_module, s_using, s_yield, s_let, s_component, s_hook, s_type, 0
    .text

# pjs_needs_parens() -> eax (needsParens) for the node at the top of the path
FUNC pjs_needs_parens
    PROLOGUE 2
    call path_is_root
    test eax, eax
    jnz 80f
    call path_value
    mov rbx, rax
    call path_key
    mov r12d, eax
    call path_parent
    mov r13, rax
    mov rdi, rbx
    call is_statement
    test eax, eax
    jnz 80f
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_Identifier
    je 100f
    cmp eax, T_ObjectExpression
    je 1f
    cmp eax, T_FunctionExpression
    je 1f
    cmp eax, T_ClassExpression
    jne 3f
    # the expression of an ExpressionStatement starts with it
1:  lea rdi, [rip + is_expression_statement]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 2f
    mov rdi, [rax + N_F0]
    lea rsi, [rip + pjs_is_node_same]
    mov rdx, rbx
    call pjs_starts_with_no_lookahead_token
    test eax, eax
    jnz 81f
2:  TYPE rbx, T_ObjectExpression
    jne 3f
    # the body of an arrow function starts with it
    lea rdi, [rip + is_arrow]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 3f
    mov rdi, [rax + N_F2]
    TYPE rdi, T_SequenceExpression
    je 3f
    TYPE rdi, T_AssignmentExpression
    je 3f
    lea rsi, [rip + pjs_is_node_same]
    mov rdx, rbx
    call pjs_starts_with_no_lookahead_token
    test eax, eax
    jnz 81f

    # switch (parent.type)
3:  movzx eax, word ptr [r13 + N_TYPE]
    movzx ecx, word ptr [rbx + N_TYPE]
    cmp eax, T_ParenthesizedExpression
    je 80f
    cmp eax, T_ClassDeclaration
    je 4f
    cmp eax, T_ClassExpression
    je 4f
    cmp eax, T_ExportDefaultDeclaration
    je 6f
    cmp eax, T_BinaryExpression
    je 7f
    cmp eax, T_VariableDeclarator
    je 8f
    cmp eax, T_Decorator
    jne 200f
    cmp r12d, K_expression
    jne 200f
    mov rdi, rbx
    call pnp_can_decorator_expression_unparenthesized
    test eax, eax
    jz 81f
    jmp 200f
4:  cmp r12d, K_superClass
    jne 200f
    cmp ecx, T_ArrowFunctionExpression
    je 81f
    cmp ecx, T_AssignmentExpression
    je 81f
    cmp ecx, T_AwaitExpression
    je 81f
    cmp ecx, T_BinaryExpression
    je 81f
    cmp ecx, T_ConditionalExpression
    je 81f
    cmp ecx, T_LogicalExpression
    je 81f
    cmp ecx, T_NewExpression
    je 81f
    cmp ecx, T_ObjectExpression
    je 81f
    cmp ecx, T_SequenceExpression
    je 81f
    cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_UnaryExpression
    je 81f
    cmp ecx, T_UpdateExpression
    je 81f
    cmp ecx, T_YieldExpression
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_ClassExpression
    jne 200f
    mov rdi, rbx
    call pjs_get_decorators
    test rax, rax
    jnz 81f
    jmp 200f
6:  call should_wrap_function_for_export_default
    test eax, eax
    jnz 81f
    TYPE rbx, T_SequenceExpression
    sete al
    movzx eax, al
    jmp 99f
7:  cmp r12d, K_left
    jne 200f
    cmp ecx, T_UnaryExpression
    jne 200f
    mov rax, [r13 + N_F2]
    cmp rax, J_IN
    je 81f
    cmp rax, J_INSTANCEOF
    je 81f
    jmp 200f
    # `for (var a = 1 in b);`
8:  cmp r12d, K_init
    jne 200f
    lea rdi, [rip + match_init_in_for_in]
    mov esi, 4
    call path_match
    test eax, eax
    jnz 81f

    # switch (node.type)
200: movzx eax, word ptr [rbx + N_TYPE]
    movzx ecx, word ptr [r13 + N_TYPE]
    cmp eax, T_UpdateExpression
    je 210f
    cmp eax, T_UnaryExpression
    je 220f
    cmp eax, T_BinaryExpression
    je 230f
    cmp eax, T_LogicalExpression
    je 240f
    cmp eax, T_SequenceExpression
    je 260f
    cmp eax, T_YieldExpression
    je 270f
    cmp eax, T_AwaitExpression
    je 280f
    cmp eax, T_StringLiteral
    je 290f
    cmp eax, T_NumericLiteral
    je 290f
    cmp eax, T_AssignmentExpression
    je 300f
    cmp eax, T_ConditionalExpression
    je 310f
    cmp eax, T_FunctionExpression
    je 320f
    cmp eax, T_ArrowFunctionExpression
    je 330f
    cmp eax, T_ClassExpression
    je 340f
    cmp eax, T_OptionalMemberExpression
    je 350f
    cmp eax, T_OptionalCallExpression
    je 350f
    cmp eax, T_CallExpression
    je 350f
    cmp eax, T_MemberExpression
    je 350f
    cmp eax, T_TaggedTemplateExpression
    je 360f
    cmp eax, T_TSNonNullExpression
    je 360f
    cmp eax, T_TSAsExpression
    je 240f
    cmp eax, T_TSSatisfiesExpression
    je 240f
    cmp eax, T_TSTypeAssertion
    je 240f
    cmp eax, T_TSInstantiationExpression
    je 370f
    # the TypeScript type cases
    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    call pnp_ts_type
    test eax, eax
    jnz 81f
    jmp 80f

    # UpdateExpression
210: cmp ecx, T_UnaryExpression
    jne 220f
    ATTR rbx, NA_PREFIX
    jz 80f
    mov rax, [rbx + N_F1]
    mov rdx, [r13 + N_F1]
    cmp rax, J_INC
    jne 211f
    cmp rdx, '+'
    je 81f
    jmp 80f
211: cmp rax, J_DEC
    jne 80f
    cmp rdx, '-'
    je 81f
    jmp 80f
    # UnaryExpression (and UpdateExpression)
220: cmp ecx, T_UnaryExpression
    jne 221f
    mov rax, [rbx + N_F1]
    cmp rax, [r13 + N_F1]
    jne 80f
    cmp rax, '+'
    je 81f
    cmp rax, '-'
    je 81f
    jmp 80f
221: cmp ecx, T_MemberExpression
    je 222f
    cmp ecx, T_OptionalMemberExpression
    je 222f
    cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_NewExpression
    je 223f
    cmp ecx, T_CallExpression
    je 223f
    cmp ecx, T_OptionalCallExpression
    je 223f
    cmp ecx, T_BinaryExpression
    jne 80f
    cmp r12d, K_left
    jne 80f
    cmp qword ptr [r13 + N_F2], J_EXP
    je 81f
    jmp 80f
222: cmp r12d, K_object
    je 81f
    jmp 80f
223: cmp r12d, K_callee
    je 81f
    jmp 80f

    # BinaryExpression
230: cmp ecx, T_UpdateExpression
    je 81f
    cmp qword ptr [rbx + N_F2], J_IN
    jne 240f
    call is_path_in_for_statement_initializer
    test eax, eax
    jnz 81f
    # LogicalExpression (and BinaryExpression)
240: movzx ecx, word ptr [r13 + N_TYPE]
    cmp ecx, T_TSAsExpression
    je 247f
    cmp ecx, T_TSSatisfiesExpression
    je 247f
    cmp ecx, T_ConditionalExpression
    jne 241f
    mov rdi, rbx
    call pjs_is_binary_cast_expression
    test eax, eax
    jnz 99f
    mov rdi, rbx
    call pjs_is_nullish_coalescing
    jmp 99f
247: mov rdi, rbx
    call pjs_is_binary_cast_expression
    xor eax, 1
    jmp 99f
248: cmp r12d, K_left
    jne 80f
    TYPE rbx, T_TSTypeAssertion
    je 81f
    mov rdi, rbx
    call pjs_is_binary_cast_expression
    jmp 99f
241: cmp ecx, T_AssignmentExpression
    je 248b
    cmp ecx, T_AssignmentPattern
    je 248b
    cmp ecx, T_TSTypeAssertion
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_CallExpression
    je 223b
    cmp ecx, T_NewExpression
    je 223b
    cmp ecx, T_OptionalCallExpression
    je 223b
    cmp ecx, T_ClassExpression
    je 242f
    cmp ecx, T_ClassDeclaration
    je 242f
    cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_UnaryExpression
    je 81f
    cmp ecx, T_SpreadElement
    je 81f
    cmp ecx, T_AwaitExpression
    je 81f
    cmp ecx, T_UpdateExpression
    je 81f
    cmp ecx, T_MemberExpression
    je 222b
    cmp ecx, T_OptionalMemberExpression
    je 222b
    cmp ecx, T_LogicalExpression
    jne 243f
    TYPE rbx, T_LogicalExpression
    jne 244f
    mov rax, [rbx + N_F2]
    cmp rax, [r13 + N_F2]
    jne 81f
    jmp 80f
243: cmp ecx, T_BinaryExpression
    jne 80f
    # precedence; a cast has no operator: `!operator && type !== "TSTypeAssertion"`,
    # and a TSTypeAssertion's undefined precedence only meets the bitwise test
244: TYPE rbx, T_TSTypeAssertion
    je 246f
    mov rdi, rbx
    call pjs_is_binary_cast_expression
    test eax, eax
    jnz 81f
    mov rdi, [rbx + N_F2]
    call pjs_get_precedence
    mov r14d, eax                   # precedence
    mov rdi, [r13 + N_F2]
    call pjs_get_precedence
    mov r15d, eax                   # parentPrecedence
    cmp r15d, r14d
    jg 81f
    jne 245f
    cmp r12d, K_right
    je 81f
    mov rdi, [r13 + N_F2]
    mov rsi, [rbx + N_F2]
    call pjs_should_flatten
    test eax, eax
    jz 81f
245: cmp r15d, r14d
    jge 246f
    cmp qword ptr [rbx + N_F2], '%'
    jne 246f
    mov rax, [r13 + N_F2]
    cmp rax, '+'
    je 81f
    cmp rax, '-'
    je 81f
    jmp 80f
246: mov rdi, [r13 + N_F2]
    call pjs_is_bitwise_operator
    jmp 99f
242: cmp r12d, K_superClass
    je 81f
    jmp 80f

    # SequenceExpression
260: cmp ecx, T_ForStatement
    je 80f
    jmp 81f

    # YieldExpression
270: cmp ecx, T_AwaitExpression
    je 81f
    cmp ecx, T_TSTypeAssertion
    je 81f
    # AwaitExpression
280: cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_TSAsExpression
    je 81f
    cmp ecx, T_TSSatisfiesExpression
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_UnaryExpression
    je 81f
    cmp ecx, T_LogicalExpression
    je 81f
    cmp ecx, T_SpreadElement
    je 81f
    cmp ecx, T_MemberExpression
    je 222b
    cmp ecx, T_OptionalMemberExpression
    je 222b
    cmp ecx, T_NewExpression
    je 223b
    cmp ecx, T_CallExpression
    je 223b
    cmp ecx, T_OptionalCallExpression
    je 223b
    cmp ecx, T_ConditionalExpression
    jne 281f
    cmp r12d, K_test
    je 81f
    jmp 80f
281: cmp ecx, T_BinaryExpression
    je 81f
    jmp 80f

    # StringLiteral, NumericLiteral
290: TYPE rbx, T_StringLiteral
    jne 292f
    cmp ecx, T_ExpressionStatement
    jne 292f
    # to avoid becoming a directive
    call path_grandparent
    TYPE rax, T_Program
    je 81f
    TYPE rax, T_BlockStatement
    je 81f
    jmp 80f
292: cmp r12d, K_object
    jne 80f
    mov rdi, r13
    call pjs_is_member_expression
    test eax, eax
    jz 80f
    TYPE rbx, T_NumericLiteral
    je 81f
    jmp 80f

    # AssignmentExpression
300: cmp ecx, T_ForStatement
    jne 301f
    cmp r12d, K_init
    je 80f
    cmp r12d, K_update
    je 80f
301: cmp r12d, K_expression
    jne 302f
    cmp ecx, T_ExpressionStatement
    jne 302f
    mov rax, [rbx + N_F0]
    TYPE rax, T_ObjectPattern
    jne 80f
302: cmp ecx, T_AssignmentExpression
    je 80f
    cmp ecx, T_TSPropertySignature
    jne 303f
    cmp r12d, K_key
    je 80f
303:
    cmp r12d, K_expressions
    jne 81f
    cmp ecx, T_SequenceExpression
    jne 81f
    lea rdi, [rip + match_for_init_update]
    mov esi, 3
    call path_match
    test eax, eax
    jnz 80f
    jmp 81f

    # ConditionalExpression
310: cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_TSTypeAssertion
    je 81f
    cmp ecx, T_TSAsExpression
    je 81f
    cmp ecx, T_TSSatisfiesExpression
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_UnaryExpression
    je 81f
    cmp ecx, T_SpreadElement
    je 81f
    cmp ecx, T_BinaryExpression
    je 81f
    cmp ecx, T_LogicalExpression
    je 81f
    cmp ecx, T_ExportDefaultDeclaration
    je 81f
    cmp ecx, T_AwaitExpression
    je 81f
    cmp ecx, T_NewExpression
    je 223b
    cmp ecx, T_CallExpression
    je 223b
    cmp ecx, T_OptionalCallExpression
    je 223b
    cmp ecx, T_ConditionalExpression
    jne 311f
    cmp qword ptr [rip + g_experimental_ternaries], 0
    jne 80f
    cmp r12d, K_test
    je 81f
    jmp 80f
311: cmp ecx, T_MemberExpression
    je 222b
    cmp ecx, T_OptionalMemberExpression
    je 222b
    jmp 80f

    # FunctionExpression
320: cmp ecx, T_NewExpression
    je 223b
    cmp ecx, T_CallExpression
    je 223b
    cmp ecx, T_OptionalCallExpression
    je 223b
    cmp ecx, T_TaggedTemplateExpression
    je 81f
    jmp 80f

    # ArrowFunctionExpression
330: cmp ecx, T_BinaryExpression
    je 81f
    cmp ecx, T_TSAsExpression
    je 81f
    cmp ecx, T_TSSatisfiesExpression
    je 81f
    cmp ecx, T_TSNonNullExpression
    je 81f
    cmp ecx, T_TSTypeAssertion
    je 81f
    cmp ecx, T_NewExpression
    je 223b
    cmp ecx, T_CallExpression
    je 223b
    cmp ecx, T_OptionalCallExpression
    je 223b
    cmp ecx, T_MemberExpression
    je 222b
    cmp ecx, T_OptionalMemberExpression
    je 222b
    cmp ecx, T_TaggedTemplateExpression
    je 81f
    cmp ecx, T_UnaryExpression
    je 81f
    cmp ecx, T_LogicalExpression
    je 81f
    cmp ecx, T_AwaitExpression
    je 81f
    cmp ecx, T_ConditionalExpression
    jne 80f
    cmp r12d, K_test
    je 81f
    jmp 80f

    # ClassExpression
340: cmp ecx, T_NewExpression
    je 223b
    jmp 80f

    # member and call chains: shouldAddParenthesesToChainElement
350: TYPE rbx, T_OptionalMemberExpression
    je 351f
    TYPE rbx, T_OptionalCallExpression
    jne 360f
351: cmp ecx, T_TaggedTemplateExpression
    jne 352f
    cmp r12d, K_tag
    je 81f
352: cmp r12d, K_object
    jne 353f
    cmp ecx, T_MemberExpression
    je 81f
353: cmp r12d, K_callee
    jne 354f
    cmp ecx, T_CallExpression
    je 81f
    cmp ecx, T_NewExpression
    je 81f
    # babel-ts: (a?.b)!``, (a?.b!).c, (a?.b)!()
354: lea rdi, [rip + match_chain_nonnull_tag]
    mov esi, 3
    call path_match
    test eax, eax
    jnz 81f
    lea rdi, [rip + match_chain_nonnull_object]
    mov esi, 3
    call path_match
    test eax, eax
    jnz 81f
    # typescript-estree ends the chain at the parentheses of `(a?.b)!?.c` and
    # `(a?.b!)?.c`, a ChainExpression in a TSNonNullExpression, and Prettier
    # parenthesizes it also under an optional member or call
    lea rdi, [rip + match_chain_nonnull_optional]
    mov esi, 3
    call path_match
    test eax, eax
    jz 355f
    ATTR rbx, NA_PARENTHESIZED
    jnz 81f
    ATTR r13, NA_PARENTHESIZED
    jnz 81f
355: movzx ecx, word ptr [r13 + N_TYPE]
    # TaggedTemplateExpression (and the chains): a call in the callee of new
360: cmp r12d, K_callee
    jne 80f
    cmp ecx, T_NewExpression
    jne 80f
    mov rdi, rbx
    call pnp_check_new_callee_chain
    mov rax, rbx
361: movzx ecx, word ptr [rax + N_TYPE]
    cmp ecx, T_CallExpression
    je 81f
    cmp ecx, T_OptionalCallExpression
    je 81f
    cmp ecx, T_MemberExpression
    je 362f
    cmp ecx, T_OptionalMemberExpression
    je 362f
    cmp ecx, T_TaggedTemplateExpression
    je 362f
    cmp ecx, T_TSNonNullExpression
    jne 80f
362: mov rax, [rax + N_F0]          # object, tag, expression
    jmp 361b

    # TSInstantiationExpression
370: cmp r12d, K_object
    jne 80f
    mov rdi, r13
    call pjs_is_member_expression
    jmp 99f

    # Identifier
100: test dword ptr [rbx + N_ATTR], NA_PARENTHESIZED
    jz 101f
    mov rdi, [rip + g_text]
    mov eax, [rbx + N_START]
    add rdi, rax
    lea rsi, [rip + s_placeholder]
    call cstr_prefix
    test eax, eax
    jnz 190f
    # `for ((async) of []);` and `for ((let) of []);`
101: cmp r12d, K_left
    jne 103f
    TYPE r13, T_ForOfStatement
    jne 103f
    mov rdi, rbx
    lea rsi, [rip + s_let]
    call pjs_ident_is
    test eax, eax
    jnz 81f
    ATTR r13, NA_AWAIT
    jnz 103f
    mov rdi, rbx
    lea rsi, [rip + s_async]
    call pjs_ident_is
    test eax, eax
    jnz 81f
103: mov rdi, rbx
    lea rsi, [rip + s_let]
    call pjs_ident_is
    test eax, eax
    jz 105f
    # `for ((let.a) of []);`
    lea rdi, [rip + is_for_of]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 104f
    mov rdi, [rax + N_F0]
    test rdi, rdi
    jz 104f
    lea rsi, [rip + pjs_is_node_same]
    mov rdx, rbx
    call pjs_starts_with_no_lookahead_token
    test eax, eax
    jnz 81f
    # `(let)[a] = 1`
104: cmp r12d, K_object
    jne 105f
    TYPE r13, T_MemberExpression
    jne 105f
    ATTR r13, NA_COMPUTED
    jz 105f
    ATTR r13, NA_OPTIONAL
    jnz 105f
    lea rdi, [rip + is_let_statement]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 105f
    mov rdi, [rax + N_F0]           # ExpressionStatement.expression, ForStatement.init, ForInStatement.left
    test rdi, rdi
    jz 105f
    lea rsi, [rip + pjs_is_node_same]
    mov rdx, rbx
    call pjs_starts_with_no_lookahead_token
    test eax, eax
    jnz 81f
    # `(type) satisfies never;` and similar cases
105: cmp r12d, K_expression
    jne 80f
    mov rdi, rbx
    lea rsi, [rip + cast_words]
    call pjs_ident_in
    test eax, eax
    jz 80f
    lea rdi, [rip + is_not_binary_cast]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 80f
    cmp rax, r13
    je 80f
    TYPE rax, T_ExpressionStatement
    je 81f
    jmp 80f

80: xor eax, eax
    jmp 99f
81: mov eax, 1
99: EPILOGUE
190: REFUSE "printer: embed placeholder identifier"
ENDF pjs_needs_parens

# pnp_check_new_callee_chain(callee): refuses where typescript-estree's
# ChainExpression changes this rule: walking the callee of `new` as the loop
# above does, an optional call reached past a non-null assertion or a plain
# member (`new (a?.()!)()`, `new ((a?.()).b)()`) is inside a ChainExpression
# that ends the walk under the typescript parser, so its output differs.
# Only in TypeScript files.
FUNC pnp_check_new_callee_chain
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    jne 9f
    xor edx, edx                    # crossed a TSNonNullExpression or plain member
1:  movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_OptionalCallExpression
    je 5f
    cmp ecx, T_OptionalMemberExpression
    je 3f
    cmp ecx, T_MemberExpression
    je 2f
    cmp ecx, T_TSNonNullExpression
    je 2f
    cmp ecx, T_TaggedTemplateExpression
    jne 9f
2:  mov edx, 1
3:  mov rdi, [rdi + N_F0]           # object, expression, tag
    jmp 1b
5:  test edx, edx
    jnz 90f
9:  leave
    ret
90: REFUSE "printer: `new` of an optional call inside parentheses or `!` (typescript-estree's ChainExpression prints it differently)"
ENDF pnp_check_new_callee_chain

# is_statement(node) -> eax (isStatement)
FUNC is_statement
    movzx ecx, word ptr [rdi + N_TYPE]
    mov eax, 1
    .irp t, T_BlockStatement, T_BreakStatement, T_ClassBody, T_ClassDeclaration, T_ClassMethod, T_ClassProperty, T_ClassPrivateProperty, T_ContinueStatement, T_DebuggerStatement, T_DoWhileStatement, T_ExportAllDeclaration, T_ExportDefaultDeclaration, T_ExportNamedDeclaration, T_ExpressionStatement, T_ForInStatement, T_ForOfStatement, T_ForStatement, T_FunctionDeclaration, T_IfStatement, T_ImportDeclaration, T_LabeledStatement, T_ReturnStatement, T_SwitchStatement, T_ThrowStatement, T_TryStatement, T_VariableDeclaration, T_WhileStatement, T_WithStatement, T_TSDeclareFunction, T_TSEnumDeclaration, T_TSImportEqualsDeclaration, T_TSInterfaceDeclaration, T_TSModuleDeclaration, T_TSNamespaceExportDeclaration
    cmp ecx, \t
    je 9f
    .endr
    xor eax, eax
9:  leave
    ret
ENDF is_statement

FUNC is_not_binary_cast
    mov rdi, rsi
    call pjs_is_binary_cast_expression
    xor eax, 1
    leave
    ret
ENDF is_not_binary_cast

FUNC is_expression_statement
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_ExpressionStatement
    sete al
    leave
    ret
ENDF is_expression_statement

FUNC is_arrow
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_ArrowFunctionExpression
    sete al
    leave
    ret
ENDF is_arrow

FUNC is_for_of
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_ForOfStatement
    sete al
    leave
    ret
ENDF is_for_of

FUNC is_let_statement
    movzx ecx, word ptr [rsi + N_TYPE]
    mov eax, 1
    cmp ecx, T_ExpressionStatement
    je 9f
    cmp ecx, T_ForStatement
    je 9f
    cmp ecx, T_ForInStatement
    je 9f
    xor eax, eax
9:  leave
    ret
ENDF is_let_statement

# path.match(undefined, undefined, declarations of a VariableDeclaration,
# left of a ForInStatement)
    .section .rodata
    .balign 8
match_init_in_for_in: .quad 0, 0, m_declarations_of_var, m_left_of_for_in
match_for_init_update: .quad 0, 0, m_init_update_of_for
    .text

    .section .rodata
    .balign 8
match_chain_nonnull_tag: .quad 0, m_expression_of_non_null, m_tag_of_tagged_template
match_chain_nonnull_object: .quad 0, m_expression_of_non_null, m_object_of_member_or_callee_of_call
match_chain_nonnull_optional: .quad 0, m_expression_of_non_null, m_object_or_callee_of_optional
    .text

FUNC m_expression_of_non_null
    xor eax, eax
    cmp esi, K_expression
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_TSNonNullExpression
    sete al
9:  leave
    ret
ENDF m_expression_of_non_null

FUNC m_tag_of_tagged_template
    xor eax, eax
    cmp esi, K_tag
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_TaggedTemplateExpression
    sete al
9:  leave
    ret
ENDF m_tag_of_tagged_template

# (name === "object" && MemberExpression) || (name === "callee" && CallExpression)
FUNC m_object_of_member_or_callee_of_call
    xor eax, eax
    cmp esi, K_object
    jne 1f
    cmp word ptr [rdi + N_TYPE], T_MemberExpression
    sete al
    jmp 9f
1:  cmp esi, K_callee
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_CallExpression
    sete al
9:  leave
    ret
ENDF m_object_of_member_or_callee_of_call

# (name === "object" && OptionalMemberExpression) || (name === "callee" && OptionalCallExpression)
FUNC m_object_or_callee_of_optional
    xor eax, eax
    cmp esi, K_object
    jne 1f
    cmp word ptr [rdi + N_TYPE], T_OptionalMemberExpression
    sete al
    jmp 9f
1:  cmp esi, K_callee
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_OptionalCallExpression
    sete al
9:  leave
    ret
ENDF m_object_or_callee_of_optional

FUNC m_declarations_of_var
    xor eax, eax
    cmp esi, K_declarations
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_VariableDeclaration
    sete al
9:  leave
    ret
ENDF m_declarations_of_var

FUNC m_left_of_for_in
    xor eax, eax
    cmp esi, K_left
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_ForInStatement
    sete al
9:  leave
    ret
ENDF m_left_of_for_in

FUNC m_init_update_of_for
    xor eax, eax
    cmp esi, K_init
    je 1f
    cmp esi, K_update
    jne 9f
1:  cmp word ptr [rdi + N_TYPE], T_ForStatement
    sete al
9:  leave
    ret
ENDF m_init_update_of_for

# is_path_in_for_statement_initializer() -> eax
FUNC is_path_in_for_statement_initializer
    PROLOGUE
    call path_value
    mov rbx, rax
    xor r12d, r12d
1:  test rbx, rbx
    jz 8f
    mov rdi, r12
    inc r12
    call path_parent_node
    test rax, rax
    jz 8f
    TYPE rax, T_ForStatement
    jne 2f
    cmp [rax + N_F0], rbx
    je 7f
2:  mov rbx, rax
    jmp 1b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF is_path_in_for_statement_initializer

# should_wrap_function_for_export_default() -> eax (shouldWrapFunctionForExportDefault)
FUNC should_wrap_function_for_export_default
    PROLOGUE
    call path_value
    mov rbx, rax
    call path_parent
    mov r12, rax
    TYPE rbx, T_FunctionExpression
    je 1f
    TYPE rbx, T_ClassExpression
    jne 2f
1:  mov eax, 1
    TYPE r12, T_ExportDefaultDeclaration
    je 9f
    call pjs_needs_parens
    xor eax, 1
    jmp 9f
2:  mov rdi, rbx
    call pjs_has_naked_left_side
    test eax, eax
    jz 9f
    TYPE r12, T_ExportDefaultDeclaration
    je 3f
    call pjs_needs_parens
    test eax, eax
    jnz 8f
3:  lea rdi, [rip + swf_cb]
    xor esi, esi
    call pjs_call_left_side
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF should_wrap_function_for_export_default

FUNC swf_cb
    call should_wrap_function_for_export_default
    leave
    ret
ENDF swf_cb

# pnp_is_decorator_member_expression(node) -> eax (isDecoratorMemberExpression)
FUNC pnp_is_decorator_member_expression
1:  mov eax, 1
    TYPE rdi, T_Identifier
    je 9f
    xor eax, eax
    TYPE rdi, T_MemberExpression
    je 2f
    TYPE rdi, T_OptionalMemberExpression
    jne 9f
2:  test dword ptr [rdi + N_ATTR], NA_COMPUTED | NA_OPTIONAL
    jnz 9f
    mov rcx, [rdi + N_F1]
    TYPE rcx, T_Identifier
    jne 9f
    mov rdi, [rdi + N_F0]
    jmp 1b
9:  leave
    ret
ENDF pnp_is_decorator_member_expression

# pnp_can_decorator_expression_unparenthesized(node) -> eax
FUNC pnp_can_decorator_expression_unparenthesized
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call pnp_is_decorator_member_expression
    test eax, eax
    jnz 9f
    TYPE rbx, T_CallExpression
    je 1f
    TYPE rbx, T_OptionalCallExpression
    jne 9f
1:  test dword ptr [rbx + N_ATTR], NA_OPTIONAL
    jnz 9f
    mov rdi, [rbx + N_F0]
    call pnp_is_decorator_member_expression
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pnp_can_decorator_expression_unparenthesized

    .section .rodata
    .balign 8
# path.match(TSFunctionType, TSTypeAnnotation as "typeAnnotation",
# ArrowFunctionExpression as "returnType")
pnp_match_fn_return: .quad pnp_is_ts_function_type, pnp_is_type_annotation_key, pnp_is_arrow_return_type
    .text

FUNC pnp_is_ts_function_type
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TSFunctionType
    sete al
    leave
    ret
ENDF pnp_is_ts_function_type

FUNC pnp_is_type_annotation_key
    xor eax, eax
    cmp esi, K_typeAnnotation
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_TSTypeAnnotation
    sete al
9:  leave
    ret
ENDF pnp_is_type_annotation_key

FUNC pnp_is_arrow_return_type
    xor eax, eax
    cmp esi, K_returnType
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_ArrowFunctionExpression
    sete al
9:  leave
    ret
ENDF pnp_is_arrow_return_type

# pnp_ts_type(node, key, parent) -> eax: the TSFunctionType ... TSTypeQuery
# cases of needsParens' switch (node.type); 0 for other node types
FUNC pnp_ts_type
    PROLOGUE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    movzx eax, word ptr [rbx + N_TYPE]
    movzx r14d, word ptr [r13 + N_TYPE]
    cmp eax, T_TSFunctionType
    je 10f
    cmp eax, T_TSConditionalType
    je 20f
    cmp eax, T_TSConstructorType
    je 20f
    cmp eax, T_TSUnionType
    je 30f
    cmp eax, T_TSIntersectionType
    je 30f
    cmp eax, T_TSInferType
    je 40f
    cmp eax, T_TSTypeOperator
    je 50f
    cmp eax, T_TSTypeQuery
    je 60f
    jmp 80f
10: lea rdi, [rip + pnp_match_fn_return]
    mov esi, 3
    call path_match
    test eax, eax
    jnz 81f
    # TSConditionalType, TSConstructorType (and TSFunctionType)
20: cmp r12d, K_extendsType
    jne 21f
    TYPE rbx, T_TSConditionalType
    jne 21f
    cmp r14d, T_TSConditionalType
    je 81f
21: cmp r12d, K_checkType
    jne 22f
    cmp r14d, T_TSConditionalType
    je 81f
22: cmp r12d, K_extendsType
    jne 30f
    cmp r14d, T_TSConditionalType
    jne 30f
    # let {typeAnnotation} = node.returnType || node.typeAnnotation
    mov rax, [rbx + N_F5]
    test rax, rax
    jz 90f
    mov rax, [rax + N_F5]
    TYPE rax, T_TSTypePredicate
    jne 23f
    mov rcx, [rax + N_F5]
    test rcx, rcx
    jz 23f
    mov rax, [rcx + N_F5]
23: TYPE rax, T_TSInferType
    jne 30f
    mov rax, [rax + N_F0]           # typeParameter
    cmp qword ptr [rax + N_F1], 0   # constraint
    jne 81f
    # TSUnionType, TSIntersectionType
30: cmp r14d, T_TSUnionType
    je 31f
    cmp r14d, T_TSIntersectionType
    jne 40f
31: mov rax, [r13 + N_F0]
    cmp qword ptr [rax], 1
    jbe 40f
    TYPE rbx, T_TSUnionType
    je 32f
    TYPE rbx, T_TSIntersectionType
    jne 81f
32: mov rax, [rbx + N_F0]
    cmp qword ptr [rax], 1
    ja 81f
    # TSInferType
40: TYPE rbx, T_TSInferType
    jne 50f
    cmp r14d, T_TSRestType
    je 80f
    cmp r12d, K_types
    jne 50f
    cmp r14d, T_TSUnionType
    je 41f
    cmp r14d, T_TSIntersectionType
    jne 50f
41: mov rax, [rbx + N_F0]
    TYPE rax, T_TSTypeParameter
    jne 50f
    cmp qword ptr [rax + N_F1], 0
    jne 81f
    # TSTypeOperator
50: cmp r14d, T_TSArrayType
    je 81f
    cmp r14d, T_TSOptionalType
    je 81f
    cmp r14d, T_TSRestType
    je 81f
    cmp r14d, T_TSTypeOperator
    je 81f
    cmp r14d, T_TSIndexedAccessType
    jne 80f
    cmp r12d, K_objectType
    je 81f
    jmp 80f
60: cmp r12d, K_objectType
    jne 61f
    cmp r14d, T_TSIndexedAccessType
    je 81f
61: cmp r12d, K_elementType
    jne 80f
    cmp r14d, T_TSArrayType
    je 81f
80: xor eax, eax
    EPILOGUE
81: mov eax, 1
    EPILOGUE
90: REFUSE "printer: TSFunctionType without a return type (needs-parens.js)"
ENDF pnp_ts_type
