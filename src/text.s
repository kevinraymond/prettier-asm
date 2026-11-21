# Source text preparation and Prettier's text helpers (src/utils/skip*.js,
# has-newline*.js, is-next-line-empty.js, is-previous-line-empty.js,
# get-next-non-space-non-comment-character-index.js).
#
# Indices are signed 64-bit byte offsets into g_text. IDX_FALSE stands for JS
# `false`. A forward scan takes and returns the offset of a character's first
# byte; a backward scan takes and returns the offset of a character's last
# byte (so `locStart(node) - 1` works as in Prettier). U+2028 and U+2029 are
# line breaks wherever Prettier treats them so.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_text, g_text_len, g_has_bom, g_non_ascii
g_text:      .quad 0
g_text_len:  .quad 0
g_has_bom:   .quad 0
g_non_ascii: .quad 0        # 1 if the text has any byte >= 0x80

# text_prepare(): strip the BOM, turn CRLF and CR into LF (normalizeEndOfLine),
# check UTF-8.
FUNC text_prepare
    push rbx
    push r12
    push r13
    push r14
    mov rsi, [rip + g_input]
    mov rcx, [rip + g_input_len]
    cmp rcx, 3
    jb 1f
    cmp byte ptr [rsi], 0xEF
    jne 1f
    cmp byte ptr [rsi + 1], 0xBB
    jne 1f
    cmp byte ptr [rsi + 2], 0xBF
    jne 1f
    mov qword ptr [rip + g_has_bom], 1
    add rsi, 3
    sub rcx, 3
1:  mov rbx, rsi
    mov r12, rcx
    # copy into the text region, folding CR
    mov rdi, R_TEXT
    call region_base
    mov [rip + g_text], rax
    mov rdi, rax
    mov rsi, rbx
    lea rdx, [rbx + r12]
2:  cmp rsi, rdx
    jae 5f
    mov al, [rsi]
    inc rsi
    cmp al, 13
    jne 3f
    mov al, 10
    cmp rsi, rdx
    jae 3f
    cmp byte ptr [rsi], 10
    jne 3f
    inc rsi
3:  mov [rdi], al
    inc rdi
    jmp 2b
5:  sub rdi, [rip + g_text]
    mov [rip + g_text_len], rdi
    call utf8_check
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF text_prepare

# utf8_check(): refuses malformed UTF-8 (Node would decode it to U+FFFD),
# sets g_non_ascii.
FUNC utf8_check
    mov rsi, [rip + g_text]
    mov rdx, rsi
    add rdx, [rip + g_text_len]
1:  cmp rsi, rdx
    jae 9f
    movzx eax, byte ptr [rsi]
    cmp al, 0x80
    jae 2f
    inc rsi
    jmp 1b
2:  mov qword ptr [rip + g_non_ascii], 1
    # lead byte: C2..DF (2), E0..EF (3), F0..F4 (4)
    cmp al, 0xC2
    jb 90f
    cmp al, 0xDF
    jbe 20f
    cmp al, 0xEF
    jbe 30f
    cmp al, 0xF4
    jbe 40f
    jmp 90f
20: lea rcx, [rsi + 2]
    cmp rcx, rdx
    ja 90f
    mov cl, [rsi + 1]
    and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    add rsi, 2
    jmp 1b
30: lea rcx, [rsi + 3]
    cmp rcx, rdx
    ja 90f
    movzx ecx, byte ptr [rsi + 1]
    # E0 needs A0..BF, ED needs 80..9F (no surrogates), others 80..BF
    cmp al, 0xE0
    jne 31f
    cmp cl, 0xA0
    jb 90f
31: cmp al, 0xED
    jne 32f
    cmp cl, 0x9F
    ja 90f
32: and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    mov cl, [rsi + 2]
    and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    add rsi, 3
    jmp 1b
40: lea rcx, [rsi + 4]
    cmp rcx, rdx
    ja 90f
    movzx ecx, byte ptr [rsi + 1]
    cmp al, 0xF0
    jne 41f
    cmp cl, 0x90
    jb 90f
41: cmp al, 0xF4
    jne 42f
    cmp cl, 0x8F
    ja 90f
42: and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    mov cl, [rsi + 2]
    and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    mov cl, [rsi + 3]
    and cl, 0xC0
    cmp cl, 0x80
    jne 90f
    add rsi, 4
    jmp 1b
9:  leave
    ret
90: REFUSE "input is not valid UTF-8"
ENDF utf8_check

