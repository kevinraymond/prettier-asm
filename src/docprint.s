# printDocToString from src/document/printer.js, with fits(), fill, trim,
# generateInd and the end-of-line conversion. Cursors are refused.
#
# print_doc_to_string can be called at any time, also while another print is
# running: the printer state lives in globals that each call saves on entry
# and restores on exit, and a nested call takes its command stacks and its
# output from above the ones in use.
.include "defs.inc"

    .data
    .balign 8
    .globl g_print_width, g_print_eol
g_print_width: .quad 80
g_print_eol:   .quad EOL_LF     # endOfLine for the top-level print
spaces_text:   .ascii "                                                                "
eol_text:      .byte 10, 13, 10, 13
eol_offset:    .byte 0, 1, 1
eol_length:    .byte 1, 2, 1

    .bss
    .balign 8
    .globl g_cmds_base, g_cur_gen, g_pd_width, g_pd_tab_width, g_pd_use_tabs
    .globl g_pd_eol, g_pd_root, g_pd_out_base
# Per-print state, saved and restored around every print (PST_*).
g_cmds_base:    .quad 0
g_cmds_top:     .quad 0     # top of the commands stack when a print is suspended
g_lsuf_base:    .quad 0
g_lsuf_top:     .quad 0
g_pos_col:      .quad 0     # `pos`
g_remeasure:    .quad 0     # shouldRemeasure
g_cur_gen:      .quad 0     # groupModeMap of this print: ids whose GID_GEN equals this
g_pd_width:     .quad 0
g_pd_tab_width: .quad 0
g_pd_use_tabs:  .quad 0
g_pd_eol:       .quad 0
g_pd_root:      .quad 0     # rootIndent()
g_pd_out_base:  .quad 0     # where this print's output starts
.equ PST_COUNT, 13
# Shared state
g_gen_counter:  .quad 0
g_fits_base:    .quad 0
g_fits_out:     .quad 0     # fits() `out`: (ptr, len) pairs, for trim

    .text

# ---------------------------------------------------------------- output
# out_raw(ptr, len): append bytes to the output buffer.
FUNC out_raw
    mov rax, [rip + g_out_ptr]
    lea rcx, [rax + rsi]
    mov rdx, [rip + g_out_base]
    add rdx, REGION_SIZE
    cmp rcx, rdx
    ja 9f
    mov [rip + g_out_ptr], rcx
    mov rcx, rsi
    mov rsi, rdi
    mov rdi, rax
    rep movsb
    leave
    ret
9:  REFUSE "output too large"
ENDF out_raw

# out_eol(): the end-of-line sequence of this print
FUNC out_eol
    mov rax, [rip + g_pd_eol]
    lea rdi, [rip + eol_text]
    lea rcx, [rip + eol_offset]
    movzx ecx, byte ptr [rcx + rax]
    add rdi, rcx
    lea rcx, [rip + eol_length]
    movzx esi, byte ptr [rcx + rax]
    call out_raw
    leave
    ret
ENDF out_eol

# out_str_eol(ptr, len): string with every "\n" replaced by the end of line
FUNC out_str_eol
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    lea r12, [rdi + rsi]            # end
    mov r13, rdi                    # piece start
1:  cmp rbx, r12
    jae 3f
    cmp byte ptr [rbx], 10
    je 2f
    inc rbx
    jmp 1b
2:  mov rdi, r13
    mov rsi, rbx
    sub rsi, r13
    call out_raw
    call out_eol
    inc rbx
    mov r13, rbx
    jmp 1b
3:  mov rdi, r13
    mov rsi, r12
    sub rsi, r13
    call out_raw
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF out_str_eol

# out_trim_pd() -> rax: trim(out) — spaces and tabs removed from the end of
# this print's output.
FUNC out_trim_pd
    mov rcx, [rip + g_out_ptr]
    mov rdx, [rip + g_pd_out_base]
    mov rax, rcx
1:  cmp rcx, rdx
    jbe 2f
    mov r8b, [rcx - 1]
    cmp r8b, ' '
    je 3f
    cmp r8b, 9
    jne 2f
3:  dec rcx
    jmp 1b
2:  mov [rip + g_out_ptr], rcx
    sub rax, rcx
    leave
    ret
ENDF out_trim_pd

