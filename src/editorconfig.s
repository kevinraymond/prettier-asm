# .editorconfig files as the editorconfig package (0.15.3) reads them and
# Prettier's editorconfig-to-prettier turns them into options. Only the six
# properties Prettier looks at are kept.
.include "defs.inc"

.equ EK_INDENT_STYLE, 0
.equ EK_INDENT_SIZE, 1
.equ EK_TAB_WIDTH, 2
.equ EK_MAX_LINE_LENGTH, 3
.equ EK_QUOTE_TYPE, 4
.equ EK_END_OF_LINE, 5
.equ EK_COUNT, 6

# A value: kind, then an integer or a token.
.equ VK_ABSENT, 0
.equ VK_INT, 1          # JSON.parse gave a non-negative integer
.equ VK_STR, 2          # not JSON: a string, lowercased for known properties
.equ VK_JSON, 3         # JSON.parse gave something else

.equ T_EMPTY, 0
.equ T_OTHER, 1
.equ T_TAB, 2
.equ T_SPACE, 3
.equ T_UNSET, 4
.equ T_OFF, 5
.equ T_SINGLE, 6
.equ T_DOUBLE, 7
.equ T_LF, 8
.equ T_CR, 9
.equ T_CRLF, 10

# Parsed file: +0 root (u64), +8 section count, +16 sections (array of ptrs)
# Section: +0 name ptr, +8 name len, +16 entry count, +24 entries
# Entry (32 bytes): raw key ptr, raw key len, value ptr, value len
.equ MAX_SECTIONS, 1024
.equ MAX_ENTRIES, 64

    .bss
    .balign 8
ec_kind:  .space 8 * EK_COUNT
ec_val:   .space 8 * EK_COUNT
ec_cur:   .quad 0                   # current section while parsing
ec_file:  .quad 0
ec_root:  .quad 0                   # preamble `root` value (ptr, len), ptr 0 if none
ec_rootlen: .quad 0

    .section .rodata
ek_names:
    .quad s_indent_style, s_indent_size, s_tab_width, s_max_line_length
    .quad s_quote_type, s_end_of_line
s_indent_style:    .asciz "indent_style"
s_indent_size:     .asciz "indent_size"
s_tab_width:       .asciz "tab_width"
s_max_line_length: .asciz "max_line_length"
s_quote_type:      .asciz "quote_type"
s_end_of_line:     .asciz "end_of_line"
s_root:            .asciz "root"
s_true4:           .asciz "true"
# tokens, in T_* order from T_TAB
tok_names:
    .quad s_tab, s_space, s_unset, s_off, s_single, s_double, s_lf, s_cr, s_crlf, 0
s_tab:    .asciz "tab"
s_space:  .asciz "space"
s_unset:  .asciz "unset"
s_off:    .asciz "off"
s_single: .asciz "single"
s_double: .asciz "double"
s_lf:     .asciz "lf"
s_cr:     .asciz "cr"
s_crlf:   .asciz "crlf"

    .text

# ec_reset(): clears the merged properties
FUNC ec_reset
    lea rdi, [rip + ec_kind]
    xor eax, eax
    mov ecx, EK_COUNT * 2
    rep stosq
    leave
    ret
ENDF ec_reset

# ec_ws(c) -> eax: \s within a line
FUNC ec_ws
    xor eax, eax
    cmp dil, ' '
    je 1f
    cmp dil, 9
    je 1f
    cmp dil, 11
    je 1f
    cmp dil, 12
    jne 2f
1:  mov eax, 1
2:  leave
    ret
ENDF ec_ws

# ec_new_section(name, len)
FUNC ec_new_section
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov edi, 24 + 32 * MAX_ENTRIES
    call alloc
    mov [rax], rbx
    mov [rax + 8], r12
    mov [rip + ec_cur], rax
    mov rdx, [rip + ec_file]
    mov rcx, [rdx + 8]
    cmp rcx, MAX_SECTIONS
    jae 90f
    mov [rdx + 16 + rcx*8], rax
    inc qword ptr [rdx + 8]
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "too many editorconfig sections"
ENDF ec_new_section

# ec_key_index(ptr, len) -> eax = EK_* of the lowercased key, or -1
FUNC ec_key_index
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, EK_COUNT
    jae 8f
    lea rax, [rip + ek_names]
    mov r14, [rax + r13*8]
    mov rdi, r14
    call strlen
    cmp rax, r12
    jne 4f
    xor ecx, ecx
