# printEstree (src/language-js/print/estree.js): the switch over node.type, as
# a table of handlers by T_*, and the cases estree.js prints itself.
# A handler is handler(node, args) -> rax doc; the node is the path's top.
.include "pjs.inc"

    .section .rodata
    .balign 8
# (type, handler) pairs; types not listed refuse (TypeScript, Flow, JSX).
estree_cases:
    .quad T_File, pes_file
    .quad T_Program, pjs_print_block
    .quad T_BlockStatement, pjs_print_block
    .quad T_StaticBlock, pjs_print_block
    .quad T_EmptyStatement, pes_empty
    .quad T_ExpressionStatement, pjs_print_expression_statement
    .quad T_ParenthesizedExpression, pes_parenthesized
    .quad T_AssignmentExpression, pjs_print_assignment_expression
    .quad T_VariableDeclarator, pjs_print_variable_declarator
    .quad T_BinaryExpression, pjs_print_binaryish_expression
    .quad T_LogicalExpression, pjs_print_binaryish_expression
    .quad T_AssignmentPattern, pes_assignment_pattern
    .quad T_MemberExpression, pjs_print_member_expression
    .quad T_OptionalMemberExpression, pjs_print_member_expression
    .quad T_MetaProperty, pes_meta_property
    .quad T_Identifier, pes_identifier
    .quad T_SpreadElement, pjs_print_rest_spread
    .quad T_RestElement, pjs_print_rest_spread
    .quad T_FunctionDeclaration, pjs_print_function
    .quad T_FunctionExpression, pjs_print_function
    .quad T_ArrowFunctionExpression, pjs_print_arrow_function
    .quad T_YieldExpression, pes_yield
    .quad T_AwaitExpression, pes_await
    .quad T_ExportDefaultDeclaration, pjs_print_export_declaration
    .quad T_ExportNamedDeclaration, pjs_print_export_declaration
    .quad T_ExportAllDeclaration, pjs_print_export_declaration
    .quad T_ImportDeclaration, pjs_print_import_declaration
    .quad T_ImportSpecifier, pjs_print_module_specifier
    .quad T_ExportSpecifier, pjs_print_module_specifier
    .quad T_ImportNamespaceSpecifier, pjs_print_module_specifier
    .quad T_ExportNamespaceSpecifier, pjs_print_module_specifier
    .quad T_ImportDefaultSpecifier, pjs_print_module_specifier
    .quad T_ImportAttribute, pjs_print_property
    .quad T_ClassBody, pjs_print_class_body
    .quad T_ThrowStatement, pjs_print_throw_statement
    .quad T_ReturnStatement, pjs_print_return_statement
    .quad T_NewExpression, pjs_print_call_expression
    .quad T_ImportExpression, pjs_print_call_expression
    .quad T_OptionalCallExpression, pjs_print_call_expression
    .quad T_CallExpression, pjs_print_call_expression
    .quad T_ObjectExpression, pjs_print_object
    .quad T_ObjectPattern, pjs_print_object
    .quad T_ObjectProperty, pjs_print_property
    .quad T_ObjectMethod, pjs_print_method
    .quad T_ArrayExpression, pjs_print_array
    .quad T_ArrayPattern, pjs_print_array
    .quad T_SequenceExpression, pes_sequence
    .quad T_ThisExpression, pes_this
    .quad T_Super, pes_super
    .quad T_Directive, pes_directive
    .quad T_UnaryExpression, pes_unary
    .quad T_UpdateExpression, pes_update
    .quad T_ConditionalExpression, pjs_print_ternary
    .quad T_VariableDeclaration, pes_variable_declaration
    .quad T_WithStatement, pes_with
    .quad T_IfStatement, pes_if
    .quad T_ForStatement, pes_for
    .quad T_WhileStatement, pes_while
    .quad T_ForInStatement, pes_for_in
    .quad T_ForOfStatement, pes_for_of
    .quad T_DoWhileStatement, pes_do_while
    .quad T_BreakStatement, pes_break_continue
    .quad T_ContinueStatement, pes_break_continue
    .quad T_LabeledStatement, pes_labeled
    .quad T_TryStatement, pes_try
    .quad T_CatchClause, pes_catch
    .quad T_SwitchStatement, pes_switch
    .quad T_SwitchCase, pes_switch_case
    .quad T_DebuggerStatement, pes_debugger
    .quad T_ClassDeclaration, pjs_print_class
    .quad T_ClassExpression, pjs_print_class
    .quad T_ClassMethod, pjs_print_class_method
    .quad T_ClassPrivateMethod, pjs_print_class_method
    .quad T_ClassProperty, pjs_print_class_property
    .quad T_ClassPrivateProperty, pjs_print_class_property
    .quad T_TemplateElement, pes_template_element
    .quad T_TemplateLiteral, pjs_print_template_literal
    .quad T_TaggedTemplateExpression, pjs_print_tagged_template_literal
    .quad T_PrivateName, pes_private_name
    .quad T_Decorator, pjs_print_decorator
    .quad T_ClassAccessorProperty, pjs_print_class_property
    .quad 0

