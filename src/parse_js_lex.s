# JS tokenizer for parse_js*.s, after Babel's tokenizer (packages/babel-parser/src/tokenizer).
# One token at a time into the g_jt_* record. The parser decides when `/` starts a regular
# expression (jl_regex) and when `}` continues a template (jl_template_continue).
# Identifiers and code outside strings, templates, regular expressions and comments must be
# ASCII; anything else is refused.
.include "defs.inc"
.include "parse_js.inc"

.equ CC_SPACE, 1
.equ CC_LF, 2
.equ CC_IDENT, 3
.equ CC_DIGIT, 4
.equ CC_QUOTE, 5
.equ CC_PUNCT, 6

.equ JF_TAIL, 1             # template chunk ended with a backtick

    .bss
    .balign 8
# The token record. jl_save copies JT_SIZE bytes from g_jt_pos; keep the order.
    .globl g_jt_pos, g_jt_type, g_jt_start, g_jt_end, g_jt_val, g_jt_len, g_jt_kw, g_jt_nl
    .globl g_jt_last_end, g_jt_raw_start, g_jt_raw_end, g_jt_flags, g_js_script
g_jt_pos:       .quad 0     # scan position
g_jt_type:      .quad 0     # J_*
g_jt_start:     .quad 0
g_jt_end:       .quad 0
g_jt_val:       .quad 0     # string, template: cooked ptr (0: invalid escape); bigint: value ptr
g_jt_len:       .quad 0     # its byte length
g_jt_kw:        .quad 0     # J_NAME: KW_* or 0
g_jt_nl:        .quad 0     # 1 if a line terminator comes between the previous token and this one
g_jt_last_end:  .quad 0     # end of the previous token
g_jt_raw_start: .quad 0     # template: raw range of the chunk; regex: flags start
g_jt_raw_end:   .quad 0
g_jt_flags:     .quad 0     # JF_*
g_jt_ncomments: .quad 0     # comment count, saved so a lookahead can drop the comments it read
.equ JT_SIZE, 13 * 8
g_js_script:    .quad 0     # 1 for sourceType script: HTML comments are refused

    .text

# jl_init(): starts lexing g_text; reads an interpreter directive and the first token.
FUNC jl_init
    mov qword ptr [rip + g_jt_pos], 0
    mov qword ptr [rip + g_jt_end], 0
    mov qword ptr [rip + g_comments], 0
    mov rsi, [rip + g_text]
    cmp qword ptr [rip + g_text_len], 2
    jb 3f
    cmp word ptr [rsi], 0x2123          # "#!"
    jne 3f
    xor ecx, ecx
1:  cmp rcx, [rip + g_text_len]
    jae 2f
    cmp byte ptr [rsi + rcx], 10
    je 2f
    cmp byte ptr [rsi + rcx], 0xE2
    jne 11f
    lea rdx, [rcx + 2]
    cmp rdx, [rip + g_text_len]
    jae 11f
    cmp byte ptr [rsi + rcx + 1], 0x80
    jne 11f
    mov dl, [rsi + rcx + 2]
    cmp dl, 0xA8
    je 2f
    cmp dl, 0xA9
    je 2f
11: inc rcx
    jmp 1b
2:  mov [rip + g_jt_pos], rcx
    mov [rip + g_jt_end], rcx
    mov edi, CT_INTERPRETER
    xor esi, esi
    mov rdx, rcx
    call add_comment
3:  call jl_next
    leave
    ret
ENDF jl_init

# jl_save(buf) / jl_restore(buf): the token record, for lookahead. Comments read after
# jl_save are dropped by jl_restore.
FUNC jl_save
    mov rax, [rip + g_comments]
    xor ecx, ecx
    test rax, rax
    jz 1f
    mov ecx, [rax]
1:  mov [rip + g_jt_ncomments], rcx
    lea rsi, [rip + g_jt_pos]
    mov ecx, JT_SIZE / 8
    rep movsq
    leave
    ret
ENDF jl_save

FUNC jl_restore
    mov rsi, rdi
    lea rdi, [rip + g_jt_pos]
    mov ecx, JT_SIZE / 8
    rep movsq
    mov rax, [rip + g_comments]
    test rax, rax
    jz 1f
    mov ecx, [rip + g_jt_ncomments]
    mov [rax], ecx
1:  leave
    ret
ENDF jl_restore

