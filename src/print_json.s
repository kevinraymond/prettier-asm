# The estree-json printer (src/language-json/printer-estree-json.js), used by
# the json-stringify parser (package.json and friends). Only hard lines, so
# string widths never matter here.
.include "defs.inc"

SDOC sj_lbracket, "["
SDOC sj_rbracket, "]"
SDOC sj_lbrace, "{"
SDOC sj_rbrace, "}"
SDOC sj_empty_array, "[]"
SDOC sj_empty_object, "{}"
SDOC sj_comma, ","
SDOC sj_colon_space, ": "
SDOC sj_null, "null"
SDOC sj_true, "true"
SDOC sj_false, "false"
SDOC sj_minus, "-"

    .section .rodata
hex_digits: .ascii "0123456789abcdef"

    .text

# json_stringify_print_root(root) -> rax: [print(node), hardline]
FUNC json_stringify_print_root
    mov rdi, [rdi + N_F0]
    xor esi, esi
    call sj_print
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    leave
    ret
ENDF json_stringify_print_root

# sj_print(node, is_key) -> rax doc
FUNC sj_print
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ArrayExpression
    je 10f
    cmp eax, T_ObjectExpression
    je 20f
    cmp eax, T_UnaryExpression
    je 30f
    cmp eax, T_NullLiteral
    je 40f
    cmp eax, T_BooleanLiteral
    je 41f
    cmp eax, T_StringLiteral
    je 42f
    cmp eax, T_NumericLiteral
    je 43f
    cmp eax, T_Identifier
    je 44f
    cmp eax, T_TemplateLiteral
    je 45f
    REFUSE "node type not ported (json-stringify)"
    # array
10: mov r13, [rbx + N_F0]
    cmp qword ptr [r13], 0
    jne 11f
    lea rax, [rip + sj_empty_array]
    jmp 99f
11: call ss_mark
    mov r14, rax
    lea rdi, [rip + d_hardline]
    call ss_push
    xor r15d, r15d
12: cmp r15, [r13]
    jae 15f
    test r15, r15
    jz 13f
    lea rdi, [rip + sj_comma]
    call ss_push
    lea rdi, [rip + d_hardline]
    call ss_push
13: mov rdi, [r13 + 8 + r15*8]
    lea rax, [rip + sj_null]
    test rdi, rdi
    jz 14f
    xor esi, esi
    call sj_print
14: mov rdi, rax
    call ss_push
    inc r15
    jmp 12b
15: lea rdi, [rip + sj_lbracket]
    lea rsi, [rip + sj_rbracket]
    jmp 50f
    # object
20: mov r13, [rbx + N_F0]
    cmp qword ptr [r13], 0
    jne 21f
    lea rax, [rip + sj_empty_object]
    jmp 99f
21: call ss_mark
    mov r14, rax
    lea rdi, [rip + d_hardline]
    call ss_push
    xor r15d, r15d
22: cmp r15, [r13]
    jae 25f
    test r15, r15
    jz 23f
    lea rdi, [rip + sj_comma]
    call ss_push
    lea rdi, [rip + d_hardline]
    call ss_push
23: mov rax, [r13 + 8 + r15*8]
    mov rdi, [rax + N_F0]
    mov esi, 1
    call sj_print
    mov rdi, rax
    call ss_push
    lea rdi, [rip + sj_colon_space]
    call ss_push
    mov rax, [r13 + 8 + r15*8]
    mov rdi, [rax + N_F1]
    xor esi, esi
    call sj_print
    mov rdi, rax
    call ss_push
    inc r15
    jmp 22b
25: lea rdi, [rip + sj_lbrace]
    lea rsi, [rip + sj_rbrace]
    # [open, indent([hardline, ...]), hardline, close]
50: mov [rsp], rsi
    mov r15, rdi
    mov rdi, r14
    call ss_to_array
    mov rdi, rax
    call doc_indent
    mov r13, rax
    call ss_mark
    mov r14, rax
    mov rdi, r15
    call ss_push
    mov rdi, r13
    call ss_push
    lea rdi, [rip + d_hardline]
    call ss_push
    mov rdi, [rsp]
    call ss_push
    mov rdi, r14
    call ss_to_array
    jmp 99f
    # unary: "+" prints nothing