SDOC sd_this, "this"
SDOC sd_super, "super"
SDOC sd_yield, "yield"
SDOC sd_await, "await"
SDOC sd_if_open, "if ("
SDOC sd_else, "else"
SDOC sd_for_open, "for ("
SDOC sd_for_ever, "for (;;)"
SDOC sd_for, "for"
SDOC sd_await_sp, " await"
SDOC sd_paren_open_sp, " ("
SDOC sd_in_sp, " in "
SDOC sd_of_sp, " of "
SDOC sd_while_open, "while ("
SDOC sd_with_open, "with ("
SDOC sd_do, "do"
SDOC sd_break, "break"
SDOC sd_continue, "continue"
SDOC sd_colon_semi, ":;"
SDOC sd_colon_sp, ": "
SDOC sd_try, "try "
SDOC sd_finally, " finally "
SDOC sd_catch, "catch "
SDOC sd_paren_close_sp, ") "
SDOC sd_switch_open, "switch ("
SDOC sd_brace_open_sp, " {"
SDOC sd_case, "case "
SDOC sd_default, "default:"
SDOC sd_debugger, "debugger"

    .bss
    .balign 8
estree_table: .space 8 * T_COUNT
estree_ready: .quad 0
comma_line:   .quad 0         # [",", line]

    .text

# pjs_print_estree(node, args) -> rax doc (printEstree)
FUNC pjs_print_estree
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    cmp qword ptr [rip + estree_ready], 0
    jne 2f
    lea rcx, [rip + estree_cases]
    lea rdx, [rip + estree_table]
    xor r9d, r9d
    # estree_cases, then ts_cases (printTypescript)
1:  mov rax, [rcx]
    test rax, rax
    jz 11f
    mov r8, [rcx + 8]
    mov [rdx + rax*8], r8
    add rcx, 16
    jmp 1b
11: test r9d, r9d
    jnz 12f
    mov r9d, 1
    lea rcx, [rip + ts_cases]
    jmp 1b
12: lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array2
    mov [rip + comma_line], rax
    mov qword ptr [rip + estree_ready], 1
2:  mov rdi, rbx
    call pjs_is_literal
    test eax, eax
    jz 3f
    mov rdi, rbx
    call pjs_print_literal
    jmp 9f
3:  movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_COUNT
    jae 90f
    lea rcx, [rip + estree_table]
    mov rax, [rcx + rax*8]
    test rax, rax
    jz 90f
    mov rdi, rbx
    mov rsi, r12
    call rax
9:  EPILOGUE
90: REFUSE "printer: node type not ported"
ENDF pjs_print_estree

# pjs_semi_doc() -> rax: options.semi ? ";" : ""
FUNC pjs_semi_doc
    xor eax, eax
    cmp qword ptr [rip + g_semi], 0
    je 1f
    lea rax, [rip + ps_semi]
1:  leave
    ret
ENDF pjs_semi_doc