# text_is_blank() -> rax = 1 if text.trim() is empty (ASCII whitespace only).
FUNC text_is_blank
    mov rsi, [rip + g_text]
    mov rdx, rsi
    add rdx, [rip + g_text_len]
1:  cmp rsi, rdx
    jae 3f
    movzx eax, byte ptr [rsi]
    inc rsi
    cmp al, ' '
    je 1b
    cmp al, 9
    jb 2f
    cmp al, 13
    jbe 1b
2:  xor eax, eax
    leave
    ret
3:  mov eax, 1
    leave
    ret
ENDF text_is_blank

# char_at(idx) -> rax = byte, or -1 when out of range
FUNC char_at
    mov rax, -1
    test rdi, rdi
    js 1f
    cmp rdi, [rip + g_text_len]
    jae 1f
    mov rax, [rip + g_text]
    movzx eax, byte ptr [rax + rdi]
1:  leave
    ret
ENDF char_at

# skip_set(idx, backwards, set) -> rax. set: 1 = " \t", 2 = ",; \t",
# 3 = anything but \n and \r.
FUNC skip_set
    mov rax, rdi
    mov r8, IDX_FALSE
    cmp rax, r8
    je 9f
    mov r9, [rip + g_text]
    mov r10, [rip + g_text_len]
    mov r11, 1
    test esi, esi
    jz 1f
    mov r11, -1
1:  test rax, rax
    js 7f
    cmp rax, r10
    jge 7f
    movzx ecx, byte ptr [r9 + rax]
    cmp edx, 3
    je 4f
    cmp cl, ' '
    je 5f
    cmp cl, 9
    je 5f
    cmp edx, 2
    jne 9f
    cmp cl, ','
    je 5f
    cmp cl, ';'
    je 5f
    jmp 9f
4:  cmp cl, 10
    je 9f
    cmp cl, 13
    je 9f
5:  add rax, r11
    jmp 1b
7:  cmp rax, -1
    je 9f
    cmp rax, r10
    je 9f
    mov rax, r8
9:  leave
    ret
ENDF skip_set

# skip_spaces(idx, backwards)
FUNC skip_spaces
    mov edx, 1
    call skip_set
    leave
    ret
ENDF skip_spaces

# skip_newline(idx, backwards) -> rax
FUNC skip_newline
    mov rax, rdi
    mov r8, IDX_FALSE
    cmp rax, r8
    je 9f
    test rax, rax
    js 9f
    cmp rax, [rip + g_text_len]
    jge 9f
    mov rcx, [rip + g_text]
    movzx edx, byte ptr [rcx + rax]
    test esi, esi
    jnz 5f
    # forward
    cmp edx, 13
    jne 1f
    lea r8, [rax + 1]
    cmp r8, [rip + g_text_len]
    jge 2f
    cmp byte ptr [rcx + rax + 1], 10
    jne 2f
    add rax, 2
    jmp 9f
1:  cmp edx, 10
    jne 3f
2:  inc rax
    jmp 9f
3:  cmp edx, 0xE2
    jne 9f
    lea r8, [rax + 2]
    cmp r8, [rip + g_text_len]
    jge 9f
    cmp byte ptr [rcx + rax + 1], 0x80
    jne 9f
    movzx edx, byte ptr [rcx + rax + 2]
    and edx, 0xFE
    cmp edx, 0xA8
    jne 9f
    add rax, 3
    jmp 9f
    # backward: idx is a character's last byte
5:  cmp edx, 10
    jne 6f
    test rax, rax
    jz 7f
    cmp byte ptr [rcx + rax - 1], 13
    jne 7f
    sub rax, 2
    jmp 9f
6:  cmp edx, 13
    jne 8f
7:  dec rax
    jmp 9f
8:  and edx, 0xFE
    cmp edx, 0xA8
    jne 9f
    cmp rax, 2
    jl 9f
    cmp byte ptr [rcx + rax - 1], 0x80
    jne 9f
    cmp byte ptr [rcx + rax - 2], 0xE2
    jne 9f
    sub rax, 3
9:  leave
    ret
ENDF skip_newline

# has_newline(idx, backwards) -> rax = 0/1
FUNC has_newline
    push rbx
    push r12
    mov ebx, esi
    test esi, esi
    jz 1f
    dec rdi
1:  call skip_spaces            # rsi still holds backwards
    mov r12, rax
    mov rdi, rax
    mov esi, ebx
    call skip_newline
    cmp rax, r12
    setne al
    movzx eax, al
    pop r12
    pop rbx
    leave
    ret
ENDF has_newline

# has_newline_in_range(start, end) -> rax = 0/1
FUNC has_newline_in_range
    mov rcx, [rip + g_text]
    xor eax, eax