# ---------------------------------------------------------------- indentation
# ind_new(ind, keep, extra) -> rax: a new indentation whose value is the first
# `keep` bytes of ind's value followed by `extra` uninitialized bytes. Root and
# prev are ind's; the caller sets the rest. rdx returns the extra bytes.
FUNC ind_new
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov edi, IND_SIZE
    call alloc
    mov r14, rax
    lea rdi, [r12 + r13]
    mov [r14 + IND_VLEN], rdi
    call alloc
    mov [r14 + IND_VALUE], rax
    mov rdi, rax
    mov rsi, [rbx + IND_VALUE]
    mov rcx, r12
    rep movsb
    mov rdx, rdi
    mov rax, [rbx + IND_ROOT]
    mov [r14 + IND_ROOT], rax
    mov [r14 + IND_PREV], rbx
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ind_new

# ind_copy(ind) -> rax: shallow copy without memos
FUNC ind_copy
    push rdi
    sub rsp, 8
    mov edi, IND_SIZE
    call alloc
    add rsp, 8
    pop rsi
    mov rcx, [rsi + IND_VALUE]
    mov [rax + IND_VALUE], rcx
    mov rcx, [rsi + IND_VLEN]
    mov [rax + IND_VLEN], rcx
    mov rcx, [rsi + IND_LENGTH]
    mov [rax + IND_LENGTH], rcx
    mov rcx, [rsi + IND_ROOT]
    mov [rax + IND_ROOT], rcx
    mov rcx, [rsi + IND_PREV]
    mov [rax + IND_PREV], rcx
    mov rcx, [rsi + IND_TC]
    mov [rax + IND_TC], rcx
    mov rcx, [rsi + IND_TS]
    mov [rax + IND_TS], rcx
    leave
    ret
ENDF ind_copy

# make_indent(ind) -> rax: generateInd(ind, {type: "indent"})
FUNC make_indent
    mov rax, [rdi + IND_MEMO_IND]
    test rax, rax
    jz 1f
    leave
    ret
1:  push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    cmp qword ptr [rip + g_pd_use_tabs], 0
    jne 2f
    # spaces: value already ends with the trailing aligns' spaces
    mov rsi, [rbx + IND_VLEN]
    mov r12, [rip + g_pd_tab_width]
    mov rdx, r12
    call ind_new
    mov rdi, rdx
    mov rcx, r12
    mov r13, rax
    mov al, ' '
    rep stosb
    mov rax, [rbx + IND_LENGTH]
    add rax, r12
    mov [r13 + IND_LENGTH], rax
    jmp 8f
    # tabs: the trailing aligns become one tab each, then the indent's tab
2:  mov rsi, [rbx + IND_VLEN]
    sub rsi, [rbx + IND_TS]
    mov r12, [rbx + IND_TC]
    inc r12
    mov rdx, r12
    call ind_new
    mov r13, rax
    mov rdi, rdx
    mov rcx, r12
    mov al, 9
    rep stosb
    mov rax, [rbx + IND_LENGTH]
    sub rax, [rbx + IND_TS]
    mov rcx, r12
    imul rcx, [rip + g_pd_tab_width]
    add rax, rcx
    mov [r13 + IND_LENGTH], rax
8:  mov [rbx + IND_MEMO_IND], r13
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF make_indent

# make_align(ind, align_doc) -> rax: makeAlign(ind, doc.n)
FUNC make_align
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    movzx r12d, byte ptr [rsi + 1]  # kind
    mov r13, [rsi + DAL_N]          # n
    cmp r12d, AK_NEG_INF
    je 10f
    cmp r12d, AK_DEDENT
    je 20f
    cmp r12d, AK_NUMBER
    jne 1f
    test r13, r13
    jz 50f                          # !widthOrDoc
    js 20f                          # widthOrDoc < 0
    jmp 2f
1:  cmp r12d, AK_STRING
    jne 2f
    cmp dword ptr [r13 + DS_LEN], 0
    je 50f
    # memo
2:  cmp [rbx + IND_MEMO_KIND], r12
    jne 3f
    cmp [rbx + IND_MEMO_N], r13
    jne 3f
    mov rax, [rbx + IND_MEMO_RES]
    jmp 99f
3:  cmp r12d, AK_ROOT
    je 30f
    cmp r12d, AK_STRING
    je 40f
    # numberAlign: n more trailing spaces
    mov rdi, rbx
    mov rsi, [rbx + IND_VLEN]
    mov rdx, r13
    call ind_new
    mov r14, rax
    mov rdi, rdx
    mov rcx, r13
    mov al, ' '
    rep stosb
    mov rax, [rbx + IND_LENGTH]
    add rax, r13
    mov [r14 + IND_LENGTH], rax
    mov rax, [rbx + IND_TC]
    inc rax
    mov [r14 + IND_TC], rax
    mov rax, [rbx + IND_TS]
    add rax, r13
    mov [r14 + IND_TS], rax
    jmp 90f
    # dedentToRoot: indent.root || rootIndent()
