# print/typescript.js: printTypescript. The switch is the ts_cases table, which
# pjs_print_estree merges into its own; a handler that is not linked in (a weak
# symbol left 0) refuses there.
.include "pjs.inc"

    .weak pjs_print_object, pjs_print_type_alias, pjs_print_class_method, pjs_print_class_property
    .weak pjs_print_interface, pjs_print_type_parameters, pjs_print_type_parameter
    .weak pjs_print_binary_cast_expression, pjs_print_enum_declaration, pjs_print_enum_body
    .weak pjs_print_enum_member, pjs_print_typescript_mapped_type, pjs_print_ternary
    .weak pjs_print_intersection_type, pjs_print_union_type, pjs_print_function_type
    .weak pjs_print_array, pjs_print_template_literal, pjs_print_function, pjs_print_block

    .section .rodata
    .balign 8
    .globl ts_cases
ts_cases:
    .irp t, TSAnyKeyword, TSBooleanKeyword, TSBigIntKeyword, TSIntrinsicKeyword, TSNeverKeyword, TSNullKeyword, TSNumberKeyword, TSObjectKeyword, TSStringKeyword, TSSymbolKeyword, TSUndefinedKeyword, TSUnknownKeyword, TSVoidKeyword
    .quad T_\t, pts_keyword
    .endr
    .quad T_TSThisType, pts_this
    .quad T_TSTypeAssertion, pts_type_assertion
    .quad T_TSDeclareFunction, pjs_print_function
    .quad T_TSExportAssignment, pts_export_assignment
    .quad T_TSModuleBlock, pjs_print_block
    .quad T_TSInterfaceBody, pjs_print_object
    .quad T_TSTypeLiteral, pjs_print_object
    .quad T_TSTypeAliasDeclaration, pjs_print_type_alias
    .quad T_TSQualifiedName, pts_qualified_name
    .quad T_TSDeclareMethod, pjs_print_class_method
    .quad T_TSExpressionWithTypeArguments, pts_expression_with_type_arguments
    .quad T_TSInstantiationExpression, pts_expression_with_type_arguments
    .quad T_TSNamedTupleMember, pjs_print_named_tuple_member
    .quad T_TSRestType, pjs_print_rest_type
    .quad T_TSOptionalType, pts_optional_type
    .quad T_TSInterfaceDeclaration, pjs_print_interface
    .quad T_TSTypeParameterDeclaration, pjs_print_type_parameters
    .quad T_TSTypeParameterInstantiation, pjs_print_type_parameters
    .quad T_TSTypeParameter, pjs_print_type_parameter
    .quad T_TSAsExpression, pjs_print_binary_cast_expression
    .quad T_TSSatisfiesExpression, pjs_print_binary_cast_expression
    .quad T_TSArrayType, pjs_print_array_type
    .quad T_TSPropertySignature, pts_property_signature
    .quad T_TSParameterProperty, pts_parameter_property
    .quad T_TSTypeQuery, pjs_print_type_query
    .quad T_TSIndexSignature, pts_index_signature
    .quad T_TSTypePredicate, pjs_print_type_predicate
    .quad T_TSNonNullExpression, pts_non_null_expression
    .quad T_TSImportType, pts_import_type
    .quad T_TSLiteralType, pts_literal_type
    .quad T_TSIndexedAccessType, pjs_print_indexed_access_type
    .quad T_TSTypeOperator, pts_type_operator
    .quad T_TSMappedType, pjs_print_typescript_mapped_type
    .quad T_TSMethodSignature, pts_method_signature
    .quad T_TSNamespaceExportDeclaration, pts_namespace_export_declaration
    .quad T_TSEnumDeclaration, pjs_print_enum_declaration
    .quad T_TSEnumBody, pjs_print_enum_body
    .quad T_TSEnumMember, pjs_print_enum_member
    .quad T_TSImportEqualsDeclaration, pts_import_equals_declaration
    .quad T_TSExternalModuleReference, pts_external_module_reference
    .quad T_TSModuleDeclaration, pts_module_declaration
    .quad T_TSConditionalType, pjs_print_ternary
    .quad T_TSInferType, pjs_print_infer_type
    .quad T_TSIntersectionType, pjs_print_intersection_type
    .quad T_TSUnionType, pjs_print_union_type
    .quad T_TSFunctionType, pjs_print_function_type
    .quad T_TSCallSignatureDeclaration, pjs_print_function_type
    .quad T_TSConstructorType, pjs_print_function_type
    .quad T_TSConstructSignatureDeclaration, pjs_print_function_type
    .quad T_TSTupleType, pjs_print_array
    .quad T_TSTypeReference, pts_type_reference
    .quad T_TSTypeAnnotation, pjs_print_type_annotation
    .quad 0