1:  cmp rdi, rsi
    jge 9f
    cmp byte ptr [rcx + rdi], 10
    je 2f
    inc rdi
    jmp 1b
2:  mov eax, 1
9:  leave
    ret
ENDF has_newline_in_range

# skip_inline_comment(idx) -> rax
FUNC skip_inline_comment
    mov rax, rdi
    mov r8, IDX_FALSE
    cmp rax, r8
    je 9f
    test rax, rax
    js 9f
    mov rcx, [rip + g_text]
    mov rdx, [rip + g_text_len]
    lea r9, [rax + 1]
    cmp r9, rdx
    jge 9f
    cmp byte ptr [rcx + rax], '/'
    jne 9f
    cmp byte ptr [rcx + rax + 1], '*'
    jne 9f
    lea r9, [rax + 2]
1:  lea r10, [r9 + 1]
    cmp r10, rdx
    jge 9f
    cmp byte ptr [rcx + r9], '*'
    jne 2f
    cmp byte ptr [rcx + r9 + 1], '/'
    jne 2f
    lea rax, [r9 + 2]
    jmp 9f
2:  inc r9
    jmp 1b
9:  leave
    ret
ENDF skip_inline_comment

# skip_trailing_comment(idx) -> rax
FUNC skip_trailing_comment
    mov rax, rdi
    mov r8, IDX_FALSE
    cmp rax, r8
    je 9f
    test rax, rax
    js 9f
    mov rcx, [rip + g_text]
    lea r9, [rax + 1]
    cmp r9, [rip + g_text_len]
    jge 9f
    cmp byte ptr [rcx + rax], '/'
    jne 9f
    cmp byte ptr [rcx + rax + 1], '/'
    jne 9f
    xor esi, esi
    mov edx, 3
    call skip_set
9:  leave
    ret
ENDF skip_trailing_comment

# is_next_line_empty(idx) -> rax = 0/1
FUNC is_next_line_empty
    push rbx
    push r12
    mov rbx, rdi
    mov r12, -12345                 # never equal to an index
1:  cmp rbx, r12
    je 2f
    mov r12, rbx
    mov rdi, rbx
    xor esi, esi
    mov edx, 2
    call skip_set
    mov rdi, rax
    call skip_inline_comment
    mov rdi, rax
    xor esi, esi
    call skip_spaces
    mov rbx, rax
    jmp 1b
2:  mov rdi, rbx
    call skip_trailing_comment
    mov rdi, rax
    xor esi, esi
    call skip_newline
    mov r8, IDX_FALSE
    cmp rax, r8
    je 3f
    mov rdi, rax
    xor esi, esi
    call has_newline
    jmp 4f
3:  xor eax, eax
4:  pop r12
    pop rbx
    leave
    ret
ENDF is_next_line_empty

# is_previous_line_empty(idx) -> rax = 0/1
FUNC is_previous_line_empty
    push rbx
    push r12
    lea rdi, [rdi - 1]
    mov esi, 1
    call skip_spaces
    mov rdi, rax
    mov esi, 1
    call skip_newline
    mov rdi, rax
    mov esi, 1
    call skip_spaces
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call skip_newline
    cmp rax, rbx
    setne al
    movzx eax, al
    pop r12
    pop rbx
    leave
    ret
ENDF is_previous_line_empty

# next_nonspace_noncomment_index(idx) -> rax (or IDX_FALSE)
FUNC next_nonspace_noncomment_index
    push rbx
    push r12
    mov rbx, rdi
    mov r12, -12345
1:  cmp rbx, r12
    je 2f
    mov r12, rbx
    mov rdi, rbx
    xor esi, esi
    call skip_spaces
    mov rdi, rax
    call skip_inline_comment
    mov rdi, rax
    call skip_trailing_comment
    mov rdi, rax
    xor esi, esi
    call skip_newline
    mov rbx, rax
    jmp 1b
2:  mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF next_nonspace_noncomment_index

# ---------------------------------------------------------------- code points
# is_js_space_cp(cp) -> eax: /\s/u, which is also what String#trim removes
FUNC is_js_space_cp
    xor eax, eax
    cmp edi, 0x20
    je 1f
    cmp edi, 9
    jb 9f
    cmp edi, 13
    jbe 1f
    cmp edi, 0xA0
    je 1f
    cmp edi, 0x1680
    je 1f
    cmp edi, 0x2000
    jb 9f
    cmp edi, 0x200A
    jbe 1f
    cmp edi, 0x2028
    je 1f
    cmp edi, 0x2029
    je 1f
    cmp edi, 0x202F
    je 1f
    cmp edi, 0x205F
    je 1f
    cmp edi, 0x3000
    je 1f
    cmp edi, 0xFEFF
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF is_js_space_cp

