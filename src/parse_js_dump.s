# --debug-ast: parses the input as JS and writes the AST in the canonical text form that
# tests/stage3/parser/babel-ast.mjs prints from Prettier's babel parser. --debug-parse only
# parses. The form is described in that script.
.include "defs.inc"
.include "parse_js.inc"

    .bss
    .balign 8
    .globl g_debug_mode
g_debug_mode: .quad 0       # 1 --debug-ast, 2 --debug-parse
g_u16_offsets: .quad 0      # u32 per text byte: its offset in UTF-16 code units, or 0

    .section .rodata
s_root:      .asciz "root"
s_comments:  .asciz "comments:\n"
s_null:      .asciz ": null\n"
s_cblock:    .asciz "CommentBlock"
s_cline:     .asciz "CommentLine"
s_cinterp:   .asciz "InterpreterDirective"
s_eq_null:   .asciz "=null"
jd_hex_digits:  .ascii "0123456789abcdef"

    .text

# jd_build_offsets(): the UTF-16 offset table, when the text is not ASCII. Positions in the dump
# are UTF-16 offsets, as in JavaScript; the AST holds byte offsets.
FUNC jd_build_offsets
    cmp qword ptr [rip + g_non_ascii], 0
    je 9f
    mov rdi, [rip + g_text_len]
    lea rdi, [rdi*4 + 4]
    call alloc
    mov [rip + g_u16_offsets], rax
    mov rsi, [rip + g_text]
    xor ecx, ecx                        # byte offset
    xor edx, edx                        # UTF-16 offset
1:  cmp rcx, [rip + g_text_len]
    jae 8f
    mov [rax + rcx*4], edx
    movzx r8d, byte ptr [rsi + rcx]
    mov r9d, r8d
    and r9d, 0xC0
    cmp r9d, 0x80
    je 3f                               # continuation byte
    inc edx
    cmp r8d, 0xF0
    jb 3f
    inc edx                             # a surrogate pair
3:  inc rcx
    jmp 1b
8:  mov [rax + rcx*4], edx
9:  leave
    ret
ENDF jd_build_offsets

# jd_pos(byte offset): writes the position as a UTF-16 offset
FUNC jd_pos
    mov eax, edi
    mov rcx, [rip + g_u16_offsets]
    test rcx, rcx
    jz 1f
    mov edi, [rcx + rax*4]
1:  call jd_u32
    leave
    ret
ENDF jd_pos

# jd_cstr(cstr)
FUNC jd_cstr
    push rdi
    sub rsp, 8
    call strlen
    add rsp, 8
    pop rdi
    mov rsi, rax
    call out_bytes
    leave
    ret
ENDF jd_cstr

# jd_u32(n): decimal
FUNC jd_u32
    sub rsp, 32
    mov eax, edi
    lea rsi, [rsp + 24]
    mov ecx, 10
1:  xor edx, edx
    div ecx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test eax, eax
    jnz 1b
    mov rdi, rsi
    lea rdx, [rsp + 24]
    sub rdx, rsi
    mov rsi, rdx
    call out_bytes
    leave
    ret
ENDF jd_u32

# jd_unit(u): one UTF-16 code unit as the dump escapes it
FUNC jd_unit
    push rbx
    sub rsp, 8
    mov ebx, edi
    cmp ebx, '"'
    je 1f
    cmp ebx, '\\'
    je 1f
    cmp ebx, 0x20
    jb 2f
    cmp ebx, 0x7f
    jae 2f
    mov edi, ebx
    call out_byte
    jmp 9f
1:  mov edi, '\\'
    call out_byte
    mov edi, ebx
    call out_byte
    jmp 9f
2:  mov edi, '\\'
    call out_byte
    mov edi, 'u'
    call out_byte
    lea r8, [rip + jd_hex_digits]
    mov ecx, 12
3:  mov eax, ebx
    shr eax, cl
    and eax, 15
    movzx edi, byte ptr [r8 + rax]
    push rcx
    push r8
    call out_byte
    pop r8
    pop rcx
    sub ecx, 4
    jns 3b
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF jd_unit

# jd_quoted(ptr, len): "..." with UTF-8 (and WTF-8 surrogates) decoded to UTF-16 units
FUNC jd_quoted
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov edi, '"'
    call out_byte
1:  cmp rbx, r12
    jae 9f
    movzx eax, byte ptr [rbx]
    cmp eax, 0x80
    jae 2f
    mov edi, eax
    inc rbx
    call jd_unit
    jmp 1b
