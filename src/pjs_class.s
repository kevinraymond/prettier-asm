# print/class.js. Flow's mixins, extends of DeclareClass and variance do not
# occur in the babel-ts AST.
.include "pjs.inc"

    .weak pjs_get_type_parameters_group_id

SDOC sd_class, "class"
SDOC sd_extends, "extends "
SDOC sd_static, "static "
SDOC sd_accessor, "accessor "
SDOC sd_eq, " ="
SDOC sd_implements, "implements"
SDOC sd_override_sp, "override "
SDOC sd_readonly_sp, "readonly "

    .section .rodata
    .balign 8
pcl_tpgid: .quad pjs_get_type_parameters_group_id
s_static: .asciz "static"
s_get: .asciz "get"
s_set: .asciz "set"
s_in: .asciz "in"
s_instanceof: .asciz "instanceof"

    .bss
    .balign 8
pcl_heritage_ids: .quad 0           # getHeritageGroupId's map: class -> group id

    .text

# pcl_heritage_group_id(class) -> rax (getHeritageGroupId)
FUNC pcl_heritage_group_id
    PROLOGUE
    mov rbx, rdi
    mov rdi, [rip + pcl_heritage_ids]
    test rdi, rdi
    jnz 1f
    mov edi, 16
    call ptrmap_new
    mov [rip + pcl_heritage_ids], rax
    mov rdi, rax
1:  mov rsi, rbx
    call ptrmap_get
    test edx, edx
    jnz 9f
    call doc_group_id_new
    mov r12, rax
    mov rdi, [rip + pcl_heritage_ids]
    mov rsi, rbx
    mov rdx, r12
    call ptrmap_put
    mov rax, r12
9:  EPILOGUE
ENDF pcl_heritage_group_id

# pjs_print_hardline_after_heritage(class) -> rax: ifBreak(hardline, "", {groupId})
FUNC pjs_print_hardline_after_heritage
    call pcl_heritage_group_id
    lea rdi, [rip + d_hardline]
    xor esi, esi
    mov rdx, rax
    call doc_if_break
    leave
    ret
ENDF pjs_print_hardline_after_heritage

# pjs_print_class(node, args) -> rax doc (printClass)
FUNC pjs_print_class
    PROLOGUE 6
    mov rbx, rdi
    # groupMode: a trailing comment on the id or the type parameters, a
    # comment on the superclass, or implements
    mov rdi, [rbx + N_F0]
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    mov r15d, eax
    test eax, eax
    jnz 1f
    mov rdi, [rbx + N_F4]
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    mov r15d, eax
    test eax, eax
    jnz 1f
    mov rdi, [rbx + N_F1]
    xor esi, esi
    xor edx, edx
    call has_comment
    mov r15d, eax
    test eax, eax
    jnz 1f
    mov rax, [rbx + N_F5]           # implements
    VLEN rcx, rax
    test rcx, rcx
    setnz r15b
    # partsGroup: [" ", print("id")], print("typeParameters")
1:  DMARK r13
    cmp qword ptr [rbx + N_F0], 0
    je 2f
    DPUSHL ps_space
    PRINT N_F0, K_id
    DPUSH rax
2:  PRINT N_F4, K_typeParameters
    DPUSH rax
    DARRAY r13
    mov [rsp], rax                  # partsGroup
    # extendsParts
    DMARK r13
    cmp qword ptr [rbx + N_F1], 0
    je 4f
    # printed = [printSuperClass, print("superTypeParameters")]
    PRINT N_F1, K_superClass
    mov r14, rax
    call path_parent
    TYPE rax, T_AssignmentExpression
    jne 3f
    DMARK r12
    DPUSHL d_softline
    DPUSH r14
    DARRAY r12
    INDENT_RAX
    mov [rsp + 8], rax
    DMARK r12
    DPUSHL ps_lparen
    DPUSH [rsp + 8]
    DPUSHL d_softline
    DPUSHL ps_rparen
    DARRAY r12
    mov rdi, rax
    mov rsi, r14
    xor edx, edx
    call doc_if_break
    GROUP_RAX
    mov r14, rax
3:  PRINT N_F3, K_superTypeParameters
    mov rdi, r14
    mov rsi, rax
    call doc_array2
    mov r14, rax
    # path.call(superClass => ["extends ", printComments(superClass, printed)], "superClass")
    mov rdi, [rbx + N_F1]
    mov esi, K_superClass
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, [rbx + N_F1]
    mov rsi, r14
    call print_comments
    mov r14, rax
    call path_pop
    lea rdi, [rip + sd_extends]
    mov rsi, r14
    call doc_array2
    mov r14, rax
    test r15d, r15d
    jz 31f
    DPUSHL d_line
    mov rdi, r14
    xor esi, esi
    call doc_group
    DPUSH rax
    jmp 4f
31: DPUSHL ps_space
    DPUSH r14