# cp_before(ptr, end) -> eax = code point ending at ptr[end - 1], rdx = its length
FUNC cp_before
    lea rsi, [rsi - 1]
1:  test rsi, rsi
    jz 2f
    movzx eax, byte ptr [rdi + rsi]
    and eax, 0xC0
    cmp eax, 0x80
    jne 2f
    dec rsi
    jmp 1b
2:  call utf8_decode
    leave
    ret
ENDF cp_before

# trim_start_bytes(ptr, start, end) -> rax = start after String#trimStart
FUNC trim_start_bytes
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  cmp r12, r13
    jae 9f
    mov rdi, rbx
    mov rsi, r12
    call utf8_decode
    mov [rsp], rdx
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jz 9f
    add r12, [rsp]
    jmp 1b
9:  mov rax, r12
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF trim_start_bytes

# trim_end_bytes(ptr, start, end) -> rax = end after String#trimEnd
FUNC trim_end_bytes
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
1:  cmp r13, r12
    jbe 9f
    mov rdi, rbx
    mov rsi, r13
    call cp_before
    mov [rsp], rdx
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jz 9f
    sub r13, [rsp]
    jmp 1b
9:  mov rax, r13
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF trim_end_bytes

# is_all_empty_no_newline(start, end) -> eax: !/[\S\n\u2028\u2029]/u.test(text.slice(start, end))
FUNC is_all_empty_no_newline
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
1:  cmp r12, r13
    jge 8f
    mov rdi, [rip + g_text]
    mov rsi, r12
    call utf8_decode
    add r12, rdx
    cmp eax, 10
    je 7f
    cmp eax, 0x2028
    je 7f
    cmp eax, 0x2029
    je 7f
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jnz 1b
7:  xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_all_empty_no_newline

# is_gap_text(start, end) -> eax: /^[\s(]*$/u.test(text.slice(start, end))
FUNC is_gap_text
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
1:  cmp r12, r13
    jge 8f
    mov rdi, [rip + g_text]
    mov rsi, r12
    call utf8_decode
    add r12, rdx
    cmp eax, '('
    je 1b
    mov edi, eax
    call is_js_space_cp
    test eax, eax
    jnz 1b
    xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_gap_text

# ---------------------------------------------------------------- more of src/utils
# skip_to_line_end(idx) -> rax: skip(",; \t")
FUNC skip_to_line_end
    xor esi, esi
    mov edx, 2
    call skip_set
    leave
    ret
ENDF skip_to_line_end

# skip_everything_but_newline(idx, backwards) -> rax: skip(/[^\n\r]/u)
FUNC skip_everything_but_newline
    mov edx, 3
    call skip_set
    leave
    ret
ENDF skip_everything_but_newline

# skip_whitespace(idx, backwards) -> rax: skip(/\s/u)
FUNC skip_whitespace
    push rbx
    push r12
    push r13
    push r14
    mov rax, rdi
    mov r8, IDX_FALSE
    cmp rax, r8
    je 9f
    mov rbx, rdi
    mov r12d, esi
1:  test rbx, rbx
    js 7f
    cmp rbx, [rip + g_text_len]
    jge 7f
    mov rdi, [rip + g_text]
    test r12d, r12d
    jnz 2f
    mov rsi, rbx
    call utf8_decode
    mov r13, rdx
    jmp 3f
2:  lea rsi, [rbx + 1]
    call cp_before
    mov r13, rdx
    neg r13
3:  mov edi, eax
    call is_js_space_cp
    test eax, eax
    jz 8f
    add rbx, r13
    jmp 1b
7:  mov rax, rbx
    cmp rbx, -1
    je 9f
    cmp rbx, [rip + g_text_len]
    je 9f
    mov rax, IDX_FALSE
    jmp 9f
8:  mov rax, rbx
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF skip_whitespace

# has_spaces(idx, backwards) -> rax = 0/1 (hasSpaces)
FUNC has_spaces
    push rbx
    sub rsp, 8
    mov rbx, rdi
    test esi, esi
    jz 1f
    dec rdi
1:  call skip_spaces
    cmp rax, rbx
    setne al
    movzx eax, al
    add rsp, 8
    pop rbx
    leave
    ret
ENDF has_spaces