# jl_peek() -> eax = type of the token after the current one, edx = its KW_*, ecx = 1 if a
# line terminator comes before it, r8 = its start, r9 = its end. Nothing changes.
FUNC jl_peek
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, JT_SIZE + 8
    mov rdi, rsp
    call jl_save
    call jl_next
    mov rbx, [rip + g_jt_type]
    mov r12, [rip + g_jt_kw]
    mov r13, [rip + g_jt_nl]
    mov r14, [rip + g_jt_start]
    mov r15, [rip + g_jt_end]
    mov rdi, rsp
    call jl_restore
    mov eax, ebx
    mov edx, r12d
    mov ecx, r13d
    mov r8, r14
    mov r9, r15
    add rsp, JT_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jl_peek

# jl_next_char(pos) -> eax = the byte at the first position from pos that is not
# whitespace or inside a comment (-1 at the end), rdx = that position, ecx = 1 if a line
# terminator was skipped. Records nothing.
FUNC jl_next_char
    mov rsi, [rip + g_text]
    mov r8, [rip + g_text_len]
    xor ecx, ecx
1:  cmp rdi, r8
    jae 8f
    movzx eax, byte ptr [rsi + rdi]
    cmp al, 10
    je 2f
    cmp al, ' '
    je 3f
    cmp al, 9
    je 3f
    cmp al, 11
    je 3f
    cmp al, 12
    je 3f
    cmp al, 0x80
    jae 10f
    cmp al, '/'
    jne 9f
    lea rdx, [rdi + 1]
    cmp rdx, r8
    jae 9f
    movzx edx, byte ptr [rsi + rdi + 1]
    cmp dl, '/'
    je 4f
    cmp dl, '*'
    je 6f
    jmp 9f
2:  mov ecx, 1
3:  inc rdi
    jmp 1b
4:  add rdi, 2                          # line comment: up to the line feed
5:  cmp rdi, r8
    jae 8f
    cmp byte ptr [rsi + rdi], 10
    je 1b
    inc rdi
    jmp 5b
6:  add rdi, 2                          # block comment
7:  lea rdx, [rdi + 1]
    cmp rdx, r8
    jae 8f
    movzx eax, byte ptr [rsi + rdi]
    cmp al, 10
    jne 71f
    mov ecx, 1
71: cmp al, '*'
    jne 72f
    cmp byte ptr [rsi + rdi + 1], '/'
    jne 72f
    add rdi, 2
    jmp 1b
72: inc rdi
    jmp 7b
8:  mov eax, -1
9:  mov rdx, rdi
    leave
    ret
10: push rdi
    push rcx
    call jl_unicode_space
    mov r9d, edx
    pop rcx
    pop rdi
    mov rsi, [rip + g_text]
    mov r8, [rip + g_text_len]
    test eax, eax
    jz 11f
    add rdi, rax
    or ecx, r9d
    jmp 1b
11: movzx eax, byte ptr [rsi + rdi]
    jmp 9b
ENDF jl_next_char

# jl_is_line_sep(pos) -> eax = 1 if U+2028 or U+2029 starts at pos
FUNC jl_is_line_sep
    xor eax, eax
    mov rsi, [rip + g_text]
    lea rdx, [rdi + 2]
    cmp rdx, [rip + g_text_len]
    jae 9f
    cmp byte ptr [rsi + rdi], 0xE2
    jne 9f
    cmp byte ptr [rsi + rdi + 1], 0x80
    jne 9f
    mov dl, [rsi + rdi + 2]
    cmp dl, 0xA8
    je 1f
    cmp dl, 0xA9
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF jl_is_line_sep

# jl_unicode_space(pos) -> eax = byte length of a non-ASCII JS whitespace or line terminator
# code point at pos (0 if none), edx = 1 for U+2028 and U+2029.
FUNC jl_unicode_space
    mov rsi, [rip + g_text]
    add rsi, rdi
    mov rcx, [rip + g_text_len]
    sub rcx, rdi
    xor eax, eax
    xor edx, edx
    movzx r8d, byte ptr [rsi]
    cmp r8d, 0xC2
    jne 1f
    cmp rcx, 2
    jb 9f
    cmp byte ptr [rsi + 1], 0xA0          # U+00A0
    jne 9f
    mov eax, 2
    jmp 9f
1:  cmp rcx, 3
    jb 9f
    movzx r9d, byte ptr [rsi + 1]
    movzx r10d, byte ptr [rsi + 2]
    cmp r8d, 0xE1
    jne 2f
    cmp r9d, 0x9A                       # U+1680
    jne 9f
    cmp r10d, 0x80
    je 8f
    jmp 9f
