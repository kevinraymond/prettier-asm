# .gitignore and .prettierignore rules as the `ignore` package (7.0.5)
# applies them: each pattern becomes a case-insensitive regex through a chain
# of string replacements, and a path is tested together with its parent
# directories. Patterns are compiled here straight to the regex pieces those
# replacements produce, for the characters ported; anything else is refused.
.include "defs.inc"

# Regex pieces. One unit is UNIT_SIZE bytes: op, char, then a 128-bit class.
.equ U_DONE, 0
.equ U_LIT, 1           # the char, any case
.equ U_ANY1, 2          # [^/]
.equ U_CLASS, 3         # [...]
.equ U_STAR_NS, 4       # [^/]*
.equ U_PLUS_NS, 5       # [^/]+
.equ U_GS_MID, 6        # (?:\/[^\/]+)*
.equ U_GS_END, 7        # \/.+
.equ U_END, 8           # $
.equ U_EOSE, 9          # (?=$|\/$)
.equ U_BOL, 10          # ^
.equ U_SOS, 11          # (?:^|\/)
.equ U_ANYDIR, 12       # ^(?:.*\/)?
.equ U_STAR, 13         # a '*' not yet rewritten
.equ UNIT_SIZE, 24
.equ MAX_RULES, 65536

    .bss
    .balign 8
ig_rules:  .quad 0                  # array of rule records
    .globl ig_count
ig_count:  .quad 0
ig_s:      .quad 0                  # string being tested
ig_n:      .quad 0

    .text

# ig_reset()
FUNC ig_reset
    mov qword ptr [rip + ig_count], 0
    cmp qword ptr [rip + ig_rules], 0
    jne 1f
    mov edi, MAX_RULES * 16
    call alloc
    mov [rip + ig_rules], rax
1:  leave
    ret
ENDF ig_reset

# ig_add_text(ptr, len): one pattern per line, lines split on \r?\n.
FUNC ig_add_text
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    lea r12, [rdi + rsi]
1:  cmp rbx, r12
    jae 9f
    mov r13, rbx
2:  cmp r13, r12
    jae 3f
    cmp byte ptr [r13], 10
    je 3f
    inc r13
    jmp 2b
3:  mov r14, r13                    # line end
    cmp r14, rbx
    je 4f
    cmp r13, r12
    jae 4f
    cmp byte ptr [r14 - 1], 13
    jne 4f
    dec r14
4:  mov rdi, rbx
    mov rsi, r14
    sub rsi, rbx
    call ig_line
    lea rbx, [r13 + 1]
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ig_add_text

# ig_is_ws(c) -> eax: \s for ASCII
FUNC ig_is_ws
    xor eax, eax
    cmp dil, ' '
    je 1f
    cmp dil, 9
    jb 2f
    cmp dil, 13
    ja 2f
1:  mov eax, 1
2:  leave
    ret
ENDF ig_is_ws

# ig_line(ptr, len): checkPattern, then compile and add the rule.
FUNC ig_line
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 99f
    cmp byte ptr [rbx], '#'
    je 99f                          # a comment, whatever it holds
    # bytes: ASCII only, no backslash
    xor ecx, ecx
    xor r13d, r13d                  # 1 when some byte is not whitespace
1:  cmp rcx, r12
    jae 2f
    movzx edi, byte ptr [rbx + rcx]
    cmp dil, 0x7f
    jae 90f
    cmp dil, '\\'
    je 90f
    mov [rsp], rcx
    call ig_is_ws
    mov rcx, [rsp]
    inc rcx
    test eax, eax
    jnz 1b
    mov r13d, 1
    jmp 1b
2:  test r13d, r13d
    jz 99f                          # blank line
    # negation
    xor r15d, r15d
    cmp byte ptr [rbx], '!'
    jne 3f
    mov r15d, 1
    inc rbx
    dec r12
    # rbx/r12 = body as written; r14 = length without trailing whitespace
3:  mov r14, r12
31: test r14, r14
    jz 90f
    movzx edi, byte ptr [rbx + r14 - 1]
    call ig_is_ws
    test eax, eax
    jz 32f
    dec r14
    jmp 31b
