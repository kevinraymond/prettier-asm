# print/enum.js for TSEnumDeclaration, TSEnumBody and TSEnumMember
.include "pjs.inc"

SDOC sd_const_sp, "const "
SDOC sd_enum_sp, "enum "
SDOC sd_eq_sp, " = "

    .text

# pjs_print_enum_declaration(node, args) -> rax (printEnumDeclaration)
FUNC pjs_print_enum_declaration
    PROLOGUE
    mov rbx, rdi
    DMARK r12
    mov rdi, rbx
    call pjs_print_declare_token
    DPUSH rax
    ATTR rbx, NA_CONST
    jz 1f
    DPUSHL sd_const_sp
1:  DPUSHL sd_enum_sp
    PRINT N_F0, K_id
    DPUSH rax
    DPUSHL ps_space
    PRINT N_F1, K_body
    DPUSH rax
    DARRAY r12
    EPILOGUE
ENDF pjs_print_enum_declaration

# pjs_print_enum_body(node, args) -> rax (printEnumBody): printObject
FUNC pjs_print_enum_body
    call pjs_print_object
    leave
    ret
ENDF pjs_print_enum_body

# pjs_print_enum_member(node, args) -> rax (printEnumMember); Babel 7 has no
# computed members
FUNC pjs_print_enum_member
    PROLOGUE
    mov rbx, rdi
    PRINT N_F0, K_id
    cmp qword ptr [rbx + N_F1], 0
    je 9f
    mov r12, rax
    PRINT N_F1, K_initializer
    mov rdi, r12
    lea rsi, [rip + sd_eq_sp]
    mov rdx, rax
    call doc_array3
9:  EPILOGUE
ENDF pjs_print_enum_member