2:  cmp r8d, 0xE2
    jne 4f
    cmp r9d, 0x80
    jne 3f
    cmp r10d, 0x8A                      # U+2000..U+200A
    jbe 8f
    cmp r10d, 0xAF                      # U+202F
    je 8f
    cmp r10d, 0xA8                      # U+2028, U+2029
    je 7f
    cmp r10d, 0xA9
    je 7f
    jmp 9f
3:  cmp r9d, 0x81                       # U+205F
    jne 9f
    cmp r10d, 0x9F
    je 8f
    jmp 9f
4:  cmp r8d, 0xE3
    jne 5f
    cmp r9d, 0x80                       # U+3000
    jne 9f
    cmp r10d, 0x80
    je 8f
    jmp 9f
5:  cmp r8d, 0xEF                       # U+FEFF
    jne 9f
    cmp r9d, 0xBB
    jne 9f
    cmp r10d, 0xBF
    jne 9f
    jmp 8f
7:  mov edx, 1
8:  mov eax, 3
9:  leave
    ret
ENDF jl_unicode_space

# jl_next(): reads the next token.
FUNC jl_next
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rax, [rip + g_jt_end]
    mov [rip + g_jt_last_end], rax
    mov qword ptr [rip + g_jt_nl], 0
    mov qword ptr [rip + g_jt_kw], 0
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    mov rbx, [rip + g_jt_pos]
    lea r15, [rip + js_char_class]
    # whitespace and comments
1:  cmp rbx, r13
    jae 50f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 0x80
    jae 11f
    movzx ecx, byte ptr [r15 + rax]
    cmp ecx, CC_SPACE
    je 2f
    cmp ecx, CC_LF
    je 3f
    cmp al, '/'
    jne 10f
    lea rdx, [rbx + 1]
    cmp rdx, r13
    jae 10f
    movzx edx, byte ptr [r12 + rbx + 1]
    cmp dl, '/'
    je 4f
    cmp dl, '*'
    je 6f
    jmp 10f
2:  inc rbx
    jmp 1b
3:  mov qword ptr [rip + g_jt_nl], 1
    inc rbx
    jmp 1b
    # non-ASCII whitespace and line terminators
11: mov rdi, rbx
    call jl_unicode_space
    test eax, eax
    jz 92f
    add rbx, rax
    test edx, edx
    jz 1b
    mov qword ptr [rip + g_jt_nl], 1
    jmp 1b
    # line comment: ends before a line terminator
4:  mov r14, rbx
    add rbx, 2
5:  cmp rbx, r13
    jae 41f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 10
    je 41f
    cmp al, 0xE2
    jne 43f
    mov rdi, rbx
    call jl_is_line_sep
    test eax, eax
    jnz 41f
43: inc rbx
    jmp 5b
41: mov edi, CT_LINE
    mov rsi, r14
    mov rdx, rbx
    call add_comment
    jmp 1b
    # block comment
6:  mov r14, rbx
    add rbx, 2
7:  lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 90f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '*'
    jne 8f
    cmp byte ptr [r12 + rbx + 1], '/'
    jne 8f
    add rbx, 2
    mov edi, CT_BLOCK
    mov rsi, r14
    mov rdx, rbx
    call add_comment
    jmp 1b
8:  cmp al, 10
    jne 81f
    mov qword ptr [rip + g_jt_nl], 1
81: cmp al, 0xE2
    jne 82f
    mov rdi, rbx
    call jl_is_line_sep
    test eax, eax
    jz 82f
    mov qword ptr [rip + g_jt_nl], 1
82: inc rbx
    jmp 7b

    # a token starts at rbx; al = its first byte, ecx = its class
10: mov [rip + g_jt_start], rbx
    cmp ecx, CC_IDENT
    je 20f
    cmp ecx, CC_PUNCT
    je 30f
    cmp ecx, CC_DIGIT
    je 24f
    cmp ecx, CC_QUOTE
    je 21f
    cmp al, '\\'
    je 91f
    jmp 93f

    # identifier or keyword
20: mov r14, rbx
    inc rbx
11: cmp rbx, r13
    jae 13f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 0x80
    jae 92f
    movzx ecx, byte ptr [r15 + rax]
    cmp ecx, CC_IDENT
    je 12f
    cmp ecx, CC_DIGIT
    jne 14f