10: mov rax, [rbx + IND_ROOT]
    test rax, rax
    jnz 99f
    mov rax, [rip + g_pd_root]
    jmp 99f
    # dedent: the queue without its last part, keeping this root
20: mov rax, [rbx + IND_PREV]
    test rax, rax
    jnz 21f
    mov rax, rbx
    jmp 99f
21: mov rcx, [rax + IND_ROOT]
    cmp rcx, [rbx + IND_ROOT]
    je 99f
    mov r12d, AK_DEDENT
    xor r13d, r13d
    cmp [rbx + IND_MEMO_KIND], r12
    jne 22f
    cmp [rbx + IND_MEMO_N], r13
    jne 22f
    mov rax, [rbx + IND_MEMO_RES]
    jmp 99f
22: mov rdi, rax
    call ind_copy
    mov r14, rax
    mov rax, [rbx + IND_ROOT]
    mov [r14 + IND_ROOT], rax
    jmp 90f
    # markAsRoot: {...indent, root: indent}
30: mov rdi, rbx
    call ind_copy
    mov r14, rax
    mov [r14 + IND_ROOT], rbx
    jmp 90f
    # stringAlign: flush, then the string; length grows by its UTF-16 length
40: mov r15d, [r13 + DS_LEN]
    mov rsi, [rbx + IND_VLEN]
    xor edx, edx
    cmp qword ptr [rip + g_pd_use_tabs], 0
    je 41f
    sub rsi, [rbx + IND_TS]
    mov rdx, [rbx + IND_TC]
41: mov [rsp], rdx                  # tabs to add
    add rdx, r15
    mov rdi, rbx
    call ind_new
    mov r14, rax
    mov rdi, rdx
    mov rcx, [rsp]
    mov al, 9
    rep stosb
    mov rsi, [r13 + DS_PTR]
    mov rcx, r15
    rep movsb
    # length
    mov rax, [rbx + IND_LENGTH]
    cmp qword ptr [rip + g_pd_use_tabs], 0
    je 42f
    sub rax, [rbx + IND_TS]
    mov rcx, [rsp]
    imul rcx, [rip + g_pd_tab_width]
    add rax, rcx
42: mov [rsp], rax
    mov rdi, [r13 + DS_PTR]
    mov rsi, r15
    call utf16_length
    add rax, [rsp]
    mov [r14 + IND_LENGTH], rax
    jmp 90f
50: mov rax, rbx
    jmp 99f
90: mov [rbx + IND_MEMO_KIND], r12
    mov [rbx + IND_MEMO_N], r13
    mov [rbx + IND_MEMO_RES], r14
    mov rax, r14
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF make_align

# utf16_length(ptr, len) -> rax: JavaScript string length of UTF-8 text
FUNC utf16_length
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    movzx edx, byte ptr [rdi + rcx]
    inc rcx
    mov r8d, edx
    and r8d, 0xC0
    cmp r8d, 0x80
    je 1b
    inc rax
    cmp edx, 0xF0
    jb 1b
    inc rax
    jmp 1b
9:  leave
    ret
ENDF utf16_length

# ---------------------------------------------------------------- fits
# fits(mode, doc, rest_top, width, has_line_suffix, must_be_flat) -> eax
# rest_top: just past the last rest command (the stack ends at g_cmds_base);
# 0 for no rest commands. A leaf: it calls nothing.
FUNC fits
    mov rax, PW_INFINITY
    cmp [rip + g_pd_width], rax
    jne 1f
    mov eax, 1
    leave
    ret
1:  push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdx                    # rest cursor
    mov r13, rcx                    # width
    mov r14, [rip + g_fits_base]    # stack base
    mov r15, r14                    # stack top
    mov r10, [rip + g_fits_out]     # out top
    mov r11, [rip + g_cmds_base]
    test r12, r12
    jnz 2f
    mov r12, r11
2:  mov rdx, rdi
    mov rbx, rsi
    jmp 20f
10: test r13, r13
    js 80f
    cmp r15, r14
    ja 11f
    cmp r12, r11
    jbe 81f
    sub r12, CMD_SIZE
    mov rdx, [r12 + CMD_MODE]
    mov rbx, [r12 + CMD_DOC]
    jmp 20f
11: sub r15, 16
    mov rdx, [r15]
    mov rbx, [r15 + 8]
20: test rbx, rbx
    jz 10b
    movzx eax, byte ptr [rbx]
    lea rcx, [rip + fits_dispatch]
    jmp [rcx + rax*8]

