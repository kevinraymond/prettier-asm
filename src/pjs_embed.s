# src/language-js/embed/: which template literals Prettier formats as another
# language (embed/index.js and the checks of css.js, graphql.js, html.js and
# markdown.js). Formatting them is not ported, so those refuse. The JSX cases
# (isStyledJsx's <style jsx>, isCssProp) cannot match.
.include "pjs.inc"

    .section .rodata
s_css: .asciz "css"
s_global: .asciz "global"
s_resolve: .asciz "resolve"
s_styled: .asciz "styled"
s_extend: .asciz "extend"
s_graphql: .asciz "graphql"
s_gql: .asciz "gql"
s_experimental: .asciz "experimental"
s_html: .asciz "html"
s_md: .asciz "md"
s_markdown: .asciz "markdown"
s_styles: .asciz "styles"
s_template: .asciz "template"
s_component: .asciz "Component"
    .balign 8
# isAngularComponentStyles and isAngularComponentTemplate (embed/utils.js)
pem_angular_styles_1:
    .quad pem_m_template_literal, pem_m_array_elements, pem_m_styles_value
    .quad pem_m_object_properties, pem_m_component_arguments, pem_m_decorator_expression
pem_angular_styles_2:
    .quad pem_m_template_literal, pem_m_styles_value
    .quad pem_m_object_properties, pem_m_component_arguments, pem_m_decorator_expression
pem_angular_template:
    .quad pem_m_template_literal, pem_m_template_value
    .quad pem_m_object_properties, pem_m_component_arguments, pem_m_decorator_expression
s_graphql_comment: .ascii " GraphQL "
s_html_comment: .ascii " HTML "
    .text

# pjs_embed(node) -> rax: embed(path) for the TemplateLiteral at the top of the
# path: 0 when Prettier does not embed it, "``" for a whitespace-only template
# it would embed; refuses when it would format the contents
FUNC pjs_embed
    PROLOGUE
    mov rbx, rdi
    call path_parent
    mov r12, rax
    # hasInvalidCookedValue
    mov rcx, [rbx + N_F0]
    xor edx, edx
1:  cmp rdx, [rcx]
    jae 2f
    mov rax, [rcx + 8 + rdx*8]
    inc rdx
    cmp qword ptr [rax + N_F0], 0
    jne 1b
    jmp 80f
2:  test r12, r12
    jz 80f
    # typescript-estree gives a template literal type its own node type
    # (TSTemplateLiteralType), which embed does not look at
    TYPE r12, T_TSLiteralType
    je 80f
    call pem_is_styled_jsx
    test eax, eax
    jnz 10f
    call pem_is_styled_components
    test eax, eax
    jnz 10f
    lea rdi, [rip + pem_angular_styles_1]
    mov esi, 6
    call path_match
    test eax, eax
    jnz 10f
    lea rdi, [rip + pem_angular_styles_2]
    mov esi, 5
    call path_match
    test eax, eax
    jnz 10f
    call pem_is_graphql
    test eax, eax
    jnz 10f
    call pem_is_html
    test eax, eax
    jnz 10f
    lea rdi, [rip + pem_angular_template]
    mov esi, 5
    call path_match
    test eax, eax
    jnz 10f
    call pem_is_markdown
    test eax, eax
    jz 80f
    # whitespace-only template literals
10: mov rcx, [rbx + N_F0]
    cmp qword ptr [rcx], 1
    jne 90f
    mov rcx, [rcx + 8]
    mov r13d, [rcx + N_END]
    mov rdi, [rip + g_text]
    mov esi, [rcx + N_START]
    mov rdx, r13
    call trim_start_bytes
    cmp rax, r13
    jne 90f
    lea rax, [rip + ps_double_backtick]
    jmp 99f
80: xor eax, eax
99: EPILOGUE
90: REFUSE "printer: embedded language in a template literal (embed)"
ENDF pjs_embed

# The checks below read rbx (the template literal) and r12 (its parent) of
# pjs_embed and return eax.

# pem_tag() -> rax: the parent's tag when the parent is a TaggedTemplateExpression, else 0
FUNC pem_tag
    xor eax, eax
    cmp word ptr [r12 + N_TYPE], T_TaggedTemplateExpression
    jne 9f
    mov rax, [r12 + N_F0]
9:  leave
    ret
ENDF pem_tag