# next_nonspace_noncomment_char(idx) -> rax: the code point at
# getNextNonSpaceNonCommentCharacterIndex, or -1 for "" (false or the end)
FUNC next_nonspace_noncomment_char
    call next_nonspace_noncomment_index
    mov r8, IDX_FALSE
    cmp rax, r8
    je 8f
    test rax, rax
    js 8f
    cmp rax, [rip + g_text_len]
    jge 8f
    mov rdi, [rip + g_text]
    mov rsi, rax
    call utf8_decode
    leave
    ret
8:  mov rax, -1
    leave
    ret
ENDF next_nonspace_noncomment_char

# get_alignment_size(ptr, len, tab_width, start) -> rax (getAlignmentSize):
# a tab moves to the next multiple of tabWidth; other UTF-16 units count 1.
FUNC get_alignment_size
    xor eax, eax
    mov r8, rdx
1:  cmp rcx, rsi
    jae 9f
    movzx r9d, byte ptr [rdi + rcx]
    inc rcx
    cmp r9d, 9
    jne 2f
    xor edx, edx
    push rax
    div r8
    pop rax
    sub rax, rdx
    add rax, r8
    jmp 1b
2:  mov r10d, r9d
    and r10d, 0xC0
    cmp r10d, 0x80
    je 1b
    inc rax
    cmp r9d, 0xF0
    jb 1b
    inc rax
    jmp 1b
9:  leave
    ret
ENDF get_alignment_size

# get_indent_size(ptr, len, tab_width) -> rax (getIndentSize): the alignment
# of the leading tabs and spaces of the text after the last "\n"; 0 without one.
FUNC get_indent_size
    mov rcx, rsi
1:  test rcx, rcx
    jz 8f
    cmp byte ptr [rdi + rcx - 1], 10
    je 2f
    dec rcx
    jmp 1b
2:  mov r8, rcx                     # start of the last line
3:  cmp rcx, rsi
    jae 4f
    movzx eax, byte ptr [rdi + rcx]
    cmp al, ' '
    je 31f
    cmp al, 9
    jne 4f
31: inc rcx
    jmp 3b
4:  mov rsi, rcx
    mov rcx, r8
    call get_alignment_size
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF get_indent_size

# continuous_counts(text, len, search, slen, out_map) -> rax = largest count
# of back-to-back occurrences of search, matched left to right as
# /(search)+/g does; each count found is marked in out_map (a byte per count,
# up to 255; larger counts are not marked).
FUNC continuous_counts
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    xor r15d, r15d                  # max
    xor ecx, ecx                    # position
    test r14, r14
    jz 9f
1:  mov rax, r12
    sub rax, rcx
    cmp rax, r14
    jb 9f
    # count the occurrences back to back from rcx
    xor r9d, r9d
2:  mov rax, r12
    sub rax, rcx
    cmp rax, r14
    jb 3f
    push rcx
    push r9
    lea rdi, [rbx + rcx]
    mov rsi, r13
    mov rdx, r14
    call mem_eq
    pop r9
    pop rcx
    test eax, eax
    jz 3f
    inc r9
    add rcx, r14
    jmp 2b
3:  test r9, r9
    jnz 4f
    inc rcx
    jmp 1b
4:  cmp r9, r15
    jbe 5f
    mov r15, r9
5:  mov r8, [rsp]
    test r8, r8
    jz 1b
    cmp r9, 255
    ja 1b
    mov byte ptr [r8 + r9], 1
    jmp 1b
9:  mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF continuous_counts

# get_max_continuous_count(text, len, search, slen) -> rax
FUNC get_max_continuous_count
    xor r8d, r8d
    call continuous_counts
    leave
    ret
ENDF get_max_continuous_count

# get_min_not_present_continuous_count(text, len, search, slen) -> rax
FUNC get_min_not_present_continuous_count
    push rbx
    sub rsp, 264
    push rdi
    push rsi
    push rdx
    push rcx
    lea rdi, [rsp + 32]
    mov ecx, 256
    xor eax, eax
    rep stosb
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    mov r8, rsp
    call continuous_counts
    mov rbx, rax                    # max
    test rbx, rbx
    jz 9f
    mov ecx, 1
1:  cmp rcx, rbx
    jae 8f
    cmp rcx, 255
    ja 90f
    cmp byte ptr [rsp + rcx], 0
    je 7f
    inc rcx
    jmp 1b
7:  mov rax, rcx
    jmp 9f
8:  lea rax, [rbx + 1]
9:  add rsp, 264
    pop rbx
    leave
    ret
90: REFUSE "more than 255 back-to-back occurrences"
ENDF get_min_not_present_continuous_count