f_str:
    sub r13, [rbx + DS_WIDTH]
    mov rax, [rbx + DS_PTR]
    mov [r10], rax
    mov eax, [rbx + DS_LEN]
    mov [r10 + 8], rax
    add r10, 16
    jmp 10b
f_array:
    mov ecx, [rbx + DA_COUNT]
    lea r9, [rbx + DA_ITEMS]
    xor r8d, r8d
    jmp 1f
f_fill:
    mov r8d, [rbx + FILL_OFFSET]
    mov rcx, [rbx + FILL_PARTS]
    lea r9, [rcx + DA_ITEMS]
    mov ecx, [rcx + DA_COUNT]
1:  cmp ecx, r8d
    jbe 10b
    dec ecx
    mov rax, [r9 + rcx*8]
    mov [r15], rdx
    mov [r15 + 8], rax
    add r15, 16
    jmp 1b
f_contents:
    mov rax, [rbx + D_CONTENTS]
    mov [r15], rdx
    mov [r15 + 8], rax
    add r15, 16
    jmp 10b
f_trim:
    xor eax, eax                    # trimCount
    mov r8, [rip + g_fits_out]
1:  cmp r10, r8
    jbe 4f
    mov rsi, [r10 - 16]
    mov rcx, [r10 - 8]
2:  test rcx, rcx
    jz 3f
    movzx r9d, byte ptr [rsi + rcx - 1]
    cmp r9d, ' '
    je 21f
    cmp r9d, 9
    jne 22f
21: inc rax
    dec rcx
    jmp 2b
22: mov [r10 - 8], rcx
    jmp 4f
3:  sub r10, 16
    jmp 1b
4:  add r13, rax
    jmp 10b
f_group:
    movzx eax, byte ptr [rbx + G_FLAGS]
    test al, GF_BREAK
    jz 1f
    cmp qword ptr [rsp + 64], 0     # must_be_flat (7th slot: see below)
    jne 80f
    mov edx, MODE_BREAK
1:  mov rax, [rbx + G_CONTENTS]
    cmp edx, MODE_BREAK
    jne 2f
    mov rcx, [rbx + G_EXPANDED]
    test rcx, rcx
    jz 2f
    mov eax, [rcx + DA_COUNT]
    mov rax, [rcx + DA_ITEMS + rax*8 - 8]
2:  mov [r15], rdx
    mov [r15 + 8], rax
    add r15, 16
    jmp 10b
f_if_break:
    mov rcx, [rbx + IB_GROUP]
    mov r8, rdx
    test rcx, rcx
    jz 1f
    mov r8d, MODE_FLAT
    mov eax, [rcx + GID_GEN]
    cmp rax, [rip + g_cur_gen]
    jne 1f
    movzx eax, byte ptr [rcx + GID_MODE]
    test eax, eax
    jz 1f
    mov r8d, eax
1:  mov rax, [rbx + IB_FLAT]
    cmp r8d, MODE_BREAK
    jne 2f
    mov rax, [rbx + IB_BREAK]
2:  test rax, rax
    jz 10b
    mov [r15], rdx
    mov [r15 + 8], rax
    add r15, 16
    jmp 10b
f_line:
    cmp edx, MODE_BREAK
    je 81f
    movzx eax, byte ptr [rbx + 1]
    test al, LF_HARD
    jnz 81f
    test al, LF_SOFT
    jnz 10b
    lea rax, [rip + spaces_text]
    mov [r10], rax
    mov qword ptr [r10 + 8], 1
    add r10, 16
    dec r13
    jmp 10b
f_line_suffix:
    mov qword ptr [rsp + 56], 1     # has_line_suffix
    jmp 10b
f_lsb:
    cmp qword ptr [rsp + 56], 0
    jne 80f
    jmp 10b
f_nothing:
    jmp 10b
80: xor eax, eax
    jmp 99f
81: mov eax, 1
99: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF fits

# fits_call(mode, doc, rest_top, width, has_line_suffix, must_be_flat) -> eax
# Puts the two flags where fits reads them: fits addresses them from its own
# frame, [rsp + 56] and [rsp + 64] after its five pushes.
    .macro FITS_CALL
    push r9
    push r8
    call fits
    add rsp, 16
    .endm