2:  cmp eax, 0xE0
    jae 3f
    and eax, 0x1F
    shl eax, 6
    movzx ecx, byte ptr [rbx + 1]
    and ecx, 0x3F
    or eax, ecx
    add rbx, 2
    jmp 6f
3:  cmp eax, 0xF0
    jae 4f
    and eax, 0x0F
    shl eax, 12
    movzx ecx, byte ptr [rbx + 1]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rbx + 2]
    and ecx, 0x3F
    or eax, ecx
    add rbx, 3
    jmp 6f
4:  and eax, 0x07
    shl eax, 18
    movzx ecx, byte ptr [rbx + 1]
    and ecx, 0x3F
    shl ecx, 12
    or eax, ecx
    movzx ecx, byte ptr [rbx + 2]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rbx + 3]
    and ecx, 0x3F
    or eax, ecx
    add rbx, 4
    sub eax, 0x10000
    mov r13d, eax
    shr eax, 10
    lea edi, [eax + 0xD800]
    call jd_unit
    mov edi, r13d
    and edi, 0x3FF
    add edi, 0xDC00
    call jd_unit
    jmp 1b
6:  mov edi, eax
    call jd_unit
    jmp 1b
9:  mov edi, '"'
    call out_byte
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jd_quoted

# jd_skip_asciz(p) -> rax: after the terminating 0
FUNC jd_skip_asciz
    mov rax, rdi
1:  cmp byte ptr [rax], 0
    lea rax, [rax + 1]
    jne 1b
    leave
    ret
ENDF jd_skip_asciz

# jd_line_start(depth, key cstr, index or -1)
FUNC jd_line_start
    push rbx
    push r12
    mov rbx, rsi
    mov r12, rdx
    call out_spaces
    mov rdi, rbx
    call jd_cstr
    test r12, r12
    js 9f
    mov edi, '['
    call out_byte
    mov edi, r12d
    call jd_u32
    mov edi, ']'
    call out_byte
9:  pop r12
    pop rbx
    leave
    ret
ENDF jd_line_start

# jd_node(node, depth, key cstr, index or -1)
FUNC jd_node
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    call jd_line_start
    mov edi, ':'
    call out_byte
    mov edi, ' '
    call out_byte
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_type_names]
    mov rdi, [rcx + rax*8]
    call jd_cstr
    mov edi, ' '
    call out_byte
    mov edi, [rbx + N_START]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov edi, [rbx + N_END]
    call jd_pos
    # props
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_type_fields]
    mov r13, [rcx + rax*8]
1:  movzx r14d, byte ptr [r13]
    test r14d, r14d
    jz 30f
    movzx r15d, byte ptr [r13 + 1]
    lea rax, [r13 + 2]
    mov [rsp], rax                      # key
    mov rdi, rax
    call jd_skip_asciz
    mov r13, rax
    cmp r14d, FK_BOOL
    je 10f
    cmp r14d, FK_FLAG
    je 11f
    cmp r14d, FK_OP
    je 12f
    cmp r14d, FK_KIND
    je 12f
    cmp r14d, FK_STR
    je 13f
    cmp r14d, FK_NAME
    je 14f
    cmp r14d, FK_INNER
    je 15f
    cmp r14d, FK_TRI
    je 16f
    jmp 1b
16: mov rax, [rbx + r15]
    test rax, rax
    jz 1b
    cmp rax, 1
    je 20f
    jmp 121f
10: mov eax, [rbx + N_ATTR]
    bt eax, r15d
    jnc 1b
    jmp 20f
11: cmp qword ptr [rbx + r15], 0
    je 1b
20: mov edi, ' '                        # ` key`
    call out_byte
    mov rdi, [rsp]
    call jd_cstr
    jmp 1b
12: mov rax, [rbx + r15]
121: test rax, rax
    jz 1b
    cmp rax, 255
    ja 1b
    lea rcx, [rip + ast_codes]
    mov rax, [rcx + rax*8]
    test rax, rax
    jz 1b
    mov [rsp + 8], rax
    mov rdi, [rsp]
    call jd_prop_key
    mov rdi, [rsp + 8]
    call strlen
    mov rsi, rax
    mov rdi, [rsp + 8]
    call jd_quoted
    jmp 1b
