# printString / makeString / getPreferredQuote (src/utils/print-string.js,
# make-string.js, get-preferred-quote.js) and printNumber
# (src/utils/print-number.js). Results are new strings in the arena.
.include "defs.inc"

# print_string(raw_ptr, raw_len) -> rax = ptr, rdx = len
# Enclosing quote: `"` for json and jsonc, and for json5 with quoteProps
# "preserve" and no singleQuote; otherwise the preferred quote. Prettier's
# __isInHtmlAttribute case (embedded in HTML) is not ported.
FUNC print_string
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, '"'
    mov rax, [rip + g_parser]
    cmp rax, P_JSON
    je 1f
    cmp rax, P_JSONC
    je 1f
    mov rdx, [rip + g_single_quote]
    cmp rax, P_JSON5
    jne 11f
    test rdx, rdx
    jnz 11f
    cmp qword ptr [rip + g_quote_props], QP_PRESERVE
    je 1f
11: lea rdi, [rbx + 1]
    lea rsi, [r12 - 2]
    call preferred_quote
    mov r13d, eax
1:  movzx eax, byte ptr [rbx]
    cmp eax, r13d
    jne 2f
    mov rax, rbx
    mov rdx, r12
    jmp 9f
2:  lea rdi, [rbx + 1]
    lea rsi, [r12 - 2]
    mov edx, r13d
    call make_string
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_string

# preferred_quote(ptr, len, prefer_single) -> eax (getPreferredQuote): the
# preferred quote unless the text has more of it than of the other one
FUNC preferred_quote
    mov r9d, edx
    xor ecx, ecx                    # double count
    xor edx, edx                    # single count
    xor eax, eax
1:  cmp rax, rsi
    jae 3f
    movzx r8d, byte ptr [rdi + rax]
    inc rax
    cmp r8b, '"'
    jne 2f
    inc ecx
    jmp 1b
2:  cmp r8b, 0x27
    jne 1b
    inc edx
    jmp 1b
3:  test r9d, r9d
    jnz 5f
    mov eax, '"'
    cmp ecx, edx
    jbe 4f
    mov eax, 0x27
4:  leave
    ret
5:  mov eax, 0x27
    cmp edx, ecx
    jbe 4b
    mov eax, '"'
    jmp 4b
ENDF preferred_quote

# make_string(content_ptr, content_len, quote) -> rax = ptr, rdx = len
FUNC make_string
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx                   # enclosing
    mov r14d, '"' ^ 0x27
    xor r14d, edx                   # other quote
    lea rdi, [r12*2 + 2]
    call alloc
    mov r15, rax
    mov rdi, rax
    mov [rdi], r13b
    inc rdi
    xor ecx, ecx
1:  cmp rcx, r12
    jae 8f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '\\'
    jne 4f
    cmp rcx, r12
    jae 3f
    movzx edx, byte ptr [rbx + rcx]
    inc rcx
    cmp edx, r14d
    je 2f
    mov byte ptr [rdi], '\\'
    inc rdi
2:  mov [rdi], dl
    inc rdi
    jmp 1b
3:  mov [rdi], al
    inc rdi
    jmp 1b
4:  cmp eax, r13d
    jne 5f
    mov byte ptr [rdi], '\\'
    inc rdi
5:  mov [rdi], al
    inc rdi
    jmp 1b
8:  mov [rdi], r13b
    inc rdi
    mov rax, r15
    mov rdx, rdi
    sub rdx, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF make_string

# print_number(ptr, len) -> rax = ptr, rdx = len
# The regex steps of printNumber, in order:
#   lowercase
#   ^([+-]?[\d.]+e)(?:\+|(-))?0*(?=\d)  -> $1$2
#   ^([+-]?[\d.]+)e[+-]?0+$              -> $1
#   ^([+-])?\.                           -> $10.
#   (\.\d+?)0+(?=e|$)                    -> $1
#   \.(?=e|$)                            -> ""
FUNC print_number
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    cmp rsi, 1
    jne 1f
    mov rax, rdi
    mov rdx, rsi
    jmp 99f
1:  mov rbx, rdi
    mov r12, rsi
    lea rdi, [r12 + 2]
    call alloc
    mov r13, rax                    # buffer
    # lowercase copy
    xor ecx, ecx