# pjs_code_doc(code) -> rax: the operator or kind string of an ast_codes code
FUNC pjs_code_doc
    push rbx
    sub rsp, 8
    lea rax, [rip + ast_codes]
    mov rbx, [rax + rdi*8]
    mov rdi, rbx
    call strlen
    mov rdi, rbx
    mov rsi, rax
    call doc_str
    add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_code_doc

# group([indent([softline, doc]), softline])
FUNC pes_soft_group
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL d_softline
    DPUSH rbx
    DARRAY r12
    INDENT_RAX
    mov rbx, rax
    DMARK r12
    DPUSH rbx
    DPUSHL d_softline
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pes_soft_group

FUNC pes_file
    PRINT N_F0, K_program
    leave
    ret
ENDF pes_file

FUNC pes_empty
    xor eax, eax
    leave
    ret
ENDF pes_empty

FUNC pes_this
    lea rax, [rip + sd_this]
    leave
    ret
ENDF pes_this

FUNC pes_super
    lea rax, [rip + sd_super]
    leave
    ret
ENDF pes_super

# [node.name, printOptionalToken(path), printDefiniteToken(path),
# printTypeAnnotationProperty(path, print)]
FUNC pes_identifier
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_ident_name
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    DPUSH rax
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    call pjs_print_definite_token
    DPUSH rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pes_identifier

# replaceEndOfLine(node.value.raw)
FUNC pes_template_element
    mov esi, [rdi + N_END]
    sub esi, [rdi + N_START]
    mov eax, [rdi + N_START]
    mov rdi, [rip + g_text]
    add rdi, rax
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    leave
    ret
ENDF pes_template_element

# ["#", print("id")]
FUNC pes_private_name
    PROLOGUE
    PRINT N_F0, K_id
    lea rdi, [rip + ps_hash]
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pes_private_name

# [print("value"), semi]
FUNC pes_directive
    PROLOGUE
    PRINT N_F0, K_value
    mov rbx, rax
    call pjs_semi_doc
    mov rdi, rbx
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pes_directive

# [print("left"), " = ", print("right")]
FUNC pes_assignment_pattern
    PROLOGUE
    PRINT N_F0, K_left
    mov rbx, rax
    PRINT N_F1, K_right
    mov rdi, rbx
    lea rsi, [rip + ps_eq_spaced]
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pes_assignment_pattern

# [print("meta"), ".", print("property")]
FUNC pes_meta_property
    PROLOGUE
    PRINT N_F0, K_meta
    mov rbx, rax
    PRINT N_F1, K_property
    mov rdi, rbx
    lea rsi, [rip + ps_dot]
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pes_meta_property

# ParenthesizedExpression (kept after a type-cast comment)
FUNC pes_parenthesized
    PROLOGUE
    mov rbx, rdi
    mov r13, [rbx + N_F0]
    PRINT N_F0, K_expression
    mov r12, rax
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 2f
    TYPE r13, T_ObjectExpression
    je 1f
    TYPE r13, T_ArrayExpression
    jne 2f
1:  lea rdi, [rip + ps_lparen]
    mov rsi, r12
    lea rdx, [rip + ps_rparen]
    call doc_array3
    jmp 9f
2:  DMARK r13
    DPUSHL d_softline
    DPUSH r12
    DARRAY r13
    INDENT_RAX
    mov r12, rax
    DMARK r13
    DPUSHL ps_lparen
    DPUSH r12
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r13
    GROUP_RAX
9:  EPILOGUE
ENDF pes_parenthesized

# ["yield", delegate ? "*" : "", argument ? [" ", print("argument")] : ""]
FUNC pes_yield
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_yield
    ATTR rbx, NA_DELEGATE
    jz 1f
    DPUSHL ps_star
1:  cmp qword ptr [rbx + N_F0], 0
    je 2f
    DPUSHL ps_space
    PRINT N_F0, K_argument
    DPUSH rax
2:  DARRAY r12
    EPILOGUE
ENDF pes_yield

# AwaitExpression
FUNC pes_await
    PROLOGUE
    mov rbx, rdi
    cmp qword ptr [rbx + N_F0], 0
    jne 1f
    lea rax, [rip + sd_await]
    jmp 9f