30: mov rdi, [rbx + N_F0]
    xor esi, esi
    call sj_print
    cmp byte ptr [rbx + N_F1], '-'
    jne 99f
    lea rdi, [rip + sj_minus]
    mov rsi, rax
    call doc_array2
    jmp 99f
40: lea rax, [rip + sj_null]
    jmp 99f
41: lea rax, [rip + sj_true]
    cmp qword ptr [rbx + N_F0], 0
    jne 99f
    lea rax, [rip + sj_false]
    jmp 99f
42: mov rdi, [rbx + N_F0]
    mov rsi, [rbx + N_F1]
    call json_quote
    jmp 98f
    # number: JSON.stringify(value), or JSON.stringify(String(value)) as a key
43: mov edi, [rbx + N_START]
    mov esi, [rbx + N_END]
    call js_number_string
    test r12d, r12d
    jnz 47f
    # JSON.stringify(Infinity) is "null"
    test ecx, ecx
    jz 98f
    lea rax, [rip + sj_null]
    jmp 99f
47:
    mov rdi, rax
    mov rsi, rdx
    call json_quote
    jmp 98f
44: mov edi, [rbx + N_START]
    add rdi, [rip + g_text]
    mov esi, [rbx + N_END]
    sub esi, [rbx + N_START]
    test r12d, r12d
    jz 46f
    call json_quote
    jmp 98f
46: mov rax, rdi
    mov rdx, rsi
    jmp 98f
    # template literal: JSON.stringify(quasis[0].value.cooked)
45: mov rax, [rbx + N_F0]
    mov rax, [rax + 8]
    mov rdi, [rax + N_F0]
    mov rsi, [rax + N_F1]
    call json_quote
98: mov rdi, rax
    mov rsi, rdx
    call doc_str
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF sj_print

# json_quote(ptr, len) -> rax = ptr, rdx = len: JSON.stringify of a string
# held as WTF-8 (lone surrogates as 3-byte sequences).
FUNC json_quote
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    imul rdi, r12, 6                # worst case: every byte as \u00xx
    add rdi, 2
    call alloc
    mov r13, rax
    mov rdi, rax
    mov byte ptr [rdi], '"'
    inc rdi
    xor ecx, ecx
    lea r14, [rip + hex_digits]
1:  cmp rcx, r12
    jae 9f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '"'
    je 2f
    cmp al, '\\'
    je 2f
    cmp al, 0x20
    jb 3f
    cmp al, 0xED
    jne 8f
    # ED A0..BF xx is a lone surrogate: \udxxx
    cmp rcx, r12
    jae 8f
    movzx edx, byte ptr [rbx + rcx]
    cmp dl, 0xA0
    jb 8f
    movzx r8d, byte ptr [rbx + rcx + 1]
    add rcx, 2
    and edx, 0x3F
    shl edx, 6
    and r8d, 0x3F
    or edx, r8d
    or edx, 0xD000
    mov dword ptr [rdi], 0x0064755C     # "\ud" (the 4th byte is overwritten)
    add rdi, 2
    mov eax, edx
    shr eax, 12
    and eax, 15
    mov al, [r14 + rax]
    mov [rdi], al
    mov eax, edx
    shr eax, 8
    and eax, 15
    mov al, [r14 + rax]
    mov [rdi + 1], al
    mov eax, edx
    shr eax, 4
    and eax, 15
    mov al, [r14 + rax]
    mov [rdi + 2], al
    mov eax, edx
    and eax, 15
    mov al, [r14 + rax]
    mov [rdi + 3], al
    add rdi, 4
    jmp 1b
2:  mov byte ptr [rdi], '\\'
    mov [rdi + 1], al
    add rdi, 2
    jmp 1b
3:  mov edx, 'b'
    cmp al, 8
    je 4f
    mov edx, 'f'
    cmp al, 12
    je 4f
    mov edx, 'n'
    cmp al, 10
    je 4f
    mov edx, 'r'
    cmp al, 13
    je 4f
    mov edx, 't'
    cmp al, 9
    je 4f
    mov dword ptr [rdi], 0x3030755C     # "\u00"
    mov edx, eax
    shr edx, 4
    mov dl, [r14 + rdx]
    mov [rdi + 4], dl
    and eax, 15
    mov al, [r14 + rax]
    mov [rdi + 5], al
    add rdi, 6
    jmp 1b