2:  cmp rcx, r12
    jae 3f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, 'A'
    jb 21f
    cmp al, 'Z'
    ja 21f
    add al, 32
21: mov [r13 + rcx], al
    inc rcx
    jmp 2b
3:  mov r14, r12                    # current length
    # prefix [+-]?[\d.]+ : r15 = index after it (0 if no digits)
    xor ecx, ecx
    movzx eax, byte ptr [r13]
    cmp al, '+'
    je 31f
    cmp al, '-'
    jne 32f
31: inc ecx
32: mov edx, ecx
33: cmp rcx, r14
    jae 34f
    movzx eax, byte ptr [r13 + rcx]
    cmp al, '.'
    je 35f
    cmp al, '0'
    jb 34f
    cmp al, '9'
    ja 34f
35: inc ecx
    jmp 33b
34: xor r15d, r15d
    cmp ecx, edx
    je 40f
    mov r15d, ecx
    # step 2: needs 'e' right after the prefix
    cmp r15, r14
    jae 40f
    cmp byte ptr [r13 + r15], 'e'
    jne 40f
    lea rcx, [r15 + 1]              # after e
    mov rdx, rcx                    # write position
    xor r8d, r8d                    # keep '-'
    cmp rcx, r14
    jae 40f
    movzx eax, byte ptr [r13 + rcx]
    cmp al, '+'
    je 36f
    cmp al, '-'
    jne 37f
    mov r8d, 1
36: inc rcx
37: mov r9, rcx                     # start of zeros
38: cmp rcx, r14
    jae 39f
    cmp byte ptr [r13 + rcx], '0'
    jne 39f
    inc rcx
    jmp 38b
    # 0* must be followed by a digit: back off one zero if none follows
39: cmp rcx, r14
    jae 391f
    movzx eax, byte ptr [r13 + rcx]
    cmp al, '0'
    jb 391f
    cmp al, '9'
    jbe 392f
391: cmp rcx, r9
    je 40f                          # no digit at all after the sign: no match
    dec rcx
392: test r8d, r8d
    jz 393f
    mov byte ptr [r13 + rdx], '-'
    inc rdx
393: # move the rest down to rdx
    mov rdi, r13
    add rdi, rdx
    mov rsi, r13
    add rsi, rcx
    mov r10, r14
    sub r10, rcx
    mov r14, rdx
    add r14, r10
    mov rcx, r10
    rep movsb
    # step 3: ^([+-]?[\d.]+)e[+-]?0+$ -> $1 (prefix unchanged by step 2)
40: test r15, r15
    jz 50f
    cmp r15, r14
    jae 50f
    cmp byte ptr [r13 + r15], 'e'
    jne 50f
    lea rcx, [r15 + 1]
    cmp rcx, r14
    jae 50f
    movzx eax, byte ptr [r13 + rcx]
    cmp al, '+'
    je 41f
    cmp al, '-'
    jne 42f
41: inc rcx
42: cmp rcx, r14
    jae 50f
    mov rdx, rcx
43: cmp rcx, r14
    jae 44f
    cmp byte ptr [r13 + rcx], '0'
    jne 50f
    inc rcx
    jmp 43b
44: cmp rcx, rdx
    je 50f
    mov r14, r15
    # step 4: ^([+-])?\. -> $10.
50: xor ecx, ecx
    movzx eax, byte ptr [r13]
    cmp al, '+'
    je 51f
    cmp al, '-'
    jne 52f
51: inc ecx
52: cmp rcx, r14
    jae 60f
    cmp byte ptr [r13 + rcx], '.'
    jne 60f
    # insert '0' at rcx (buffer has room for 2 extra bytes)
    mov rdx, r14
53: cmp rdx, rcx
    jbe 54f
    mov al, [r13 + rdx - 1]
    mov [r13 + rdx], al
    dec rdx
    jmp 53b
54: mov byte ptr [r13 + rcx], '0'
    inc r14
    # step 5: (\.\d+?)0+(?=e|$): first '.', then digits up to e/end
60: xor ecx, ecx
61: cmp rcx, r14
    jae 70f
    cmp byte ptr [r13 + rcx], '.'
    je 62f
    inc rcx
    jmp 61b
62: lea rdx, [rcx + 1]              # first digit
    mov r8, rdx
