# Tokenizer for the expression subset Babel's parseExpression accepts in JSON
# files. Collects comments in source order. Anything it does not understand
# is refused rather than guessed at; a JS lexer grows from here.
.include "defs.inc"

.equ TK_EOF, 0
.equ TK_PUNCT, 1
.equ TK_STRING, 2
.equ TK_NUM, 3
.equ TK_NAME, 4
.equ TK_TEMPLATE, 5

    .bss
    .balign 8
    .globl g_pos, g_tok_type, g_tok_start, g_tok_end, g_tok_val, g_tok_len
    .globl g_tok_raw_start, g_tok_raw_end, g_comments, g_hi_surrogate_at
g_pos:        .quad 0
g_tok_type:   .quad 0
g_tok_start:  .quad 0
g_tok_end:    .quad 0
g_tok_val:    .quad 0     # punct: the byte. string/template: cooked ptr
g_tok_len:    .quad 0     # string/template: cooked length
g_tok_raw_start: .quad 0  # template: raw start (after the backtick)
g_tok_raw_end:   .quad 0
g_comments:   .quad 0     # LIST of comment records
g_hi_surrogate_at: .quad 0  # cooked offset just after a lone high surrogate, or 0

# lex_next(): reads the next token into g_tok_*.
FUNC lex_next
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    mov rbx, [rip + g_pos]
    # whitespace and comments
1:  cmp rbx, r13
    jae 50f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, ' '
    je 2f
    cmp al, 9                       # \t \n \v \f
    jb 3f
    cmp al, 12
    ja 3f
2:  inc rbx
    jmp 1b
3:  cmp al, '/'
    jne 10f
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 10f
    movzx ecx, byte ptr [r12 + rbx + 1]
    cmp cl, '/'
    je 4f
    cmp cl, '*'
    je 6f
    jmp 10f
    # line comment, ends before \n (or a Unicode line separator)
4:  mov r14, rbx
    add rbx, 2
5:  cmp rbx, r13
    jae 41f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, 10
    je 41f
    cmp al, 0xE2
    jne 42f
    lea rcx, [rbx + 2]
    cmp rcx, r13
    jae 42f
    cmp byte ptr [r12 + rbx + 1], 0x80
    jne 42f
    mov cl, [r12 + rbx + 2]
    cmp cl, 0xA8
    je 41f
    cmp cl, 0xA9
    je 41f
42: cmp byte ptr [r12 + rbx], 0x80
    jb 43f
    mov rdi, rbx
    call refuse_unicode_space
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
    cmp byte ptr [r12 + rbx], '*'
    jne 8f
    cmp byte ptr [r12 + rbx + 1], '/'
    jne 8f
    add rbx, 2
    mov edi, CT_BLOCK
    mov rsi, r14
    mov rdx, rbx
    call add_comment
    jmp 1b
8:  cmp byte ptr [r12 + rbx], 0x80
    jb 81f
    mov rdi, rbx
    call refuse_unicode_space
81: inc rbx
    jmp 7b

    # a token starts at rbx
10: mov [rip + g_tok_start], rbx
    cmp al, '{'
    je 20f
    cmp al, '}'
    je 20f
    cmp al, '['
    je 20f
    cmp al, ']'
    je 20f
    cmp al, ','
    je 20f
    cmp al, ':'
    je 20f
    cmp al, '+'
    je 20f
    cmp al, '-'
    je 20f
    cmp al, '('
    je 20f
    cmp al, ')'
    je 20f
    cmp al, '"'
    je 21f
    cmp al, 0x27
    je 21f
    cmp al, '`'
    je 22f
    cmp al, '.'
    je 23f
    cmp al, '0'
    jb 25f
    cmp al, '9'
    jbe 24f
25: mov edi, eax
    call is_ident_start
    test eax, eax
    jnz 26f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '\\'
    je 91f
    cmp al, 0x80
    jae 92f
    jmp 93f

20: mov qword ptr [rip + g_tok_type], TK_PUNCT
    mov [rip + g_tok_val], rax
    inc rbx
    jmp 60f
21: mov rdi, rbx
    call lex_string
    mov rbx, rax
    mov qword ptr [rip + g_tok_type], TK_STRING
    jmp 60f
