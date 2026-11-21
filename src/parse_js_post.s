# Prettier's postprocess for the babel parser (src/language-js/parse/postprocess/index.js):
# merges nestled JSDoc comments, replaces ParenthesizedExpression by its expression with
# NA_PARENTHESIZED (unless a type cast comment precedes it), rebalances same-operator
# LogicalExpression chains and ends a VariableDeclaration without `;` at its last declarator.
# For TypeScript it drops TSParenthesizedType and one-member unions and intersections and gives
# TSTypeParameter.name the range Prettier gives it. A node with decorators starts at the first
# one, as Prettier's locStart says (N_START is locStart).
.include "defs.inc"
.include "parse_js.inc"

    .bss
    .balign 8
g_cast_ends:  .quad 0       # LIST of the ends of type cast comments, or 0
    .text

# js_postprocess(file)
FUNC js_postprocess
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call js_merge_jsdoc_comments
    call js_collect_type_casts
    mov rdi, [rbx + N_F0]
    call js_visit
    mov [rbx + N_F0], rax
    add rsp, 8
    pop rbx
    leave
    ret
ENDF js_postprocess

# js_merge_jsdoc_comments(): two indentable block comments that touch become one
FUNC js_merge_jsdoc_comments
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_comments]
    test r12, r12
    jz 9f
    mov ebx, [r12]                      # i + 1
    xor r13d, r13d                      # following comment
1:  test ebx, ebx
    jz 9f
    dec ebx
    mov r14, [r12 + 8 + rbx*8]
    test r13, r13
    jz 5f
    mov eax, [r14 + CM_END]
    cmp eax, [r13 + CM_START]
    jne 5f
    cmp byte ptr [r14 + CM_TYPE], CT_BLOCK
    jne 5f
    cmp byte ptr [r13 + CM_TYPE], CT_BLOCK
    jne 5f
    mov rdi, r14
    call js_indentable_comment
    test eax, eax
    jz 5f
    mov rdi, r13
    call js_indentable_comment
    test eax, eax
    jz 5f
    # extend comment i over i + 1 and remove i + 1
    mov eax, [r13 + CM_END]
    mov [r14 + CM_END], eax
    lea ecx, [rbx + 1]
2:  lea edx, [rcx + 1]
    cmp edx, [r12]
    jae 3f
    mov rax, [r12 + 8 + rdx*8]
    mov [r12 + 8 + rcx*8], rax
    inc ecx
    jmp 2b
3:  dec dword ptr [r12]
5:  mov r13, r14
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_merge_jsdoc_comments

# js_indentable_comment(comment) -> eax: Prettier's isIndentableBlockComment for a block
# comment: `*${value}*` has more than one line and every line starts with `*` after
# whitespace.
FUNC js_indentable_comment
    mov rsi, [rip + g_text]
    mov ecx, [rdi + CM_START]
    inc ecx                             # the `*` of `/*` stands for the added `*`
    mov edx, [rdi + CM_END]
    dec edx                             # through the `*` of `*/`
    xor r8d, r8d                        # line breaks
1:  cmp ecx, edx                        # line start: skip whitespace, then `*`
    jae 8f
    movzx eax, byte ptr [rsi + rcx]
    cmp al, '*'
    je 3f
    cmp al, 10
    je 8f
    cmp al, ' '
    je 2f
    cmp al, 9
    jb 8f
    cmp al, 13
    ja 8f
2:  inc ecx
    jmp 1b
3:  cmp ecx, edx                        # rest of the line
    jae 7f
    cmp byte ptr [rsi + rcx], 10
    je 4f
    inc ecx
    jmp 3b
4:  inc r8d
    inc ecx
    jmp 1b
7:  xor eax, eax
    test r8d, r8d
    setnz al
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF js_indentable_comment

# js_is_type_cast_comment(comment) -> eax: a block comment whose value starts with `*` and
# holds @type or @satisfies as a word
FUNC js_is_type_cast_comment
    xor eax, eax
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    jne 9f
    mov rsi, [rip + g_text]
    mov ecx, [rdi + CM_START]
    mov edx, [rdi + CM_END]
    sub edx, 2                          # value end
    add ecx, 2                          # value start
    cmp ecx, edx
    jae 9f
    cmp byte ptr [rsi + rcx], '*'
    jne 9f
1:  cmp ecx, edx
    jae 8f
    cmp byte ptr [rsi + rcx], '@'
    jne 7f
    lea r8d, [ecx + 5]                  # "@type"
    cmp r8d, edx
    ja 3f
    cmp dword ptr [rsi + rcx + 1], 0x65707974   # "type"
    jne 3f
    jmp 5f
3:  lea r8d, [ecx + 10]                 # "@satisfies"
    cmp r8d, edx
    ja 7f
    cmp dword ptr [rsi + rcx + 1], 0x69746173   # "sati"
    jne 7f
    cmp dword ptr [rsi + rcx + 5], 0x65696673   # "sfie"
    jne 7f
    cmp byte ptr [rsi + rcx + 9], 's'
    jne 7f