1:  PRINT N_F0, K_argument
    mov r13, rax                    # print("argument")
    DMARK r12
    DPUSHL sd_await
    DPUSHL ps_space
    DPUSH r13
    DARRAY r12
    mov r14, rax                    # parts
    call path_parent
    mov r15, rax
    mov rdi, r15
    call pjs_is_call_expression
    test eax, eax
    jz 2f
    cmp [r15 + N_F0], rbx
    je 3f
2:  mov rdi, r15
    call pjs_is_member_expression
    test eax, eax
    jz 8f
    cmp [r15 + N_F0], rbx
    jne 8f
    # parts = [indent([softline, ...parts]), softline]
3:  DMARK r12
    DPUSHL d_softline
    DPUSHL sd_await
    DPUSHL ps_space
    DPUSH r13
    DARRAY r12
    INDENT_RAX
    mov r13, rax
    DMARK r12
    DPUSH r13
    DPUSHL d_softline
    DARRAY r12
    mov r14, rax
    lea rdi, [rip + is_await_or_block]
    xor esi, esi
    call path_find_ancestor
    test rax, rax
    jz 4f
    TYPE rax, T_AwaitExpression
    jne 4f
    mov rdi, [rax + N_F0]
    lea rsi, [rip + pjs_is_node_same]
    mov rdx, rbx
    call pjs_starts_with_no_lookahead_token
    test eax, eax
    jnz 8f
4:  mov rax, r14
    GROUP_RAX
    jmp 9f
8:  mov rax, r14
9:  EPILOGUE
ENDF pes_await

FUNC is_await_or_block
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_AwaitExpression
    je 1f
    cmp word ptr [rsi + N_TYPE], T_BlockStatement
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF is_await_or_block

# SequenceExpression
FUNC pes_sequence
    PROLOGUE
    mov rbx, rdi
    mov r13, [rbx + N_F0]           # expressions
    call path_parent
    mov r14, rax
    TYPE r14, T_ExpressionStatement
    je 1f
    TYPE r14, T_ForStatement
    jne 10f
    # [print(first), ",", indent([line, print()]), ...] in a group
1:  DMARK r12
    xor r15d, r15d
2:  cmp r15, [r13]
    jae 3f
    mov rdi, r13
    mov rsi, r15
    mov edx, K_expressions
    xor ecx, ecx
    call print_elem
    test r15, r15
    jz 21f
    mov [rsp], rax
    lea rdi, [rip + d_line]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov [rsp], rax
    DPUSHL ps_comma
    mov rax, [rsp]
21: DPUSH rax
    inc r15
    jmp 2b
3:  DARRAY r12
    GROUP_RAX
    jmp 9f
    # join([",", line], path.map(print, "expressions"))
10: mov edi, N_F0
    mov esi, K_expressions
    xor edx, edx
    call print_map
    mov rdi, [rip + comma_line]
    mov rsi, rax
    call doc_join
    mov r12, rax
    call path_key
    mov r15d, eax
    TYPE r14, T_ReturnStatement
    je 11f
    TYPE r14, T_ThrowStatement
    jne 12f
11: cmp r15d, K_argument
    je 13f
    jmp 18f
12: TYPE r14, T_ArrowFunctionExpression
    jne 18f
    cmp r15d, K_body
    jne 18f
    # group(ifBreak([indent([softline, parts]), softline], parts))
13: DMARK r13
    DPUSHL d_softline
    DPUSH r12
    DARRAY r13
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    mov rdi, rax
    mov rsi, r12
    xor edx, edx
    call doc_if_break
    GROUP_RAX
    jmp 9f
18: mov rax, r12
    GROUP_RAX
9:  EPILOGUE
ENDF pes_sequence

# UnaryExpression
FUNC pes_unary
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, [rbx + N_F1]
    call pjs_code_doc
    DPUSH rax
    # /[a-z]$/: typeof, void, delete
    mov rax, [rbx + N_F1]
    cmp rax, J_TYPEOF
    je 1f
    cmp rax, J_VOID
    je 1f
    cmp rax, J_DELETE
    jne 2f