22: mov rdi, rbx
    call lex_template
    mov rbx, rax
    mov qword ptr [rip + g_tok_type], TK_TEMPLATE
    jmp 60f
23: lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 93f
    movzx ecx, byte ptr [r12 + rbx + 1]
    cmp cl, '0'
    jb 93f
    cmp cl, '9'
    ja 93f
24: mov rdi, rbx
    call lex_number
    mov rbx, rax
    mov qword ptr [rip + g_tok_type], TK_NUM
    jmp 60f
26: inc rbx
27: cmp rbx, r13
    jae 28f
    movzx edi, byte ptr [r12 + rbx]
    call is_ident_part
    test eax, eax
    jz 29f
    inc rbx
    jmp 27b
29: movzx eax, byte ptr [r12 + rbx]
    cmp al, '\\'
    je 91f
    cmp al, 0x80
    jae 92f
28: mov qword ptr [rip + g_tok_type], TK_NAME
    jmp 60f

50: mov qword ptr [rip + g_tok_type], TK_EOF
    mov [rip + g_tok_start], rbx
60: mov [rip + g_tok_end], rbx
    mov [rip + g_pos], rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "unterminated comment"
91: REFUSE "escape in identifier"
92: REFUSE "non-ASCII outside strings"
93: REFUSE "unexpected character"
ENDF lex_next

# refuse_unicode_space(pos): refuses when a non-ASCII whitespace code point
# (Zs, U+2028, U+2029, U+FEFF) starts at pos. Prettier trims comments with
# String#trim, which removes those; the port's trims are ASCII only.
FUNC refuse_unicode_space
    mov rsi, [rip + g_text]
    add rsi, rdi
    mov rcx, [rip + g_text_len]
    sub rcx, rdi                    # bytes left
    movzx eax, byte ptr [rsi]
    cmp al, 0xC2
    jne 1f
    cmp rcx, 2
    jb 9f
    cmp byte ptr [rsi + 1], 0xA0
    je 90f
    jmp 9f
1:  cmp rcx, 3
    jb 9f
    movzx edx, byte ptr [rsi + 1]
    movzx r8d, byte ptr [rsi + 2]
    cmp al, 0xE1
    jne 2f
    cmp dl, 0x9A
    jne 9f
    cmp r8b, 0x80
    je 90f
    jmp 9f
2:  cmp al, 0xE2
    jne 4f
    cmp dl, 0x80
    jne 3f
    cmp r8b, 0x8A
    jbe 90f
    cmp r8b, 0xA8
    je 90f
    cmp r8b, 0xA9
    je 90f
    cmp r8b, 0xAF
    je 90f
    jmp 9f
3:  cmp dl, 0x81
    jne 9f
    cmp r8b, 0x9F
    je 90f
    jmp 9f
4:  cmp al, 0xE3
    jne 5f
    cmp dl, 0x80
    jne 9f
    cmp r8b, 0x80
    je 90f
    jmp 9f
5:  cmp al, 0xEF
    jne 9f
    cmp dl, 0xBB
    jne 9f
    cmp r8b, 0xBF
    je 90f
9:  leave
    ret
90: REFUSE "non-ASCII whitespace in a comment"
ENDF refuse_unicode_space

# add_comment(type, start, end)
FUNC add_comment
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov edi, COMMENT_SIZE
    call alloc
    mov [rax + CM_TYPE], bl
    mov [rax + CM_START], r12d
    mov [rax + CM_END], r13d
    mov rsi, rax
    mov rdi, [rip + g_comments]
    call list_push
    mov [rip + g_comments], rax
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF add_comment

# is_ident_start(c) -> eax
FUNC is_ident_start
    xor eax, eax
    cmp dil, '$'
    je 1f
    cmp dil, '_'
    je 1f
    mov ecx, edi
    or cl, 0x20
    cmp cl, 'a'
    jb 2f
    cmp cl, 'z'
    ja 2f
1:  mov eax, 1
2:  leave
    ret
ENDF is_ident_start