12: inc rbx
    jmp 11b
14: cmp al, '\\'
    je 91f
13: mov qword ptr [rip + g_jt_type], J_NAME
    movzx eax, byte ptr [r12 + r14]
    sub eax, 'a'
    cmp eax, 25
    ja 60f
    lea rcx, [rip + kw_buckets]
    mov rsi, [rcx + rax*8]
    mov rdx, rbx
    sub rdx, r14                        # length
15: movzx ecx, byte ptr [rsi]
    test ecx, ecx
    jz 60f
    cmp rcx, rdx
    jne 17f
    xor r8d, r8d
    lea r9, [r12 + r14]
16: mov al, [rsi + 2 + r8]
    cmp al, [r9 + r8]
    jne 17f
    inc r8
    cmp r8, rdx
    jb 16b
    movzx eax, byte ptr [rsi + 1]
    mov [rip + g_jt_kw], rax
    jmp 60f
17: lea rsi, [rsi + rcx + 2]
    jmp 15b

    # string
21: mov rdi, rbx
    call lex_string
    mov rbx, rax
    mov rax, [rip + g_tok_val]
    mov [rip + g_jt_val], rax
    mov rax, [rip + g_tok_len]
    mov [rip + g_jt_len], rax
    mov qword ptr [rip + g_jt_type], J_STRING
    jmp 60f

    # number
24: mov rdi, rbx
    call jl_number
    mov rbx, rax
    jmp 60f

    # punctuators
30: lea rcx, [rbx + 1]
    xor edx, edx                        # next byte, 0 at the end
    cmp rcx, r13
    jae 31f
    movzx edx, byte ptr [r12 + rbx + 1]
31: xor r8d, r8d                        # byte after that
    lea rcx, [rbx + 2]
    cmp rcx, r13
    jae 32f
    movzx r8d, byte ptr [r12 + rbx + 2]
32: mov qword ptr [rip + g_jt_type], rax  # single character by default
    cmp al, '.'
    je 33f
    cmp al, '='
    je 34f
    cmp al, '`'
    je 35f
    cmp al, '?'
    je 36f
    cmp al, '<'
    je 37f
    cmp al, '>'
    je 38f
    cmp al, '!'
    je 39f
    cmp al, '+'
    je 40f
    cmp al, '-'
    je 42f
    cmp al, '*'
    je 44f
    cmp al, '&'
    je 45f
    cmp al, '|'
    je 46f
    cmp al, '/'
    je 47f
    cmp al, '%'
    je 47f
    cmp al, '^'
    je 47f
    cmp al, '#'
    je 48f
    cmp al, ':'
    je 49f
    jmp 70f                             # ( ) [ ] { } ; , @ ~
33: cmp dl, '.'
    jne 331f
    cmp r8b, '.'
    jne 93f
    mov qword ptr [rip + g_jt_type], J_ELLIPSIS
    add rbx, 3
    jmp 60f
331: cmp dl, '0'
    jb 70f
    cmp dl, '9'
    ja 70f
    jmp 24b
34: cmp dl, '>'
    je 341f
    cmp dl, '='
    jne 70f
    mov ecx, J_EQ2
    mov esi, J_EQ3
    jmp 80f
341: mov qword ptr [rip + g_jt_type], J_ARROW
    add rbx, 2
    jmp 60f
35: mov rdi, rbx
    call jl_template
    mov rbx, rax
    jmp 60f
36: cmp dl, '?'
    je 361f
    cmp dl, '.'
    jne 70f
    cmp r8b, '0'                        # `a?.5:b` is a conditional
    jb 362f
    cmp r8b, '9'
    jbe 70f
362: mov qword ptr [rip + g_jt_type], J_QDOT
    add rbx, 2
    jmp 60f
361: mov ecx, J_NULLISH
    mov esi, J_NULLISH_EQ
    jmp 81f
37: test qword ptr [rip + g_ts], TS_IN_TYPE
    jnz 70f
    cmp dl, '<'
    je 371f
    cmp dl, '='
    jne 372f
    mov qword ptr [rip + g_jt_type], J_LE
    add rbx, 2
    jmp 60f
372: cmp qword ptr [rip + g_js_script], 0
    je 70f
    cmp dl, '!'
    jne 70f
    cmp r8b, '-'
    je 94f
    jmp 70f
