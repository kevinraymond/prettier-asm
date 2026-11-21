# print/array.js for ArrayExpression, ArrayPattern and TSTupleType
.include "pjs.inc"

    .bss
    .balign 8
# options.__inJestEach: set while printJestEachTemplateLiteral prints the
# table's expressions
    .globl g_in_jest_each
g_in_jest_each: .quad 0

    .text

# pjs_print_array(node, args) -> rax doc (printArray)
FUNC pjs_print_array
    PROLOGUE 6
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # elements
    VLEN r13, r12
    test r13, r13
    jnz 10f
    # printEmptyArrayElements
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 3f
    lea rdi, [rip + ps_lbracket]
    lea rsi, [rip + ps_rbracket]
    call doc_array2
    jmp 98f
3:  DMARK r14
    DPUSHL ps_lbracket
    mov rdi, rbx
    mov esi, 1
    call print_dangling_comments
    DPUSH rax
    DPUSHL d_softline
    DPUSHL ps_rbracket
    DARRAY r14
    GROUP_RAX
    jmp 98f

10: call doc_group_with_id
    mov [rsp], rax                  # the array group, its own id
    # shouldBreak: more than one element, all objects (or all arrays) of the
    # same type as the next, each with more than one entry
    xor r15d, r15d
    cmp qword ptr [rip + g_in_jest_each], 0
    jne 14f
    cmp r13, 1
    jbe 14f
    xor ecx, ecx
11: cmp rcx, r13
    jae 13f
    mov rax, [r12 + 8 + rcx*8]
    test rax, rax
    jz 14f
    movzx edx, word ptr [rax + N_TYPE]
    cmp edx, T_ObjectExpression
    je 12f
    cmp edx, T_ArrayExpression
    jne 14f
12: lea r8, [rcx + 1]
    cmp r8, r13
    jae 121f
    mov r8, [r12 + 8 + r8*8]
    test r8, r8
    jz 121f
    cmp dx, [r8 + N_TYPE]
    jne 14f
121: mov r8, [rax + N_F0]
    test r8, r8
    jz 14f
    cmp qword ptr [r8], 1
    jbe 14f
    inc rcx
    jmp 11b
13: mov r15d, 1
14: mov [rsp + 8], r15              # shouldBreak
    mov rdi, rbx
    call pjs_is_concisely_printed_array
    mov [rsp + 16], rax             # shouldUseConciseFormatting
    # trailingComma
    mov rax, [r12 + r13*8]          # last element
    test rax, rax
    jnz 15f
    lea rax, [rip + ps_comma]       # needsForcedTrailingComma
    jmp 17f
15: TYPE rax, T_RestElement
    jne 151f
    xor eax, eax
    jmp 17f
151: xor edi, edi
    call pjs_should_print_comma
    test eax, eax
    jz 17f
    lea rdi, [rip + ps_comma]
    xor esi, esi
    xor edx, edx
    cmp qword ptr [rsp + 16], 0
    je 16f
    mov rdx, [rsp]
16: call doc_if_break
17: mov [rsp + 24], rax             # trailingComma
    # indent([softline, elements, printDanglingComments(path, options)])
    DMARK r14
    DPUSHL d_softline
    cmp qword ptr [rsp + 16], 0
    je 20f
    mov rdi, rbx
    mov rsi, [rsp + 24]
    call par_print_elements_concisely
    DPUSH rax
    jmp 21f
20: mov rdi, rbx
    call par_print_elements
    mov rdi, rax
    mov rsi, [rsp + 24]
    call doc_array2
    DPUSH rax
21: mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
    DARRAY r14
    INDENT_RAX
    mov r15, rax
    DMARK r14
    DPUSHL ps_lbracket
    DPUSH r15
    DPUSHL d_softline
    DPUSHL ps_rbracket
    DARRAY r14
    mov rcx, [rsp]
    mov [rcx + G_CONTENTS], rax
    cmp qword ptr [rsp + 8], 0
    je 22f
    or byte ptr [rcx + G_FLAGS], GF_BREAK
22: mov rax, rcx
    # [group, printOptionalToken(path), printTypeAnnotationProperty(path, print)]
98: mov r14, rax
    ATTR rbx, NA_OPTIONAL
    jnz 981f
    cmp qword ptr [rbx + N_F5], 0
    je 99f
