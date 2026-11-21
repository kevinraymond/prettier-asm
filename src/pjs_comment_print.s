# The JS printer's comment methods: src/language-js/comments/printer-methods.js,
# src/language-js/print/comment.js, and the ignore and comment-kind utils of
# src/language-js/utils/. GAP marks branches for node types the parser does
# not produce yet.
.include "pjs.inc"

    .text

# pjs_can_attach_comment(node) -> eax (canAttachComment)
FUNC pjs_can_attach_comment
    movzx ecx, word ptr [rdi + N_TYPE]
    xor eax, eax
    cmp ecx, T_EmptyStatement
    je 9f
    cmp ecx, T_TemplateElement
    je 9f
    # GAP(ts, estree): TSEmptyBodyFunctionExpression, ChainExpression
    mov eax, 1
9:  leave
    ret
ENDF pjs_can_attach_comment

# pjs_get_comment_child_nodes(node) -> rax: VEC, or 0 for undefined
# (getCommentChildNodes). It returns a list only for a MethodDefinition under
# the estree parsers; under babel it is always undefined.
FUNC pjs_get_comment_child_nodes
    # GAP(typescript, flow and the other estree parsers): MethodDefinition with
    # an empty parameter list returns [...decorators, key, value.body]
    xor eax, eax
    leave
    ret
ENDF pjs_get_comment_child_nodes

# pjs_is_block_comment(comment) -> eax (isBlockComment)
FUNC pjs_is_block_comment
    xor eax, eax
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    sete al
    leave
    ret
ENDF pjs_is_block_comment

# pjs_is_gap(start, end) -> eax: isGap, -1 for undefined. Only the flow
# parsers have one.
FUNC pjs_is_gap
    mov eax, -1
    leave
    ret
ENDF pjs_is_gap

# pjs_is_type_cast_comment(comment) -> eax (isTypeCastComment)
FUNC pjs_is_type_cast_comment
    call is_type_cast_comment
    leave
    ret
ENDF pjs_is_type_cast_comment

# pjs_is_prettier_ignore_comment(comment) -> eax (isPrettierIgnoreComment):
# value.trim() === "prettier-ignore" and not unignored
FUNC pjs_is_prettier_ignore_comment
    call is_prettier_ignore_comment
    leave
    ret
ENDF pjs_is_prettier_ignore_comment

# pjs_has_ignore_comment(node) -> eax (hasNodeIgnoreComment): node.prettierIgnore,
# or a prettier-ignore comment attached to the node
FUNC pjs_has_ignore_comment
    xor eax, eax
    test rdi, rdi
    jz 9f
    test word ptr [rdi + N_FLAGS], NF_PRETTIER_IGNORE
    jnz 1f
    mov esi, CC_PrettierIgnore
    xor edx, edx
    call has_comment
    jmp 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pjs_has_ignore_comment

# pjs_is_ignored() -> eax (utils/is-ignored.js) for the node at the top of the path
FUNC pjs_is_ignored
    call path_value
    mov rdi, rax
    call pjs_has_ignore_comment
    # GAP(jsx): hasJsxIgnoreComment(path)
    leave
    ret
ENDF pjs_is_ignored

# pjs_will_print_own_comments() -> eax (willPrintOwnComments) for the node at
# the top of the path
FUNC pjs_will_print_own_comments
    PROLOGUE
    call path_value
    mov rbx, rax
    call path_parent
    mov r12, rax
    # GAP(jsx): isJsxElement(node); parent JSXSpreadAttribute or JSXSpreadChild
    test r12, r12
    jz 8f
    mov rdi, r12
    call pjc_is_union_type
    test eax, eax
    jnz 7f
    movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_ClassDeclaration
    je 1f
    cmp eax, T_ClassExpression
    jne 8f
1:  cmp rbx, [r12 + N_F1]               # superClass
    jne 8f
    mov rdi, rbx
    call pjs_has_ignore_comment
    xor eax, 1
    EPILOGUE
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
ENDF pjs_will_print_own_comments

# pjs_print_comment(comment) -> rax doc (printComment of print/comment.js):
# a line comment or hashbang is its text with trailing whitespace trimmed; an
# indentable block comment is re-indented; another block comment is printed
# as it is, with its line breaks as literal lines.
FUNC pjs_print_comment
    PROLOGUE
    mov rbx, rdi
    call pjs_is_line_comment
    test eax, eax
    jz 1f
    mov r12d, [rbx + CM_START]
    mov rdi, [rip + g_text]
    mov rsi, r12
    mov edx, [rbx + CM_END]
    call trim_end_bytes
    mov rdi, r12
    mov rsi, rax
    call doc_text
    EPILOGUE
1:  mov rdi, rbx
    call is_indentable_block_comment
    test eax, eax
    jz 2f
    mov rdi, rbx
    call print_indentable_block_comment
    EPILOGUE
    # ["/*", replaceEndOfLine(comment.value), "*/"]