4:  mov rdi, rbx
    call pcl_print_heritage_clauses
    DPUSH rax
    DARRAY r13
    mov [rsp + 8], rax              # extendsParts
    DMARK r13
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    mov rdi, rbx
    call pjs_print_abstract_token
    DPUSH rax
    DPUSHL sd_class
    test r15d, r15d
    jnz 10f
    # parts.push(...partsGroup, ...extendsParts, " ")
    DPUSH [rsp]
    DPUSH [rsp + 8]
6:  DPUSHL ps_space
    jmp 20f
10: mov rdi, rbx
    call pcl_should_indent_only_heritage_clauses
    test eax, eax
    jz 11f
    # [...partsGroup, indent(extendsParts)]
    mov rdi, [rsp + 8]
    call doc_indent
    mov rsi, rax
    mov rdi, [rsp]
    call doc_array2
    jmp 12f
    # indent([...partsGroup, extendsParts])
11: mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call doc_array2
    INDENT_RAX
12: mov r12, rax
    mov rdi, rbx
    call pcl_heritage_group_id
    mov r14, rax
    mov rdi, r12
    xor esi, esi
    mov rdx, r14
    call doc_group_ex
    DPUSH rax
    mov rax, [rbx + N_F2]           # ClassBody
    mov rax, [rax + N_F0]
    VLEN rcx, rax
    test rcx, rcx
    jz 6b
    lea rdi, [rip + d_hardline]
    lea rsi, [rip + ps_space]
    mov rdx, r14
    call doc_if_break
    DPUSH rax
20: PRINT N_F2, K_body
    DPUSH rax
    DARRAY r13
    EPILOGUE
ENDF pjs_print_class

# pcl_should_indent_only_heritage_clauses(class) -> eax
# (shouldIndentOnlyHeritageClauses): typeParameters without a trailing line
# comment, and at most one of superclass and implements
FUNC pcl_should_indent_only_heritage_clauses
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    mov rdi, [rbx + N_F4]
    test rdi, rdi
    jz 9f
    mov esi, CC_Trailing | CC_Line
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 8f
    # hasMultipleHeritage
    xor ecx, ecx
    cmp qword ptr [rbx + N_F1], 0
    setne cl
    mov rax, [rbx + N_F5]
    VLEN rdx, rax
    add rcx, rdx
    xor eax, eax
    cmp rcx, 1
    setbe al
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pcl_should_indent_only_heritage_clauses

# pcl_print_heritage_clauses(class) -> rax (printHeritageClauses(path, options,
# print, "implements")); the class is the path's top
FUNC pcl_print_heritage_clauses
    PROLOGUE 2
    mov rbx, rdi
    xor eax, eax
    mov rcx, [rbx + N_F5]
    VLEN rdx, rcx
    test rdx, rdx
    jz 99f
    xor edi, edi
    lea rsi, [rip + pjs_marker_implements]
    xor edx, edx
    xor ecx, ecx
    call print_dangling_comments_ex
    mov r13, rax                    # printedLeadingComments
    DMARK r12
    mov rdi, rbx
    call pcl_should_indent_only_heritage_clauses
    test eax, eax
    jz 1f
    cmp qword ptr [rip + pcl_tpgid], 0
    je 90f
    mov rdi, [rbx + N_F4]
    call pjs_get_type_parameters_group_id
    lea rdi, [rip + ps_space]
    lea rsi, [rip + d_line]
    mov rdx, rax
    call doc_if_break
    DPUSH rax
    jmp 2f
1:  DPUSHL d_line
2:  test r13, r13
    jz 3f
    DPUSH r13
    DPUSHL d_hardline
3:  DPUSHL sd_implements
    mov edi, N_F5
    mov esi, K_implements
    xor edx, edx
    call print_map
    mov r14, rax
    lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array2
    mov rdi, rax
    mov rsi, r14
    call doc_join
    lea rdi, [rip + d_line]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    GROUP_RAX
    DPUSH rax
    DARRAY r12
99: EPILOGUE
90: REFUSE "printer: getTypeParametersGroupId (type-parameters.js) not linked"
ENDF pcl_print_heritage_clauses

# pjs_print_class_method(node, args) -> rax doc (printClassMethod)
FUNC pjs_print_class_method
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_get_decorators
    test rax, rax
    jz 1f
    mov rdi, rbx
    call pjs_print_class_member_decorators
    DPUSH rax
1:  mov rdi, rbx
    call pjs_print_ts_accessibility_token
    DPUSH rax
    ATTR rbx, NA_STATIC
    jz 2f
    DPUSHL sd_static
2:  mov rdi, rbx
    call pjs_print_abstract_token
    DPUSH rax
    ATTR rbx, NA_OVERRIDE
    jz 3f
    DPUSHL sd_override_sp
3:  mov rdi, rbx
    xor esi, esi
    call pjs_print_method
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_class_method

# pjs_print_class_property(node, args) -> rax doc (printClassProperty)
FUNC pjs_print_class_property
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_get_decorators
    test rax, rax
    jz 10f
    mov rdi, rbx
    call pjs_print_class_member_decorators
    DPUSH rax
10: mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    mov rdi, rbx
    call pjs_print_ts_accessibility_token
    DPUSH rax
    ATTR rbx, NA_STATIC
    jz 11f
    DPUSHL sd_static
