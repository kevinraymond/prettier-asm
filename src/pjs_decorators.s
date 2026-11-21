# print/decorators.js
.include "pjs.inc"

    .bss
decorators_slot: .space T_COUNT     # per type: 0 not looked up, 0xff none, else the slot offset
    .section .rodata
s_decorators: .asciz "decorators"
    .text

# pjs_decorators_slot(node) -> eax: the field offset of node.decorators, or 0 when
# the type has none (from the type's field descriptors)
FUNC pjs_decorators_slot
    PROLOGUE
    movzx r12d, word ptr [rdi + N_TYPE]
    lea r13, [rip + decorators_slot]
    movzx eax, byte ptr [r13 + r12]
    test eax, eax
    jnz 5f
    lea rax, [rip + ast_type_fields]
    mov r14, [rax + r12*8]
    xor r15d, r15d                  # lists passed
1:  movzx eax, byte ptr [r14]
    test eax, eax
    jnz 2f
    inc r14
    inc r15d
    cmp r15d, 2
    jb 1b
    mov eax, 0xff
    jmp 4f
2:  lea rdi, [r14 + 2]
    lea rsi, [rip + s_decorators]
    call cstr_eq
    test eax, eax
    jz 3f
    movzx eax, byte ptr [r14 + 1]
    jmp 4f
3:  lea rdi, [r14 + 2]
    call strlen
    lea r14, [r14 + rax + 3]
    jmp 1b
4:  mov [r13 + r12], al
5:  cmp eax, 0xff
    jne 9f
    xor eax, eax
9:  EPILOGUE
ENDF pjs_decorators_slot

# pjs_get_decorators(node) -> rax: node.decorators when non-empty, else 0
# (isNonEmptyArray(node.decorators)); node may be 0
FUNC pjs_get_decorators
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    test rbx, rbx
    jz 9f
    call pjs_decorators_slot
    test eax, eax
    jz 9f
    mov rax, [rbx + rax]
    test rax, rax
    jz 9f
    cmp qword ptr [rax], 0
    jne 9f
    xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF pjs_get_decorators

# pdc_has_newline_between_or_after(node) -> eax (hasNewlineBetweenOrAfterDecorators)
FUNC pdc_has_newline_between_or_after
    PROLOGUE
    call pjs_get_decorators
    mov rbx, rax
    xor r12d, r12d
1:  xor eax, eax
    cmp r12, [rbx]
    jae 9f
    mov rax, [rbx + 8 + r12*8]
    inc r12
    mov edi, [rax + N_END]
    xor esi, esi
    call has_newline
    test eax, eax
    jz 1b
9:  EPILOGUE
ENDF pdc_has_newline_between_or_after

# pdc_has_decorators_before_export(node) -> eax (hasDecoratorsBeforeExport):
# an export whose declaration's first decorator starts where the export does
# (locStart of the export takes in that decorator)
FUNC pdc_has_decorators_before_export
    PROLOGUE
    mov rbx, rdi
    xor eax, eax
    test rbx, rbx
    jz 9f
    TYPE rbx, T_ExportDefaultDeclaration
    je 1f
    TYPE rbx, T_ExportNamedDeclaration
    jne 9f
1:  mov rdi, [rbx + N_F0]           # declaration
    call pjs_get_decorators
    test rax, rax
    jz 9f
    mov rax, [rax + 8]
    mov ecx, [rax + N_START]        # locStart(decorators[0])
    mov edx, [rbx + N_START]
    cmp ecx, edx
    cmovb edx, ecx                  # locStart(node)
    xor eax, eax
    cmp ecx, edx
    sete al
9:  EPILOGUE
ENDF pdc_has_decorators_before_export

# pdc_join_decorators(separator, slot) -> rax: join(separator, path.map(print,
# "decorators")) for the node at the top of the path
FUNC pdc_join_decorators
    PROLOGUE
    mov rbx, rdi
    mov edi, esi
    mov esi, K_decorators
    xor edx, edx
    call print_map
    mov rdi, rbx
    mov rsi, rax
    call doc_join
    EPILOGUE
ENDF pdc_join_decorators

# pjs_print_class_member_decorators(node) -> rax (printClassMemberDecorators):
# group([join(line, decorators), hasNewlineBetweenOrAfterDecorators ? hardline : line])
FUNC pjs_print_class_member_decorators
    PROLOGUE
    mov rbx, rdi
    call pjs_decorators_slot
    lea rdi, [rip + d_line]
    mov esi, eax
    call pdc_join_decorators
    mov r12, rax
    mov rdi, rbx
    call pdc_has_newline_between_or_after
    lea rsi, [rip + d_line]
    test eax, eax
    jz 1f
    lea rsi, [rip + d_hardline]
1:  mov rdi, r12
    call doc_array2
    GROUP_RAX
    EPILOGUE
ENDF pjs_print_class_member_decorators

# pjs_print_decorators_before_export(node) -> rax (printDecoratorsBeforeExport):
# [join(hardline, path.map(print, "declaration", "decorators")), hardline] or ""
FUNC pjs_print_decorators_before_export
    PROLOGUE
    mov rbx, rdi
    call pdc_has_decorators_before_export
    test eax, eax
    jz 9f
    mov r12, [rbx + N_F0]
    mov rdi, r12
    mov esi, K_declaration
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    call pjs_decorators_slot
    lea rdi, [rip + d_hardline]
    mov esi, eax
    call pdc_join_decorators
    mov r13, rax
    call path_pop
    mov rdi, r13
    lea rsi, [rip + d_hardline]
    call doc_array2
    jmp 99f
9:  xor eax, eax
99: EPILOGUE
ENDF pjs_print_decorators_before_export

# pjs_print_decorators(node) -> rax (printDecorators), 0 for ""
FUNC pjs_print_decorators
    PROLOGUE
    mov rbx, rdi
    call pjs_get_decorators
    test rax, rax
    jz 8f
    call path_parent
    mov r12, rax
    mov rdi, r12
    call pdc_has_decorators_before_export
    test eax, eax
    jnz 8f
    call pjs_is_ignored
    test eax, eax
    jnz 8f
    DMARK r13
    call path_key
    cmp eax, K_declaration
    jne 1f
    mov rdi, r12
    call pjs_is_export_declaration
    test eax, eax
    jz 1f
    DPUSHL d_hardline
    jmp 3f
1:  TYPE rbx, T_ClassExpression
    je 2f
    TYPE rbx, T_ClassDeclaration
    je 2f
    mov rdi, rbx
    call pdc_has_newline_between_or_after
    test eax, eax
    jz 3f
2:  DPUSHL d_break_parent
3:  mov rdi, rbx
    call pjs_decorators_slot
    lea rdi, [rip + d_line]
    mov esi, eax
    call pdc_join_decorators
    DPUSH rax
    DPUSHL d_line
    DARRAY r13
    jmp 99f
8:  xor eax, eax
99: EPILOGUE
ENDF pjs_print_decorators

# pjs_print_decorator(node, args) -> rax: ["@", print("expression")]
FUNC pjs_print_decorator
    PRINT N_F0, K_expression
    lea rdi, [rip + pdc_at]
    mov rsi, rax
    call doc_array2
    leave
    ret
ENDF pjs_print_decorator

SDOC pdc_at, "@"