# ---------------------------------------------------------------- printDocToString
# Frame of print_run: scratch slots [rsp, rsp + 64), then the saved state.
.equ PR_SAVED, 64
# print_run(doc, options) -> rax = output start, rdx = length. The output stays
# in the output buffer; the caller keeps it or takes it back.
FUNC print_run
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, PR_SAVED + 8 * PST_COUNT
    mov rbx, rdi
    mov r12, rsi
    # save the state of a print that may be running
    lea rsi, [rip + g_cmds_base]
    lea rdi, [rsp + PR_SAVED]
    mov ecx, PST_COUNT
    rep movsq
    cmp qword ptr [rip + g_fits_base], 0
    jne 1f
    mov rdi, R_FITS
    call region_base
    mov [rip + g_fits_base], rax
    add rax, REGION_SIZE / 2
    mov [rip + g_fits_out], rax
    # new stacks start above the suspended print's
1:  mov rax, [rip + g_cmds_top]
    test rax, rax
    jnz 2f
    mov rdi, R_CMDS
    call region_base
2:  mov [rip + g_cmds_base], rax
    mov rax, [rip + g_lsuf_top]
    test rax, rax
    jnz 3f
    mov rdi, R_LSUF
    call region_base
3:  mov [rip + g_lsuf_base], rax
    mov [rip + g_lsuf_top], rax
    mov rax, [r12 + PO_WIDTH]
    mov [rip + g_pd_width], rax
    mov rax, [r12 + PO_TAB_WIDTH]
    mov [rip + g_pd_tab_width], rax
    mov rax, [r12 + PO_USE_TABS]
    mov [rip + g_pd_use_tabs], rax
    mov rax, [r12 + PO_EOL]
    mov [rip + g_pd_eol], rax
    inc qword ptr [rip + g_gen_counter]
    mov rax, [rip + g_gen_counter]
    mov [rip + g_cur_gen], rax
    mov qword ptr [rip + g_pos_col], 0
    mov qword ptr [rip + g_remeasure], 0
    mov rax, [rip + g_out_ptr]
    mov [rip + g_pd_out_base], rax
    mov edi, IND_SIZE
    call alloc
    mov [rip + g_pd_root], rax
    mov rdi, rbx
    call propagate_breaks
    mov r15, [rip + g_cmds_base]
    mov rax, [rip + g_pd_root]
    mov [r15 + CMD_IND], rax
    mov qword ptr [r15 + CMD_MODE], MODE_BREAK
    mov [r15 + CMD_DOC], rbx
    add r15, CMD_SIZE

# r15: commands stack top. Popped command: r12 ind, r13 mode, rbx doc.
.macro CPUSH ind, mode, doc
    mov [r15 + CMD_IND], \ind
    mov [r15 + CMD_MODE], \mode
    mov [r15 + CMD_DOC], \doc
    add r15, CMD_SIZE
.endm

main_loop:
    cmp r15, [rip + g_cmds_base]
    jbe done
    sub r15, CMD_SIZE
    mov r12, [r15 + CMD_IND]
    mov r13, [r15 + CMD_MODE]
    mov rbx, [r15 + CMD_DOC]
    test rbx, rbx
    jz next
    movzx eax, byte ptr [rbx]
    lea rcx, [rip + dispatch]
    jmp [rcx + rax*8]

p_str:
    mov rdi, [rbx + DS_PTR]
    mov esi, [rbx + DS_LEN]
    cmp qword ptr [rip + g_pd_eol], EOL_LF
    jne 2f
    mov rax, [rip + g_out_ptr]
    lea rcx, [rax + rsi]
    mov rdx, [rip + g_out_base]
    add rdx, REGION_SIZE
    cmp rcx, rdx
    ja 90f
    mov [rip + g_out_ptr], rcx
    mov rcx, rsi
    mov rsi, rdi
    mov rdi, rax
    rep movsb
1:  cmp r15, [rip + g_cmds_base]
    jbe next
    mov rax, [rbx + DS_WIDTH]
    add [rip + g_pos_col], rax
    jmp next
2:  call out_str_eol
    jmp 1b
90: REFUSE "output too large"

p_array:
    mov ecx, [rbx + DA_COUNT]
1:  test ecx, ecx
    jz next
    dec ecx
    mov rax, [rbx + DA_ITEMS + rcx*8]
    CPUSH r12, r13, rax
    jmp 1b

p_indent:
    mov rdi, r12
    call make_indent
    mov rcx, [rbx + D_CONTENTS]
    CPUSH rax, r13, rcx
    jmp next

p_align:
    mov rdi, r12
    mov rsi, rbx
    call make_align
    mov rcx, [rbx + D_CONTENTS]
    CPUSH rax, r13, rcx
    jmp next

p_trim:
    call out_trim_pd
    sub [rip + g_pos_col], rax
    jmp next

p_label:
    mov rax, [rbx + D_CONTENTS]
    CPUSH r12, r13, rax
    jmp next