5:  cmp r8d, edx                        # \b: a non-word character or the end
    jae 6f
    movzx r9d, byte ptr [rsi + r8]
    cmp r9b, '_'
    je 7f
    cmp r9b, '0'
    jb 6f
    cmp r9b, '9'
    jbe 7f
    or r9b, 0x20
    cmp r9b, 'a'
    jb 6f
    cmp r9b, 'z'
    jbe 7f
6:  mov eax, 1
    jmp 9f
7:  inc ecx
    jmp 1b
8:  xor eax, eax
9:  leave
    ret
ENDF js_is_type_cast_comment

# js_collect_type_casts(): g_cast_ends
FUNC js_collect_type_casts
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov qword ptr [rip + g_cast_ends], 0
    mov r12, [rip + g_comments]
    test r12, r12
    jz 9f
    xor ebx, ebx
1:  cmp ebx, [r12]
    jae 9f
    mov r13, [r12 + 8 + rbx*8]
    mov rdi, r13
    call js_is_type_cast_comment
    test eax, eax
    jz 2f
    mov rdi, [rip + g_cast_ends]
    mov esi, [r13 + CM_END]
    call list_push
    mov [rip + g_cast_ends], rax
2:  inc ebx
    jmp 1b
9:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_collect_type_casts

# js_keep_paren(paren) -> eax: a type cast comment ends at or before the parenthesis with only
# whitespace between
FUNC js_keep_paren
    xor eax, eax
    mov rsi, [rip + g_cast_ends]
    test rsi, rsi
    jz 9f
    mov edx, [rdi + N_START]
    mov ecx, [rsi]
    xor r8d, r8d
    mov r9, -1                          # last end <= start
1:  test ecx, ecx
    jz 2f
    dec ecx
    mov r10, [rsi + 8 + rcx*8]
    cmp r10, rdx
    ja 1b
    mov r9, r10
2:  cmp r9, -1
    je 9f
    test r9, r9
    jz 9f
    mov rsi, [rip + g_text]
3:  cmp r9, rdx
    jae 8f
    movzx ecx, byte ptr [rsi + r9]
    cmp cl, ' '
    je 4f
    cmp cl, 9
    jb 9f
    cmp cl, 13
    ja 9f
4:  inc r9
    jmp 3b
8:  mov eax, 1
9:  leave
    ret
ENDF js_keep_paren

# js_visit(node) -> rax: the node after postprocess (children first, as visitNode does)
FUNC js_visit
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_type_fields]
    mov r12, [rcx + rax*8]
    # skip the props
1:  movzx eax, byte ptr [r12]
    inc r12
    test eax, eax
    jz 3f
    inc r12
2:  cmp byte ptr [r12], 0
    lea r12, [r12 + 1]
    jne 2b
    jmp 1b
    # children
3:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 20f
    movzx r13d, byte ptr [r12 + 1]      # slot offset
    add r12, 2
31: cmp byte ptr [r12], 0
    lea r12, [r12 + 1]
    jne 31b
    cmp eax, FK_VEC
    je 5f
    mov rdi, [rbx + r13]
    test rdi, rdi
    jz 3b
    call js_visit
    mov [rbx + r13], rax
    jmp 3b
5:  mov r14, [rbx + r13]
    test r14, r14
    jz 3b
    xor r15d, r15d
6:  cmp r15, [r14]
    jae 3b
    mov rdi, [r14 + 8 + r15*8]
    test rdi, rdi
    jz 7f
    call js_visit
    mov [r14 + 8 + r15*8], rax
7:  inc r15
    jmp 6b
    # the node itself
20: movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ParenthesizedExpression
    je 21f
    cmp eax, T_LogicalExpression
    je 22f
    cmp eax, T_VariableDeclaration
    je 23f
    cmp eax, T_TSParenthesizedType
    je 30f
    cmp eax, T_TSUnionType
    je 31f
    cmp eax, T_TSIntersectionType
    je 31f
    cmp eax, T_TSTypeParameter
    je 32f
    cmp eax, T_ExportNamedDeclaration
    je 33f
    cmp eax, T_ExportDefaultDeclaration
    je 33f
    mov rdi, rbx
    call js_decorated_start
    jmp 99f
30: mov rbx, [rbx + N_F5]
    jmp 99f
31: mov rax, [rbx + N_F0]
    cmp qword ptr [rax], 1
    jne 99f
    mov rbx, [rax + 8]
    jmp 99f
    # fixBabelTSTypeParameter: the name's range starts where the parameter does (before in, out
    # and const); F0 keeps where the name's text is
