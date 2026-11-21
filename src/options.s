# Format options and the CLI flags that set them. Defaults are Prettier's.
# Only the options listed in opt_table are ported; any other flag is refused.
.include "defs.inc"

    .data
    .balign 8
    .globl g_tab_width, g_use_tabs, g_single_quote, g_quote_props
    .globl g_trailing_comma, g_bracket_spacing, g_object_wrap
    .globl g_semi, g_bracket_same_line, g_experimental_ternaries, g_arrow_parens
    .globl g_operator_position, g_embedded_off
g_tab_width:      .quad 2
g_use_tabs:       .quad 0
g_single_quote:   .quad 0
g_quote_props:    .quad QP_AS_NEEDED
g_trailing_comma: .quad TC_ALL
g_bracket_spacing: .quad 1
g_object_wrap:    .quad OW_PRESERVE
g_semi:           .quad 1
g_bracket_same_line: .quad 0
g_experimental_ternaries: .quad 0
g_arrow_parens:   .quad AP_ALWAYS
g_operator_position: .quad OP_END
g_embedded_off:   .quad 0
# one byte per opt_table entry: set once
g_opt_seen:       .space 16

    .section .rodata
s_print_width:    .asciz "--print-width"
s_tab_width:      .asciz "--tab-width"
s_use_tabs:       .asciz "--use-tabs"
s_single_quote:   .asciz "--single-quote"
s_no_bracket:     .asciz "--no-bracket-spacing"
s_quote_props:    .asciz "--quote-props"
s_trailing_comma: .asciz "--trailing-comma"
s_object_wrap:    .asciz "--object-wrap"
s_no_semi:        .asciz "--no-semi"
s_bracket_same_line: .asciz "--bracket-same-line"
s_experimental_ternaries: .asciz "--experimental-ternaries"
s_arrow_parens:   .asciz "--arrow-parens"
s_operator_position: .asciz "--experimental-operator-position"
s_embedded:       .asciz "--embedded-language-formatting"
s_always:         .asciz "always"
s_avoid:          .asciz "avoid"
s_start:          .asciz "start"
s_end:            .asciz "end"
s_auto:           .asciz "auto"
s_off:            .asciz "off"
s_as_needed:      .asciz "as-needed"
s_consistent:     .asciz "consistent"
s_preserve:       .asciz "preserve"
s_all:            .asciz "all"
s_es5:            .asciz "es5"
s_none:           .asciz "none"
s_collapse:       .asciz "collapse"

.equ OK_FLAG, 1         # sets the target to the entry's value
.equ OK_INT, 2          # integer in [1, value]
.equ OK_ENUM, 3         # value names a list of (cstr, number) pairs ending in 0

    .balign 8
# entry: name, kind, target, value
opt_table:
    .quad s_print_width, OK_INT, g_print_width, 1000
    .quad s_tab_width, OK_INT, g_tab_width, 64
    .quad s_use_tabs, OK_FLAG, g_use_tabs, 1
    .quad s_single_quote, OK_FLAG, g_single_quote, 1
    .quad s_no_bracket, OK_FLAG, g_bracket_spacing, 0
    .quad s_quote_props, OK_ENUM, g_quote_props, enum_quote_props
    .quad s_trailing_comma, OK_ENUM, g_trailing_comma, enum_trailing_comma
    .quad s_object_wrap, OK_ENUM, g_object_wrap, enum_object_wrap
    .quad s_no_semi, OK_FLAG, g_semi, 0
    .quad s_bracket_same_line, OK_FLAG, g_bracket_same_line, 1
    .quad s_experimental_ternaries, OK_FLAG, g_experimental_ternaries, 1
    .quad s_arrow_parens, OK_ENUM, g_arrow_parens, enum_arrow_parens
    .quad s_operator_position, OK_ENUM, g_operator_position, enum_operator_position
    .quad s_embedded, OK_ENUM, g_embedded_off, enum_embedded
    .quad 0
enum_quote_props:
    .quad s_as_needed, QP_AS_NEEDED, s_consistent, QP_CONSISTENT, s_preserve, QP_PRESERVE, 0
enum_trailing_comma:
    .quad s_all, TC_ALL, s_es5, TC_ES5, s_none, TC_NONE, 0
enum_object_wrap:
    .quad s_preserve, OW_PRESERVE, s_collapse, OW_COLLAPSE, 0