p_group:
    cmp r13, MODE_FLAT
    jne 2f
    cmp qword ptr [rip + g_remeasure], 0
    jne 2f
    mov eax, MODE_FLAT
    mov ecx, MODE_BREAK
    test byte ptr [rbx + G_FLAGS], GF_BREAK
    cmovnz eax, ecx
    mov rcx, [rbx + G_CONTENTS]
    CPUSH r12, rax, rcx
    jmp 8f
2:  mov qword ptr [rip + g_remeasure], 0
    mov r14, [rip + g_pd_width]
    sub r14, [rip + g_pos_col]      # rem
    test byte ptr [rbx + G_FLAGS], GF_BREAK
    jnz 3f
    mov edi, MODE_FLAT
    mov rsi, [rbx + G_CONTENTS]
    mov rdx, r15
    mov rcx, r14
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    seta al
    movzx r8d, al
    xor r9d, r9d
    FITS_CALL
    test eax, eax
    jz 3f
    mov rcx, [rbx + G_CONTENTS]
    mov eax, MODE_FLAT
    CPUSH r12, rax, rcx
    jmp 8f
3:  mov rax, [rbx + G_EXPANDED]
    test rax, rax
    jz 7f
    test byte ptr [rbx + G_FLAGS], GF_BREAK
    jnz 6f
    mov qword ptr [rsp], 1          # i
4:  mov rax, [rbx + G_EXPANDED]
    mov ecx, [rax + DA_COUNT]
    mov rdx, [rsp]
    cmp rdx, rcx
    jae 6f
    mov rsi, [rax + DA_ITEMS + rdx*8]
    mov [rsp + 8], rsi
    mov edi, MODE_FLAT
    mov rdx, r15
    mov rcx, r14
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    seta al
    movzx r8d, al
    xor r9d, r9d
    FITS_CALL
    test eax, eax
    jz 5f
    mov rcx, [rsp + 8]
    mov eax, MODE_FLAT
    CPUSH r12, rax, rcx
    jmp 8f
5:  inc qword ptr [rsp]
    jmp 4b
    # mostExpanded
6:  mov rax, [rbx + G_EXPANDED]
    mov ecx, [rax + DA_COUNT]
    mov rcx, [rax + DA_ITEMS + rcx*8 - 8]
    mov eax, MODE_BREAK
    CPUSH r12, rax, rcx
    jmp 8f
7:  mov rcx, [rbx + G_CONTENTS]
    mov eax, MODE_BREAK
    CPUSH r12, rax, rcx
8:  mov rcx, [rbx + G_ID]
    test rcx, rcx
    jz next
    mov rax, [r15 - CMD_SIZE + CMD_MODE]
    mov [rcx + GID_MODE], al
    mov rax, [rip + g_cur_gen]
    mov [rcx + GID_GEN], eax
    jmp next

p_fill:
    mov r14, [rip + g_pd_width]
    sub r14, [rip + g_pos_col]      # rem
    mov rax, [rbx + FILL_PARTS]
    mov ecx, [rax + DA_COUNT]
    mov edx, [rbx + FILL_OFFSET]
    sub ecx, edx                    # length
    jbe next
    mov [rsp], rcx
    lea rax, [rax + DA_ITEMS + rdx*8]
    mov [rsp + 16], rax             # &parts[offset]
    # contentFits = fits(contentFlatCmd, [], rem, hasLineSuffix, true)
    mov edi, MODE_FLAT
    mov rsi, [rax]
    xor edx, edx
    mov rcx, r14
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    seta al
    movzx r8d, al
    mov r9d, 1
    mov rdx, [rip + g_cmds_base]    # no rest commands
    FITS_CALL
    mov [rsp + 8], rax              # contentFits
    mov rsi, [rsp + 16]
    mov eax, MODE_FLAT
    mov ecx, MODE_BREAK
    cmp qword ptr [rsp + 8], 0
    cmove eax, ecx                  # content mode
    cmp qword ptr [rsp], 1
    jne 2f
    mov rcx, [rsi]
    CPUSH r12, rax, rcx
    jmp next
2:  cmp qword ptr [rsp], 2
    jne 4f
    mov rcx, [rsi + 8]
    CPUSH r12, rax, rcx             # whitespace, in the content's mode
    mov rcx, [rsi]
    CPUSH r12, rax, rcx
    jmp next
    # three or more parts left
