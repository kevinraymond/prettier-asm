# print/interface.js: printInterface for TSInterfaceDeclaration
.include "pjs.inc"

SDOC sd_interface, "interface"
SDOC sd_extends_sp, "extends "

    .text

# pjs_print_interface(node, args) -> rax (printInterface)
FUNC pjs_print_interface
    PROLOGUE 6
    mov rbx, rdi
    # shouldIndentOnlyHeritageClauses
    xor r15d, r15d
    mov rdi, [rbx + N_F4]
    test rdi, rdi
    jz 1f
    mov esi, CC_Trailing | CC_Line
    xor edx, edx
    call has_comment
    xor eax, 1
    mov r15d, eax
    # partsGroup = [" ", print("id"), print("typeParameters")]
1:  PRINT N_F0, K_id
    mov [rsp], rax
    PRINT N_F4, K_typeParameters
    mov [rsp + 8], rax
    mov qword ptr [rsp + 16], 0     # extendsParts
    mov r12, [rbx + N_F1]           # extends
    VLEN r13, r12
    test r13, r13
    jz 3f
    mov edi, N_F1
    mov esi, K_extends
    xor edx, edx
    call print_map
    mov r14, rax
    lea rdi, [rip + ps_comma]
    lea rsi, [rip + d_line]
    call doc_array2
    mov rdi, rax
    mov rsi, r14
    call doc_join
    cmp r13, 1
    je 2f
    INDENT_RAX
2:  mov r14, rax
    lea rax, [rip + d_line]
    test r15d, r15d
    jz 21f
    mov rdi, [rbx + N_F4]
    call pjs_get_type_parameters_group_id
    lea rdi, [rip + ps_space]
    lea rsi, [rip + d_line]
    mov rdx, rax
    call doc_if_break
21: mov rdi, rax
    lea rsi, [rip + sd_extends_sp]
    mov rdx, r14
    call doc_array3
    mov [rsp + 16], rax
3:  DMARK r12
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    DPUSHL sd_interface
    test r13, r13
    jnz 4f
    mov rdi, [rbx + N_F0]
    mov esi, CC_Trailing
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 4f
    # parts.push(...partsGroup, ...extendsParts)
    DPUSHL ps_space
    DPUSH [rsp]
    DPUSH [rsp + 8]
    DPUSH [rsp + 16]
    jmp 8f
4:  DMARK r14
    DPUSHL ps_space
    DPUSH [rsp]
    DPUSH [rsp + 8]
    test r15d, r15d
    jz 5f
    # group([...partsGroup, indent(extendsParts)])
    mov rdi, [rsp + 16]
    call doc_indent
    DPUSH rax
    DARRAY r14
    GROUP_RAX
    jmp 6f
    # group(indent([...partsGroup, ...extendsParts]))
5:  DPUSH [rsp + 16]
    DARRAY r14
    INDENT_RAX
    GROUP_RAX
6:  DPUSH rax
8:  DPUSHL ps_space
    PRINT N_F2, K_body
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_interface