# Keyword names, indexed by T_* - T_TSAnyKeyword: node.type.slice(2, -7).toLowerCase()
    .balign 8
kw_docs:
    .quad sd_kw_any, sd_kw_boolean, sd_kw_bigint, sd_kw_intrinsic, sd_kw_never, sd_kw_null
    .quad sd_kw_number, sd_kw_object, sd_kw_string, sd_kw_symbol, sd_kw_undefined, sd_kw_unknown
    .quad sd_kw_void

SDOC sd_kw_any, "any"
SDOC sd_kw_boolean, "boolean"
SDOC sd_kw_bigint, "bigint"
SDOC sd_kw_intrinsic, "intrinsic"
SDOC sd_kw_never, "never"
SDOC sd_kw_null, "null"
SDOC sd_kw_number, "number"
SDOC sd_kw_object, "object"
SDOC sd_kw_string, "string"
SDOC sd_kw_symbol, "symbol"
SDOC sd_kw_undefined, "undefined"
SDOC sd_kw_unknown, "unknown"
SDOC sd_kw_void, "void"
SDOC sd_this, "this"
SDOC sd_lt, "<"
SDOC sd_gt, ">"
SDOC sd_bang, "!"
SDOC sd_export_eq, "export = "
SDOC sd_import, "import"
SDOC sd_import_sp, "import "
SDOC sd_export_sp, "export "
SDOC sd_readonly_sp, "readonly "
SDOC sd_override_sp, "override "
SDOC sd_static_sp, "static "
SDOC sd_comma_sp, ", "
SDOC sd_eq_sp, " = "
SDOC sd_require_open, "require("
SDOC sd_export_as_ns, "export as namespace "
SDOC sd_get_sp, "get "
SDOC sd_set_sp, "set "
SDOC sd_keyof, "keyof"
SDOC sd_unique, "unique"
SDOC sd_readonly, "readonly"
SDOC sd_kd_module, "module"
SDOC sd_kd_namespace, "namespace"

    .text

FUNC pts_keyword
    movzx eax, word ptr [rdi + N_TYPE]
    sub eax, T_TSAnyKeyword
    lea rcx, [rip + kw_docs]
    mov rax, [rcx + rax*8]
    leave
    ret
ENDF pts_keyword

FUNC pts_this
    lea rax, [rip + sd_this]
    leave
    ret
ENDF pts_this

