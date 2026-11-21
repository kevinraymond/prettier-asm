# formatWithCursor / coreFormat (src/main/core.js) for the default options.
.include "defs.inc"

# format_input() -> rax = 1 if the output must start with a BOM.
# The formatted text is left in the output buffer.
FUNC format_input
    push rbx
    sub rsp, 8
    call text_prepare
    # coreFormat: blank input formats to ""
    call text_is_blank
    test eax, eax
    jz 1f
    cmp qword ptr [rip + g_debug_doc], 0
    je 9f
1:  cmp qword ptr [rip + g_parser], P_BABEL
    je 11f
    cmp qword ptr [rip + g_parser], P_TYPESCRIPT
    jne 2f
11:
    call js_source_is_script
    mov edi, eax
    call js_parse
    mov rdi, rax
    call pjs_print_root
    mov rbx, rax
    jmp 6f
2:  call json_parse
    mov rbx, rax
    cmp qword ptr [rip + g_parser], P_JSON_STRINGIFY
    je 5f
    lea rax, [rip + estree_printer]
    mov [rip + g_printer], rax
    mov rdi, rbx
    call attach_comments
    mov rdi, rbx
    call estree_print_root
    mov rbx, rax
    call ensure_all_comments_printed
    jmp 6f
5:  mov rdi, rbx
    call json_stringify_print_root
    mov rbx, rax
6:  cmp qword ptr [rip + g_debug_doc], 0
    jne 7f
    mov rdi, rbx
    call print_doc
9:  mov rax, [rip + g_has_bom]
    add rsp, 8
    pop rbx
    leave
    ret
    # --debug-doc: the doc in canonical text instead of the formatted text
7:  mov rdi, rbx
    call doc_dump
    mov edi, 10
    call out_byte
    xor eax, eax
    add rsp, 8
    pop rbx
    leave
    ret
ENDF format_input
