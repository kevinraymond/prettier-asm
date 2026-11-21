# print/block.js
.include "pjs.inc"

SDOC sd_static, "static "

# pjs_print_block(node, args) -> rax doc (printBlock): Program, BlockStatement,
# StaticBlock, TSModuleBlock
FUNC pjs_print_block
    PROLOGUE
    mov rbx, rdi
    call print_block_body
    mov r13, rax                    # bodyDoc
    TYPE rbx, T_Program
    jne 1f
    test r13, r13
    jz 9f
    mov rdi, r13
    lea rsi, [rip + d_hardline]
    call doc_array2
    jmp 9f
1:  DMARK r12
    TYPE rbx, T_StaticBlock
    jne 2f
    DPUSHL sd_static
2:  DPUSHL ps_lbrace
    test r13, r13
    jz 3f
    lea rdi, [rip + d_hardline]
    mov rsi, r13
    call doc_array2
    INDENT_RAX
    DPUSH rax
    DPUSHL d_hardline
    jmp 8f
3:  call path_parent
    movzx ecx, word ptr [rax + N_TYPE]
    cmp ecx, T_ArrowFunctionExpression
    je 8f
    cmp ecx, T_FunctionExpression
    je 8f
    cmp ecx, T_FunctionDeclaration
    je 8f
    cmp ecx, T_ObjectMethod
    je 8f
    cmp ecx, T_ClassMethod
    je 8f
    cmp ecx, T_ClassPrivateMethod
    je 8f
    cmp ecx, T_ForStatement
    je 8f
    cmp ecx, T_WhileStatement
    je 8f
    cmp ecx, T_DoWhileStatement
    je 8f
    cmp ecx, T_TSModuleDeclaration
    je 8f
    TYPE rbx, T_StaticBlock
    je 8f
    cmp ecx, T_CatchClause
    jne 4f
    call path_grandparent
    cmp qword ptr [rax + N_F2], 0   # TryStatement.finalizer
    je 8f
4:  DPUSHL d_hardline
8:  DPUSHL ps_rbrace
    DARRAY r12
9:  EPILOGUE
ENDF pjs_print_block

# print_block_body(node) -> rax doc (printBlockBody), 0 for ""
FUNC print_block_body
    PROLOGUE
    mov rbx, rdi
    xor r13d, r13d                  # hasDirectives
    TYPE rbx, T_StaticBlock
    je 1f
    mov rax, [rbx + N_F1]
    test rax, rax
    jz 1f
    cmp qword ptr [rax], 0
    setne r13b
1:  xor r14d, r14d                  # hasBody
    mov rcx, [rbx + N_F0]
    xor edx, edx
    test rcx, rcx
    jz 3f
2:  cmp rdx, [rcx]
    jae 3f
    mov rax, [rcx + 8 + rdx*8]
    inc rdx
    TYPE rax, T_EmptyStatement
    je 2b
    mov r14d, 1
3:  mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    mov r15d, eax                   # hasDanglingComments
    xor eax, eax
    mov ecx, r13d
    or ecx, r14d
    or ecx, r15d
    jz 9f
    DMARK r12
    test r13d, r13d
    jz 5f
    mov rdi, rbx
    mov esi, K_directives
    mov rdx, [rbx + N_F1]
    call pjs_print_statement_sequence
    DPUSH rax
    mov eax, r14d
    or eax, r15d
    jz 5f
    DPUSHL d_hardline
    mov rdi, [rbx + N_F1]
    call pjs_vec_last
    mov rdi, rax
    call pjs_is_next_line_empty
    test eax, eax
    jz 5f
    DPUSHL d_hardline
5:  test r14d, r14d
    jz 6f
    mov rdi, rbx
    mov esi, K_body
    mov rdx, [rbx + N_F0]
    call pjs_print_statement_sequence
    DPUSH rax
6:  test r15d, r15d
    jz 7f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    DPUSH rax
7:  DARRAY r12
9:  EPILOGUE
ENDF print_block_body