4:  mov edi, FILL_SIZE
    call alloc
    mov byte ptr [rax], DK_FILL
    mov rcx, [rbx + FILL_PARTS]
    mov [rax + FILL_PARTS], rcx
    mov ecx, [rbx + FILL_OFFSET]
    add ecx, 2
    mov [rax + FILL_OFFSET], ecx
    CPUSH r12, r13, rax             # remainingCmd
    # [content, whitespace, secondContent], built in this frame
    mov rsi, [rsp + 16]
    mov byte ptr [rsp + 32], DK_ARRAY
    mov dword ptr [rsp + 36], 3
    mov rax, [rsi]
    mov [rsp + 40], rax
    mov rax, [rsi + 8]
    mov [rsp + 48], rax
    mov rax, [rsi + 16]
    mov [rsp + 56], rax
    mov edi, MODE_FLAT
    lea rsi, [rsp + 32]
    mov rdx, [rip + g_cmds_base]
    mov rcx, r14
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    seta al
    movzx r8d, al
    mov r9d, 1
    FITS_CALL
    mov rsi, [rsp + 16]
    test eax, eax
    jz 5f
    mov rcx, [rsi + 8]
    mov eax, MODE_FLAT
    CPUSH r12, rax, rcx
    mov rcx, [rsi]
    CPUSH r12, rax, rcx
    jmp next
5:  mov rcx, [rsi + 8]
    mov eax, MODE_BREAK
    CPUSH r12, rax, rcx
    mov eax, MODE_FLAT
    mov ecx, MODE_BREAK
    cmp qword ptr [rsp + 8], 0
    cmove eax, ecx
    mov rcx, [rsi]
    CPUSH r12, rax, rcx
    jmp next

p_if_break:
p_indent_if_break:
    mov r14, r13                    # groupMode
    mov rcx, [rbx + IB_GROUP]
    cmp byte ptr [rbx], DK_INDENT_IF_BREAK
    jne 1f
    mov rcx, [rbx + IIB_GROUP]
1:  test rcx, rcx
    jz 2f
    xor r14d, r14d                  # groupModeMap[id] may be undefined
    mov eax, [rcx + GID_GEN]
    cmp rax, [rip + g_cur_gen]
    jne 2f
    movzx r14d, byte ptr [rcx + GID_MODE]
2:  cmp byte ptr [rbx], DK_IF_BREAK
    jne 20f
    cmp r14, MODE_BREAK
    jne 3f
    mov rdx, [rbx + IB_BREAK]
    jmp 4f
3:  cmp r14, MODE_FLAT
    jne next
    mov rdx, [rbx + IB_FLAT]
4:  test rdx, rdx
    jz next
    CPUSH r12, r13, rdx
    jmp next
    # indentIfBreak: indent the contents when broken xor negate
20: xor eax, eax
    cmp r14, MODE_BREAK
    jne 21f
    mov eax, 1
    jmp 22f
21: cmp r14, MODE_FLAT
    jne next
22: movzx ecx, byte ptr [rbx + IIB_NEGATE]
    and ecx, 1
    xor eax, ecx
    mov rdx, [rbx + IIB_CONTENTS]
    test rdx, rdx
    jz next
    test eax, eax
    jz 4b
    mov rdi, r12
    call make_indent
    mov rdx, [rbx + IIB_CONTENTS]
    CPUSH rax, r13, rdx
    jmp next

p_line_suffix:
    mov rax, [rip + g_lsuf_top]
    mov [rax + CMD_IND], r12
    mov [rax + CMD_MODE], r13
    mov rcx, [rbx + D_CONTENTS]
    mov [rax + CMD_DOC], rcx
    add rax, CMD_SIZE
    mov [rip + g_lsuf_top], rax
    jmp next

p_line_suffix_boundary:
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    jbe next
    lea rax, [rip + d_hardline_nb]
    CPUSH r12, r13, rax
    jmp next

p_line:
    movzx eax, byte ptr [rbx + 1]
    cmp r13, MODE_FLAT
    jne 2f
    test al, LF_HARD
    jnz 1f
    test al, LF_SOFT
    jnz next
    mov rax, [rip + g_out_ptr]
    mov byte ptr [rax], ' '
    inc rax
    mov [rip + g_out_ptr], rax
    inc qword ptr [rip + g_pos_col]
    jmp next
1:  mov qword ptr [rip + g_remeasure], 1
2:  mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    jbe 4f
    CPUSH r12, r13, rbx
    call flush_line_suffix
    jmp next
4:  test byte ptr [rbx + 1], LF_LITERAL
    jz 6f
    call out_eol
    mov rax, [r12 + IND_ROOT]
    test rax, rax
    jz 5f
    mov rdi, [rax + IND_VALUE]
    mov rsi, [rax + IND_VLEN]
    mov r14, [rax + IND_LENGTH]
    call out_raw
    mov [rip + g_pos_col], r14
    jmp next