# isStyledJsx without JSX: css``, css.global``, css.resolve``
FUNC pem_is_styled_jsx
    push r13
    sub rsp, 8
    call pem_tag
    test rax, rax
    jz 8f
    mov r13, rax
    mov rdi, rax
    lea rsi, [rip + s_css]
    call pjs_ident_is
    test eax, eax
    jnz 9f
    TYPE r13, T_MemberExpression
    jne 8f
    mov rdi, [r13 + N_F0]
    lea rsi, [rip + s_css]
    call pjs_ident_is
    test eax, eax
    jz 9f
    mov rdi, [r13 + N_F1]
    lea rsi, [rip + s_global]
    call pjs_ident_is
    test eax, eax
    jnz 9f
    mov rdi, [r13 + N_F1]
    lea rsi, [rip + s_resolve]
    call pjs_ident_is
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop r13
    leave
    ret
ENDF pem_is_styled_jsx

# pem_is_styled(node) -> eax: isStyledIdentifier
FUNC pem_is_styled
    lea rsi, [rip + s_styled]
    call pjs_ident_is
    leave
    ret
ENDF pem_is_styled

# pem_is_styled_extend(member) -> eax: /^[A-Z]/.test(object.name) && property.name === "extend"
FUNC pem_is_styled_extend
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    mov rcx, [rbx + N_F0]
    cmp word ptr [rcx + N_TYPE], T_Identifier
    jne 9f
    mov edx, [rcx + N_START]
    mov rcx, [rip + g_text]
    movzx ecx, byte ptr [rcx + rdx]
    sub ecx, 'A'
    cmp ecx, 25
    ja 9f
    mov rdi, [rbx + N_F1]
    lea rsi, [rip + s_extend]
    call pjs_ident_is
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pem_is_styled_extend

# isStyledComponents
FUNC pem_is_styled_components
    push r13
    push r14
    call pem_tag
    test rax, rax
    jz 8f
    mov r13, rax
    TYPE r13, T_ParenthesizedExpression
    jne 1f
    mov r13, [r13 + N_F0]
1:  movzx eax, word ptr [r13 + N_TYPE]
    cmp eax, T_MemberExpression
    je 10f
    cmp eax, T_CallExpression
    je 20f
    cmp eax, T_Identifier
    jne 8f
    mov rdi, r13
    lea rsi, [rip + s_css]
    call pjs_ident_is
    jmp 9f
10: mov rdi, [r13 + N_F0]
    call pem_is_styled
    test eax, eax
    jnz 9f
    mov rdi, r13
    call pem_is_styled_extend
    jmp 9f
20: mov r14, [r13 + N_F0]           # callee
    mov rdi, r14
    call pem_is_styled
    test eax, eax
    jnz 9f
    TYPE r14, T_MemberExpression
    jne 8f
    mov r14, [r14 + N_F0]           # callee.object
    TYPE r14, T_MemberExpression
    jne 21f
    mov rdi, [r14 + N_F0]
    call pem_is_styled
    test eax, eax
    jnz 9f
    mov rdi, r14
    call pem_is_styled_extend
    jmp 9f
21: TYPE r14, T_CallExpression
    jne 8f
    mov rdi, [r14 + N_F0]
    call pem_is_styled
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    leave
    ret
ENDF pem_is_styled_components

# pem_comment_is(comment, str, len) -> eax: the block comment's value is str
FUNC pem_comment_is
    xor eax, eax
    mov ecx, [rdi + CM_END]
    mov r8d, [rdi + CM_START]
    sub ecx, r8d
    sub ecx, 4
    cmp rcx, rdx
    jne 9f
    mov rdi, [rip + g_text]
    lea rdi, [rdi + r8 + 2]
    call mem_eq
9:  leave
    ret
ENDF pem_comment_is

FUNC pem_graphql_comment
    lea rsi, [rip + s_graphql_comment]
    mov edx, 9
    call pem_comment_is
    leave
    ret
ENDF pem_graphql_comment

FUNC pem_html_comment
    lea rsi, [rip + s_html_comment]
    mov edx, 6
    call pem_comment_is
    leave
    ret
ENDF pem_html_comment

    .section .rodata
s_const: .asciz "const"
    .text

# pem_has_language_comment(pred) -> eax (hasLanguageComment): a leading block
# comment on the node, or on its `as const` or ExpressionStatement parent,
# matching pred
FUNC pem_has_language_comment
    push r13
    sub rsp, 8
    mov r13, rdi
    mov rdi, rbx
    mov esi, CC_Block | CC_Leading
    mov rdx, r13
    call has_comment
    test eax, eax
    jnz 9f
    # isAsConstExpression(parent): `as const`
    TYPE r12, T_TSAsExpression
    jne 1f
    mov rax, [r12 + N_F5]
    TYPE rax, T_TSTypeReference
    jne 1f
    mov rdi, [rax + N_F0]
    lea rsi, [rip + s_const]
    call pjs_ident_is
    test eax, eax
    jz 1f
    mov rdi, r12
    mov esi, CC_Block | CC_Leading
    mov rdx, r13
    call has_comment
    test eax, eax
    jnz 9f