# is_ident_part(c) -> eax
FUNC is_ident_part
    cmp dil, '0'
    jb 1f
    cmp dil, '9'
    ja 1f
    mov eax, 1
    leave
    ret
1:  call is_ident_start
    leave
    ret
ENDF is_ident_part

# hex_val(c) -> eax = 0..15, or -1
FUNC hex_val
    mov eax, edi
    sub eax, '0'
    cmp eax, 9
    jbe 2f
    mov eax, edi
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 5
    ja 1f
    add eax, 10
    jmp 2f
1:  mov eax, -1
2:  leave
    ret
ENDF hex_val

# ---------------------------------------------------------------- cooked strings
# The cooked value is written at the arena pointer and committed afterwards
# (cooked UTF-8 is never longer than the raw text). Lone surrogates are kept
# as 3-byte sequences (WTF-8); an escaped high surrogate directly followed by
# an escaped low surrogate becomes one code point, as in a UTF-16 string.

# cook_put_cp(dst, cp) -> rax = new dst
FUNC cook_put_cp
    mov eax, esi
    # low surrogate right after a lone high surrogate: combine
    cmp eax, 0xDC00
    jb 5f
    cmp eax, 0xDFFF
    ja 5f
    cmp rdi, [rip + g_hi_surrogate_at]
    jne 5f
    # decode the high surrogate written just before
    movzx ecx, byte ptr [rdi - 2]
    and ecx, 0x3F
    shl ecx, 6
    movzx edx, byte ptr [rdi - 1]
    and edx, 0x3F
    or ecx, edx
    or ecx, 0xD000                  # ED xx xx -> 0xD000 | bits; high is D800..DBFF
    sub rdi, 3
    sub ecx, 0xD800
    shl ecx, 10
    sub eax, 0xDC00
    or eax, ecx
    add eax, 0x10000
    mov qword ptr [rip + g_hi_surrogate_at], 0
    jmp 4f
5:  mov qword ptr [rip + g_hi_surrogate_at], 0
    cmp eax, 0x80
    jae 1f
    mov [rdi], al
    lea rax, [rdi + 1]
    leave
    ret
1:  cmp eax, 0x800
    jae 2f
    mov ecx, eax
    shr ecx, 6
    or cl, 0xC0
    mov [rdi], cl
    and al, 0x3F
    or al, 0x80
    mov [rdi + 1], al
    lea rax, [rdi + 2]
    leave
    ret
2:  cmp eax, 0x10000
    jae 4f
    mov ecx, eax
    shr ecx, 12
    or cl, 0xE0
    mov [rdi], cl
    mov ecx, eax
    shr ecx, 6
    and cl, 0x3F
    or cl, 0x80
    mov [rdi + 1], cl
    and al, 0x3F
    or al, 0x80
    mov [rdi + 2], al
    lea rcx, [rdi + 3]
    # remember a high surrogate
    cmp eax, 0xD800
    jb 3f
    cmp eax, 0xDBFF
    ja 3f
    mov [rip + g_hi_surrogate_at], rcx
3:  mov rax, rcx
    leave
    ret
4:  mov ecx, eax
    shr ecx, 18
    or cl, 0xF0
    mov [rdi], cl
    mov ecx, eax
    shr ecx, 12
    and cl, 0x3F
    or cl, 0x80
    mov [rdi + 1], cl
    mov ecx, eax
    shr ecx, 6
    and cl, 0x3F
    or cl, 0x80
    mov [rdi + 2], cl
    and al, 0x3F
    or al, 0x80
    mov [rdi + 3], al
    lea rax, [rdi + 4]
    leave
    ret
ENDF cook_put_cp

# read_escape(pos, dst, in_template) -> rax = new pos, rdx = new dst.
# pos is just after the backslash. Refuses invalid escapes, except with
# in_template 2, where an invalid escape returns rax = -1.
FUNC read_escape
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r15d, edx
    mov r13, [rip + g_text]
    mov r14, [rip + g_text_len]
    cmp rbx, r14
    jae 90f
    movzx eax, byte ptr [r13 + rbx]
    inc rbx
    cmp al, 'n'
    mov ecx, 10
    je 10f
    cmp al, 'r'
    mov ecx, 13
    je 10f
    cmp al, 't'
    mov ecx, 9
    je 10f
    cmp al, 'b'
    mov ecx, 8
    je 10f
    cmp al, 'v'
    mov ecx, 11
    je 10f
    cmp al, 'f'
    mov ecx, 12
    je 10f
    cmp al, 10
    je 20f                          # line continuation
    cmp al, 'x'
    je 30f
    cmp al, 'u'
    je 40f
    cmp al, '0'
    jb 5f
    cmp al, '7'
    jbe 50f
    cmp al, '9'
    jbe 60f