2:  cmp rcx, r12
    jae 9f
    movzx eax, byte ptr [rbx + rcx]
    mov edx, eax
    sub edx, 'A'
    cmp edx, 25
    ja 3f
    add eax, 32
3:  cmp al, [r14 + rcx]
    jne 4f
    inc rcx
    jmp 2b
4:  inc r13
    jmp 1b
8:  mov r13, -1
9:  mov eax, r13d
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ec_key_index

# ec_add(key, klen, val, vlen): a property line in the current section.
# The section body is a JS object: a repeated key keeps its first position.
FUNC ec_add
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, [rip + ec_cur]
    # the preamble's `root`
    cmp qword ptr [r15], 0
    jne 1f
    cmp r12, 4
    jne 1f
    cmp dword ptr [rbx], 0x746f6f72 # "root"
    jne 1f
    mov [rip + ec_root], r13
    mov [rip + ec_rootlen], r14
    mov rax, [rip + ec_file]
    mov qword ptr [rax], 1
1:  mov rdi, rbx
    mov rsi, r12
    call ec_key_index
    test eax, eax
    js 9f
    # same raw key: replace the value in place
    mov rcx, [r15 + 16]
    xor edx, edx
2:  cmp rdx, rcx
    jae 4f
    mov r8, rdx
    shl r8, 5
    lea r8, [r15 + 24 + r8]
    cmp [r8 + 8], r12
    jne 3f
    mov [rsp], rcx
    mov [rsp + 8], rdx
    mov rdi, [r8]
    mov rsi, rbx
    push r8
    sub rsp, 8
    mov rdx, r12
    call mem_eq
    add rsp, 8
    pop r8
    mov rcx, [rsp]
    mov rdx, [rsp + 8]
    test eax, eax
    jz 3f
    mov [r8 + 16], r13
    mov [r8 + 24], r14
    jmp 9f
3:  inc rdx
    jmp 2b
4:  cmp rcx, MAX_ENTRIES
    jae 90f
    mov r8, rcx
    shl r8, 5
    lea r8, [r15 + 24 + r8]
    mov [r8], rbx
    mov [r8 + 8], r12
    mov [r8 + 16], r13
    mov [r8 + 24], r14
    inc qword ptr [r15 + 16]
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "too many editorconfig properties"
ENDF ec_add

# ec_parse(ptr, len) -> rax = parsed file. Lines split on \r\n, \r or \n;
# each is a comment, a `key = value` line, a `[section]` line, or ignored.
FUNC ec_parse
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov edi, 16 + 8 * MAX_SECTIONS
    call alloc
    mov [rip + ec_file], rax
    mov qword ptr [rip + ec_root], 0
    xor edi, edi
    xor esi, esi
    call ec_new_section
    # line loop: rbx = line start
3:  cmp rbx, r12
    ja 80f
    mov r13, rbx
4:  cmp r13, r12
    jae 5f
    movzx eax, byte ptr [r13]
    cmp al, 10
    je 5f
    cmp al, 13
    je 5f
    inc r13
    jmp 4b
5:  mov rdi, rbx
    mov rsi, r13
    call ec_line
    cmp r13, r12
    jae 80f
    lea rbx, [r13 + 1]
    cmp byte ptr [r13], 13
    jne 3b
    cmp rbx, r12
    jae 3b
    cmp byte ptr [rbx], 10
    jne 3b
    inc rbx
    jmp 3b
80: mov rax, [rip + ec_file]
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ec_parse

# ec_line(start, end)
FUNC ec_line
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    # leading whitespace
1:  cmp rbx, r12
    jae 99f
    movzx edi, byte ptr [rbx]
    call ec_ws
    test eax, eax
    jz 2f
    inc rbx
    jmp 1b
    # a line starting with '#' or ';' is ignored whatever follows; other
    # lines must be ASCII, as \s and . in the package's regexes see more
2:  movzx eax, byte ptr [rbx]
    cmp al, '#'
    je 99f
    cmp al, ';'
    je 99f
    mov rcx, rbx
21: cmp rcx, r12
    jae 22f
    movzx edx, byte ptr [rcx]
    inc rcx
    cmp dl, 0x7f
    jae 90f
    cmp dl, 9
    jb 90f
    jmp 21b
22: cmp al, '['
    je 50f
    # key: [A-Za-z0-9_.-]+
    mov r13, rbx