371: mov ecx, J_SHL
    mov esi, J_SHL_EQ
    jmp 81f
38: test qword ptr [rip + g_ts], TS_IN_TYPE
    jnz 70f
    cmp dl, '='
    jne 381f
    mov qword ptr [rip + g_jt_type], J_GE
    add rbx, 2
    jmp 60f
381: cmp dl, '>'
    jne 70f
    cmp r8b, '>'
    je 382f
    mov ecx, J_SHR
    mov esi, J_SHR_EQ
    jmp 81f
382: inc rbx
    mov ecx, J_USHR
    mov esi, J_USHR_EQ
    jmp 81f
39: cmp dl, '='
    jne 70f
    mov ecx, J_NE
    mov esi, J_NE2
    jmp 80f
40: cmp dl, '+'
    jne 401f
    mov qword ptr [rip + g_jt_type], J_INC
    add rbx, 2
    jmp 60f
401: cmp dl, '='
    jne 70f
    mov qword ptr [rip + g_jt_type], J_ADD_EQ
    add rbx, 2
    jmp 60f
42: cmp dl, '-'
    jne 421f
    cmp qword ptr [rip + g_js_script], 0
    je 422f
    cmp r8b, '>'
    jne 422f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 94f
422: mov qword ptr [rip + g_jt_type], J_DEC
    add rbx, 2
    jmp 60f
421: cmp dl, '='
    jne 70f
    mov qword ptr [rip + g_jt_type], J_SUB_EQ
    add rbx, 2
    jmp 60f
44: cmp dl, '*'
    je 441f
    cmp dl, '='
    jne 70f
    mov qword ptr [rip + g_jt_type], J_MUL_EQ
    add rbx, 2
    jmp 60f
441: mov ecx, J_EXP
    mov esi, J_EXP_EQ
    jmp 81f
45: cmp dl, '&'
    je 451f
    cmp dl, '='
    jne 70f
    mov qword ptr [rip + g_jt_type], J_AND_EQ
    add rbx, 2
    jmp 60f
451: mov ecx, J_AND2
    mov esi, J_AND2_EQ
    jmp 81f
46: cmp dl, '|'
    je 461f
    cmp dl, '>'
    je 95f
    cmp dl, '}'
    je 93f
    cmp dl, ']'
    je 93f
    cmp dl, '='
    jne 70f
    mov qword ptr [rip + g_jt_type], J_OR_EQ
    add rbx, 2
    jmp 60f
461: mov ecx, J_OR2
    mov esi, J_OR2_EQ
    jmp 81f
47: cmp dl, '='                         # / % ^ with =
    jne 70f
    mov ecx, J_DIV_EQ
    cmp al, '/'
    je 471f
    mov ecx, J_MOD_EQ
    cmp al, '%'
    je 471f
    mov ecx, J_XOR_EQ
471: mov [rip + g_jt_type], rcx
    add rbx, 2
    jmp 60f
48: mov ecx, edx                        # #name
    cmp ecx, 0x80
    jae 93f
    movzx ecx, byte ptr [r15 + rcx]
    cmp ecx, CC_IDENT
    jne 93f
    inc rbx
    mov r14, rbx
    inc rbx
481: cmp rbx, r13
    jae 482f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 0x80
    jae 92f
    movzx ecx, byte ptr [r15 + rax]
    cmp ecx, CC_IDENT
    je 483f
    cmp ecx, CC_DIGIT
    jne 484f
483: inc rbx
    jmp 481b
484: cmp al, '\\'
    je 91f
482: mov qword ptr [rip + g_jt_type], J_PRIVATE
    jmp 60f
49: cmp dl, ':'
    je 96f
    jmp 70f

    # two or three character operators: ecx = op, esi = op followed by `=`
80: inc rbx                             # ==, != : maybe ===, !==
    cmp r8b, '='
    jne 801f
    inc rbx
    mov ecx, esi
801: inc rbx
    mov [rip + g_jt_type], rcx
    jmp 60f
81: add rbx, 2                          # ?? << >> >>> ** && || : maybe followed by =
    cmp rbx, r13
    jae 811f
    cmp byte ptr [r12 + rbx], '='
    jne 811f
    inc rbx
    mov ecx, esi
811: mov [rip + g_jt_type], rcx
    jmp 60f

70: inc rbx
    jmp 60f

50: mov qword ptr [rip + g_jt_type], J_EOF
    mov [rip + g_jt_start], rbx