5:  cmp al, 0xE2                    # \ + U+2028/U+2029 is a line continuation
    jne 6f
    lea rcx, [rbx + 1]
    cmp rcx, r14
    jae 6f
    cmp byte ptr [r13 + rbx], 0x80
    jne 6f
    mov cl, [r13 + rbx + 1]
    cmp cl, 0xA8
    je 7f
    cmp cl, 0xA9
    jne 6f
7:  add rbx, 2
    jmp 20f
    # any other character stands for itself (copy its UTF-8 bytes)
6:  dec rbx
    movzx eax, byte ptr [r13 + rbx]
8:  mov [r12], al
    inc r12
    inc rbx
    cmp rbx, r14
    jae 20f
    movzx eax, byte ptr [r13 + rbx]
    mov cl, al
    and cl, 0xC0
    cmp cl, 0x80
    je 8b
    mov qword ptr [rip + g_hi_surrogate_at], 0
    jmp 20f
10: mov rdi, r12
    mov esi, ecx
    call cook_put_cp
    mov r12, rax
    jmp 20f
    # \xHH
30: cmp rbx, r14
    jae 90f
    movzx edi, byte ptr [r13 + rbx]
    call hex_val
    test eax, eax
    js 90f
    mov ecx, eax
    lea rdx, [rbx + 1]
    cmp rdx, r14
    jae 90f
    push rcx
    push rcx
    movzx edi, byte ptr [r13 + rbx + 1]
    call hex_val
    pop rcx
    pop rcx
    test eax, eax
    js 90f
    shl ecx, 4
    or ecx, eax
    add rbx, 2
    jmp 10b
    # \uHHHH or \u{H+}
40: cmp rbx, r14
    jae 90f
    cmp byte ptr [r13 + rbx], '{'
    je 45f
    xor ecx, ecx
    mov edx, 4
41: cmp rbx, r14
    jae 90f
    push rcx
    push rdx
    movzx edi, byte ptr [r13 + rbx]
    call hex_val
    pop rdx
    pop rcx
    test eax, eax
    js 90f
    shl ecx, 4
    or ecx, eax
    inc rbx
    dec edx
    jnz 41b
    jmp 10b
45: inc rbx
    xor ecx, ecx
    xor edx, edx                    # digit count
46: cmp rbx, r14
    jae 90f
    cmp byte ptr [r13 + rbx], '}'
    je 47f
    push rcx
    push rdx
    movzx edi, byte ptr [r13 + rbx]
    call hex_val
    pop rdx
    pop rcx
    test eax, eax
    js 90f
    shl ecx, 4
    or ecx, eax
    cmp ecx, 0x10FFFF
    ja 90f
    inc edx
    inc rbx
    jmp 46b
47: test edx, edx
    jz 90f
    inc rbx
    jmp 10b
    # \0-\7: legacy octal (sloppy strings); templates only allow \0 not
    # followed by a digit
50: movzx ecx, al
    sub ecx, '0'
    mov edx, 1                      # digits taken
51: cmp edx, 3
    jae 53f
    cmp rbx, r14
    jae 53f
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '0'
    jb 53f
    cmp al, '7'
    ja 53f
    mov r8d, ecx
    shl r8d, 3
    sub eax, '0'
    or r8d, eax
    cmp r8d, 255
    ja 53f
    mov ecx, r8d
    inc rbx
    inc edx
    jmp 51b
53: test r15d, r15d
    jz 10b
    # template: only a lone \0 with no digit after it
    cmp edx, 1
    jne 90f
    test ecx, ecx
    jnz 90f
    cmp rbx, r14
    jae 10b
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '0'
    jb 10b
    cmp al, '9'
    jbe 90f
    jmp 10b
    # \8 \9: themselves in sloppy strings, invalid in templates
