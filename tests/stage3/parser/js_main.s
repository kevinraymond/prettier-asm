# Standalone entry for the JS parser, linked by tests/stage3/parser/build.sh with the parser
# and core files only, so parser work can be tested while other parts of src/ are in flux.
# `js-parse --debug-ast --stdin-filepath x.js < x.js` behaves as prettier-asm does.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_filepath, g_from_stdin
g_filepath:   .quad 0
g_from_stdin: .quad 0

    .section .rodata
s_unsupported: .asciz "unsupported: "
s_newline:     .asciz "\n"
s_no_mode:     .asciz "--debug-ast or --debug-parse expected"

    .text
    .globl _start
_start:
    mov rdi, [rsp]
    lea rsi, [rsp + 8]
    and rsp, -16
    push rdi
    push rsi
    call mem_init
    pop rsi
    pop rdi
    call js_debug_scan
    lea rdi, [rip + s_no_mode]
    call refuse

# refuse(reason): never returns
FUNC refuse
    push rdi
    sub rsp, 8
    mov edi, 2
    lea rsi, [rip + s_unsupported]
    call write_cstr
    mov rsi, [rsp + 8]
    mov edi, 2
    call write_cstr
    mov edi, 2
    lea rsi, [rip + s_newline]
    call write_cstr
    mov edi, 3
    call sys_exit
ENDF refuse