11: mov rdi, rbx
    call pjs_print_abstract_token
    DPUSH rax
    ATTR rbx, NA_OVERRIDE
    jz 12f
    DPUSHL sd_override_sp
12: ATTR rbx, NA_READONLY
    jz 13f
    DPUSHL sd_readonly_sp
13: TYPE rbx, T_ClassAccessorProperty
    jne 1f
    DPUSHL sd_accessor
1:  mov rdi, rbx
    call pjs_print_property_key
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
    mov rdi, rax
    lea rsi, [rip + sd_eq]
    mov edx, N_F1
    mov ecx, K_value
    call pjs_print_assignment
    mov r13, rax
    call pjs_semi_doc
    mov rdi, r13
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pjs_print_class_property

# pjs_print_class_body(node, args) -> rax doc (printClassBody)
FUNC pjs_print_class_body
    PROLOGUE 2
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # body
    VLEN r15, r12
    DMARK r13
    xor r14d, r14d
1:  cmp r14, r15
    jae 5f
    mov rdi, r12
    mov rsi, r14
    mov edx, K_body
    xor ecx, ecx
    call print_elem
    DPUSH rax
    cmp qword ptr [rip + g_semi], 0
    jne 2f
    mov rdi, [r12 + 8 + r14*8]
    TYPE rdi, T_ClassProperty
    je 11f
    TYPE rdi, T_ClassAccessorProperty
    je 11f
    TYPE rdi, T_ClassPrivateProperty
    jne 2f
11: xor esi, esi
    lea rax, [r14 + 1]
    cmp rax, r15
    jae 12f
    mov rsi, [r12 + 8 + rax*8]
12: call pcl_should_print_semicolon_after_class_property
    test eax, eax
    jz 2f
    DPUSHL ps_semi
2:  lea rax, [r14 + 1]
    cmp rax, r15
    jae 3f
    DPUSHL d_hardline
    mov rdi, [r12 + 8 + r14*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 3f
    DPUSHL d_hardline
3:  inc r14
    jmp 1b
5:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 6f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
6:  call ss_mark
    cmp rax, r13
    je 8f
    DARRAY r13
    lea rdi, [rip + d_hardline]
    mov rsi, rax
    call doc_array2
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    mov r13, rax
    lea rdi, [rip + ps_lbrace]
    mov rsi, r13
    lea rdx, [rip + ps_rbrace]
    call doc_array3
    jmp 9f
8:  DARRAY r13
    lea rdi, [rip + ps_lbrace]
    lea rsi, [rip + ps_rbrace]
    call doc_array2
9:  EPILOGUE
ENDF pjs_print_class_body

# pcl_should_print_semicolon_after_class_property(node, next_or_0) -> eax
FUNC pcl_should_print_semicolon_after_class_property
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    ATTR rbx, NA_COMPUTED
    jnz 2f
    cmp qword ptr [rbx + N_F1], 0
    jne 2f
    cmp qword ptr [rbx + N_F5], 0   # typeAnnotation
    jne 2f
    mov r13, [rbx + N_F0]
    mov rdi, r13
    lea rsi, [rip + s_static]
    call pjs_ident_is
    test eax, eax
    jnz 7f
    mov rdi, r13
    lea rsi, [rip + s_get]
    call pjs_ident_is
    test eax, eax
    jnz 7f
    mov rdi, r13
    lea rsi, [rip + s_set]
    call pjs_ident_is
    test eax, eax
    jnz 7f
2:  test r12, r12
    jz 8f
    ATTR r12, NA_STATIC | NA_READONLY
    jnz 8f
    movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_StaticBlock
    je 8f                           # no key
    cmp eax, T_TSIndexSignature
    je 7f                           # no key, no accessibility
    cmp qword ptr [r12 + N_F7], 0   # accessibility
    jne 8f
    ATTR r12, NA_COMPUTED
    jnz 3f
    mov r13, [r12 + N_F0]
    mov rdi, r13
    lea rsi, [rip + s_in]
    call pjs_ident_is
    test eax, eax
    jnz 7f
    mov rdi, r13
    lea rsi, [rip + s_instanceof]
    call pjs_ident_is
    test eax, eax
    jnz 7f
3:  movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_ClassProperty
    jne 4f
    ATTR r12, NA_COMPUTED
    jnz 7f
    jmp 8f
    # TSDeclareMethod is typescript-estree's MethodDefinition or
    # TSAbstractMethodDefinition, which this switch lists
4:  cmp eax, T_ClassMethod
    je 5f
    cmp eax, T_TSDeclareMethod
    je 5f
    cmp eax, T_ClassPrivateMethod
    jne 8f
5:  ATTR r12, NA_ASYNC
    jnz 8f
    mov rax, [r12 + N_F3]
    cmp rax, KD_GET
    je 8f
    cmp rax, KD_SET
    je 8f
    ATTR r12, NA_COMPUTED | NA_GENERATOR
    jnz 7f
    jmp 8f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF pcl_should_print_semicolon_after_class_property