60: test r15d, r15d
    jnz 90f
    movzx ecx, al
    jmp 10b
20: mov rax, rbx
    mov rdx, r12
21: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: cmp r15d, 2
    jne 91f
    mov rax, -1
    jmp 21b
91: REFUSE "invalid escape sequence"
ENDF read_escape

# lex_string(pos at quote) -> rax = pos after the closing quote.
# Sets g_tok_val/g_tok_len to the cooked value.
FUNC lex_string
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r13, [rip + g_text]
    mov r14, [rip + g_text_len]
    movzx r15d, byte ptr [r13 + rbx]   # quote
    inc rbx
    mov r12, [rip + g_arena_ptr]
    mov [rip + g_tok_val], r12
    mov qword ptr [rip + g_hi_surrogate_at], 0
1:  cmp rbx, r14
    jae 90f
    movzx eax, byte ptr [r13 + rbx]
    cmp eax, r15d
    je 5f
    cmp al, '\\'
    je 3f
    cmp al, 10
    je 90f
    mov [r12], al
    inc r12
    inc rbx
    mov qword ptr [rip + g_hi_surrogate_at], 0
    jmp 1b
3:  lea rdi, [rbx + 1]
    mov rsi, r12
    xor edx, edx
    call read_escape
    mov rbx, rax
    mov r12, rdx
    jmp 1b
5:  inc rbx
    mov rdi, r12
    sub rdi, [rip + g_tok_val]
    mov [rip + g_tok_len], rdi
    call alloc                      # commits the bytes written at the arena pointer
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "unterminated string"
ENDF lex_string

# lex_template(pos at backtick) -> rax = pos after the closing backtick.
# Only templates without ${} are accepted.
FUNC lex_template
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r13, [rip + g_text]
    mov r14, [rip + g_text_len]
    inc rbx
    mov [rip + g_tok_raw_start], rbx
    mov r12, [rip + g_arena_ptr]
    mov [rip + g_tok_val], r12
    mov qword ptr [rip + g_hi_surrogate_at], 0
1:  cmp rbx, r14
    jae 90f
    movzx eax, byte ptr [r13 + rbx]
    cmp al, '`'
    je 5f
    cmp al, '\\'
    je 3f
    cmp al, '$'
    jne 2f
    lea rcx, [rbx + 1]
    cmp rcx, r14
    jae 2f
    cmp byte ptr [r13 + rbx + 1], '{'
    je 91f
2:  mov [r12], al
    inc r12
    inc rbx
    mov qword ptr [rip + g_hi_surrogate_at], 0
    jmp 1b
3:  lea rdi, [rbx + 1]
    mov rsi, r12
    mov edx, 1
    call read_escape
    mov rbx, rax
    mov r12, rdx
    jmp 1b
5:  mov [rip + g_tok_raw_end], rbx
    inc rbx
    mov rdi, r12
    sub rdi, [rip + g_tok_val]
    mov [rip + g_tok_len], rdi
    call alloc
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "unterminated template"
91: REFUSE "template literal with an expression"
ENDF lex_template

# digit_ok(c, radix) -> eax = 1 if c is a digit of radix
FUNC digit_ok
    mov edi, edi
    call hex_val
    test eax, eax
    js 1f
    cmp eax, esi
    jae 1f
    mov eax, 1
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF digit_ok

# scan_digits(pos, radix) -> rax = pos after the digits, rdx = digit count.
# A `_` is allowed only between two digits.
FUNC scan_digits
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
    movzx edi, byte ptr [r14 + rbx - 1]
    cmp dil, '_'
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
90: REFUSE "numeric separator"
ENDF scan_digits