63: cmp r8, r14
    jae 64f
    movzx eax, byte ptr [r13 + r8]
    cmp al, '0'
    jb 64f
    cmp al, '9'
    ja 64f
    inc r8
    jmp 63b
    # digits are [rdx, r8); they must end at 'e' or the end
64: cmp r8, r14
    jae 65f
    cmp byte ptr [r13 + r8], 'e'
    jne 70f
65: mov r9, r8                      # strip trailing zeros, keep one digit
66: lea rax, [rdx + 1]
    cmp r9, rax
    jbe 67f
    cmp byte ptr [r13 + r9 - 1], '0'
    jne 67f
    dec r9
    jmp 66b
67: cmp r9, r8
    je 70f
    mov rdi, r13
    add rdi, r9
    mov rsi, r13
    add rsi, r8
    mov rcx, r14
    sub rcx, r8
    sub r14, r8
    add r14, r9
    rep movsb
    # step 6: \.(?=e|$) -> ""
70: xor ecx, ecx
71: cmp rcx, r14
    jae 80f
    cmp byte ptr [r13 + rcx], '.'
    je 72f
    inc rcx
    jmp 71b
72: lea rdx, [rcx + 1]
    cmp rdx, r14
    jae 73f
    cmp byte ptr [r13 + rdx], 'e'
    jne 80f
73: mov rdi, r13
    add rdi, rcx
    mov rsi, r13
    add rsi, rdx
    mov r8, r14
    sub r8, rdx
    dec r14
    mov rcx, r8
    rep movsb
80: mov rax, r13
    mov rdx, r14
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_number

# is_simple_number(ptr, len) -> eax: /^(?:\d+|\d+\.\d+)$/
FUNC is_simple_number
    xor ecx, ecx
    xor edx, edx                    # digits in the current run
    xor r8d, r8d                    # seen '.'
1:  cmp rcx, rsi
    jae 5f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp al, '.'
    je 2f
    cmp al, '0'
    jb 8f
    cmp al, '9'
    ja 8f
    inc edx
    jmp 1b
2:  test r8d, r8d
    jnz 8f
    test edx, edx
    jz 8f
    mov r8d, 1
    xor edx, edx
    jmp 1b
5:  test edx, edx
    jz 8f
    mov eax, 1
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF is_simple_number

# simple_number_is_canonical(ptr, len) -> eax: String(Number(s)) === s for a
# simple number s. Refuses when s has more than 15 significant digits, where
# the answer needs a full double conversion.
FUNC simple_number_is_canonical
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    # integer part [0, r13), fraction (r13, r12)
    xor r13d, r13d
1:  cmp r13, r12
    jae 2f
    cmp byte ptr [rbx + r13], '.'
    je 2f
    inc r13
    jmp 1b
    # a leading zero followed by more integer digits is never canonical
2:  cmp r13, 1
    jbe 3f
    cmp byte ptr [rbx], '0'
    je 8f
3:  cmp r13, r12
    jae 4f
    # fraction: canonical has no trailing zero and something after the dot
    cmp byte ptr [rbx + r12 - 1], '0'
    je 8f
4:  # value >= 1e21 prints with an exponent
    cmp r13, 22
    jae 8f
    # count significant digits; small values below 1e-6 use an exponent
    xor ecx, ecx                    # first nonzero index (in digit order)
    xor r14d, r14d                  # significant digit count
    mov r8, -1                      # index of first nonzero digit
    mov r9, -1                      # index of last nonzero digit
    xor ecx, ecx
    xor edx, edx                    # digit ordinal
5:  cmp rcx, r12
    jae 6f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '.'
    je 5b
    cmp al, '0'
    je 51f
    cmp r8, -1
    jne 52f
    mov r8, rdx
52: mov r9, rdx
51: inc rdx
    jmp 5b
6:  cmp r8, -1
    je 7f                           # zero: "0" or "0.0..." (the latter has a trailing zero)
    mov rax, r9
    sub rax, r8
    inc rax
    cmp rax, 15
    ja 90f
    # integer part "0": count zeros after the dot before the first nonzero
    cmp r13, 1
    jne 7f
    cmp byte ptr [rbx], '0'
    jne 7f
    mov rax, r8
    dec rax                         # zeros between the dot and the digit
    cmp rax, 6
    jae 8f
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "number key with more than 15 significant digits"
ENDF simple_number_is_canonical