4:  mov byte ptr [rdi], '\\'
    mov [rdi + 1], dl
    add rdi, 2
    jmp 1b
8:  mov [rdi], al
    inc rdi
    jmp 1b
9:  mov byte ptr [rdi], '"'
    inc rdi
    mov rax, r13
    mov rdx, rdi
    sub rdx, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF json_quote

# js_number_string(start, end) -> rax = ptr, rdx = len: String(value) of the
# numeric literal text[start:end]; rcx = 1 when the value is Infinity. Refuses where that needs more than the
# exact cases: over 15 significant digits, integers above 2^53, values
# outside [1e-300, 1e300].
FUNC js_number_string
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov rbx, [rip + g_text]
    add rbx, rdi                    # p
    mov r12, rsi
    sub r12, rdi                    # len
    # radix literals and legacy octal
    cmp r12, 2
    jb 20f
    cmp byte ptr [rbx], '0'
    jne 20f
    movzx eax, byte ptr [rbx + 1]
    or al, 0x20
    mov ecx, 16
    cmp al, 'x'
    je 10f
    mov ecx, 8
    cmp al, 'o'
    je 10f
    mov ecx, 2
    cmp al, 'b'
    je 10f
    movzx eax, byte ptr [rbx + 1]
    cmp al, '0'
    jb 20f
    cmp al, '9'
    ja 20f
    # legacy octal 0[0-7]+; a leading zero with an 8 or 9 is a decimal
    mov r13d, 1
101: cmp r13, r12
    jae 102f
    movzx eax, byte ptr [rbx + r13]
    inc r13
    cmp al, '8'
    je 20f
    cmp al, '9'
    je 20f
    jmp 101b
102: mov ecx, 8
    mov r13d, 1
    jmp 11f
10: mov r13d, 2
11: xor r14d, r14d                  # value
12: cmp r13, r12
    jae 15f
    movzx edi, byte ptr [rbx + r13]
    inc r13
    cmp dil, '_'
    je 12b
    push rcx
    sub rsp, 8
    call hex_val
    add rsp, 8
    pop rcx
    imul r14, rcx
    jo 90f
    add r14, rax
    mov rax, 1 << 53
    cmp r14, rax
    ja 90f
    jmp 12b
    # integer to decimal
15: lea rdi, [rsp + 39]
    mov rax, r14
    mov ecx, 10
16: xor edx, edx
    div rcx
    add dl, '0'
    mov [rdi], dl
    dec rdi
    test rax, rax
    jnz 16b
    lea rsi, [rdi + 1]
    lea rdx, [rsp + 40]
    sub rdx, rsi
    mov rdi, rsi
    mov rsi, rdx
    call alloc_copy_len
    jmp 99f

    # decimal: digits of int and fraction without '_', exponent
20: mov rdi, r12
    add rdi, 32
    call alloc
    mov r13, rax                    # digit buffer S
    xor ecx, ecx                    # read index
    xor r14d, r14d                  # S length
    xor r15d, r15d                  # int digit count
21: cmp rcx, r12
    jae 25f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, '_'
    je 22f
    cmp al, '.'
    je 23f
    cmp al, '0'
    jb 25f
    cmp al, '9'
    ja 24f
    mov [r13 + r14], al
    inc r14
    inc r15
22: inc rcx
    jmp 21b
23: inc rcx
230: cmp rcx, r12
    jae 25f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, '_'
    je 231f
    cmp al, '0'
    jb 25f
    cmp al, '9'
    ja 24f
    mov [r13 + r14], al
    inc r14
231: inc rcx
    jmp 230b
    # exponent
24: xor r8d, r8d                    # exponent value
    xor r9d, r9d                    # negative
    inc rcx                         # 'e'
    movzx eax, byte ptr [rbx + rcx]
    cmp al, '+'
    je 241f
    cmp al, '-'
    jne 242f
    mov r9d, 1
241: inc rcx
242: cmp rcx, r12
    jae 243f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '_'
    je 242b
    sub eax, '0'
    imul r8, r8, 10
    add r8, rax
    cmp r8, 100000
    jbe 242b
    mov r8d, 100000                 # saturate: far outside the double range
    jmp 242b