32: # control characters inside the pattern are not ported
    xor ecx, ecx
33: cmp rcx, r14
    jae 34f
    cmp byte ptr [rbx + rcx], 0x20
    jb 90f
    inc rcx
    jmp 33b
34: cmp r14, 1
    jne 35f
    cmp byte ptr [rbx], '/'
    je 90f
    # a slash before the last character of the body as written: anchored
35: xor r13d, r13d
    lea rcx, [r12 - 1]
36: test rcx, rcx
    jz 37f
    dec rcx
    cmp byte ptr [rbx + rcx], '/'
    jne 36b
    mov r13d, 1
37: mov rdi, rbx
    mov rsi, r14
    mov edx, r13d
    call ig_compile
    mov r13, rax
    mov rcx, [rip + ig_count]
    cmp rcx, MAX_RULES
    jae 91f
    shl rcx, 4
    add rcx, [rip + ig_rules]
    mov [rcx], r15
    mov [rcx + 8], r13
    inc qword ptr [rip + ig_count]
99: add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "ignore pattern not ported"
91: REFUSE "too many ignore patterns"
ENDF ig_line

# ig_compile(body, len, anchored) -> rax = unit array ending in U_DONE
FUNC ig_compile
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rdx
    lea rdi, [r12 + 8]
    imul rdi, rdi, UNIT_SIZE
    call alloc
    mov r13, rax                    # units, room for one prefix and two suffixes
    add rax, UNIT_SIZE              # leave unit 0 free for the prefix
    mov r14, rax                    # write cursor
    xor r15d, r15d                  # read index
    # characters to units
1:  cmp r15, r12
    jae 20f
    movzx eax, byte ptr [rbx + r15]
    cmp al, '/'
    jne 2f
    test r15, r15
    jnz 2f
    mov byte ptr [r14], U_BOL
    jmp 8f
2:  cmp al, '?'
    jne 3f
    mov byte ptr [r14], U_ANY1
    jmp 8f
3:  cmp al, '*'
    jne 4f
    mov byte ptr [r14], U_STAR
    jmp 8f
4:  cmp al, ']'
    je 90f
    cmp al, '['
    jne 7f
    # [class]: names, digits, '_' and ranges within one kind
    mov byte ptr [r14], U_CLASS
    inc r15
    mov rcx, r15
41: cmp rcx, r12
    jae 90f
    cmp byte ptr [rbx + rcx], ']'
    je 42f
    inc rcx
    jmp 41b
42: cmp rcx, r15
    je 90f
    mov [rsp + 8], rcx
43: cmp r15, [rsp + 8]
    jae 49f
    movzx eax, byte ptr [rbx + r15]
    mov edi, eax
    call ig_char_kind
    test eax, eax
    jz 90f
    mov edx, eax                    # kind of the first end
    movzx eax, byte ptr [rbx + r15]
    mov ecx, eax                    # range end, the same char unless a-b
    lea r8, [r15 + 2]
    cmp r8, [rsp + 8]
    jae 45f
    cmp byte ptr [rbx + r15 + 1], '-'
    jne 45f
    movzx ecx, byte ptr [rbx + r15 + 2]
    push rax
    push rcx
    push rdx
    sub rsp, 8
    mov edi, ecx
    call ig_char_kind
    add rsp, 8
    pop rdx
    pop rcx
    mov r9d, eax
    pop rax
    cmp r9d, edx
    jne 90f
    cmp ecx, eax
    jb 90f
    add r15, 2
    jmp 46f
45: cmp al, '-'
    je 90f
46: # set bits eax..ecx
    cmp eax, ecx
    ja 47f
    mov r8d, eax
    shr r8d, 3
    mov r9d, eax
    and r9d, 7
    mov r10b, 1
    push rcx
    mov ecx, r9d
    shl r10b, cl
    pop rcx
    or [r14 + 8 + r8], r10b
    inc eax
    jmp 46b
