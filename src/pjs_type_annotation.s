# print/type-annotation.js
.include "pjs.inc"

SDOC sd_arrow, "=>"
SDOC sd_brackets, "[]"
SDOC sd_infer, "infer "
SDOC sd_typeof, "typeof "
SDOC sd_asserts, "asserts "
SDOC sd_is, " is "
SDOC sd_colon_sp, ": "

    .text

# pjs_print_type_annotation_property(offset, key) -> rax
# (printTypeAnnotationProperty) for the node at the path's top: "" without the
# property, [" ", print(key)] when the annotation starts with "=>" or has a
# leading comment after its ":", else print(key)
FUNC pjs_print_type_annotation_property
    PROLOGUE
    mov r12d, edi
    mov r13d, esi
    call path_value
    mov rbx, rax
    mov r14, [rbx + r12]
    xor eax, eax
    test r14, r14
    jz 9f
    xor r15d, r15d                  # shouldPrintLeadingSpace
    TYPE r14, T_TSTypeAnnotation
    jne 5f
    mov rdi, rbx
    mov esi, r13d
    call pta_first_token
    cmp eax, 1
    je 4f
    test eax, eax
    jnz 5f
    mov rdi, r14
    mov esi, CC_Leading
    xor edx, edx
    call has_comment
    test eax, eax
    jz 5f
4:  mov r15d, 1
5:  mov edi, r12d
    mov esi, r13d
    xor edx, edx
    call print_field
    test r15d, r15d
    jz 9f
    lea rdi, [rip + ps_space]
    mov rsi, rax
    call doc_array2
9:  EPILOGUE
ENDF pjs_print_type_annotation_property

# pta_first_token(parent, key) -> eax (getTypeAnnotationFirstToken) for a
# TSTypeAnnotation that is `parent[key]`: 0 ":", 1 "=>", 2 ""
FUNC pta_first_token
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_TSFunctionType
    je 1f
    cmp ecx, T_TSConstructorType
    je 1f
    cmp ecx, T_TSTypePredicate
    jne 8f
    cmp esi, K_typeAnnotation
    jne 8f
    mov eax, 2
    leave
    ret
1:  cmp esi, K_returnType
    je 2f
    cmp esi, K_typeAnnotation
    jne 8f
2:  mov eax, 1
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF pta_first_token

# pjs_print_type_annotation(node, args) -> rax (printTypeAnnotation):
# [token, " ", print("typeAnnotation")], or print("typeAnnotation") without a token
FUNC pjs_print_type_annotation
    PROLOGUE
    call path_parent
    mov rbx, rax
    call path_key
    mov rdi, rbx
    mov esi, eax
    call pta_first_token
    mov r12d, eax
    PRINT N_F5, K_typeAnnotation
    cmp r12d, 2
    je 9f
    mov r13, rax
    DMARK r14
    lea rax, [rip + ps_colon]
    cmp r12d, 1
    jne 1f
    lea rax, [rip + sd_arrow]
1:  DPUSH rax
    DPUSHL ps_space
    DPUSH r13
    DARRAY r14
9:  EPILOGUE
ENDF pjs_print_type_annotation

# pjs_print_array_type(node, args) -> rax (printArrayType): [print("elementType"), "[]"]
FUNC pjs_print_array_type
    PRINT N_F0, K_elementType
    mov rdi, rax
    lea rsi, [rip + sd_brackets]
    call doc_array2
    leave
    ret
ENDF pjs_print_array_type

# pjs_print_infer_type(node, args) -> rax (printInferType): ["infer ", print("typeParameter")]
FUNC pjs_print_infer_type
    PRINT N_F0, K_typeParameter
    lea rdi, [rip + sd_infer]
    mov rsi, rax
    call doc_array2
    leave
    ret
ENDF pjs_print_infer_type

# pjs_print_rest_type(node, args) -> rax (printRestType): ["...", print("typeAnnotation")]
FUNC pjs_print_rest_type
    PRINT N_F5, K_typeAnnotation
    lea rdi, [rip + ps_ellipsis]
    mov rsi, rax
    call doc_array2
    leave
    ret