# TSTypeAssertion
FUNC pts_type_assertion
    PROLOGUE 2
    mov rbx, rdi
    # castGroup = group(["<", indent([softline, print("typeAnnotation")]), softline, ">"])
    PRINT N_F5, K_typeAnnotation
    lea rdi, [rip + d_softline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov r13, rax
    DMARK r12
    DPUSHL sd_lt
    DPUSH r13
    DPUSHL d_softline
    DPUSHL sd_gt
    DARRAY r12
    GROUP_RAX
    mov r13, rax                    # castGroup
    PRINT N_F0, K_expression
    mov r14, rax                    # print("expression")
    mov rax, [rbx + N_F0]
    TYPE rax, T_ArrayExpression
    je 5f
    TYPE rax, T_ObjectExpression
    je 5f
    # exprContents = [ifBreak("("), indent([softline, print("expression")]), softline, ifBreak(")")]
    lea rdi, [rip + d_softline]
    mov rsi, r14
    call doc_array2
    INDENT_RAX
    mov r15, rax
    DMARK r12
    lea rdi, [rip + ps_lparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DPUSH r15
    DPUSHL d_softline
    lea rdi, [rip + ps_rparen]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
    DARRAY r12
    mov rdi, rax
    mov esi, 1
    call doc_group
    mov rsi, rax
    mov rdi, r13
    call doc_array2
    mov r15, rax
    mov rdi, r13
    mov rsi, r14
    call doc_array2
    mov [rsp], rax
    mov rdi, r13
    mov rsi, r14
    call doc_array2
    mov [rsp + 8], rax
    DMARK r12
    DPUSH [rsp]
    DPUSH r15
    DPUSH [rsp + 8]
    DARRAYK r12
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call doc_conditional_group
    jmp 9f
    # group([castGroup, print("expression")])
5:  mov rdi, r13
    mov rsi, r14
    call doc_array2
    GROUP_RAX
9:  EPILOGUE
ENDF pts_type_assertion

# ["export = ", print("expression"), semi]
FUNC pts_export_assignment
    PROLOGUE
    PRINT N_F0, K_expression
    mov rbx, rax
    call pjs_semi_doc
    lea rdi, [rip + sd_export_eq]
    mov rsi, rbx
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pts_export_assignment

# [print("left"), ".", print("right")]
FUNC pts_qualified_name
    PROLOGUE
    PRINT N_F0, K_left
    mov rbx, rax
    PRINT N_F1, K_right
    mov rdi, rbx
    lea rsi, [rip + ps_dot]
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pts_qualified_name

# [print("expression"), print("typeParameters")]
FUNC pts_expression_with_type_arguments
    PROLOGUE
    PRINT N_F0, K_expression
    mov rbx, rax
    PRINT N_F4, K_typeParameters
    mov rdi, rbx
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pts_expression_with_type_arguments

# [print("typeAnnotation"), "?"]
FUNC pts_optional_type
    PRINT N_F5, K_typeAnnotation
    mov rdi, rax
    lea rsi, [rip + ps_question]
    call doc_array2
    leave
    ret
ENDF pts_optional_type

# [print("expression"), "!"]
FUNC pts_non_null_expression
    mov rdi, [rdi + N_F0]
    call pjs_check_cast_of_pattern
    PRINT N_F0, K_expression
    mov rdi, rax
    lea rsi, [rip + sd_bang]
    call doc_array2
    leave
    ret
ENDF pts_non_null_expression

# print("literal")
FUNC pts_literal_type
    PRINT N_F0, K_literal
    leave
    ret
ENDF pts_literal_type

# [node.operator, " ", print("typeAnnotation")]
FUNC pts_type_operator
    PROLOGUE
    mov rbx, rdi
    PRINT N_F5, K_typeAnnotation
    mov r12, rax
    mov rax, [rbx + N_F1]
    lea rdi, [rip + sd_keyof]
    cmp rax, KD_KEYOF
    je 1f
    lea rdi, [rip + sd_unique]
    cmp rax, KD_UNIQUE
    je 1f
    lea rdi, [rip + sd_readonly]
    cmp rax, KD_READONLY
    jne 90f
1:  lea rsi, [rip + ps_space]
    mov rdx, r12
    call doc_array3
    EPILOGUE
90: REFUSE "printer: TSTypeOperator operator"
ENDF pts_type_operator

# ["export as namespace ", print("id"), semi]
FUNC pts_namespace_export_declaration
    PROLOGUE
    PRINT N_F0, K_id
    mov rbx, rax
    call pjs_semi_doc
    lea rdi, [rip + sd_export_as_ns]
    mov rsi, rbx
    mov rdx, rax
    call doc_array3
    EPILOGUE
ENDF pts_namespace_export_declaration

# ["require(", print("expression"), ")"]
FUNC pts_external_module_reference
    PRINT N_F0, K_expression
    lea rdi, [rip + sd_require_open]
    mov rsi, rax
    lea rdx, [rip + ps_rparen]
    call doc_array3
    leave
    ret
ENDF pts_external_module_reference

# [print("typeName"), printTypeParameters(path, options, print, "typeParameters")]
FUNC pts_type_reference
    PROLOGUE
    PRINT N_F0, K_typeName
    mov rbx, rax
    PRINT N_F4, K_typeParameters
    mov rdi, rbx
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pts_type_reference

# ["import", printCallArguments(path, options, print), qualifier ? [".",
# print("qualifier")] : "", printTypeParameters(path, ..., "typeParameters")]
FUNC pts_import_type
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    DPUSHL sd_import
    call pjs_print_call_arguments
    DPUSH rax
    cmp qword ptr [rbx + N_F2], 0
    je 1f
    PRINT N_F2, K_qualifier
    lea rdi, [rip + ps_dot]
    mov rsi, rax
    call doc_array2
    DPUSH rax
1:  PRINT N_F4, K_typeParameters
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pts_import_type

# [readonly ? "readonly " : "", printPropertyKey, printOptionalToken,
# printTypeAnnotationProperty]
FUNC pts_property_signature
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    ATTR rbx, NA_READONLY
    jz 1f
    DPUSHL sd_readonly_sp
1:  mov rdi, rbx
    call pjs_print_property_key
    DPUSH rax
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pts_property_signature

# [accessibility, static, override, readonly, print("parameter")]
FUNC pts_parameter_property
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_ts_accessibility_token
    DPUSH rax
    ATTR rbx, NA_STATIC
    jz 1f
    DPUSHL sd_static_sp
1:  ATTR rbx, NA_OVERRIDE
    jz 2f
    DPUSHL sd_override_sp
2:  ATTR rbx, NA_READONLY
    jz 3f
    DPUSHL sd_readonly_sp
3:  PRINT N_F0, K_parameter
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pts_parameter_property

# TSIndexSignature
FUNC pts_index_signature
    PROLOGUE 2
    mov rbx, rdi
    # trailingComma: parameters.length > 1 ? ifBreak(shouldPrintComma ? "," : "") : ""
    xor r13d, r13d
    mov rax, [rbx + N_F1]
    VLEN rcx, rax
    cmp rcx, 1
    jbe 1f
    xor edi, edi
    call pjs_should_print_comma
    xor edi, edi
    test eax, eax
    jz 11f
    lea rdi, [rip + ps_comma]
11: xor esi, esi
    xor edx, edx
    call doc_if_break
    mov r13, rax
    # group([indent([softline, join([", ", softline], path.map(print, "parameters"))]), trailingComma, softline])
1:  mov edi, N_F1
    mov esi, K_parameters
    xor edx, edx
    call print_map
    mov r14, rax
    lea rdi, [rip + sd_comma_sp]
    lea rsi, [rip + d_softline]
    call doc_array2
    mov rdi, rax
    mov rsi, r14
    call doc_join
    mov rsi, rax
    lea rdi, [rip + d_softline]
    call doc_array2
    INDENT_RAX
    mov rdi, rax
    mov rsi, r13
    lea rdx, [rip + d_softline]
    call doc_array3
    GROUP_RAX
    mov r13, rax                    # parametersGroup
    # isClassMember = path.parent.type === "ClassBody" && path.key === "body"
    xor r14d, r14d
    call path_parent
    TYPE rax, T_ClassBody
    jne 2f
    call path_key
    cmp eax, K_body
    jne 2f
    mov r14d, 1
2:  DMARK r12
    test r14d, r14d
    jz 3f
    ATTR rbx, NA_STATIC
    jz 3f
    DPUSHL sd_static_sp
3:  ATTR rbx, NA_READONLY
    jz 4f
    DPUSHL sd_readonly_sp
4:  DPUSHL ps_lbracket
    DPUSH r13
    DPUSHL ps_rbracket
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    test r14d, r14d
    jz 5f
    call pjs_semi_doc
    DPUSH rax
5:  DARRAY r12
    EPILOGUE
ENDF pts_index_signature

# TSMethodSignature
FUNC pts_method_signature
    PROLOGUE 2
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_ts_accessibility_token
    DPUSH rax
    mov rax, [rbx + N_F3]
    cmp rax, KD_GET
    jne 1f
    DPUSHL sd_get_sp
    jmp 2f
1:  cmp rax, KD_SET
    jne 2f
    DPUSHL sd_set_sp
2:  ATTR rbx, NA_COMPUTED
    jz 3f
    DPUSHL ps_lbracket
3:  PRINT N_F0, K_key
    DPUSH rax
    ATTR rbx, NA_COMPUTED
    jz 4f
    DPUSHL ps_rbracket
4:  mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    xor edi, edi
    mov esi, 1
    call pjs_print_function_parameters
    mov r13, rax                    # parametersDoc
    xor r14d, r14d                  # returnTypeDoc
    cmp qword ptr [rbx + N_F5], 0
    je 5f
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    mov r14, rax
5:  mov rdi, rbx
    mov rsi, r14
    call pjs_should_group_function_parameters
    test eax, eax
    jz 6f
    mov rdi, r13
    xor esi, esi
    call doc_group
    mov r13, rax
6:  DPUSH r13
    cmp qword ptr [rbx + N_F5], 0
    je 7f
    mov rdi, r14
    xor esi, esi
    call doc_group
    DPUSH rax
7:  DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pts_method_signature

# [isExport ? "export " : "", "import ", printImportKind(node, false), print("id"),
# " = ", print("moduleReference"), semi]
FUNC pts_import_equals_declaration
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    ATTR rbx, NA_IS_EXPORT
    jz 1f
    DPUSHL sd_export_sp
1:  DPUSHL sd_import_sp
    mov rdi, [rbx + N_F3]
    xor esi, esi
    call pjs_print_import_or_export_kind
    DPUSH rax
    PRINT N_F0, K_id
    DPUSH rax
    DPUSHL sd_eq_sp
    PRINT N_F1, K_moduleReference
    DPUSH rax
    call pjs_semi_doc
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pts_import_equals_declaration

# TSModuleDeclaration
FUNC pts_module_declaration
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    call path_parent
    TYPE rax, T_TSModuleDeclaration
    jne 1f
    DPUSHL ps_dot
    jmp 3f
1:  mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    mov rax, [rbx + N_F3]
    cmp rax, KD_GLOBAL
    je 3f
    lea rdi, [rip + sd_kd_module]
    cmp rax, KD_MODULE
    je 2f
    lea rdi, [rip + sd_kd_namespace]
    cmp rax, KD_NAMESPACE
    jne 90f
2:  DPUSH rdi
    DPUSHL ps_space
3:  PRINT N_F0, K_id
    DPUSH rax
    mov rax, [rbx + N_F1]
    test rax, rax
    jz 5f
    TYPE rax, T_TSModuleDeclaration
    jne 4f
    PRINT N_F1, K_body
    DPUSH rax
    jmp 9f
4:  DPUSHL ps_space
    PRINT N_F1, K_body
    GROUP_RAX
    DPUSH rax
    jmp 9f
5:  call pjs_semi_doc
    DPUSH rax
9:  DARRAY r12
    EPILOGUE
90: REFUSE "printer: TSModuleDeclaration kind"
ENDF pts_module_declaration