47: inc r15
    jmp 43b
49: mov r15, [rsp + 8]
    jmp 8f
7:  mov byte ptr [r14], U_LIT
    mov [r14 + 1], al
8:  add r14, UNIT_SIZE
    inc r15
    jmp 1b
    # r13 = unit 0 (free), units 1.. up to r14
20: lea rbx, [r13 + UNIT_SIZE]      # first unit
    # leading "**/" or "/**/" becomes ^(?:.*\/)?
    mov rax, r14
    sub rax, rbx
    cmp byte ptr [rbx], U_BOL
    jne 22f
    cmp rax, UNIT_SIZE * 4
    jb 25f
    cmp byte ptr [rbx + UNIT_SIZE], U_STAR
    jne 25f
    cmp byte ptr [rbx + UNIT_SIZE * 2], U_STAR
    jne 25f
    lea rdi, [rbx + UNIT_SIZE * 3]
    call ig_is_slash
    test eax, eax
    jz 25f
    lea rsi, [rbx + UNIT_SIZE * 3]
    jmp 23f
22: cmp rax, UNIT_SIZE * 3
    jb 24f
    cmp byte ptr [rbx], U_STAR
    jne 24f
    cmp byte ptr [rbx + UNIT_SIZE], U_STAR
    jne 24f
    lea rdi, [rbx + UNIT_SIZE * 2]
    call ig_is_slash
    test eax, eax
    jz 24f
    lea rsi, [rbx + UNIT_SIZE * 2]
    # the slash unit becomes the ANYDIR unit; drop what came before it
23: mov byte ptr [rsi], U_ANYDIR
    mov rbx, rsi
    jmp 25f
    # no ^ at the start: (?:^|\/) for a pattern without an inner slash, else ^
24: sub rbx, UNIT_SIZE
    mov byte ptr [rbx], U_SOS
    cmp qword ptr [rsp], 0
    je 25f
    mov byte ptr [rbx], U_BOL
    # "/**" followed by "/" or the end: (?:\/[^\/]+)* or \/.+
25: mov rsi, rbx
    mov rdi, rbx                    # write
26: cmp rsi, r14
    jae 29f
    mov rcx, r14
    sub rcx, rsi
    cmp rcx, UNIT_SIZE * 3
    jb 28f
    push rsi
    push rdi
    mov rdi, rsi
    call ig_is_slash
    pop rdi
    pop rsi
    test eax, eax
    jz 28f
    cmp byte ptr [rsi + UNIT_SIZE], U_STAR
    jne 28f
    cmp byte ptr [rsi + UNIT_SIZE * 2], U_STAR
    jne 28f
    lea r8, [rsi + UNIT_SIZE * 3]
    cmp r8, r14
    je 27f
    push rsi
    push rdi
    mov rdi, r8
    call ig_is_slash
    pop rdi
    pop rsi
    test eax, eax
    jz 28f
    mov byte ptr [rdi], U_GS_MID
    jmp 271f
27: mov byte ptr [rdi], U_GS_END
271: add rdi, UNIT_SIZE
    add rsi, UNIT_SIZE * 3
    jmp 26b
28: cmp rsi, rdi
    je 281f
    mov rcx, UNIT_SIZE
    push rsi
    push rdi
    rep movsb
    pop rdi
    pop rsi
281: add rsi, UNIT_SIZE
    add rdi, UNIT_SIZE
    jmp 26b
29: mov r14, rdi                    # new end
    # every '*' but a last one: [^\/]*
    lea rsi, [r14 - UNIT_SIZE]
    mov rcx, rbx
30: cmp rcx, rsi
    jae 31f
    cmp byte ptr [rcx], U_STAR
    jne 301f
    mov byte ptr [rcx], U_STAR_NS
301: add rcx, UNIT_SIZE
    jmp 30b
    # the end
31: movzx eax, byte ptr [rsi]
    cmp al, U_STAR
    jne 33f
    lea rdi, [rsi - UNIT_SIZE]
    cmp rdi, rbx
    jb 32f
    call ig_is_slash
    test eax, eax
    jz 32f
    mov byte ptr [rsi], U_PLUS_NS
    jmp 34f