ENDF pjs_print_rest_type

# pjs_print_named_tuple_member(node, args) -> rax (printNamedTupleMember):
# [print("label"), optional ? "?" : "", ": ", print("elementType")]
FUNC pjs_print_named_tuple_member
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    PRINT N_F0, K_label
    DPUSH rax
    ATTR rbx, NA_OPTIONAL
    jz 1f
    DPUSHL ps_question
1:  DPUSHL sd_colon_sp
    PRINT N_F1, K_elementType
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_named_tuple_member

# pjs_print_indexed_access_type(node, args) -> rax (printIndexedAccessType):
# [print("objectType"), printOptionalToken(path), "[", print("indexType"), "]"]
FUNC pjs_print_indexed_access_type
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    PRINT N_F0, K_objectType
    DPUSH rax
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    DPUSHL ps_lbracket
    PRINT N_F1, K_indexType
    DPUSH rax
    DPUSHL ps_rbracket
    DARRAY r12
    EPILOGUE
ENDF pjs_print_indexed_access_type

# pjs_print_type_query(node, args) -> rax (printTypeQuery):
# ["typeof ", print("exprName"), print("typeParameters")]
FUNC pjs_print_type_query
    PROLOGUE
    DMARK r12
    DPUSHL sd_typeof
    PRINT N_F0, K_exprName
    DPUSH rax
    PRINT N_F4, K_typeParameters
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_type_query

# pjs_print_type_predicate(node, args) -> rax (printTypePredicate)
FUNC pjs_print_type_predicate
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    ATTR rbx, NA_ASSERTS
    jz 1f
    DPUSHL sd_asserts
1:  PRINT N_F0, K_parameterName
    DPUSH rax
    cmp qword ptr [rbx + N_F5], 0
    je 2f
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    lea rdi, [rip + sd_is]
    mov rsi, rax
    call doc_array2
    DPUSH rax
2:  DARRAY r12
    EPILOGUE
ENDF pjs_print_type_predicate

SDOC sd_bar_sp, "| "
SDOC sd_sp_bar_sp, " | "
SDOC sd_amp_spaced, " & "
SDOC sd_sp_amp, " &"
SDOC sd_amp_sp, "& "
SDOC sd_new_sp, "new "
SDOC sd_type_sp, "type "
SDOC sd_sp_eq, " ="

    .bss
    .balign 8
pta_line_bar: .quad 0               # [line, "| "]

    .text

# pta_is_object_like_type(node) -> eax (isObjectLikeType)
FUNC pta_is_object_like_type
    xor eax, eax
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_TSTypeLiteral
    je 1f
    cmp ecx, T_TSTypeReference
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pta_is_object_like_type

# pjs_should_hug_type(node) -> eax (shouldHugType)
FUNC pjs_should_hug_type
    PROLOGUE
    mov rbx, rdi
    call pjs_is_simple_type
    test eax, eax
    jnz 9f
    mov rdi, rbx
    call pjs_is_object_type
    test eax, eax
    jnz 9f
    TYPE rbx, T_TSUnionType
    jne 8f
    # shouldHugUnionType
    mov r12, [rbx + N_F0]
    VLEN r13, r12
    xor r14d, r14d
1:  cmp r14, r13
    jae 2f
    mov rdi, [r12 + 8 + r14*8]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    inc r14
    jmp 1b
2:  xor r14d, r14d                  # objectType
    xor ecx, ecx
3:  cmp rcx, r13
    jae 4f
    mov rdi, [r12 + 8 + rcx*8]
    inc rcx
    mov r15, rcx
    call pta_is_object_like_type
    mov rcx, r15
    test eax, eax
    jz 3b
    mov r14, [r12 + rcx*8]
4:  test r14, r14
    jz 8f
    xor ecx, ecx
5:  cmp rcx, r13
    jae 7f
    mov rax, [r12 + 8 + rcx*8]
    inc rcx
    cmp rax, r14
    je 5b
    movzx edx, word ptr [rax + N_TYPE]
    cmp edx, T_TSVoidKeyword
    je 5b
    cmp edx, T_TSNullKeyword
    je 5b
    jmp 8f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pjs_should_hug_type