enum_arrow_parens:
    .quad s_always, AP_ALWAYS, s_avoid, AP_AVOID, 0
enum_operator_position:
    .quad s_end, OP_END, s_start, OP_START, 0
enum_embedded:
    .quad s_auto, 0, s_off, 1, 0

    .text

# match_flag(arg, name) -> rax = 0 (no), 1 (exact), or pointer to the value
# after "name="
FUNC match_flag
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call cstr_prefix
    test eax, eax
    jz 9f
    mov rdi, r12
    call strlen
    movzx ecx, byte ptr [rbx + rax]
    test ecx, ecx
    jz 1f
    cmp ecx, '='
    jne 8f
    lea rax, [rbx + rax + 1]
    jmp 9f
1:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF match_flag

# parse_option(arg, next_arg_or_0) -> rax = number of arguments used
# (0 when arg is not a ported option). Refuses bad values and repeats.
FUNC parse_option
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    lea rbx, [rip + opt_table]
    xor r15d, r15d                  # entry index
1:  mov rsi, [rbx]
    test rsi, rsi
    jz 80f
    mov rdi, r12
    call match_flag
    test rax, rax
    jnz 2f
    add rbx, 32
    inc r15
    jmp 1b
2:  lea rcx, [rip + g_opt_seen]
    cmp byte ptr [rcx + r15], 0
    jne 90f
    mov byte ptr [rcx + r15], 1
    mov r14, rax                    # 1 or value pointer
    mov rax, [rbx + 8]
    cmp rax, OK_FLAG
    jne 3f
    cmp r14, 1
    jne 91f                         # `--flag=value` is not ported
    mov rax, [rbx + 24]
    mov rcx, [rbx + 16]
    mov [rcx], rax
    mov eax, 1
    jmp 99f
    # options with a value: inline after `=` or the next argument
3:  mov qword ptr [rsp], 1
    cmp r14, 1
    jne 4f
    test r13, r13
    jz 91f
    mov r14, r13
    mov qword ptr [rsp], 2
4:  mov rax, [rbx + 8]
    cmp rax, OK_INT
    jne 6f
    # decimal digits only, no leading zero, within [1, max]
    xor eax, eax
    mov rcx, r14
    cmp byte ptr [rcx], '0'
    je 91f
5:  movzx edx, byte ptr [rcx]
    test edx, edx
    jz 51f
    sub edx, '0'
    cmp edx, 9
    ja 91f
    imul rax, rax, 10
    add rax, rdx
    cmp rax, [rbx + 24]
    ja 91f
    inc rcx
    jmp 5b
51: cmp rcx, r14
    je 91f
    mov rcx, [rbx + 16]
    mov [rcx], rax
    mov rax, [rsp]
    jmp 99f
6:  mov r15, [rbx + 24]             # enum list
7:  mov rsi, [r15]
    test rsi, rsi
    jz 91f
    mov rdi, r14
    call cstr_eq
    test eax, eax
    jnz 71f
    add r15, 16
    jmp 7b
71: mov rax, [r15 + 8]
    mov rcx, [rbx + 16]
    mov [rcx], rax
    mov rax, [rsp]
    jmp 99f
80: xor eax, eax
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "option given twice"
91: REFUSE "option value not ported"
ENDF parse_option

# option_from_config(index, value): a value from a config file, for the
# opt_table entry at index. Flags on the command line win.
FUNC option_from_config
    lea rax, [rip + g_opt_seen]
    cmp byte ptr [rax + rdi], 0
    jne 1f
    lea rax, [rip + opt_table]
    shl rdi, 5
    mov rax, [rax + rdi + 16]
    mov [rax], rsi
1:  leave
    ret
ENDF option_from_config

# options_for_parser(): normalizeFormatOptions forces trailingComma "none"
# for the json parser.
FUNC options_for_parser
    cmp qword ptr [rip + g_parser], P_JSON
    jne 1f
    mov qword ptr [rip + g_trailing_comma], TC_NONE
1:  leave
    ret
ENDF options_for_parser

# should_print_comma() -> eax: shouldPrintComma(options) at level "es5"
FUNC should_print_comma
    xor eax, eax
    cmp qword ptr [rip + g_trailing_comma], TC_NONE
    setne al
    leave
    ret
ENDF should_print_comma
