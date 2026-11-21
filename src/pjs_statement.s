# print/statement.js
.include "pjs.inc"

# pjs_print_statement_sequence(node, key, vec) -> rax doc (printStatementSequence):
# the statements of node[key] (vec) without EmptyStatements, a hardline after
# each but the last, and another where the source has a blank line
FUNC pjs_print_statement_sequence
    PROLOGUE
    mov rbx, rdx                    # vec
    mov r12d, esi                   # key
    # lastStatement: the last that is not an EmptyStatement
    xor r15d, r15d
    VLEN rcx, rbx
1:  test rcx, rcx
    jz 2f
    mov rax, [rbx + rcx*8]
    dec rcx
    TYPE rax, T_EmptyStatement
    je 1b
    mov r15, rax
2:  DMARK r13
    xor r14d, r14d
3:  VLEN rax, rbx
    cmp r14, rax
    jae 9f
    mov rax, [rbx + 8 + r14*8]
    TYPE rax, T_EmptyStatement
    je 5f
    mov rdi, rbx
    mov rsi, r14
    mov edx, r12d
    xor ecx, ecx
    call print_elem
    DPUSH rax
    mov rax, [rbx + 8 + r14*8]
    cmp rax, r15
    je 5f
    DPUSHL d_hardline
    mov rdi, [rbx + 8 + r14*8]
    call pjs_is_next_line_empty
    test eax, eax
    jz 5f
    DPUSHL d_hardline
5:  inc r14
    jmp 3b
9:  DARRAY r13
    EPILOGUE
ENDF pjs_print_statement_sequence