# pjs_print_type_alias(node, args) -> rax (printTypeAlias):
# [printAssignment(path, options, print, [declare, "type ", print("id"),
# print("typeParameters")], " =", "typeAnnotation"), semi]
FUNC pjs_print_type_alias
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    DPUSHL sd_type_sp
    PRINT N_F0, K_id
    DPUSH rax
    PRINT N_F4, K_typeParameters
    DPUSH rax
    DARRAY r12
    mov rdi, rax
    lea rsi, [rip + sd_sp_eq]
    mov edx, N_F5
    mov ecx, K_typeAnnotation
    call pjs_print_assignment
    mov r13, rax
    call pjs_semi_doc
    mov rdi, r13
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pjs_print_type_alias

# pjs_print_intersection_type(node, args) -> rax (printIntersectionType)
FUNC pjs_print_intersection_type
    PROLOGUE 2
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # types
    VLEN r13, r12
    mov qword ptr [rsp], 0          # wasIndented
    DMARK rax
    mov [rsp + 8], rax
    xor r14d, r14d
1:  cmp r14, r13
    jae 9f
    mov rdi, r12
    mov rsi, r14
    mov edx, K_types
    xor ecx, ecx
    call print_elem
    mov r15, rax                    # doc
    test r14, r14
    jz 8f
    mov rdi, [r12 + 8 + r14*8]
    call pjs_is_object_type
    mov ebx, eax                    # currentIsObjectType
    mov rdi, [r12 + r14*8]
    call pjs_is_object_type
    # previousIsObjectType in eax
    test eax, eax
    jz 2f
    test ebx, ebx
    jz 3f
    # [" & ", wasIndented ? indent(doc) : doc]
    cmp qword ptr [rsp], 0
    je 7f
    mov rdi, r15
    call doc_indent
    mov r15, rax
    jmp 7f
2:  test ebx, ebx
    jz 4f
3:  mov rdi, [r12 + 8 + r14*8]
    call pjs_has_leading_own_line_comment
    test eax, eax
    jnz 4f
    # [" & ", index > 1 ? indent(doc) : doc]
    cmp r14, 1
    jbe 7f
    mov qword ptr [rsp], 1
    mov rdi, r15
    call doc_indent
    mov r15, rax
    jmp 7f
    # indent([" &", line, doc]) or, with operator position start, indent([line, "& ", doc])
4:  cmp qword ptr [rip + g_operator_position], OP_START
    je 5f
    lea rdi, [rip + sd_sp_amp]
    lea rsi, [rip + d_line]
    mov rdx, r15
    jmp 6f
5:  lea rdi, [rip + d_line]
    lea rsi, [rip + sd_amp_sp]
    mov rdx, r15
6:  call doc_array3
    INDENT_RAX
    mov r15, rax
    jmp 8f
7:  lea rdi, [rip + sd_amp_spaced]
    mov rsi, r15
    call doc_array2
    mov r15, rax
8:  DPUSH r15
    inc r14
    jmp 1b
9:  mov rdi, [rsp + 8]
    call ss_to_array
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_intersection_type

# pta_union_member(flags, node, index) -> rax: print() of a union member,
# align(2, ...) unless hugging (flags 1), then printComments
FUNC pta_union_member
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    xor edi, edi
    call main_print_here
    test ebx, ebx
    jnz 1f
    mov edi, 2
    mov rsi, rax
    call doc_align_n
1:  mov rdi, r12
    mov rsi, rax
    call print_comments
    EPILOGUE
ENDF pta_union_member

# pjs_print_union_type(node, args) -> rax (printUnionType)
FUNC pjs_print_union_type
    PROLOGUE 2
    mov rbx, rdi
    call path_parent
    mov r12, rax                    # parent
    # shouldIndent
    xor r13d, r13d
    movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_TSTypeParameterInstantiation
    je 2f
    cmp eax, T_TSConditionalType
    jne 1f
    cmp qword ptr [rip + g_experimental_ternaries], 0
    jne 2f