32: mov byte ptr [rsi], U_STAR_NS
    jmp 34f
33: mov rdi, rsi
    call ig_is_slash
    test eax, eax
    jz 34f
    mov byte ptr [r14], U_END
    jmp 35f
34: mov byte ptr [r14], U_EOSE
35: add r14, UNIT_SIZE
    mov byte ptr [r14], U_DONE
    mov rax, rbx
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "ignore pattern not ported"
ENDF ig_compile

# ig_is_slash(unit) -> eax: a literal '/' unit
FUNC ig_is_slash
    xor eax, eax
    cmp byte ptr [rdi], U_LIT
    jne 1f
    cmp byte ptr [rdi + 1], '/'
    jne 1f
    mov eax, 1
1:  leave
    ret
ENDF ig_is_slash

# ig_char_kind(c) -> eax: 1 digit, 2 lowercase, 3 uppercase, 4 '_', 0 other
FUNC ig_char_kind
    xor eax, eax
    mov ecx, edi
    sub ecx, '0'
    cmp ecx, 9
    ja 1f
    mov eax, 1
    jmp 9f
1:  mov ecx, edi
    sub ecx, 'a'
    cmp ecx, 25
    ja 2f
    mov eax, 2
    jmp 9f
2:  mov ecx, edi
    sub ecx, 'A'
    cmp ecx, 25
    ja 3f
    mov eax, 3
    jmp 9f
3:  cmp edi, '_'
    jne 9f
    mov eax, 4
9:  leave
    ret
ENDF ig_char_kind

# ig_lower(c) -> eax
FUNC ig_lower
    mov eax, edi
    mov ecx, edi
    sub ecx, 'A'
    cmp ecx, 25
    ja 1f
    add eax, 32
1:  leave
    ret
ENDF ig_lower

# ig_in_class(unit, c) -> eax: c or its other case in the class
FUNC ig_in_class
    mov eax, esi
    call ig_class_bit
    test eax, eax
    jnz 9f
    mov eax, esi
    mov ecx, esi
    sub ecx, 'a'
    cmp ecx, 25
    ja 1f
    sub eax, 32
    jmp 2f
1:  mov ecx, esi
    sub ecx, 'A'
    cmp ecx, 25
    ja 8f
    add eax, 32
2:  call ig_class_bit
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF ig_in_class

# ig_class_bit(unit in rdi, char in eax) -> eax
FUNC ig_class_bit
    cmp eax, 127
    ja 1f
    mov ecx, eax
    shr ecx, 3
    movzx edx, byte ptr [rdi + 8 + rcx]
    mov ecx, eax
    and ecx, 7
    shr edx, cl
    and edx, 1
    mov eax, edx
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF ig_class_bit

# ig_um(unit, i) -> eax: the units from here match ig_s at index i
FUNC ig_um
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rip + ig_n]
    mov r14, [rip + ig_s]
    movzx eax, byte ptr [rbx]
    lea rdi, [rbx + UNIT_SIZE]      # next unit
    cmp al, U_DONE
    je 80f
    cmp al, U_LIT
    jne 2f
    cmp r12, r13
    jae 81f
    movzx edi, byte ptr [r14 + r12]
    call ig_lower
    mov ecx, eax
    movzx edi, byte ptr [rbx + 1]
    push rcx
    sub rsp, 8
    call ig_lower
    add rsp, 8
    pop rcx
    cmp eax, ecx
    jne 81f
    jmp 70f
2:  cmp al, U_ANY1
    jne 3f
    cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    je 81f
    jmp 70f
3:  cmp al, U_CLASS
    jne 4f
    cmp r12, r13
    jae 81f
    movzx esi, byte ptr [r14 + r12]
    mov rdi, rbx
    call ig_in_class
    test eax, eax
    jz 81f
    lea rdi, [rbx + UNIT_SIZE]
    jmp 70f