1:  DPUSHL ps_space
2:  PRINT N_F0, K_argument
    mov r13, rax
    mov rdi, [rbx + N_F0]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jz 3f
    DMARK r14
    DPUSHL d_softline
    DPUSH r13
    DARRAY r14
    INDENT_RAX
    mov r13, rax
    DMARK r14
    DPUSHL ps_lparen
    DPUSH r13
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r14
    GROUP_RAX
    mov r13, rax
3:  DPUSH r13
    DARRAY r12
    EPILOGUE
ENDF pes_unary

# [prefix ? operator : "", print("argument"), prefix ? "" : operator]
FUNC pes_update
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rbx + N_F1]
    call pjs_code_doc
    mov r13, rax
    DMARK r12
    ATTR rbx, NA_PREFIX
    jz 1f
    DPUSH r13
1:  PRINT N_F0, K_argument
    DPUSH rax
    ATTR rbx, NA_PREFIX
    jnz 2f
    DPUSH r13
2:  DARRAY r12
    EPILOGUE
ENDF pes_update

# VariableDeclaration
FUNC pes_variable_declaration
    PROLOGUE 4
    mov rbx, rdi
    mov edi, N_F0
    mov esi, K_declarations
    xor edx, edx
    call print_map
    mov r12, rax                    # printed
    call path_parent
    mov r13, rax
    xor r14d, r14d                  # isParentForLoop
    TYPE r13, T_ForStatement
    je 1f
    TYPE r13, T_ForInStatement
    je 1f
    TYPE r13, T_ForOfStatement
    jne 2f
1:  mov r14d, 1
    # hasValue
2:  mov rcx, [rbx + N_F0]
    xor edx, edx
    xor r15d, r15d
3:  cmp rdx, [rcx]
    jae 4f
    mov rax, [rcx + 8 + rdx*8]
    inc rdx
    cmp qword ptr [rax + N_F1], 0
    je 3b
    mov r15d, 1
4:  # firstVariable
    mov qword ptr [rsp], 0
    cmp qword ptr [r12], 0
    je 6f
    mov rax, [r12 + 8]
    mov [rsp], rax
    cmp qword ptr [r12], 1
    jne 5f
    mov rdi, [rbx + N_F0]
    mov rdi, [rdi + 8]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jz 6f
5:  mov rdi, [rsp]
    call doc_indent
    mov [rsp], rax
6:  # indent(printed.slice(1).map(p => [",", sep, p]))
    lea rax, [rip + d_line]
    test r14d, r14d
    jnz 7f
    test r15d, r15d
    jz 7f
    lea rax, [rip + d_hardline]
7:  mov [rsp + 8], rax
    DMARK rax
    mov [rsp + 16], rax
    mov r15d, 1
8:  cmp r15, [r12]
    jae 81f
    lea rdi, [rip + ps_comma]
    mov rsi, [rsp + 8]
    mov rdx, [r12 + 8 + r15*8]
    call doc_array3
    DPUSH rax
    inc r15
    jmp 8b
81: mov rdi, [rsp + 16]
    call ss_to_array
    INDENT_RAX
    mov [rsp + 16], rax
    DMARK r15
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    mov rdi, [rbx + N_F1]
    call pjs_code_doc
    DPUSH rax
    cmp qword ptr [rsp], 0
    je 82f
    DPUSHL ps_space
    DPUSH [rsp]
82: DPUSH [rsp + 16]
    # semi unless the declaration is the init or left of a for loop
    test r14d, r14d
    jz 83f
    mov rax, [r13 + N_F2]           # ForInStatement.body, ForOfStatement.body
    TYPE r13, T_ForStatement
    jne 85f
    mov rax, [r13 + N_F3]           # ForStatement.body
85: cmp rax, rbx
    jne 84f
83: call pjs_semi_doc
    DPUSH rax
84: DARRAY r15
    GROUP_RAX
    EPILOGUE