13: mov rdi, [rsp]
    call jd_prop_key
    mov rdi, [rbx + r15]
    test rdi, rdi
    jz 131f
    mov rsi, [rbx + r15 + 8]
    call jd_quoted
    jmp 1b
131: mov edi, 'n'
    call out_byte
    mov edi, 'u'
    call out_byte
    mov edi, 'l'
    call out_byte
    mov edi, 'l'
    call out_byte
    jmp 1b
14: mov rdi, [rsp]
    call jd_prop_key
    mov eax, [rbx + N_START]
    mov esi, [rbx + N_END]
    sub esi, eax
    mov rcx, [rbx + N_F7]
    test rcx, rcx
    jz 141f
    mov esi, ecx
141: mov rcx, [rbx + N_F0]
    test rcx, rcx
    jz 142f
    lea eax, [rcx - 1]
142: mov rdi, [rip + g_text]
    add rdi, rax
    call jd_quoted
    jmp 1b
15: mov rdi, [rsp]
    call jd_prop_key
    mov eax, [rbx + N_START]
    mov rdi, [rip + g_text]
    lea rdi, [rdi + rax + 1]
    mov esi, [rbx + N_END]
    sub esi, eax
    sub esi, 2
    call jd_quoted
    jmp 1b
    # children
30: mov edi, 10
    call out_byte
    inc r13
31: movzx r14d, byte ptr [r13]
    test r14d, r14d
    jz 99f
    movzx r15d, byte ptr [r13 + 1]
    lea rax, [r13 + 2]
    mov [rsp], rax
    mov rdi, rax
    call jd_skip_asciz
    mov r13, rax
    cmp r14d, FK_VEC
    je 35f
    mov rdi, [rbx + r15]
    test rdi, rdi
    jz 31b
    lea rsi, [r12 + 1]
    mov rdx, [rsp]
    mov rcx, -1
    call jd_node
    jmp 31b
35: mov r14, [rbx + r15]
    test r14, r14
    jz 31b
    xor r15d, r15d
36: cmp r15, [r14]
    jae 31b
    mov rdi, [r14 + 8 + r15*8]
    test rdi, rdi
    jz 37f
    lea rsi, [r12 + 1]
    mov rdx, [rsp]
    mov rcx, r15
    call jd_node
    inc r15
    jmp 36b
37: lea rdi, [r12 + 1]
    mov rsi, [rsp]
    mov rdx, r15
    call jd_line_start
    lea rdi, [rip + s_null]
    call jd_cstr
    inc r15
    jmp 36b
99: add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jd_node

# jd_prop_key(key cstr): writes ` key=`
FUNC jd_prop_key
    push rdi
    sub rsp, 8
    mov edi, ' '
    call out_byte
    add rsp, 8
    pop rdi
    call jd_cstr
    mov edi, '='
    call out_byte
    leave
    ret
ENDF jd_prop_key

# jd_comments()
FUNC jd_comments
    push rbx
    push r12
    push r13
    push r14
    lea rdi, [rip + s_comments]
    call jd_cstr
    mov r12, [rip + g_comments]
    test r12, r12
    jz 9f
    xor ebx, ebx
1:  cmp ebx, [r12]
    jae 9f
    mov r13, [r12 + 8 + rbx*8]
    mov edi, ' '
    call out_byte
    lea rdi, [rip + s_cblock]
    cmp byte ptr [r13 + CM_TYPE], CT_BLOCK
    je 2f
    lea rdi, [rip + s_cline]
    cmp byte ptr [r13 + CM_TYPE], CT_LINE
    je 2f
    lea rdi, [rip + s_cinterp]
2:  call jd_cstr
    mov edi, ' '
    call out_byte
    mov edi, [r13 + CM_START]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov edi, [r13 + CM_END]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov eax, [r13 + CM_START]
    add eax, 2
    mov esi, [r13 + CM_END]
    cmp byte ptr [r13 + CM_TYPE], CT_BLOCK
    jne 3f
    sub esi, 2
3:  sub esi, eax
    mov rdi, [rip + g_text]
    add rdi, rax
    call jd_quoted
    mov edi, 10
    call out_byte
    inc ebx
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jd_comments