60: mov [rip + g_jt_end], rbx
    mov [rip + g_jt_pos], rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unterminated comment"
91: REFUSE "escape in identifier"
92: REFUSE "non-ASCII character outside strings, templates and comments"
93: REFUSE "syntax error: unexpected character"
94: REFUSE "HTML comment"
95: REFUSE "pipeline operator"
96: REFUSE "bind operator"
ENDF jl_next

# jl_rescan(): reads the current token again from its start, in the current mode (Babel's
# reScan_lt_gt after a type: a `>` read as a type token may be `>=` or `>>`).
FUNC jl_rescan
    push rbx
    push r12
    mov rbx, [rip + g_jt_last_end]
    mov r12, [rip + g_jt_nl]
    mov rax, [rip + g_jt_start]
    mov [rip + g_jt_pos], rax
    mov [rip + g_jt_end], rbx
    call jl_next
    mov [rip + g_jt_last_end], rbx
    mov [rip + g_jt_nl], r12
    pop r12
    pop rbx
    leave
    ret
ENDF jl_rescan

# jl_rescan_lt_gt(): Babel's reScan_lt_gt: a `<` or `>` token is read again outside type mode
FUNC jl_rescan_lt_gt
    TT_IS J_LT
    je 1f
    TT_IS J_GT
    jne 9f
1:  mov rax, [rip + g_ts]
    push rax
    sub rsp, 8
    and qword ptr [rip + g_ts], ~TS_IN_TYPE
    call jl_rescan
    add rsp, 8
    pop qword ptr [rip + g_ts]
9:  leave
    ret
ENDF jl_rescan_lt_gt

# jl_rescan_lt() -> eax: Babel's reScan_lt: `<<` becomes `<` (its first character); returns the
# token type.
FUNC jl_rescan_lt
    TT_IS J_SHL
    jne 9f
    mov qword ptr [rip + g_jt_type], J_LT
    mov rax, [rip + g_jt_start]
    inc rax
    mov [rip + g_jt_end], rax
    mov [rip + g_jt_pos], rax
9:  mov rax, [rip + g_jt_type]
    leave
    ret
ENDF jl_rescan_lt

# jl_number(pos) -> rax = end; sets the token type (J_NUM or J_BIGINT) and a BigInt's value.
# Babel's readNumber and readRadixNumber. Refuses what Babel reports, and numbers with a
# leading zero and a separator (Babel accepts some of those in strict mode).
FUNC jl_number
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r14, rdi                        # start
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    xor r15d, r15d                      # bit 0 float, bit 1 leading zero, bit 2 legacy octal
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '.'
    je 20f
    cmp al, '0'
    jne 10f
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 10f
    movzx ecx, byte ptr [r12 + rbx + 1]
    or cl, 0x20
    mov esi, 16
    cmp cl, 'x'
    je 40f
    mov esi, 8
    cmp cl, 'o'
    je 40f
    mov esi, 2
    cmp cl, 'b'
    je 40f
    # decimal integer part
10: mov rdi, rbx
    mov esi, 10
    call jl_scan_digits
    test rdx, rdx
    jz 90f
    mov rcx, rax
    sub rcx, rbx
    cmp rcx, 2
    jb 12f
    cmp byte ptr [r12 + rbx], '0'
    jne 12f
    or r15d, 2                          # leading zero
    or r15d, 4
    mov rdi, rbx
11: cmp rdi, rax
    jae 12f
    movzx ecx, byte ptr [r12 + rdi]
    cmp cl, '_'
    je 90f
    cmp cl, '8'
    jb 111f
    and r15d, ~4                        # an 8 or 9: decimal with a leading zero
111: inc rdi
    jmp 11b
12: mov rbx, rax
    cmp rbx, r13
    jae 30f
    test r15d, 4
    jnz 25f
    cmp byte ptr [r12 + rbx], '.'
    jne 25f
20: inc rbx                             # fraction
    or r15d, 1
    cmp rbx, r13
    jae 30f
    cmp byte ptr [r12 + rbx], '_'
    je 90f
    mov rdi, rbx
    mov esi, 10
    call jl_scan_digits
    mov rbx, rax
25: cmp rbx, r13                        # exponent
    jae 30f
    test r15d, 4
    jnz 28f
    movzx eax, byte ptr [r12 + rbx]
    or al, 0x20
    cmp al, 'e'
    jne 28f
    inc rbx
    or r15d, 1
    cmp rbx, r13
    jae 90f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '+'
    je 26f
    cmp al, '-'
    jne 27f