ENDF pes_variable_declaration

# group(["with (", print("object"), ")", adjustClause(node.body, print("body"))])
FUNC pes_with
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_with_open
    PRINT N_F0, K_object
    DPUSH rax
    DPUSHL ps_rparen
    PRINT N_F1, K_body
    mov rdi, [rbx + N_F1]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pes_with

# IfStatement
FUNC pes_if
    PROLOGUE 2
    mov rbx, rdi
    PRINT N_F1, K_consequent
    mov rdi, [rbx + N_F1]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    mov r13, rax                    # consequent clause
    PRINT N_F0, K_test
    mov rdi, rax
    call pes_soft_group
    mov r14, rax
    DMARK r12
    DPUSHL sd_if_open
    DPUSH r14
    DPUSHL ps_rparen
    DPUSH r13
    DARRAY r12
    GROUP_RAX
    mov r13, rax                    # opening
    DMARK r12
    DPUSH r13
    cmp qword ptr [rbx + N_F2], 0
    je 9f
    mov rdi, [rbx + N_F1]
    mov esi, CC_Trailing | CC_Line
    xor edx, edx
    call has_comment
    mov r14d, eax
    test eax, eax
    jnz 1f
    mov rdi, rbx
    call pjs_needs_hardline_after_dangling_comment
    mov r14d, eax                   # commentOnOwnLine
1:  lea rdi, [rip + d_hardline]
    test r14d, r14d
    jnz 2f
    mov rax, [rbx + N_F1]
    TYPE rax, T_BlockStatement
    jne 2f
    lea rdi, [rip + ps_space]
2:  call ss_push
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 4f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
    lea rdi, [rip + ps_space]
    test r14d, r14d
    jz 3f
    lea rdi, [rip + d_hardline]
3:  call ss_push
4:  DPUSHL sd_else
    PRINT N_F2, K_alternate
    mov rsi, rax
    mov rdi, [rbx + N_F2]
    xor edx, edx
    TYPE rdi, T_IfStatement
    sete dl
    call pjs_adjust_clause
    GROUP_RAX
    DPUSH rax
9:  DARRAY r12
    EPILOGUE
ENDF pes_if

# ForStatement
FUNC pes_for
    PROLOGUE 2
    mov rbx, rdi
    PRINT N_F3, K_body
    mov rdi, [rbx + N_F3]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    mov r13, rax                    # body
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    mov r14, rax
    test rax, rax
    jz 1f
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    mov r14, rax                    # printedComments
1:  cmp qword ptr [rbx + N_F0], 0
    jne 2f
    cmp qword ptr [rbx + N_F1], 0
    jne 2f
    cmp qword ptr [rbx + N_F2], 0
    jne 2f
    lea rdi, [rip + sd_for_ever]
    mov rsi, r13
    call doc_array2
    GROUP_RAX
    mov rdi, r14
    mov rsi, rax
    call doc_array2
    jmp 9f
2:  DMARK r12
    DPUSHL d_softline
    PRINT N_F0, K_init
    DPUSH rax
    DPUSHL ps_semi
    DPUSHL d_line
    PRINT N_F1, K_test
    DPUSH rax
    DPUSHL ps_semi
    DPUSHL d_line
    PRINT N_F2, K_update
    DPUSH rax
    DARRAY r12
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    GROUP_RAX
    mov r15, rax
    DMARK r12
    DPUSHL sd_for_open
    DPUSH r15
    DPUSHL ps_rparen
    DPUSH r13
    DARRAY r12
    GROUP_RAX
    mov rdi, r14
    mov rsi, rax
    call doc_array2
9:  EPILOGUE
ENDF pes_for

# group(["while (", group([indent([softline, print("test")]), softline]), ")",
# adjustClause(node.body, print("body"))])
FUNC pes_while
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_while_open
    PRINT N_F0, K_test
    mov rdi, rax
    call pes_soft_group
    DPUSH rax
    DPUSHL ps_rparen
    PRINT N_F1, K_body
    mov rdi, [rbx + N_F1]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pes_while