# lex_number(pos) -> rax = pos after the number
FUNC lex_number
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rip + g_text]
    mov r13, [rip + g_text_len]
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '0'
    jne 20f
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jae 20f
    movzx ecx, byte ptr [r12 + rbx + 1]
    or cl, 0x20
    mov esi, 16
    cmp cl, 'x'
    je 10f
    mov esi, 8
    cmp cl, 'o'
    je 10f
    mov esi, 2
    cmp cl, 'b'
    je 10f
    movzx ecx, byte ptr [r12 + rbx + 1]
    cmp cl, '_'
    je 91f
    cmp cl, '0'
    jb 20f
    cmp cl, '9'
    ja 20f
    # 0 followed by digits: legacy octal when all are 0-7 (and nothing
    # number-like follows), otherwise a decimal with a leading zero that may
    # have a fraction and an exponent. Separators are refused in both.
    lea rdi, [rbx + 1]
    xor r8d, r8d                    # saw 8 or 9
11: cmp rdi, r13
    jae 13f
    movzx ecx, byte ptr [r12 + rdi]
    cmp cl, '0'
    jb 12f
    cmp cl, '9'
    ja 12f
    cmp cl, '8'
    jb 111f
    mov r8d, 1
111: inc rdi
    jmp 11b
12: cmp cl, '_'
    je 91f
    test r8d, r8d
    jnz 14f
    cmp cl, '.'
    je 91f
    or cl, 0x20
    cmp cl, 'e'
    je 91f
13: mov rbx, rdi
    jmp 30f
14: mov rbx, rdi
    # fraction and exponent; no separators
    cmp cl, '.'
    jne 16f
    inc rbx
15: cmp rbx, r13
    jae 30f
    movzx ecx, byte ptr [r12 + rbx]
    cmp cl, '_'
    je 91f
    cmp cl, '0'
    jb 16f
    cmp cl, '9'
    ja 16f
    inc rbx
    jmp 15b
16: cmp rbx, r13
    jae 30f
    movzx ecx, byte ptr [r12 + rbx]
    or cl, 0x20
    cmp cl, 'e'
    jne 30f
    lea rdi, [rbx + 1]
    cmp rdi, r13
    jae 91f
    movzx ecx, byte ptr [r12 + rdi]
    cmp cl, '+'
    je 17f
    cmp cl, '-'
    jne 18f
17: inc rdi
18: mov rbx, rdi
19: cmp rbx, r13
    jae 191f
    movzx ecx, byte ptr [r12 + rbx]
    cmp cl, '_'
    je 91f
    cmp cl, '0'
    jb 191f
    cmp cl, '9'
    ja 191f
    inc rbx
    jmp 19b
191: cmp rbx, rdi
    je 91f
    jmp 30f
    # 0x / 0o / 0b
10: lea rdi, [rbx + 2]
    call scan_digits
    test rdx, rdx
    jz 91f
    mov rbx, rax
    jmp 30f
    # decimal
20: cmp al, '.'
    je 21f
    mov rdi, rbx
    mov esi, 10
    call scan_digits
    mov rbx, rax
    cmp rbx, r13
    jae 30f
    cmp byte ptr [r12 + rbx], '.'
    jne 22f
21: inc rbx
    cmp rbx, r13
    jae 30f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '_'
    je 91f
    mov rdi, rbx
    mov esi, 10
    call scan_digits
    mov rbx, rax
22: cmp rbx, r13
    jae 30f
    movzx eax, byte ptr [r12 + rbx]
    or al, 0x20
    cmp al, 'e'
    jne 30f
    inc rbx
    cmp rbx, r13
    jae 91f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '+'
    je 23f
    cmp al, '-'
    jne 24f
23: inc rbx
24: cmp rbx, r13
    jae 91f
    movzx eax, byte ptr [r12 + rbx]
    cmp al, '_'
    je 91f
    mov rdi, rbx
    mov esi, 10
    call scan_digits
    test rdx, rdx
    jz 91f
    mov rbx, rax
    # nothing identifier-like or numeric may follow (this also refuses BigInt)
30: cmp rbx, r13
    jae 39f
    movzx edi, byte ptr [r12 + rbx]
    cmp dil, 0x80
    jae 91f
    cmp dil, '\\'
    je 91f
    cmp dil, '.'
    jne 31f
    # `1..x` and `1.0.5` are not numbers we print
    jmp 91f
31: call is_ident_part
    test eax, eax
    jnz 91f
39: mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
91: REFUSE "number not ported"
ENDF lex_number