26: inc rbx
27: cmp rbx, r13
    jae 90f
    cmp byte ptr [r12 + rbx], '_'
    je 90f
    mov rdi, rbx
    mov esi, 10
    call jl_scan_digits
    test rdx, rdx
    jz 90f
    mov rbx, rax
28: cmp rbx, r13                        # BigInt suffix
    jae 30f
    cmp byte ptr [r12 + rbx], 'n'
    jne 30f
    test r15d, 3
    jnz 90f
    inc rbx
    jmp 50f
30: mov qword ptr [rip + g_jt_type], J_NUM
    jmp 60f
    # 0x 0o 0b
40: lea rdi, [rbx + 2]
    cmp rdi, r13
    jae 90f
    cmp byte ptr [r12 + rdi], '_'
    je 90f
    call jl_scan_digits
    test rdx, rdx
    jz 90f
    mov rbx, rax
    cmp rbx, r13
    jae 30b
    cmp byte ptr [r12 + rbx], 'n'
    jne 30b
    inc rbx
    # BigInt: the value is the text without separators and the n
50: mov qword ptr [rip + g_jt_type], J_BIGINT
    mov rdi, rbx
    sub rdi, r14
    call alloc
    mov [rip + g_jt_val], rax
    mov rdi, rax
    mov rsi, r14
51: cmp rsi, rbx
    jae 53f
    mov al, [r12 + rsi]
    inc rsi
    cmp al, '_'
    je 51b
    cmp al, 'n'
    je 51b
    mov [rdi], al
    inc rdi
    jmp 51b
53: sub rdi, [rip + g_jt_val]
    mov [rip + g_jt_len], rdi
    # nothing identifier-like may follow
60: cmp rbx, r13
    jae 69f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '\\'
    je 90f
    cmp al, 0x80
    jae 90f
    lea rcx, [rip + js_char_class]
    movzx ecx, byte ptr [rcx + rax]
    cmp ecx, CC_IDENT
    je 90f
    cmp ecx, CC_DIGIT
    je 90f
69: mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: invalid number"
ENDF jl_number

# jl_scan_digits(pos, radix) -> rax = end, rdx = digit count. A separator must sit between
# two digits; anything else about separators is refused.
FUNC jl_scan_digits
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    xor r13d, r13d
    mov r14, [rip + g_text]
1:  cmp rbx, [rip + g_text_len]
    jae 9f
    movzx edi, byte ptr [r14 + rbx]
    cmp dil, '_'
    je 2f
    mov esi, r12d
    call digit_ok
    test eax, eax
    jz 9f
    inc r13
    inc rbx
    jmp 1b
2:  test r13, r13
    jz 90f
    cmp byte ptr [r14 + rbx - 1], '_'
    je 90f
    lea rcx, [rbx + 1]
    cmp rcx, [rip + g_text_len]
    jae 90f
    movzx edi, byte ptr [r14 + rbx + 1]
    mov esi, r12d
    call digit_ok
    test eax, eax
    jz 90f
    inc rbx
    jmp 1b
9:  mov rax, rbx
    mov rdx, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: numeric separator"
ENDF jl_scan_digits

# jl_template(pos at the backtick) -> rax = end of the chunk
FUNC jl_template
    inc rdi
    call jl_template_chunk
    leave
    ret
ENDF jl_template

# jl_template_continue(): the current token is the `}` that closes a substitution; reads the
# template chunk after it.
FUNC jl_template_continue
    mov rdi, [rip + g_jt_start]
    inc rdi
    call jl_template_chunk
    mov [rip + g_jt_end], rax
    mov [rip + g_jt_pos], rax
    leave
    ret
ENDF jl_template_continue

# jl_template_chunk(pos after ` or }) -> rax = position after the closing ` or ${.
# Sets J_TEMPLATE with the raw range, JF_TAIL, and the cooked value (0 when an escape is
# invalid, which Babel reports as a recoverable error and Prettier allows).
FUNC jl_template_chunk
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r14, rdi                        # raw start
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    mov qword ptr [rip + g_jt_type], J_TEMPLATE
    mov [rip + g_jt_raw_start], rbx
    mov qword ptr [rip + g_jt_flags], 0
    # raw scan