2:  mov r12d, [rbx + CM_START]
    mov rdi, [rip + g_text]
    lea rdi, [rdi + r12 + 2]
    mov esi, [rbx + CM_END]
    sub esi, r12d
    sub esi, 4
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    lea rdi, [rip + pjc_sd_open_block]
    mov rsi, rax
    lea rdx, [rip + pjc_sd_close_block]
    call doc_array3
    EPILOGUE
ENDF pjs_print_comment

SDOC pjc_sd_open_block, "/*"
SDOC pjc_sd_close_block, "*/"

# pjs_check_ts_comments(): for a TypeScript file, after attachComments.
# Prettier's CLI parses TypeScript with typescript-estree, whose tree differs
# from babel-ts where comments can land: a method is MethodDefinition{key,
# value: FunctionExpression} (or a TSEmptyBodyFunctionExpression), an optional
# chain is wrapped in a ChainExpression, a template literal type is
# TSTemplateLiteralType, and TSTypeParameter.name covers only the name. A
# comment decorated in one of those places would attach elsewhere, so it refuses.
# getCommentChildNodes gives a MethodDefinition without parameters and return
# type the children [decorators, key, value.body], so a comment in its type
# parameters attaches elsewhere too.
FUNC pjs_check_ts_comments
    PROLOGUE 2
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    jne 99f
    mov rbx, [rip + g_comments]
    test rbx, rbx
    jz 99f
    cmp dword ptr [rbx], 0
    je 99f
    # the type parameter ranges of methods without parameters and return type
    call ss_mark
    mov [rsp], rax
    mov rdi, [rip + g_root]
    call pcp_collect_bare_methods
    mov rdi, [rsp]
    call ss_to_vec
    mov [rsp + 8], rax
    xor r12d, r12d
1:  cmp r12d, [rbx]
    jae 99f
    mov r13, [rbx + 8 + r12*8]
    mov rcx, [rsp + 8]
    mov rdx, [rcx]
    mov eax, [r13 + CM_START]
11: test rdx, rdx
    jz 12f
    mov r8, [rcx + rdx*8]
    dec rdx
    cmp eax, [r8 + N_START]
    jb 11b
    cmp eax, [r8 + N_END]
    jae 11b
    jmp 91f
12:
    inc r12d
    mov r14, [r13 + CM_ENCL]
    test r14, r14
    jz 5f
    movzx eax, word ptr [r14 + N_TYPE]
    # directly inside a method, after its key: inside typescript-estree's value node
    cmp eax, T_ClassMethod
    je 2f
    cmp eax, T_ClassPrivateMethod
    je 2f
    cmp eax, T_TSDeclareMethod
    je 2f
    cmp eax, T_ObjectMethod
    jne 31f
2:  mov rcx, [r14 + N_F0]
    mov ecx, [rcx + N_END]
    cmp [r13 + CM_START], ecx
    jae 91f
    jmp 5f
    # after a superclass read as a TSInstantiationExpression (`extends B<T>` and a
    # line break) and before `implements`: typescript-estree has superClass B and
    # superTypeArguments, so handleClassComments sees another preceding node.
    # Before the body both trees give the body's first comment.
31: cmp eax, T_ClassDeclaration
    je 32f
    cmp eax, T_ClassExpression
    jne 3f
32: mov rcx, [r14 + N_F1]
    test rcx, rcx
    jz 5f
    cmp word ptr [rcx + N_TYPE], T_TSInstantiationExpression
    jne 5f
    cmp rcx, [r13 + CM_PREC]
    jne 5f
    mov rcx, [r14 + N_F2]
    cmp rcx, [r13 + CM_FOLL]
    jne 97f
    jmp 5f
    # inside a template literal type
3:  cmp eax, T_TemplateLiteral
    jne 4f
    mov rdi, r14
    call pcp_is_template_literal_type
    test eax, eax
    jnz 92f
    jmp 5f
    # export * as ns: typescript-estree's ExportAllDeclaration has no specifier
4:  cmp eax, T_ExportNamespaceSpecifier
    je 95f
    cmp eax, T_ExportNamedDeclaration
    jne 41f
    mov rcx, [r14 + N_F1]
    test rcx, rcx
    jz 5f
    cmp qword ptr [rcx], 0
    je 5f
    mov rcx, [rcx + 8]
    cmp word ptr [rcx + N_TYPE], T_ExportNamespaceSpecifier
    je 95f
    jmp 5f
    # export import a = b: typescript-estree's ExportNamedDeclaration around it
41: cmp eax, T_TSImportEqualsDeclaration
    jne 42f
    test dword ptr [r14 + N_ATTR], NA_IS_EXPORT
    jz 5f
    mov edi, [r14 + N_START]
    add edi, 6
    call next_nonspace_noncomment_index
    cmp [r13 + CM_START], eax
    jb 96f
    jmp 5f
    # a type parameter's modifiers: typescript-estree's name covers only the name
42: cmp eax, T_TSTypeParameter
    jne 43f
    mov rcx, [r14 + N_F0]
    mov rcx, [rcx + N_F0]
    test rcx, rcx
    jz 5f
    dec ecx
    cmp [r13 + CM_START], ecx
    jb 93f
    jmp 5f
