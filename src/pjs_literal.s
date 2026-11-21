# print/literal.js
.include "pjs.inc"

SDOC sd_null, "null"
SDOC sd_true, "true"
SDOC sd_false, "false"

# pjs_print_literal(node) -> rax doc (printLiteral)
FUNC pjs_print_literal
    PROLOGUE
    mov rbx, rdi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_RegExpLiteral
    je 10f
    cmp eax, T_BigIntLiteral
    je 20f
    cmp eax, T_NumericLiteral
    je 30f
    cmp eax, T_StringLiteral
    je 40f
    cmp eax, T_NullLiteral
    je 50f
    cmp eax, T_BooleanLiteral
    je 60f
    cmp eax, T_DirectiveLiteral
    je 70f
    REFUSE "printer: printLiteral"
    # printRegex: `/${pattern}/${[...flags].sort().join("")}`
10: mov r12, [rbx + N_F0]
    mov r13, [rbx + N_F1]
    mov r14, [rbx + N_F2]
    mov r15, [rbx + N_F3]
    lea rdi, [r13 + r15 + 2]
    call alloc
    mov rbx, rax
    mov byte ptr [rbx], '/'
    lea rdi, [rbx + 1]
    mov rsi, r12
    mov rdx, r13
    call memcpy
    mov byte ptr [rbx + r13 + 1], '/'
    lea r12, [rbx + r13 + 2]        # flags
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    call memcpy
    # insertion sort of the flags (ASCII letters)
    mov ecx, 1
11: cmp rcx, r15
    jae 14f
    mov al, [r12 + rcx]
    mov rdx, rcx
12: test rdx, rdx
    jz 13f
    mov r8b, [r12 + rdx - 1]
    cmp r8b, al
    jbe 13f
    mov [r12 + rdx], r8b
    dec rdx
    jmp 12b
13: mov [r12 + rdx], al
    inc rcx
    jmp 11b
14: mov rdi, rbx
    lea rsi, [r13 + r15 + 2]
    call doc_str
    jmp 99f
    # printBigInt: raw.toLowerCase()
20: mov rdi, rbx
    call pjs_raw
    mov r12, rax
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    call alloc_copy
    mov rbx, rax
    xor ecx, ecx
21: cmp rcx, r13
    jae 22f
    mov al, [rbx + rcx]
    cmp al, 'A'
    jb 23f
    cmp al, 'Z'
    ja 23f
    add al, 32
    mov [rbx + rcx], al
23: inc rcx
    jmp 21b
22: mov rdi, rbx
    mov rsi, r13
    call doc_str
    jmp 99f
    # printNumber(raw)
30: mov rdi, rbx
    call pjs_raw
    mov rdi, rax
    mov rsi, rdx
    call print_number
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    jmp 99f
    # replaceEndOfLine(printString(raw, options))
40: mov rdi, rbx
    call pjs_raw
    mov rdi, rax
    mov rsi, rdx
    call print_string
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    jmp 99f
50: lea rax, [rip + sd_null]
    jmp 99f
60: lea rax, [rip + sd_true]
    cmp qword ptr [rbx + N_F0], 0
    jne 99f
    lea rax, [rip + sd_false]
    jmp 99f
    # printDirective(raw): the raw text when the content has a quote, else
    # the content in the preferred enclosing quote
70: mov rdi, rbx
    call pjs_raw
    mov r12, rax
    mov r13, rdx
    mov ecx, 1
71: lea rax, [r13 - 1]
    cmp rcx, rax
    jae 73f
    mov al, [r12 + rcx]
    cmp al, '"'
    je 72f
    cmp al, 0x27
    je 72f
    inc rcx
    jmp 71b
72: mov rdi, r12
    mov rsi, r13
    call doc_str
    jmp 99f
73: mov rdi, r12
    mov rsi, r13
    call alloc_copy
    mov ecx, '"'
    cmp qword ptr [rip + g_single_quote], 0
    je 74f
    mov ecx, 0x27
74: mov [rax], cl
    mov [rax + r13 - 1], cl
    mov rdi, rax
    mov rsi, r13
    call doc_str
99: EPILOGUE
ENDF pjs_print_literal