# js_source_is_script() -> eax: js_parse's flags from the file name (any case): JS_SRC_SCRIPT for
# .cjs and .cts, JS_SRC_TS for .ts, .mts and .cts. A .tsx file is refused: Prettier parses it with
# JSX, which is not ported.
FUNC js_source_is_script
    push rbx
    sub rsp, 8
    mov rdi, [rip + g_filepath]
    call strlen
    xor ebx, ebx
    cmp rax, 3
    jb 9f
    mov rdi, [rip + g_filepath]
    lea rdx, [rdi + rax]
    movzx ecx, word ptr [rdx - 2]
    or ecx, 0x2020
    movzx r8d, byte ptr [rdx - 3]
    cmp ecx, 0x7374                     # "ts"
    jne 2f
    cmp r8b, '.'
    je 7f                               # .ts
    cmp rax, 4
    jb 9f
    cmp byte ptr [rdx - 4], '.'
    jne 9f
    or r8d, 0x20
    cmp r8b, 'm'
    je 7f                               # .mts
    cmp r8b, 'c'
    jne 9f
    mov ebx, JS_SRC_SCRIPT | JS_SRC_TS  # .cts
    jmp 9f
7:  mov ebx, JS_SRC_TS
    jmp 9f
2:  cmp rax, 4
    jb 9f
    mov eax, [rdx - 4]
    or eax, 0x20202000                  # lowercase the letters, keep the dot
    cmp eax, 0x736a632e                 # ".cjs"
    jne 3f
    mov ebx, JS_SRC_SCRIPT
    jmp 9f
3:  cmp eax, 0x78737400 | '.'           # ".tsx"
    je 90f
9:  mov eax, ebx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "TSX (JSX is not ported)"
ENDF js_source_is_script

# js_debug_scan(argc, argv): with --debug-ast or --debug-parse among the arguments, reads the
# file named by --stdin-filepath (from stdin) or by the first other argument, runs the mode,
# writes the output and exits 0. Otherwise returns.
FUNC js_debug_scan
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d                      # path
    xor r15d, r15d                      # 1: from stdin
    mov ebx, 1
1:  cmp rbx, r12
    jae 5f
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_ast]
    call cstr_eq
    test eax, eax
    jz 2f
    mov qword ptr [rip + g_debug_mode], 1
    jmp 4f
2:  mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_parse]
    call cstr_eq
    test eax, eax
    jz 21f
    mov qword ptr [rip + g_debug_mode], 2
    jmp 4f
21: mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_stdin]
    call cstr_eq
    test eax, eax
    jz 22f
    inc rbx
    cmp rbx, r12
    jae 5f
    mov r14, [r13 + rbx*8]
    mov r15d, 1
    jmp 4f
22: mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_stdin_eq]
    call cstr_prefix
    test eax, eax
    jz 23f
    mov r14, [r13 + rbx*8]
    add r14, 17
    mov r15d, 1
    jmp 4f
23: test r14, r14
    jnz 4f
    mov rax, [r13 + rbx*8]
    cmp byte ptr [rax], '-'
    je 4f
    mov r14, rax
4:  inc rbx
    jmp 1b
5:  cmp qword ptr [rip + g_debug_mode], 0
    je 9f
    test r14, r14
    jz 90f
    mov [rip + g_filepath], r14
    mov [rip + g_from_stdin], r15
    test r15d, r15d
    jz 6f
    xor edi, edi
    call read_fd_all
    jmp 7f
6:  mov rdi, r14
    call read_file
7:  test rax, rax
    jnz 91f
    call out_init
    call js_debug_main
    mov rdx, [rip + g_out_ptr]
    mov rsi, [rip + g_out_base]
    sub rdx, rsi
    mov edi, 1
    call write_all
    xor edi, edi
    call sys_exit
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "--debug-ast without a file"
91: REFUSE "cannot read the input"
ENDF js_debug_scan

    .section .rodata
s_flag_ast:      .asciz "--debug-ast"
s_flag_parse:    .asciz "--debug-parse"
s_flag_stdin:    .asciz "--stdin-filepath"
s_flag_stdin_eq: .asciz "--stdin-filepath="
    .text

# js_debug_main(): the --debug-ast and --debug-parse modes; output goes to the output buffer
FUNC js_debug_main
    push rbx
    sub rsp, 8
    call text_prepare
    call js_source_is_script
    mov edi, eax
    call js_parse
    mov rbx, rax
    cmp qword ptr [rip + g_debug_mode], 1
    jne 9f
    call jd_build_offsets
    mov rdi, rbx
    xor esi, esi
    lea rdx, [rip + s_root]
    mov rcx, -1
    call jd_node
    call jd_comments
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_debug_main