# group(["for (", print("left"), " in ", print("right"), ")", adjustClause(...)])
FUNC pes_for_in
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_for_open
    PRINT N_F0, K_left
    DPUSH rax
    DPUSHL sd_in_sp
    PRINT N_F1, K_right
    DPUSH rax
    DPUSHL ps_rparen
    PRINT N_F2, K_body
    mov rdi, [rbx + N_F2]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pes_for_in

# group(["for", await ? " await" : "", " (", print("left"), " of ",
# print("right"), ")", adjustClause(...)])
FUNC pes_for_of
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_for
    ATTR rbx, NA_AWAIT
    jz 1f
    DPUSHL sd_await_sp
1:  DPUSHL sd_paren_open_sp
    PRINT N_F0, K_left
    DPUSH rax
    DPUSHL sd_of_sp
    PRINT N_F1, K_right
    DPUSH rax
    DPUSHL ps_rparen
    PRINT N_F2, K_body
    mov rdi, [rbx + N_F2]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pes_for_of

# DoWhileStatement
FUNC pes_do_while
    PROLOGUE
    mov rbx, rdi
    PRINT N_F1, K_body
    mov rdi, [rbx + N_F1]
    mov rsi, rax
    xor edx, edx
    call pjs_adjust_clause
    lea rdi, [rip + sd_do]
    mov rsi, rax
    call doc_array2
    GROUP_RAX
    mov r13, rax
    DMARK r12
    DPUSH r13
    lea rdi, [rip + d_hardline]
    mov rax, [rbx + N_F1]
    TYPE rax, T_BlockStatement
    jne 1f
    lea rdi, [rip + ps_space]
1:  call ss_push
    DPUSHL sd_while_open
    PRINT N_F0, K_test
    mov rdi, rax
    call pes_soft_group
    DPUSH rax
    DPUSHL ps_rparen
    call pjs_semi_doc
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pes_do_while

# [break|continue, label ? [" ", print("label")] : "", semi]
FUNC pes_break_continue
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    lea rdi, [rip + sd_break]
    TYPE rbx, T_BreakStatement
    je 1f
    lea rdi, [rip + sd_continue]
1:  call ss_push
    cmp qword ptr [rbx + N_F0], 0
    je 2f
    DPUSHL ps_space
    PRINT N_F0, K_label
    DPUSH rax
2:  call pjs_semi_doc
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pes_break_continue

# LabeledStatement
FUNC pes_labeled
    PROLOGUE
    mov rbx, rdi
    PRINT N_F0, K_label
    mov r12, rax
    mov rax, [rbx + N_F1]
    TYPE rax, T_EmptyStatement
    jne 1f
    mov rdi, r12
    lea rsi, [rip + sd_colon_semi]
    call doc_array2
    jmp 9f
1:  PRINT N_F1, K_body
    mov rdi, r12
    lea rsi, [rip + sd_colon_sp]
    mov rdx, rax
    call doc_array3
9:  EPILOGUE
ENDF pes_labeled

# ["try ", print("block"), handler ? [" ", print("handler")] : "",
#  finalizer ? [" finally ", print("finalizer")] : ""]
FUNC pes_try
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_try
    PRINT N_F0, K_block
    DPUSH rax
    cmp qword ptr [rbx + N_F1], 0
    je 1f
    DPUSHL ps_space
    PRINT N_F1, K_handler
    DPUSH rax
1:  cmp qword ptr [rbx + N_F2], 0
    je 2f
    DPUSHL sd_finally
    PRINT N_F2, K_finalizer
    DPUSH rax
2:  DARRAY r12
    EPILOGUE
ENDF pes_try

# CatchClause
FUNC pes_catch
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_catch
    cmp qword ptr [rbx + N_F0], 0
    je 5f
    mov rdi, [rbx + N_F0]
    xor esi, esi
    lea rdx, [rip + catch_param_comment]
    call has_comment
    mov r14d, eax
    PRINT N_F0, K_param
    mov r13, rax
    DPUSHL ps_lparen
    test r14d, r14d
    jz 1f
    lea rdi, [rip + d_softline]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
    DPUSH rax
    DPUSHL d_softline
    jmp 2f
