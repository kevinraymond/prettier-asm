# getStringWidth (src/utils/get-string-width.js): text.replace(emojiRegex(), "  ")
# then 0 for control and combining characters, 2 for wide ones, 1 otherwise.
# The emoji regex is replaced by a trie of everything it can match (see
# unicode_tables.s): the regex's match at a position is the longest trie match.
.include "defs.inc"

# str_width(ptr, len) -> rax. Text is valid UTF-8.
FUNC str_width
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    # fast path: only 0x20..0x7F
    xor ecx, ecx
1:  cmp rcx, r12
    jae 2f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, 0x20
    jb 10f
    cmp al, 0x7F
    jbe 1b
    jmp 10f
2:  mov rax, r12
    jmp 99f
10: xor r13d, r13d                  # width
    xor r14d, r14d                  # position
11: cmp r14, r12
    jae 90f
    # longest emoji match starting here
    xor r15d, r15d                  # best end (0: none)
    xor eax, eax
    mov [rsp], rax                  # trie node
    mov rcx, r14                    # cursor
12: cmp rcx, r12
    jae 15f
    push rcx
    sub rsp, 8
    mov rdi, rbx
    mov rsi, rcx
    call utf8_decode
    mov rsi, rdx
    add rsp, 8
    pop rcx
    add rcx, rsi
    push rcx
    sub rsp, 8
    mov edi, [rsp + 16]
    mov esi, eax
    call emoji_child
    add rsp, 8
    pop rcx
    test eax, eax
    js 15f
    mov [rsp], rax
    lea rdx, [rip + emoji_nodes]
    test dword ptr [rdx + rax*8 + 4], 0x80000000
    jz 12b
    mov r15, rcx
    jmp 12b
15: test r15, r15
    jz 16f
    add r13, 2
    mov r14, r15
    jmp 11b
    # no match: one code point
16: mov rdi, rbx
    mov rsi, r14
    call utf8_decode
    add r14, rdx
    mov edi, eax
    call cp_width
    add r13, rax
    jmp 11b
90: mov rax, r13
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF str_width

# utf8_decode(ptr, index) -> eax = code point, rdx = byte length
FUNC utf8_decode
    movzx eax, byte ptr [rdi + rsi]
    cmp eax, 0x80
    jae 1f
    mov edx, 1
    leave
    ret
1:  cmp eax, 0xE0
    jae 2f
    and eax, 0x1F
    shl eax, 6
    movzx ecx, byte ptr [rdi + rsi + 1]
    and ecx, 0x3F
    or eax, ecx
    mov edx, 2
    leave
    ret
2:  cmp eax, 0xF0
    jae 3f
    and eax, 0x0F
    shl eax, 12
    movzx ecx, byte ptr [rdi + rsi + 1]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + rsi + 2]
    and ecx, 0x3F
    or eax, ecx
    mov edx, 3
    leave
    ret
3:  and eax, 0x07
    shl eax, 18
    movzx ecx, byte ptr [rdi + rsi + 1]
    and ecx, 0x3F
    shl ecx, 12
    or eax, ecx
    movzx ecx, byte ptr [rdi + rsi + 2]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + rsi + 3]
    and ecx, 0x3F
    or eax, ecx
    mov edx, 4
    leave
    ret
ENDF utf8_decode

# emoji_child(node, cp) -> eax = child node, or -1
FUNC emoji_child
    lea r8, [rip + emoji_nodes]
    mov ecx, [r8 + rdi*8]           # first edge
    mov edx, [r8 + rdi*8 + 4]
    and edx, 0x7FFFFFFF             # edge count
    lea r9, [rip + emoji_edges]
    # binary search in [ecx, ecx + edx)
    lea r10d, [rcx + rdx]           # hi
    mov r11d, ecx                   # lo
1:  cmp r11d, r10d
    jae 8f
    lea eax, [r11 + r10]
    shr eax, 1
    mov edx, [r9 + rax*8]
    cmp esi, edx
    je 2f
    jb 3f
    lea r11d, [rax + 1]
    jmp 1b
3:  mov r10d, eax
    jmp 1b
2:  mov eax, [r9 + rax*8 + 4]
    leave
    ret
8:  mov eax, -1
    leave
    ret
ENDF emoji_child

# cp_width(cp) -> rax
FUNC cp_width
    xor eax, eax
    cmp edi, 0x1F
    jbe 9f
    cmp edi, 0x7F
    jb 1f
    cmp edi, 0x9F
    jbe 9f
    cmp edi, 0x300
    jb 1f
    cmp edi, 0x36F
    jbe 9f
1:  call is_wide
    inc eax
9:  leave
    ret
ENDF cp_width

# in_ranges(cp, table, count) -> eax
FUNC in_ranges
    xor eax, eax
1:  test edx, edx
    jz 9f
    cmp edi, [rsi]
    jb 9f                           # sorted: nothing further can match
    cmp edi, [rsi + 4]
    jbe 2f
    add rsi, 8
    dec edx
    jmp 1b
2:  mov eax, 1
9:  leave
    ret
ENDF in_ranges

# is_wide(cp) -> eax: isFullWidth || isWide
FUNC is_wide
    lea rsi, [rip + wide_ranges]
    mov edx, [rip + wide_ranges_count]
    call in_ranges
    leave
    ret
ENDF is_wide