1:  cmp eax, T_TSTypeReference
    je 2f
    cmp eax, T_TSTypeAssertion
    je 2f
    cmp eax, T_TSTupleType
    je 2f
    mov r13d, 1
    cmp eax, T_TSTypeAliasDeclaration
    je 11f
    cmp eax, T_VariableDeclarator
    jne 2f
11: mov rdi, rbx
    call pjs_has_leading_own_line_comment
    test eax, eax
    jz 2f
    xor r13d, r13d
2:  mov rdi, rbx
    call pjs_should_hug_type
    mov r14d, eax                   # shouldHug
    lea rdi, [rip + pta_union_member]
    mov esi, r14d
    mov edx, K_types
    mov ecx, N_F0
    call path_map
    mov r15, rax                    # printed (VEC)
    test r14d, r14d
    jz 3f
    lea rdi, [rip + sd_sp_bar_sp]
    mov rsi, r15
    call doc_join
    jmp 99f
    # code = [ifBreak([shouldAddStartLine ? line : "", "| "]), join([line, "| "], printed)]
3:  xor r14d, r14d                  # shouldAddStartLine
    test r13d, r13d
    jz 4f
    mov rdi, rbx
    call pjs_has_leading_own_line_comment
    test eax, eax
    jnz 4f
    lea r14, [rip + d_line]
4:  mov rdi, r14
    lea rsi, [rip + sd_bar_sp]
    call doc_array2
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r14, rax
    mov rax, [rip + pta_line_bar]
    test rax, rax
    jnz 5f
    lea rdi, [rip + d_line]
    lea rsi, [rip + sd_bar_sp]
    call doc_array2
    mov [rip + pta_line_bar], rax
5:  mov rdi, rax
    mov rsi, r15
    call doc_join
    mov rdi, r14
    mov rsi, rax
    call doc_array2
    mov r14, rax                    # code
    call pjs_needs_parens
    test eax, eax
    jz 6f
    # group([indent(code), softline])
    mov rdi, r14
    call doc_indent
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    GROUP_RAX
    jmp 99f
6:  TYPE r12, T_TSTupleType
    jne 7f
    mov rax, [r12 + N_F0]
    VLEN rcx, rax
    cmp rcx, 1
    jbe 7f
    # group([indent([ifBreak(["(", softline]), code]), softline, ifBreak(")")])
    lea rdi, [rip + ps_lparen]
    lea rsi, [rip + d_softline]
    call doc_array2
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov rdi, rax
    mov rsi, r14
    call doc_array2
    INDENT_RAX
    mov r14, rax
    lea rdi, [rip + ps_rparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    mov rdi, r14
    lea rsi, [rip + d_softline]
    mov rdx, rax
    call doc_array3
    GROUP_RAX
    jmp 99f
7:  mov rax, r14
    test r13d, r13d
    jz 8f
    INDENT_RAX
8:  GROUP_RAX
99: EPILOGUE
ENDF pjs_print_union_type

# pjs_print_function_type(node, args) -> rax (printFunctionType) for
# TSFunctionType, TSConstructorType, TSCallSignatureDeclaration and
# TSConstructSignatureDeclaration
FUNC pjs_print_function_type
    PROLOGUE 2
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_abstract_token
    DPUSH rax
    TYPE rbx, T_TSConstructorType
    je 1f
    TYPE rbx, T_TSConstructSignatureDeclaration
    jne 2f
1:  DPUSHL sd_new_sp
2:  xor edi, edi
    mov esi, 1
    call pjs_print_function_parameters
    mov r13, rax                    # parametersDoc
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    mov rdi, rax
    xor esi, esi
    call doc_array2
    mov r14, rax                    # returnTypeDoc = [printTypeAnnotationProperty(...)]
    mov rdi, rbx
    mov rsi, r14
    call pjs_should_group_function_parameters
    test eax, eax
    jz 3f
    mov rdi, r13
    xor esi, esi
    call doc_group
    mov r13, rax
3:  DPUSH r13
    DPUSH r14
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_function_type