43: cmp eax, T_Identifier
    jne 5f
    mov rcx, [r14 + N_F0]
    test rcx, rcx
    jz 5f
    dec ecx
    cmp [r13 + CM_START], ecx
    jb 93f
    # inside an optional chain, or next to its outermost node
5:  mov rdi, r14
    call pcp_is_chainish
    test eax, eax
    jnz 94f
    mov rdi, [r13 + CM_PREC]
    mov rsi, r14
    call pcp_is_chain_top
    test eax, eax
    jnz 94f
    mov rdi, [r13 + CM_FOLL]
    mov rsi, r14
    call pcp_is_chain_top
    test eax, eax
    jnz 94f
    jmp 1b
99: EPILOGUE
91: REFUSE "comment in a method's signature (typescript-estree's method value node attaches it differently)"
92: REFUSE "comment in a template literal type (typescript-estree's TSTemplateLiteralType)"
93: REFUSE "comment between a type parameter's modifiers and its name"
95: REFUSE "comment in `export * as ns` (typescript-estree's ExportAllDeclaration)"
96: REFUSE "comment between `export` and `import` (typescript-estree's ExportNamedDeclaration)"
94: REFUSE "comment in or next to an optional chain (typescript-estree's ChainExpression)"
97: REFUSE "comment between a superclass's type arguments, a line break and `implements` (typescript-estree's superTypeArguments)"
ENDF pjs_check_ts_comments

# pcp_collect_bare_methods(node): pushes on the scratch stack the type
# parameters of every method under node that has type parameters, a body, no
# parameters and no return type
FUNC pcp_collect_bare_methods
    PROLOGUE
    mov rbx, rdi
    test rbx, rbx
    jz 9f
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ClassMethod
    je 1f
    cmp eax, T_ClassPrivateMethod
    je 1f
    cmp eax, T_ObjectMethod
    jne 3f
1:  cmp qword ptr [rbx + N_F4], 0
    je 3f
    cmp qword ptr [rbx + N_F5], 0
    jne 3f
    cmp qword ptr [rbx + N_F2], 0
    je 3f
    mov rax, [rbx + N_F1]
    VLEN rcx, rax
    test rcx, rcx
    jnz 3f
    mov rdi, [rbx + N_F4]
    call ss_push
    # children by visitor keys
3:  movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_visitor_keys]
    mov r12, [rcx + rax*8]
4:  movzx r13d, byte ptr [r12]
    test r13d, r13d
    jz 9f
    inc r12
    mov r14d, r13d
    and r14d, 0x7f
    mov r15, [rbx + r14]
    test r13d, 0x80
    jnz 5f
    mov rdi, r15
    call pcp_collect_bare_methods
    jmp 4b
5:  test r15, r15
    jz 4b
    xor r13d, r13d
6:  cmp r13, [r15]
    jae 4b
    mov rdi, [r15 + 8 + r13*8]
    call pcp_collect_bare_methods
    inc r13
    jmp 6b
9:  EPILOGUE
ENDF pcp_collect_bare_methods

# pcp_is_template_literal_type(template) -> eax: one of its expressions is a type
FUNC pcp_is_template_literal_type
    mov rcx, [rdi + N_F1]
    xor eax, eax
    test rcx, rcx
    jz 9f
    mov rdx, [rcx]
1:  test rdx, rdx
    jz 9f
    mov r8, [rcx + rdx*8]
    dec rdx
    movzx r8d, word ptr [r8 + N_TYPE]
    cmp r8d, T_TSParameterProperty
    jb 1b
    cmp r8d, T_TSInstantiationExpression
    je 1b
    cmp r8d, T_TSAsExpression
    je 1b
    cmp r8d, T_TSSatisfiesExpression
    je 1b
    cmp r8d, T_TSTypeAssertion
    je 1b
    cmp r8d, T_TSNonNullExpression
    je 1b
    mov eax, 1
9:  leave
    ret
ENDF pcp_is_template_literal_type

# pcp_is_chainish(node) -> eax: an optional member or call, or a `!` on one
FUNC pcp_is_chainish
    xor eax, eax
1:  test rdi, rdi
    jz 9f
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_OptionalMemberExpression
    je 8f
    cmp ecx, T_OptionalCallExpression
    je 8f
    cmp ecx, T_TSNonNullExpression
    jne 9f
    mov rdi, [rdi + N_F0]
    jmp 1b
8:  mov eax, 1
9:  leave
    ret
ENDF pcp_is_chainish

# pcp_is_chain_top(node, enclosing) -> eax: node is chainish and enclosing does
# not continue its chain (an optional member or call, or a `!`, whose object,
# callee or expression is node)
FUNC pcp_is_chain_top
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call pcp_is_chainish
    test eax, eax
    jz 9f
    test r12, r12
    jz 9f
    cmp [r12 + N_F0], rbx
    jne 9f
    movzx ecx, word ptr [r12 + N_TYPE]
    cmp ecx, T_OptionalMemberExpression
    je 8f
    cmp ecx, T_OptionalCallExpression
    je 8f
    cmp ecx, T_TSNonNullExpression
    je 8f
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF pcp_is_chain_top