243: test r9d, r9d
    jz 244f
    neg r8
244: jmp 26f
25: xor r8d, r8d
    # strip leading zeros: p = intDigits - lz + E
26: xor ecx, ecx
27: cmp rcx, r14
    jae 28f
    cmp byte ptr [r13 + rcx], '0'
    jne 28f
    inc rcx
    jmp 27b
28: mov rax, r15
    sub rax, rcx
    add rax, r8
    mov [rsp], rax                  # n (point position)
    add r13, rcx
    sub r14, rcx
    # strip trailing zeros
29: test r14, r14
    jz 30f
    cmp byte ptr [r13 + r14 - 1], '0'
    jne 31f
    dec r14
    jmp 29b
    # zero
30: lea rdi, [rip + s_zero]
    mov esi, 1
    call alloc_copy_len
    jmp 99f
.Lnum_infinity:
    lea rdi, [rip + s_infinity]
    mov esi, 8
    call alloc_copy_len
    mov ecx, 1
    jmp 991f
    # value = 0.D x 10^n: n >= 310 is at least 1e309 and overflows to
    # Infinity; n <= -324 is below 1e-324, under half the smallest subnormal
    # (4.9e-324), and rounds to 0. Nearer the limits a full conversion is needed.
31: mov rax, [rsp]
    cmp rax, 310
    jge .Lnum_infinity
    cmp rax, -324
    jle 30b
    cmp r14, 15
    ja 90f
    cmp rax, 300
    jg 90f
    cmp rax, -300
    jl 90f
    # format as Number::toString
    mov rdi, r14
    add rdi, 32
    call alloc
    mov r15, rax                    # out
    mov rdi, rax
    mov rax, [rsp]                  # n
    mov rcx, r14                    # k
    cmp rax, rcx
    jl 40f
    cmp rax, 21
    jg 50f
    # digits then n-k zeros
    mov rsi, r13
    rep movsb
    mov rcx, rax
    sub rcx, r14
    mov al, '0'
    rep stosb
    jmp 60f
40: test rax, rax
    jle 45f
    # digits with the point after n of them (n <= 21 holds since n < k <= 15)
    mov rcx, rax
    mov rsi, r13
    rep movsb
    mov byte ptr [rdi], '.'
    inc rdi
    mov rcx, r14
    sub rcx, rax
    rep movsb
    jmp 60f
45: cmp rax, -6
    jle 50f
    mov word ptr [rdi], 0x2E30          # "0."
    add rdi, 2
    mov rcx, rax
    neg rcx
    mov al, '0'
    rep stosb
    mov rcx, r14
    mov rsi, r13
    rep movsb
    jmp 60f
    # exponent form d[.ddd]e(+|-)x with x = n - 1
50: mov al, [r13]
    mov [rdi], al
    inc rdi
    cmp r14, 1
    je 51f
    mov byte ptr [rdi], '.'
    inc rdi
    lea rsi, [r13 + 1]
    mov rcx, r14
    dec rcx
    rep movsb
51: mov byte ptr [rdi], 'e'
    inc rdi
    mov rax, [rsp]
    dec rax
    mov byte ptr [rdi], '+'
    test rax, rax
    jns 52f
    mov byte ptr [rdi], '-'
    neg rax
52: inc rdi
    # decimal digits of rax
    lea r8, [rsp + 39]
    mov ecx, 10
53: xor edx, edx
    div rcx
    add dl, '0'
    mov [r8], dl
    dec r8
    test rax, rax
    jnz 53b
    lea rsi, [r8 + 1]
    lea rcx, [rsp + 40]
    sub rcx, rsi
    rep movsb
60: mov rax, r15
    mov rdx, rdi
    sub rdx, r15
99: xor ecx, ecx
991: add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "number needs a full double conversion (json-stringify)"
ENDF js_number_string

    .section .rodata
s_zero: .ascii "0"
s_infinity: .ascii "Infinity"
    .text

# alloc_copy_len(ptr, len) -> rax = copy, rdx = len
FUNC alloc_copy_len
    push rsi
    sub rsp, 8
    call alloc_copy
    add rsp, 8
    pop rdx
    leave
    ret
ENDF alloc_copy_len