1:  TYPE r12, T_ExpressionStatement
    jne 9f
    mov rdi, r12
    mov esi, CC_Block | CC_Leading
    mov rdx, r13
    call has_comment
9:  add rsp, 8
    pop r13
    leave
    ret
ENDF pem_has_language_comment

# isGraphQL
FUNC pem_is_graphql
    push r13
    sub rsp, 8
    lea rdi, [rip + pem_graphql_comment]
    call pem_has_language_comment
    test eax, eax
    jnz 9f
    call pem_tag
    test rax, rax
    jz 5f
    mov r13, rax
    TYPE r13, T_MemberExpression
    jne 2f
    mov rdi, [r13 + N_F0]
    lea rsi, [rip + s_graphql]
    call pjs_ident_is
    test eax, eax
    jz 9f
    mov rdi, [r13 + N_F1]
    lea rsi, [rip + s_experimental]
    call pjs_ident_is
    jmp 9f
2:  mov rdi, r13
    lea rsi, [rip + s_gql]
    call pjs_ident_is
    test eax, eax
    jnz 9f
    mov rdi, r13
    lea rsi, [rip + s_graphql]
    call pjs_ident_is
    jmp 9f
5:  xor eax, eax
    TYPE r12, T_CallExpression
    jne 9f
    mov rdi, [r12 + N_F0]
    lea rsi, [rip + s_graphql]
    call pjs_ident_is
9:  add rsp, 8
    pop r13
    leave
    ret
ENDF pem_is_graphql

# isHtml (isAngularComponentTemplate needs a decorator)
FUNC pem_is_html
    lea rdi, [rip + pem_html_comment]
    call pem_has_language_comment
    test eax, eax
    jnz 9f
    call pem_tag
    test rax, rax
    jz 9f
    cmp [r12 + N_F1], rbx           # key === "quasi"
    jne 8f
    mov rdi, rax
    lea rsi, [rip + s_html]
    call pjs_ident_is
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF pem_is_html

# isMarkdown
FUNC pem_is_markdown
    push r13
    sub rsp, 8
    call pem_tag
    test rax, rax
    jz 9f
    mov r13, rax
    xor eax, eax
    mov rcx, [rbx + N_F0]
    cmp qword ptr [rcx], 1
    jne 9f
    mov rdi, r13
    lea rsi, [rip + s_md]
    call pjs_ident_is
    test eax, eax
    jnz 9f
    mov rdi, r13
    lea rsi, [rip + s_markdown]
    call pjs_ident_is
9:  add rsp, 8
    pop r13
    leave
    ret
ENDF pem_is_markdown

# path_match predicates of the Angular checks: pred(node, key, index) -> eax
FUNC pem_m_template_literal
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_TemplateLiteral
    sete al
    leave
    ret
ENDF pem_m_template_literal

FUNC pem_m_array_elements
    xor eax, eax
    cmp esi, K_elements
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_ArrayExpression
    sete al
9:  leave
    ret
ENDF pem_m_array_elements

# isObjectProperty(node) && !computed && key is the Identifier `name` && key === "value"
FUNC pem_m_property_named
    xor eax, eax
    cmp esi, K_value
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_ObjectProperty
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_COMPUTED
    jnz 9f
    mov rdi, [rdi + N_F0]
    mov rsi, rdx
    call pjs_ident_is
9:  leave
    ret
ENDF pem_m_property_named

FUNC pem_m_styles_value
    lea rdx, [rip + s_styles]
    call pem_m_property_named
    leave
    ret
ENDF pem_m_styles_value

FUNC pem_m_template_value
    lea rdx, [rip + s_template]
    call pem_m_property_named
    leave
    ret
ENDF pem_m_template_value

FUNC pem_m_object_properties
    xor eax, eax
    cmp esi, K_properties
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_ObjectExpression
    sete al
9:  leave
    ret
ENDF pem_m_object_properties

FUNC pem_m_component_arguments
    xor eax, eax
    cmp esi, K_arguments
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_CallExpression
    jne 9f
    mov rdi, [rdi + N_F0]
    lea rsi, [rip + s_component]
    call pjs_ident_is
9:  leave
    ret
ENDF pem_m_component_arguments

FUNC pem_m_decorator_expression
    xor eax, eax
    cmp esi, K_expression
    jne 9f
    cmp word ptr [rdi + N_TYPE], T_Decorator
    sete al
9:  leave
    ret
ENDF pem_m_decorator_expression