1:  DPUSH r13
2:  DPUSHL sd_paren_close_sp
5:  PRINT N_F1, K_body
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pes_catch

# !isBlockComment(comment) || (comment.leading && hasNewline(text, locEnd(comment)))
# || (comment.trailing && hasNewline(text, locStart(comment), {backwards: true}))
FUNC catch_param_comment
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov eax, 1
    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK
    jne 9f
    test byte ptr [rbx + CM_FLAGS], CF_LEADING
    jz 1f
    mov edi, [rbx + CM_END]
    xor esi, esi
    call has_newline
    test eax, eax
    jnz 9f
1:  xor eax, eax
    test byte ptr [rbx + CM_FLAGS], CF_TRAILING
    jz 9f
    mov edi, [rbx + CM_START]
    mov esi, 1
    call has_newline
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF catch_param_comment

# SwitchStatement
FUNC pes_switch
    PROLOGUE
    mov rbx, rdi
    PRINT N_F0, K_discriminant
    lea rdi, [rip + d_softline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov r13, rax
    DMARK r12
    DPUSHL sd_switch_open
    DPUSH r13
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r12
    GROUP_RAX
    mov r13, rax
    DMARK r12
    DPUSH r13
    DPUSHL sd_brace_open_sp
    mov r13, [rbx + N_F1]           # cases
    VLEN r14, r13
    test r14, r14
    jz 5f
    # join(hardline, cases.map(c => [print(), !isLast && isNextLineEmpty ? hardline : ""]))
    DMARK r15
    DPUSHL d_hardline
    xor ebx, ebx
1:  cmp rbx, r14
    jae 4f
    test rbx, rbx
    jz 2f
    DPUSHL d_hardline
2:  mov rdi, r13
    mov rsi, rbx
    mov edx, K_cases
    xor ecx, ecx
    call print_elem
    DPUSH rax
    lea rax, [rbx + 1]
    cmp rax, r14
    jae 3f
    mov rdi, [r13 + 8 + rbx*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 3f
    DPUSHL d_hardline
3:  inc rbx
    jmp 1b
4:  DARRAY r15
    INDENT_RAX
    DPUSH rax
5:  DPUSHL d_hardline
    DPUSHL ps_rbrace
    DARRAY r12
    EPILOGUE
ENDF pes_switch

# SwitchCase
FUNC pes_switch_case
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    cmp qword ptr [rbx + N_F0], 0
    je 1f
    DPUSHL sd_case
    PRINT N_F0, K_test
    DPUSH rax
    DPUSHL ps_colon
    jmp 2f
1:  DPUSHL sd_default
2:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 3f
    DPUSHL ps_space
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
    # consequent without EmptyStatements: count and the first one
3:  mov r13, [rbx + N_F1]
    xor r14d, r14d                  # count
    xor r15d, r15d                  # first
    xor ecx, ecx
    test r13, r13
    jz 5f
4:  cmp rcx, [r13]
    jae 5f
    mov rax, [r13 + 8 + rcx*8]
    inc rcx
    TYPE rax, T_EmptyStatement
    je 4b
    test r14, r14
    jnz 41f
    mov r15, rax
41: inc r14
    jmp 4b
5:  test r14, r14
    jz 9f
    mov rdi, rbx
    mov esi, K_consequent
    mov rdx, r13
    call pjs_print_statement_sequence
    mov r13, rax
    cmp r14, 1
    jne 6f
    TYPE r15, T_BlockStatement
    jne 6f
    lea rdi, [rip + ps_space]
    mov rsi, r13
    call doc_array2
    jmp 7f
6:  lea rdi, [rip + d_hardline]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
7:  DPUSH rax
9:  DARRAY r12
    EPILOGUE
ENDF pes_switch_case

# ["debugger", semi]
FUNC pes_debugger
    PROLOGUE
    call pjs_semi_doc
    lea rdi, [rip + sd_debugger]
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pes_debugger