5:  mov qword ptr [rip + g_pos_col], 0
    jmp next
6:  call out_trim_pd
    call out_eol
    mov rdi, [r12 + IND_VALUE]
    mov rsi, [r12 + IND_VLEN]
    call out_raw
    mov rax, [r12 + IND_LENGTH]
    mov [rip + g_pos_col], rax
    jmp next

p_cursor:
    REFUSE "cursor doc"
p_invalid:
    REFUSE "invalid doc"

next:
    # flush line suffixes left at the end of the document
    cmp r15, [rip + g_cmds_base]
    ja main_loop
    mov rax, [rip + g_lsuf_top]
    cmp rax, [rip + g_lsuf_base]
    jbe main_loop
    call flush_line_suffix
    jmp main_loop

# cmds.push(...lineSuffix.reverse()); lineSuffix = []  (r15 is the stack top)
flush_line_suffix:
    mov rcx, [rip + g_lsuf_top]
    mov rdx, [rip + g_lsuf_base]
1:  cmp rcx, rdx
    jbe 2f
    sub rcx, CMD_SIZE
    mov r8, [rcx + CMD_IND]
    mov r9, [rcx + CMD_MODE]
    mov r10, [rcx + CMD_DOC]
    CPUSH r8, r9, r10
    jmp 1b
2:  mov [rip + g_lsuf_top], rdx
    ret

done:
    mov rax, [rip + g_pd_out_base]
    mov rdx, [rip + g_out_ptr]
    sub rdx, rax
    mov r12, rax
    mov r13, rdx
    # restore the suspended print's state
    lea rsi, [rsp + PR_SAVED]
    lea rdi, [rip + g_cmds_base]
    mov ecx, PST_COUNT
    rep movsq
    mov rax, r12
    mov rdx, r13
    add rsp, PR_SAVED + 8 * PST_COUNT
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_run

# print_doc_to_string(doc, options) -> rax = ptr, rdx = len: printDocToString
# into a new string in the arena.
FUNC print_doc_to_string
    push rbx
    push r12
    call print_run
    mov rbx, rax
    mov r12, rdx
    mov rdi, rax
    mov rsi, rdx
    call alloc_copy
    mov [rip + g_out_ptr], rbx
    mov rdx, r12
    pop r12
    pop rbx
    leave
    ret
ENDF print_doc_to_string

# print_doc(doc): prints with the format options and leaves the text at the
# end of the output buffer.
FUNC print_doc
    sub rsp, PO_SIZE
    mov rax, [rip + g_print_width]
    mov [rsp + PO_WIDTH], rax
    mov rax, [rip + g_tab_width]
    mov [rsp + PO_TAB_WIDTH], rax
    mov rax, [rip + g_use_tabs]
    mov [rsp + PO_USE_TABS], rax
    mov rax, [rip + g_print_eol]
    mov [rsp + PO_EOL], rax
    mov rsi, rsp
    call print_run
    leave
    ret
ENDF print_doc

    .section .rodata
    .balign 8
dispatch:
    .quad next              # 0
    .quad p_str             # DK_STR
    .quad p_array           # DK_ARRAY
    .quad p_indent          # DK_INDENT
    .quad p_align           # DK_ALIGN
    .quad p_group           # DK_GROUP
    .quad p_fill            # DK_FILL
    .quad p_if_break        # DK_IF_BREAK
    .quad p_indent_if_break # DK_INDENT_IF_BREAK
    .quad p_line            # DK_LINE
    .quad p_line_suffix     # DK_LINE_SUFFIX
    .quad p_line_suffix_boundary
    .quad next              # DK_BREAK_PARENT
    .quad p_trim            # DK_TRIM
    .quad p_label           # DK_LABEL
    .quad p_cursor          # DK_CURSOR
    .quad p_invalid         # DK_GROUP_ID
fits_dispatch:
    .quad f_nothing         # 0
    .quad f_str
    .quad f_array
    .quad f_contents        # DK_INDENT
    .quad f_contents        # DK_ALIGN
    .quad f_group
    .quad f_fill
    .quad f_if_break
    .quad f_contents        # DK_INDENT_IF_BREAK
    .quad f_line
    .quad f_line_suffix
    .quad f_lsb
    .quad f_nothing         # DK_BREAK_PARENT
    .quad f_trim
    .quad f_contents        # DK_LABEL
    .quad f_nothing         # DK_CURSOR
    .quad f_nothing         # DK_GROUP_ID