3:  cmp r13, r12
    jae 99f
    movzx eax, byte ptr [r13]
    cmp al, '_'
    je 31f
    cmp al, '.'
    je 31f
    cmp al, '-'
    je 31f
    mov ecx, eax
    sub ecx, '0'
    cmp ecx, 9
    jbe 31f
    or al, 0x20
    sub al, 'a'
    cmp al, 25
    ja 32f
31: inc r13
    jmp 3b
32: cmp r13, rbx
    je 99f
    mov r14, r13                    # key end
33: cmp r13, r12
    jae 99f
    movzx edi, byte ptr [r13]
    call ec_ws
    test eax, eax
    jz 34f
    inc r13
    jmp 33b
34: movzx eax, byte ptr [r13]
    cmp al, '='
    je 35f
    cmp al, ':'
    jne 99f
35: inc r13
36: cmp r13, r12
    jae 37f
    movzx edi, byte ptr [r13]
    call ec_ws
    test eax, eax
    jz 37f
    inc r13
    jmp 36b
    # value: up to the first '#' or ';', trailing whitespace dropped
37: mov r15, r13
38: cmp r15, r12
    jae 39f
    movzx eax, byte ptr [r15]
    cmp al, '#'
    je 39f
    cmp al, ';'
    je 39f
    inc r15
    jmp 38b
39: cmp r15, r13
    jbe 40f
    movzx edi, byte ptr [r15 - 1]
    call ec_ws
    test eax, eax
    jz 40f
    dec r15
    jmp 39b
40: mov rdi, rbx
    mov rsi, r14
    sub rsi, rbx
    mov rdx, r13
    mov rcx, r15
    sub rcx, r13
    call ec_add
    jmp 99f
    # [name]: the part before the first '#' or ';' ends in ']' and blanks
50: inc rbx
    mov r13, rbx
51: cmp r13, r12
    jae 52f
    movzx eax, byte ptr [r13]
    cmp al, '\\'
    je 91f
    cmp al, '#'
    je 52f
    cmp al, ';'
    je 52f
    inc r13
    jmp 51b
52: cmp r13, rbx
    jbe 99f
    movzx edi, byte ptr [r13 - 1]
    call ec_ws
    test eax, eax
    jz 53f
    dec r13
    jmp 52b
53: cmp byte ptr [r13 - 1], ']'
    jne 99f
    dec r13
    cmp r13, rbx
    je 99f
    mov rdi, rbx
    mov rsi, r13
    sub rsi, rbx
    call ec_new_section
99: add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "editorconfig with non-ASCII or control characters"
91: REFUSE "editorconfig section with backslash"
ENDF ec_line

# ec_file_root(file) -> eax: the preamble says root = true (any case)
FUNC ec_file_root
    xor eax, eax
    cmp qword ptr [rdi], 0
    je 9f
    mov rsi, [rip + ec_root]
    test rsi, rsi
    jz 9f
    cmp qword ptr [rip + ec_rootlen], 4
    jne 9f
    mov ecx, [rsi]
    or ecx, 0x20202020
    cmp ecx, 0x65757274             # "true"
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF ec_file_root

# ec_apply(file, dir, dlen, rel, rlen): every section whose glob matches the
# file sets its properties, in order.
FUNC ec_apply
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov [rsp], rcx
    mov [rsp + 8], r8
    xor r12d, r12d
1:  cmp r12, [rbx + 8]
    jae 9f
    mov r13, [rbx + 16 + r12*8]
    inc r12
    cmp qword ptr [r13], 0
    je 1b
    mov rdi, [r13]
    mov rsi, [r13 + 8]
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call gl_ec_match
    test eax, eax
    jz 1b
    xor r14d, r14d
2:  cmp r14, [r13 + 16]
    jae 1b
    mov r15, r14
    shl r15, 5
    lea r15, [r13 + 24 + r15]
    inc r14
    mov rdi, [r15]
    mov rsi, [r15 + 8]
    call ec_key_index
    mov edi, eax
    mov rsi, [r15 + 16]
    mov rdx, [r15 + 24]
    call ec_set
    jmp 2b
9:  add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ec_apply

# ec_set(key, val, vlen): extendProps for one property. JSON.parse runs on
# the value as written; known properties are lowercased otherwise.
FUNC ec_set
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    call cfg_json_parse
    test rax, rax
    jz 2f
    mov ecx, VK_JSON
    xor edx, edx
    cmp byte ptr [rax + CV_TYPE], CV_NUM
    jne 1f
    test byte ptr [rax + CV_FLAGS], CVF_INT
    jz 1f
    mov ecx, VK_INT
    mov rdx, [rax + CV_A]
