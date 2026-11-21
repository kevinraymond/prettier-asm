# print/mapped-type.js: printTypeScriptMappedType (the Flow mapped type
# property does not occur)
.include "pjs.inc"

SDOC sd_readonly, "readonly"
SDOC sd_plus_readonly, "+readonly"
SDOC sd_minus_readonly, "-readonly"
SDOC sd_plus_q, "+?"
SDOC sd_minus_q, "-?"
SDOC sd_in_sp, " in "
SDOC sd_as_sp, " as "
SDOC sd_colon_sp, ": "

    .text

# pjs_print_typescript_mapped_type(node, args) -> rax (printTypeScriptMappedType)
FUNC pjs_print_typescript_mapped_type
    PROLOGUE 4
    mov rbx, rdi
    # shouldBreak: objectWrap "preserve" and a newline between "{" and the
    # first token after it
    xor r15d, r15d
    cmp qword ptr [rip + g_object_wrap], OW_PRESERVE
    jne 1f
    mov edi, [rbx + N_START]
    inc edi
    call next_nonspace_noncomment_index
    mov rcx, [rbx + N_F0]
    mov ecx, [rcx + N_START]
    mov esi, [rbx + N_START]
    cmp rax, rcx
    jae 11f
    mov esi, eax
11: mov edi, [rbx + N_START]
    call has_newline_in_range
    mov r15d, eax
1:  lea rax, [rip + d_line]
    cmp qword ptr [rip + g_bracket_spacing], 0
    jne 2f
    lea rax, [rip + d_softline]
2:  mov [rsp], rax                  # line or softline
    # the inner group
    DMARK r12
    mov rax, [rbx + N_F3]           # readonly
    test rax, rax
    jz 3f
    lea rdi, [rip + sd_readonly]
    cmp rax, J_PLUS
    jne 21f
    lea rdi, [rip + sd_plus_readonly]
21: cmp rax, J_MINUS
    jne 22f
    lea rdi, [rip + sd_minus_readonly]
22: lea rsi, [rip + ps_space]
    call doc_array2
    DPUSH rax
3:  DPUSHL ps_lbracket
    PRINT N_F0, K_key
    DPUSH rax
    DPUSHL sd_in_sp
    PRINT N_F1, K_constraint
    DPUSH rax
    cmp qword ptr [rbx + N_F2], 0
    je 4f
    PRINT N_F2, K_nameType
    lea rdi, [rip + sd_as_sp]
    mov rsi, rax
    call doc_array2
    DPUSH rax
4:  DPUSHL ps_rbracket
    mov rax, [rbx + N_F4]           # optional
    test rax, rax
    jz 5f
    lea rdi, [rip + ps_question]
    cmp rax, J_PLUS
    jne 41f
    lea rdi, [rip + sd_plus_q]
41: cmp rax, J_MINUS
    jne 42f
    lea rdi, [rip + sd_minus_q]
42: DPUSH rdi
5:  cmp qword ptr [rbx + N_F5], 0
    je 6f
    DPUSHL sd_colon_sp
6:  PRINT N_F5, K_typeAnnotation
    DPUSH rax
    DARRAY r12
    GROUP_RAX
    mov r13, rax
    # indent([line, dangling ? group([printDanglingComments, hardline]) : "", group, semi ? ifBreak(";") : ""])
    DMARK r12
    DPUSH [rsp]
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jz 7f
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    mov rdi, rax
    lea rsi, [rip + d_hardline]
    call doc_array2
    GROUP_RAX
    DPUSH rax
7:  DPUSH r13
    cmp qword ptr [rip + g_semi], 0
    je 8f
    lea rdi, [rip + ps_semi]
    xor esi, esi
    xor edx, edx
    call doc_if_break
    DPUSH rax
8:  DARRAY r12
    INDENT_RAX
    mov r13, rax
    DMARK r12
    DPUSHL ps_lbrace
    DPUSH r13
    DPUSH [rsp]
    DPUSHL ps_rbrace
    DARRAY r12
    mov rdi, rax
    mov esi, r15d
    call doc_group
    EPILOGUE
ENDF pjs_print_typescript_mapped_type