1:  cmp rbx, r13
    jae 90f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '`'
    je 3f
    cmp al, '\\'
    je 2f
    cmp al, '$'
    jne 11f
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 11f
    cmp byte ptr [r12 + rbx + 1], '{'
    je 4f
11: inc rbx
    jmp 1b
2:  add rbx, 2
    jmp 1b
3:  mov qword ptr [rip + g_jt_flags], JF_TAIL
    mov [rip + g_jt_raw_end], rbx
    lea r15, [rbx + 1]
    jmp 5f
4:  mov [rip + g_jt_raw_end], rbx
    lea r15, [rbx + 2]
    # cook r14..raw_end
5:  mov rbx, r14
    mov r13, [rip + g_jt_raw_end]
    mov rax, [rip + g_arena_ptr]
    mov [rip + g_jt_val], rax
    mov r14, rax                        # write cursor
    mov qword ptr [rip + g_hi_surrogate_at], 0
6:  cmp rbx, r13
    jae 8f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '\\'
    je 7f
    mov [r14], al
    inc r14
    inc rbx
    mov qword ptr [rip + g_hi_surrogate_at], 0
    jmp 6b
7:  lea rdi, [rbx + 1]
    mov rsi, r14
    mov edx, 2
    call read_escape
    cmp rax, -1
    je 71f
    mov rbx, rax
    mov r14, rdx
    jmp 6b
71: mov qword ptr [rip + g_jt_val], 0
    mov qword ptr [rip + g_jt_len], 0
    jmp 9f
8:  mov rdi, r14
    sub rdi, [rip + g_jt_val]
    mov [rip + g_jt_len], rdi
    call alloc
9:  mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unterminated template"
ENDF jl_template_chunk

# jl_regex(): the current token is `/` or `/=` where an expression starts; reads it as a
# regular expression. g_jt_val/g_jt_len: pattern; g_jt_raw_start/g_jt_raw_end: flags.
FUNC jl_regex
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    mov rbx, [rip + g_jt_start]
    inc rbx
    lea rax, [r12 + rbx]
    mov [rip + g_jt_val], rax
    xor r14d, r14d                      # bit 0 escaped, bit 1 in class
1:  cmp rbx, r13
    jae 90f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 10
    je 90f
    cmp al, 0xE2
    jne 2f
    mov rdi, rbx
    call jl_is_line_sep
    test eax, eax
    jnz 90f
    movzx eax, byte ptr [r12 + rbx]
2:  test r14d, 1
    jz 3f
    and r14d, ~1
    jmp 6f
3:  cmp al, '['
    jne 4f
    or r14d, 2
    jmp 5f
4:  cmp al, ']'
    jne 41f
    and r14d, ~2
    jmp 5f
41: cmp al, '/'
    jne 5f
    test r14d, 2
    jz 7f
5:  cmp al, '\\'
    jne 6f
    or r14d, 1
6:  inc rbx
    jmp 1b
7:  lea rax, [r12 + rbx]
    sub rax, [rip + g_jt_val]
    mov [rip + g_jt_len], rax
    inc rbx
    mov [rip + g_jt_raw_start], rbx
    # flags: d g i m s u v y, each once, not both u and v
    xor r14d, r14d                      # seen flags as bits
8:  cmp rbx, r13
    jae 9f
    movzx eax, byte ptr [r12 + rbx]
    lea rsi, [rip + regex_flag_chars]
    xor ecx, ecx
81: movzx edx, byte ptr [rsi + rcx]
    test edx, edx
    jz 85f
    cmp eax, edx
    je 82f
    inc ecx
    jmp 81b
82: bts r14d, ecx
    jc 91f
    inc rbx
    jmp 8b
85: cmp al, '\\'
    je 91f
    cmp al, 0x80
    jae 91f
    lea rcx, [rip + js_char_class]
    movzx ecx, byte ptr [rcx + rax]
    cmp ecx, CC_IDENT
    je 91f
    cmp ecx, CC_DIGIT
    je 91f
9:  mov eax, r14d
    and eax, 0x60                       # u and v
    cmp eax, 0x60
    je 91f
    mov [rip + g_jt_raw_end], rbx
    mov [rip + g_jt_end], rbx
    mov [rip + g_jt_pos], rbx
    mov qword ptr [rip + g_jt_type], J_REGEX
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unterminated regular expression"
91: REFUSE "syntax error: invalid regular expression flags"
ENDF jl_regex

    .section .rodata
regex_flag_chars: .asciz "dgimsuvy"