1:  lea rax, [rip + ec_kind]
    mov [rax + rbx*8], rcx
    lea rax, [rip + ec_val]
    mov [rax + rbx*8], rdx
    jmp 9f
    # a string; tokens compare after lowercasing for indent_style,
    # indent_size and end_of_line only
2:  mov r14d, T_EMPTY
    test r13, r13
    jz 8f
    mov edi, ebx
    call ec_token
    mov r14d, eax
8:  lea rax, [rip + ec_kind]
    mov qword ptr [rax + rbx*8], VK_STR
    lea rax, [rip + ec_val]
    mov [rax + rbx*8], r14
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ec_set

# ec_token(key) with r12/r13 = value -> eax = T_*
FUNC ec_token
    push rbx
    push r14
    mov ebx, edi
    lea r14, [rip + tok_names]
    mov r8d, T_TAB
1:  mov rsi, [r14]
    test rsi, rsi
    jz 7f
    xor ecx, ecx
2:  movzx eax, byte ptr [rsi + rcx]
    cmp rcx, r13
    je 5f
    test al, al
    jz 6f
    movzx edx, byte ptr [r12 + rcx]
    cmp ebx, EK_TAB_WIDTH
    je 3f
    cmp ebx, EK_QUOTE_TYPE
    je 3f
    cmp ebx, EK_MAX_LINE_LENGTH
    je 3f
    mov r9d, edx
    sub r9d, 'A'
    cmp r9d, 25
    ja 3f
    add edx, 32
3:  cmp eax, edx
    jne 6f
    inc rcx
    jmp 2b
5:  test al, al
    jnz 6f
    mov eax, r8d
    jmp 9f
6:  add r14, 8
    inc r8d
    jmp 1b
7:  mov eax, T_OTHER
9:  pop r14
    pop rbx
    leave
    ret
ENDF ec_token

# ec_is(key, token) -> eax: the property is that string
FUNC ec_is
    xor eax, eax
    lea rcx, [rip + ec_kind]
    cmp qword ptr [rcx + rdi*8], VK_STR
    jne 9f
    lea rcx, [rip + ec_val]
    cmp [rcx + rdi*8], rsi
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF ec_is

# ec_truthy(key) -> eax
FUNC ec_truthy
    xor eax, eax
    lea rcx, [rip + ec_kind]
    mov rdx, [rcx + rdi*8]
    lea rcx, [rip + ec_val]
    cmp rdx, VK_ABSENT
    je 9f
    cmp qword ptr [rcx + rdi*8], 0
    je 9f
    mov eax, 1
9:  leave
    ret
ENDF ec_truthy

# ec_copy(dst, src)
FUNC ec_copy
    lea rcx, [rip + ec_kind]
    mov rax, [rcx + rsi*8]
    mov [rcx + rdi*8], rax
    lea rcx, [rip + ec_val]
    mov rax, [rcx + rsi*8]
    mov [rcx + rdi*8], rax
    leave
    ret
ENDF ec_copy

# ec_kind_of(key) -> rax
FUNC ec_kind_of
    lea rcx, [rip + ec_kind]
    mov rax, [rcx + rdi*8]
    leave
    ret
ENDF ec_kind_of

# ec_value_option(key, slot, max): sets the option to an integer property
FUNC ec_value_option
    lea rcx, [rip + ec_kind]
    cmp qword ptr [rcx + rdi*8], VK_INT
    jne 90f
    lea rcx, [rip + ec_val]
    mov rax, [rcx + rdi*8]
    test rax, rax
    jz 90f
    cmp rax, rdx
    ja 90f
    mov rdi, rsi
    mov rsi, rax
    call cfg_pend
    leave
    ret
90: REFUSE "editorconfig value not ported"
ENDF ec_value_option

# ec_finish(): processMatches, then editorconfig-to-prettier, into pending
# options.
FUNC ec_finish
    push rbx
    push r12
    # indent_style = tab without indent_size: indent_size = tab
    mov edi, EK_INDENT_STYLE
    mov esi, T_TAB
    call ec_is
    test eax, eax
    jz 1f
    mov edi, EK_INDENT_SIZE
    call ec_kind_of
    test rax, rax
    jnz 1f
    lea rcx, [rip + ec_kind]
    mov qword ptr [rcx + EK_INDENT_SIZE*8], VK_STR
    lea rcx, [rip + ec_val]
    mov qword ptr [rcx + EK_INDENT_SIZE*8], T_TAB
    # indent_size without tab_width, not tab: tab_width = indent_size
