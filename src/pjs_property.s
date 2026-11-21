# print/property.js
.include "pjs.inc"

    .text

# ppr_simple_number_is_canonical(ptr, len) -> eax: String(Number(s)) === s for
# a simple number s. More than 17 digits from the first nonzero digit to the
# last cannot survive the round trip; other cases go to simple_number_is_canonical.
FUNC ppr_simple_number_is_canonical
    push rdi
    push rsi
    mov rcx, -1                     # first nonzero digit
    xor r8d, r8d                    # digits up to the last nonzero one
    xor r9d, r9d                    # digits seen since the first nonzero one
    xor edx, edx
1:  cmp rdx, rsi
    jae 3f
    movzx eax, byte ptr [rdi + rdx]
    inc rdx
    cmp eax, '.'
    je 1b
    test rcx, rcx
    jns 2f
    cmp eax, '0'
    je 1b
    mov rcx, rdx
2:  inc r9
    cmp eax, '0'
    je 1b
    mov r8, r9
    jmp 1b
3:  pop rsi
    pop rdi
    xor eax, eax
    cmp r8, 17
    ja 9f
    call simple_number_is_canonical
9:  leave
    ret
ENDF ppr_simple_number_is_canonical

# pjs_print_property(node, args) -> rax doc (printProperty): ObjectProperty,
# ImportAttribute
FUNC pjs_print_property
    PROLOGUE
    mov rbx, rdi
    ATTR rbx, NA_SHORTHAND
    jz 1f
    PRINT N_F1, K_value
    jmp 9f
1:  mov rdi, rbx
    call pjs_print_property_key
    mov rdi, rax
    lea rsi, [rip + ps_colon]
    mov edx, N_F1
    mov ecx, K_value
    call pjs_print_assignment
9:  EPILOGUE
ENDF pjs_print_property

# ppr_has_key(node) -> eax: the node type has `key` in F0 (and `computed`)
FUNC ppr_has_key
    movzx ecx, word ptr [rdi + N_TYPE]
    mov eax, 1
    .irp t, T_ObjectProperty, T_ObjectMethod, T_ClassMethod, T_ClassPrivateMethod, T_ClassProperty, T_ClassPrivateProperty, T_ClassAccessorProperty, T_ImportAttribute, T_TSPropertySignature, T_TSMethodSignature, T_TSDeclareMethod
    cmp ecx, \t
    je 9f
    .endr
    xor eax, eax
9:  leave
    ret
ENDF ppr_has_key

# ppr_string_key_safe_to_unquote(prop) -> eax (isStringKeySafeToUnquote) for
# the babel and typescript parsers: in TypeScript a class property's string
# key stays quoted and a string key is never unquoted as a number
FUNC ppr_string_key_safe_to_unquote
    PROLOGUE
    mov rbx, rdi
    call ppr_has_key
    test eax, eax
    jz 8f
    mov r12, [rbx + N_F0]           # key
    TYPE r12, T_StringLiteral
    jne 8f
    # printString(raw).slice(1, -1) === key.value
    mov rdi, r12
    call pjs_raw
    mov rdi, rax
    mov rsi, rdx
    call print_string
    lea rcx, [rdx - 2]
    cmp rcx, [r12 + N_F1]
    jne 8f
    lea rdi, [rax + 1]
    mov rsi, [r12 + N_F0]
    mov rdx, rcx
    call mem_eq
    test eax, eax
    jz 8f
    mov rdi, [r12 + N_F0]
    mov rsi, [r12 + N_F1]
    call is_es5_identifier_name
    test eax, eax
    jz 1f
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    jne 9f
    TYPE rbx, T_ClassProperty
    jne 9f
1:  TYPE rbx, T_ImportAttribute
    je 8f
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    je 8f
    mov rdi, [r12 + N_F0]
    mov rsi, [r12 + N_F1]
    call is_simple_number
    test eax, eax
    jz 8f
    mov rdi, [r12 + N_F0]
    mov rsi, [r12 + N_F1]
    call ppr_simple_number_is_canonical
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF ppr_string_key_safe_to_unquote