981: DMARK r15
    DPUSH r14
    mov rdi, rbx
    call pjs_print_optional_token
    DPUSH rax
    mov edi, N_F5
    mov esi, K_typeAnnotation
    call pjs_print_type_annotation_property
    DPUSH rax
    DARRAY r15
    jmp 99f
99: EPILOGUE
ENDF pjs_print_array

# pjs_is_concisely_printed_array(node) -> eax (isConciselyPrintedArray)
FUNC pjs_is_concisely_printed_array
    PROLOGUE
    xor eax, eax
    TYPE rdi, T_ArrayExpression
    jne 9f
    mov rbx, [rdi + N_F0]
    VLEN r14, rbx
    cmp r14, 1
    jbe 9f
    xor r12d, r12d
1:  cmp r12, r14
    jae 8f
    mov r13, [rbx + 8 + r12*8]
    test r13, r13
    jz 7f
    TYPE r13, T_NumericLiteral
    je 2f
    mov rdi, r13
    call pjs_is_signed_numeric_literal
    test eax, eax
    jz 7f
    mov rdi, [r13 + N_F0]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 7f
2:  mov rdi, r13
    mov esi, CC_Trailing | CC_Line
    lea rdx, [rip + par_comment_not_after_newline]
    call has_comment
    test eax, eax
    jnz 7f
    inc r12
    jmp 1b
7:  xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  EPILOGUE
ENDF pjs_is_concisely_printed_array

# par_comment_not_after_newline(comment) -> eax: !hasNewline(text, locStart, backwards)
FUNC par_comment_not_after_newline
    mov edi, [rdi + CM_START]
    mov esi, 1
    call has_newline
    xor eax, 1
    leave
    ret
ENDF par_comment_not_after_newline

# par_print_elements(array) -> rax (printArrayElements)
FUNC par_print_elements
    PROLOGUE
    mov rbx, rdi
    mov r12, [rbx + N_F0]
    VLEN r15, r12
    DMARK r13
    xor r14d, r14d
1:  cmp r14, r15
    jae 9f
    mov rax, [r12 + 8 + r14*8]
    test rax, rax
    jz 2f
    mov rdi, r12
    mov rsi, r14
    mov edx, K_elements
    cmp word ptr [rbx + N_TYPE], T_TSTupleType
    jne 11f
    mov edx, K_elementTypes
11: xor ecx, ecx
    call print_elem
    GROUP_RAX
    DPUSH rax
2:  lea rax, [r14 + 1]
    cmp rax, r15
    jae 9f
    # [",", line, node && isLineAfterElementEmpty ? softline : ""]
    xor edx, edx
    mov rdi, [r12 + 8 + r14*8]
    test rdi, rdi
    jz 3f
    call is_line_after_element_empty
    xor edx, edx
    test eax, eax
    jz 3f
    lea rdx, [rip + d_softline]
3:  lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array3
    DPUSH rax
    inc r14
    jmp 1b
9:  DARRAY r13
    EPILOGUE
ENDF par_print_elements

# par_print_elements_concisely(array, trailing_comma) -> rax: fill(parts)
FUNC par_print_elements_concisely
    PROLOGUE 2
    mov rbx, rdi
    mov [rsp], rsi
    mov r12, [rbx + N_F0]
    VLEN r15, r12
    DMARK r13
    xor r14d, r14d
1:  cmp r14, r15
    jae 9f
    mov rdi, r12
    mov rsi, r14
    mov edx, K_elements
    xor ecx, ecx
    call print_elem
    # [print(), isLast ? trailingComma : ","]
    lea rcx, [r14 + 1]
    lea rsi, [rip + ps_comma]
    cmp rcx, r15
    jb 2f
    mov rsi, [rsp]
2:  mov rdi, rax
    call doc_array2
    DPUSH rax
    inc r14
    cmp r14, r15
    jae 9f
    mov rdi, [r12 + r14*8]          # the element just printed
    call is_line_after_element_empty
    test eax, eax
    jz 3f
    lea rdi, [rip + d_hardline]
    lea rsi, [rip + d_hardline]
    call doc_array2
    jmp 5f
3:  mov rdi, [r12 + 8 + r14*8]
    mov esi, CC_Leading | CC_Line
    xor edx, edx
    call has_comment
    mov ecx, eax
    lea rax, [rip + d_line]
    test ecx, ecx
    jz 5f
    lea rax, [rip + d_hardline]
5:  DPUSH rax
    jmp 1b
9:  DARRAYK r13
    mov rdi, rax
    call doc_fill
    EPILOGUE
ENDF par_print_elements_concisely