1:  mov edi, EK_INDENT_SIZE
    call ec_kind_of
    test rax, rax
    jz 2f
    mov edi, EK_TAB_WIDTH
    call ec_kind_of
    test rax, rax
    jnz 2f
    mov edi, EK_INDENT_SIZE
    mov esi, T_TAB
    call ec_is
    test eax, eax
    jnz 2f
    mov edi, EK_TAB_WIDTH
    mov esi, EK_INDENT_SIZE
    call ec_copy
    # indent_size = tab with tab_width: indent_size = tab_width
2:  mov edi, EK_INDENT_SIZE
    mov esi, T_TAB
    call ec_is
    test eax, eax
    jz 3f
    mov edi, EK_TAB_WIDTH
    call ec_kind_of
    test rax, rax
    jz 3f
    mov edi, EK_INDENT_SIZE
    mov esi, EK_TAB_WIDTH
    call ec_copy
    # removeUnset; JSON values other than integers are not ported
3:  xor ebx, ebx
31: cmp ebx, EK_COUNT
    jae 4f
    mov edi, ebx
    mov esi, T_UNSET
    call ec_is
    test eax, eax
    jz 32f
    lea rcx, [rip + ec_kind]
    mov qword ptr [rcx + rbx*8], VK_ABSENT
32: mov edi, ebx
    call ec_kind_of
    cmp rax, VK_JSON
    je 90f
    inc ebx
    jmp 31b
    # useTabs (r12: -1 unset)
4:  mov r12, -1
    mov edi, EK_INDENT_STYLE
    call ec_truthy
    test eax, eax
    jz 41f
    mov edi, EK_INDENT_STYLE
    mov esi, T_TAB
    call ec_is
    mov r12d, eax
41: mov edi, EK_INDENT_SIZE
    mov esi, T_TAB
    call ec_is
    test eax, eax
    jz 42f
    mov r12d, 1
42: cmp r12, -1
    je 43f
    mov edi, 2
    mov rsi, r12
    call cfg_pend
    # tabWidth
43: cmp r12, 1
    jne 44f
    mov edi, EK_TAB_WIDTH
    call ec_truthy
    test eax, eax
    jz 44f
    mov edi, EK_TAB_WIDTH
    jmp 47f
44: mov edi, EK_INDENT_STYLE
    mov esi, T_SPACE
    call ec_is
    test eax, eax
    jz 45f
    mov edi, EK_INDENT_SIZE
    call ec_truthy
    test eax, eax
    jz 45f
    mov edi, EK_INDENT_SIZE
    mov esi, T_TAB
    call ec_is
    test eax, eax
    jnz 45f
    mov edi, EK_INDENT_SIZE
    jmp 47f
45: mov edi, EK_TAB_WIDTH
    call ec_kind_of
    test rax, rax
    jz 5f
    mov edi, EK_TAB_WIDTH
47: mov esi, 1
    mov edx, 64
    call ec_value_option
    # printWidth
5:  mov edi, EK_MAX_LINE_LENGTH
    call ec_truthy
    test eax, eax
    jz 6f
    mov edi, EK_MAX_LINE_LENGTH
    xor esi, esi
    mov edx, 1000
    call ec_value_option
    # singleQuote
6:  mov edi, EK_QUOTE_TYPE
    mov esi, T_SINGLE
    call ec_is
    test eax, eax
    jz 61f
    mov edi, 3
    mov esi, 1
    call cfg_pend
    jmp 7f
61: mov edi, EK_QUOTE_TYPE
    mov esi, T_DOUBLE
    call ec_is
    test eax, eax
    jz 7f
    mov edi, 3
    xor esi, esi
    call cfg_pend
    # endOfLine: lf is the default; cr and crlf are not ported
7:  mov edi, EK_END_OF_LINE
    mov esi, T_CR
    call ec_is
    test eax, eax
    jnz 91f
    mov edi, EK_END_OF_LINE
    mov esi, T_CRLF
    call ec_is
    test eax, eax
    jnz 91f
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "editorconfig value not ported"
91: REFUSE "editorconfig end_of_line not ported"
ENDF ec_finish