# ppr_compute_needs_quote_props(parent, siblings): needsQuoteProps for
# quoteProps "consistent", once per parent
FUNC ppr_compute_needs_quote_props
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    test word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS_SET
    jnz 9f
    or word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS_SET
    test r12, r12
    jz 9f
    mov r13d, [r12]                 # count (VEC or LIST)
    xor r14d, r14d
1:  cmp r14, r13
    jae 9f
    mov r15, [r12 + 8 + r14*8]
    inc r14
    test r15, r15
    jz 1b
    mov rdi, r15
    call ppr_has_key
    test eax, eax
    jz 1b
    ATTR r15, NA_COMPUTED
    jnz 1b
    mov rax, [r15 + N_F0]
    TYPE rax, T_StringLiteral
    jne 1b
    mov rdi, r15
    call ppr_string_key_safe_to_unquote
    test eax, eax
    jnz 1b
    or word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS
9:  EPILOGUE
ENDF ppr_compute_needs_quote_props

# pjs_print_property_key(node) -> rax doc (printPropertyKey); the property is
# the path's top
FUNC pjs_print_property_key
    PROLOGUE 2
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # key
    ATTR rbx, NA_COMPUTED
    jz 1f
    DMARK r13
    DPUSHL ps_lbracket
    PRINT N_F0, K_key
    DPUSH rax
    DPUSHL ps_rbracket
    DARRAY r13
    jmp 99f
1:  call path_parent
    mov r13, rax                    # parent
    cmp qword ptr [rip + g_quote_props], QP_CONSISTENT
    jne 2f
    call path_siblings
    mov rdi, r13
    mov rsi, rax
    call ppr_compute_needs_quote_props
    # shouldQuotePropertyKey: consistent with needsQuoteProps, and an
    # identifier or a simple number key that prints as its value
    test word ptr [r13 + N_FLAGS], NF_QUOTE_PROPS
    jz 2f
    TYPE r12, T_Identifier
    jne 11f
    mov rdi, r12
    call pjs_raw
    mov r14, rax
    mov r15, rdx
    jmp 20f
11: TYPE r12, T_NumericLiteral
    jne 2f
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    je 2f
    mov rdi, r12
    call pjs_raw
    mov rdi, rax
    mov rsi, rdx
    call print_number
    mov r14, rax
    mov r15, rdx
    mov rdi, r14
    mov rsi, r15
    call is_simple_number
    test eax, eax
    jz 2f
    mov rdi, r14
    mov rsi, r15
    call ppr_simple_number_is_canonical
    test eax, eax
    jz 2f
    # printString(JSON.stringify(text)): the text needs no escapes
20: lea rdi, [r15 + 2]
    call alloc
    mov [rsp], rax
    mov ecx, '"'
    cmp qword ptr [rip + g_single_quote], 0
    je 21f
    mov ecx, 0x27
21: mov [rax], cl
    mov [rax + r15 + 1], cl
    lea rdi, [rax + 1]
    mov rsi, r14
    mov rdx, r15
    call memcpy
    mov rdi, [rsp]
    lea rsi, [r15 + 2]
    call doc_str
    jmp 50f
    # unquote: isStringKeySafeToUnquote and as-needed, or consistent without
    # needsQuoteProps
2:  mov rax, [rip + g_quote_props]
    cmp rax, QP_AS_NEEDED
    je 3f
    cmp rax, QP_CONSISTENT
    jne 40f
    test word ptr [r13 + N_FLAGS], NF_QUOTE_PROPS
    jnz 40f
3:  mov rdi, rbx
    call ppr_string_key_safe_to_unquote
    test eax, eax
    jz 40f
    mov rdi, [r12 + N_F0]
    mov rsi, [r12 + N_F1]
    movzx eax, byte ptr [rdi]
    sub eax, '0'
    cmp eax, 9
    ja 31f
    call print_number
    mov rdi, rax
    mov rsi, rdx
31: call doc_str
    jmp 50f
40: PRINT N_F0, K_key
    jmp 99f
    # path.call(keyPath => printComments(keyPath, doc), "key")
50: mov r14, rax
    mov rdi, r12
    mov esi, K_key
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    mov rsi, r14
    call print_comments
    mov r14, rax
    call path_pop
    mov rax, r14
99: EPILOGUE
ENDF pjs_print_property_key