32: mov rax, [rbx + N_F0]
    test rax, rax
    jz 99f
    cmp qword ptr [rax + N_F0], 0
    jne 99f
    mov ecx, [rax + N_END]
    sub ecx, [rax + N_START]
    cmp qword ptr [rax + N_F7], 0
    je 321f
    mov rcx, [rax + N_F7]
321: mov [rax + N_F7], rcx
    mov edx, [rax + N_START]
    inc edx
    mov [rax + N_F0], rdx
    mov edx, [rbx + N_START]
    mov [rax + N_START], edx
    add edx, ecx
    mov [rax + N_END], edx
    jmp 99f
33: mov rax, [rbx + N_F0]
    test rax, rax
    jz 99f
    mov rdi, rbx
    mov rsi, [rax + N_F6]
    call js_min_start
    jmp 99f
21: mov rdi, rbx
    call js_keep_paren
    test eax, eax
    jnz 99f
    mov rbx, [rbx + N_F0]
    or dword ptr [rbx + N_ATTR], NA_PARENTHESIZED
    jmp 99f
22: mov rdi, rbx
    call js_rebalance
    mov rbx, rax
    jmp 99f
23: mov rax, [rbx + N_F0]
    mov rcx, [rax]
    test rcx, rcx
    jz 99f
    mov rax, [rax + rcx*8]              # last declarator
    cmp qword ptr [rax + N_F1], 0
    je 99f
    mov ecx, [rax + N_END]
    cmp rcx, [rip + g_text_len]
    jae 24f
    mov rdx, [rip + g_text]
    cmp byte ptr [rdx + rcx], ';'
    je 99f
24: mov [rbx + N_END], ecx
99: mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_visit

# js_decorated_start(node): a node with decorators (F6) starts at the first one, when that is
# earlier
FUNC js_decorated_start
    movzx eax, word ptr [rdi + N_TYPE]
    lea rcx, [rip + js_decorated_types]
1:  movzx edx, word ptr [rcx]
    test edx, edx
    jz 9f
    add rcx, 2
    cmp edx, eax
    jne 1b
    mov rsi, [rdi + N_F6]
    call js_min_start
9:  leave
    ret
ENDF js_decorated_start

# js_min_start(node, decorators VEC or 0). An Identifier keeps its name's offset and length in F0
# and F7.
FUNC js_min_start
    test rsi, rsi
    jz 9f
    cmp qword ptr [rsi], 0
    je 9f
    mov rax, [rsi + 8]
    mov eax, [rax + N_START]
    cmp eax, [rdi + N_START]
    jae 9f
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 2f
    mov ecx, [rdi + N_START]
    cmp qword ptr [rdi + N_F7], 0
    jne 1f
    mov edx, [rdi + N_END]
    sub edx, ecx
    mov [rdi + N_F7], rdx
1:  cmp qword ptr [rdi + N_F0], 0
    jne 2f
    inc ecx
    mov [rdi + N_F0], rcx
2:  mov [rdi + N_START], eax
9:  leave
    ret
ENDF js_min_start

    .section .rodata
    .balign 2
js_decorated_types:
    .short T_Identifier, T_ObjectPattern, T_ArrayPattern, T_AssignmentPattern, T_RestElement
    .short T_ClassMethod, T_ClassPrivateMethod, T_ClassProperty, T_ClassPrivateProperty
    .short T_ClassAccessorProperty, T_ClassDeclaration, T_ClassExpression, T_TSParameterProperty
    .short T_TSDeclareMethod, 0
    .text

# js_rebalance(node) -> rax: `a && (b && c)` becomes `(a && b) && c` with new nodes, as
# Prettier's rebalanceLogicalTree does
FUNC js_rebalance
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
1:  mov r12, [rbx + N_F1]
    cmp word ptr [r12 + N_TYPE], T_LogicalExpression
    jne 9f
    mov rax, [r12 + N_F2]
    cmp rax, [rbx + N_F2]
    jne 9f
    # left: node.left op node.right.left
    mov rax, [rbx + N_F0]
    NODE T_LogicalExpression, [rax + N_START]
    mov r13, rax
    mov rax, [rbx + N_F0]
    mov [r13 + N_F0], rax
    mov rax, [r12 + N_F0]
    mov [r13 + N_F1], rax
    mov eax, [rax + N_END]
    mov [r13 + N_END], eax
    mov rax, [rbx + N_F2]
    mov [r13 + N_F2], rax
    mov rdi, r13
    call js_rebalance
    mov r13, rax
    # top: left' op node.right.right
    mov esi, [rbx + N_START]
    NODE T_LogicalExpression, rsi
    mov r14, rax
    mov [r14 + N_F0], r13
    mov rax, [r12 + N_F1]
    mov [r14 + N_F1], rax
    mov eax, [rbx + N_END]
    mov [r14 + N_END], eax
    mov rax, [rbx + N_F2]
    mov [r14 + N_F2], rax
    mov rbx, r14
    jmp 1b
9:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_rebalance