4:  cmp al, U_PLUS_NS
    jne 5f
    cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    je 81f
    inc r12
    jmp 51f
5:  cmp al, U_STAR_NS
    jne 6f
    # try every length of the non-slash run
51: lea rdi, [rbx + UNIT_SIZE]
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
    cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    je 81f
    inc r12
    jmp 51b
6:  cmp al, U_GS_MID
    jne 7f
    lea rdi, [rbx + UNIT_SIZE]
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
    cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    jne 81f
    inc r12
61: cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    je 81f
    inc r12
    mov rdi, rbx
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
    jmp 61b
7:  cmp al, U_GS_END
    jne 10f
    cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    jne 81f
    add r12, 2
71: cmp r12, r13
    ja 81f
    lea rdi, [rbx + UNIT_SIZE]
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
    inc r12
    jmp 71b
10: cmp al, U_END
    jne 11f
    cmp r12, r13
    jne 81f
    jmp 72f
11: cmp al, U_EOSE
    jne 12f
    cmp r12, r13
    je 72f
    lea rcx, [r12 + 1]
    cmp rcx, r13
    jne 81f
    cmp byte ptr [r14 + r12], '/'
    jne 81f
    jmp 72f
12: cmp al, U_BOL
    jne 13f
    test r12, r12
    jnz 81f
    jmp 72f
13: cmp al, U_SOS
    jne 14f
    test r12, r12
    jnz 131f
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
131: cmp r12, r13
    jae 81f
    cmp byte ptr [r14 + r12], '/'
    jne 81f
    lea rdi, [rbx + UNIT_SIZE]
    jmp 70f
14: # U_ANYDIR: only at the start, then nothing or anything ending in '/'
    test r12, r12
    jnz 81f
    lea rdi, [rbx + UNIT_SIZE]
    xor esi, esi
    call ig_um
    test eax, eax
    jnz 80f
141: inc r12
    cmp r12, r13
    ja 81f
    cmp byte ptr [r14 + r12 - 1], '/'
    jne 141b
    lea rdi, [rbx + UNIT_SIZE]
    mov rsi, r12
    call ig_um
    test eax, eax
    jnz 80f
    jmp 141b
    # consume one char, then the rest
70: lea rdi, [rbx + UNIT_SIZE]
    lea rsi, [r12 + 1]
    call ig_um
    jmp 9f
    # zero width, then the rest
72: lea rdi, [rbx + UNIT_SIZE]
    mov rsi, r12
    call ig_um
    jmp 9f
80: mov eax, 1
    jmp 9f
81: xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ig_um

# ig_match_string(ptr, len) -> eax: 1 when the last rule whose regex finds a
# match is not negated.
FUNC ig_match_string
    push rbx
    push r12
    push r13
    push r14
    mov [rip + ig_s], rdi
    mov [rip + ig_n], rsi
    xor r12d, r12d                  # rule index
    xor r13d, r13d                  # result
1:  cmp r12, [rip + ig_count]
    jae 9f
    mov rbx, r12
    shl rbx, 4
    add rbx, [rip + ig_rules]
    xor r14d, r14d                  # start index for the regex search
2:  cmp r14, [rip + ig_n]
    ja 4f
    mov rdi, [rbx + 8]
    mov rsi, r14
    call ig_um
    test eax, eax
    jnz 3f
    inc r14
    jmp 2b
3:  mov r13, [rbx]
    xor r13, 1
4:  inc r12
    jmp 1b
9:  mov eax, r13d
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ig_match_string

# ig_test(path, len) -> eax: ignored. Parent directories are tested first,
# as "a/", "a/b/", and an ignored parent decides.
FUNC ig_test
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
1:  cmp r13, r12
    jae 3f
    cmp byte ptr [rbx + r13], '/'
    jne 2f
    test r13, r13
    jz 2f
    mov rdi, rbx
    lea rsi, [r13 + 1]
    call ig_match_string
    test eax, eax
    jnz 9f
2:  inc r13
    jmp 1b
3:  mov rdi, rbx
    mov rsi, r12
    call ig_match_string
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ig_test
