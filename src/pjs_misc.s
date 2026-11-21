# print/misc.js
.include "pjs.inc"

SDOC sd_bang, "!"
SDOC sd_declare, "declare "
SDOC sd_abstract, "abstract "
SDOC sd_private_sp, "private "
SDOC sd_protected_sp, "protected "
SDOC sd_public_sp, "public "

# pjs_adjust_clause(node, clause, force_space) -> rax (adjustClause)
FUNC pjs_adjust_clause
    TYPE rdi, T_EmptyStatement
    jne 1f
    lea rax, [rip + ps_semi]
    leave
    ret
1:  test edx, edx
    jnz 2f
    TYPE rdi, T_BlockStatement
    je 2f
    lea rdi, [rip + d_line]
    call doc_array2
    mov rdi, rax
    call doc_indent
    leave
    ret
2:  lea rdi, [rip + ps_space]
    call doc_array2
    leave
    ret
ENDF pjs_adjust_clause

# pjs_print_rest_spread(node, args) -> rax: ["...", print("argument"),
# printTypeAnnotationProperty(path, print)]
FUNC pjs_print_rest_spread
    PROLOGUE
    PRINT N_F0, K_argument
    mov rbx, rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    lea rdi, [rip + ps_ellipsis]
    mov rsi, rbx
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pjs_print_rest_spread

# pjs_print_optional_token(node) -> rax (printOptionalToken); an Identifier is
# the path's top
FUNC pjs_print_optional_token
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    test dword ptr [rdi + N_ATTR], NA_OPTIONAL
    jz 9f
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 3f
    # node === path.parent.key: "?" is printed in printMethod
    call path_key
    cmp eax, K_key
    mov eax, 0
    je 9f
    mov rdi, rbx
3:  lea rax, [rip + ps_qdot]
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_CallExpression
    je 9f
    cmp ecx, T_OptionalCallExpression
    je 9f
    cmp ecx, T_MemberExpression
    je 1f
    cmp ecx, T_OptionalMemberExpression
    jne 2f
1:  test dword ptr [rdi + N_ATTR], NA_COMPUTED
    jnz 9f
2:  lea rax, [rip + ps_question]
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_print_optional_token

# pjs_print_definite_token() -> rax (printDefiniteToken): "!" when the node at
# the path's top is definite or is the id of a definite VariableDeclarator
FUNC pjs_print_definite_token
    call path_value
    test dword ptr [rax + N_ATTR], NA_DEFINITE
    jnz 1f
    cmp word ptr [rax + N_TYPE], T_Identifier
    je 3f
    xor eax, eax
    leave
    ret
3:  call path_key
    cmp eax, K_id
    jne 8f
    call path_parent
    test rax, rax
    jz 8f
    cmp word ptr [rax + N_TYPE], T_VariableDeclarator
    jne 8f
    test dword ptr [rax + N_ATTR], NA_DEFINITE
    jz 8f
1:  lea rax, [rip + sd_bang]
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF pjs_print_definite_token

# pjs_print_declare_token(node) -> rax (printDeclareToken)
FUNC pjs_print_declare_token
    xor eax, eax
    test dword ptr [rdi + N_ATTR], NA_DECLARE
    jz 9f
    lea rax, [rip + sd_declare]
9:  leave
    ret
ENDF pjs_print_declare_token

# pjs_print_abstract_token(node) -> rax (printAbstractToken)
FUNC pjs_print_abstract_token
    xor eax, eax
    test dword ptr [rdi + N_ATTR], NA_ABSTRACT
    jz 9f
    lea rax, [rip + sd_abstract]
9:  leave
    ret
ENDF pjs_print_abstract_token

# pjs_print_ts_accessibility_token(node) -> rax
# (printTypeScriptAccessibilityToken); only for the types whose F7 is
# accessibility
FUNC pjs_print_ts_accessibility_token
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_Identifier
    je 9f
    mov rcx, [rdi + N_F7]
    lea rax, [rip + sd_private_sp]
    cmp rcx, KD_PRIVATE
    je 9f
    lea rax, [rip + sd_protected_sp]
    cmp rcx, KD_PROTECTED
    je 9f
    lea rax, [rip + sd_public_sp]
    cmp rcx, KD_PUBLIC
    je 9f
    xor eax, eax
9:  leave
    ret
ENDF pjs_print_ts_accessibility_token

# pjs_print_function_type_parameters() -> rax (printFunctionTypeParameters):
# print("typeParameters") of the node at the path's top, or ""
FUNC pjs_print_function_type_parameters
    call path_value
    cmp qword ptr [rax + N_F4], 0
    je 9f
    PRINT N_F4, K_typeParameters
    leave
    ret
9:  xor eax, eax
    leave
    ret
ENDF pjs_print_function_type_parameters
