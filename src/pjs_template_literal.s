# print/template-literal.js. escapeTemplateCharacters, uncookTemplateElementValue
# and printTemplateExpression(s) serve only the embedders, which refuse (pjs_embed.s).
.include "pjs.inc"

SDOC sd_dollar_brace, "${"
SDOC sd_bar_spaced, " | "

    .section .rodata
s_each: .asciz "each"
s_only: .asciz "only"
s_skip: .asciz "skip"
    .text

# ptl_print_flat(doc, eol) -> rax ptr, rdx len: printDocToString(doc,
# {...options, printWidth: Infinity, endOfLine}).formatted
FUNC ptl_print_flat
    sub rsp, PO_SIZE
    mov rax, PW_INFINITY
    mov [rsp + PO_WIDTH], rax
    mov rax, [rip + g_tab_width]
    mov [rsp + PO_TAB_WIDTH], rax
    mov rax, [rip + g_use_tabs]
    mov [rsp + PO_USE_TABS], rax
    mov [rsp + PO_EOL], rsi
    mov rsi, rsp
    call print_doc_to_string
    leave
    ret
ENDF ptl_print_flat

# ptl_has_lf(ptr, len) -> eax: the string has "\n"
FUNC ptl_has_lf
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    cmp byte ptr [rdi + rcx], 10
    je 2f
    inc rcx
    jmp 1b
2:  mov eax, 1
9:  leave
    ret
ENDF ptl_has_lf

# pjs_print_template_literal(node, args) -> rax (printTemplateLiteral)
FUNC pjs_print_template_literal
    PROLOGUE 6
    mov rbx, rdi
    call ptl_is_jest_each_template_literal
    test eax, eax
    jz 1f
    mov rdi, rbx
    call ptl_print_jest_each_template_literal
    test rax, rax
    jnz 99f
1:  mov edi, N_F1
    mov esi, K_expressions
    xor edx, edx
    call print_map
    mov [rsp], rax                  # expressionDocs
    DMARK r12
    DPUSHL d_line_suffix_boundary
    DPUSHL ps_backtick
    mov qword ptr [rsp + 8], 0      # previousQuasiIndentSize
    xor r13d, r13d                  # index
2:  mov rax, [rbx + N_F0]
    cmp r13, [rax]
    jae 90f
    mov rdi, rax
    mov rsi, r13
    mov edx, K_quasis
    xor ecx, ecx
    call print_elem
    DPUSH rax
    mov rax, [rbx + N_F0]
    mov r14, [rax + 8 + r13*8]      # quasi
    ATTR r14, NA_TAIL
    jnz 80f
    # indentSize
    mov edi, [r14 + N_START]
    mov esi, [r14 + N_END]
    call has_newline_in_range
    test eax, eax
    jz 3f
    mov rdi, [rip + g_text]
    mov eax, [r14 + N_START]
    add rdi, rax
    mov esi, [r14 + N_END]
    sub esi, [r14 + N_START]
    mov rdx, [rip + g_tab_width]
    call get_indent_size
    mov [rsp + 8], rax
3:  mov rax, [rsp]
    mov r15, [rax + 8 + r13*8]      # expressionDoc
    mov rax, [rbx + N_F1]
    mov rax, [rax + 8 + r13*8]
    mov [rsp + 16], rax             # expression
    # interpolationHasNewline
    mov rax, [rbx + N_F0]
    mov rax, [rax + 16 + r13*8]     # quasis[index + 1]
    mov edi, [r14 + N_END]
    mov esi, [rax + N_START]
    call has_newline_in_range
    mov [rsp + 24], rax
    test eax, eax
    jnz 4f
    mov rdi, r15
    mov rsi, [rip + g_print_eol]
    call ptl_print_flat
    mov [rsp + 32], rax
    mov [rsp + 40], rdx
    mov rdi, rax
    mov rsi, rdx
    call ptl_has_lf
    test eax, eax
    jz 31f
    mov qword ptr [rsp + 24], 1
    jmp 4f
31: mov rdi, [rsp + 32]
    mov rsi, [rsp + 40]
    call doc_str
    mov r15, rax
4:  cmp qword ptr [rsp + 24], 0
    je 6f
    mov rdi, [rsp + 16]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 5f
    mov rdi, [rsp + 16]
    movzx eax, word ptr [rdi + N_TYPE]
    cmp eax, T_Identifier
    je 5f
    cmp eax, T_ConditionalExpression
    je 5f
    cmp eax, T_SequenceExpression
    je 5f
    call pjs_is_member_expression
    test eax, eax
    jnz 5f
    mov rdi, [rsp + 16]
    call pjs_is_binaryish
    test eax, eax
    jz 6f
    # [indent([softline, expressionDoc]), softline]
5:  lea rdi, [rip + d_softline]
    mov rsi, r15
    call doc_array2
    INDENT_RAX
    mov rdi, rax
    lea rsi, [rip + d_softline]
    call doc_array2
    mov r15, rax
    # aligned
6:  cmp qword ptr [rsp + 8], 0
    jne 7f
    mov eax, [r14 + N_END]
    cmp eax, [r14 + N_START]
    je 7f
    mov rcx, [rip + g_text]
    cmp byte ptr [rcx + rax - 1], 10
    jne 7f
    mov rdi, r15
    call doc_dedent_to_root
    jmp 71f
7:  mov rdi, r15
    mov rsi, [rsp + 8]
    mov rdx, [rip + g_tab_width]
    call add_alignment_to_doc
71: mov r15, rax
    DMARK r14
    DPUSHL sd_dollar_brace
    DPUSH r15
    DPUSHL d_line_suffix_boundary
    DPUSHL ps_rbrace
    DARRAY r14
    GROUP_RAX
    DPUSH rax
80: inc r13
    jmp 2b
90: DPUSHL ps_backtick
    DARRAY r12
99: EPILOGUE
ENDF pjs_print_template_literal

# pjs_print_tagged_template_literal(node, args) -> rax (printTaggedTemplateLiteral)
FUNC pjs_print_tagged_template_literal
    PROLOGUE
    mov rbx, rdi
    PRINT N_F1, K_quasi
    mov r12, rax                    # quasiDoc
    xor r13d, r13d                  # space
    mov rdi, [rbx + N_F1]
    mov esi, CC_Leading
    xor edx, edx
    call get_comments
    cmp qword ptr [rax], 0
    je 1f
    mov rax, [rax + 8]
    mov rcx, [rbx + N_F4]           # typeParameters ?? tag
    test rcx, rcx
    jnz 11f
    mov rcx, [rbx + N_F0]
11: mov edi, [rcx + N_END]
    mov esi, [rax + CM_START]
    call has_newline_in_range
    lea r13, [rip + ps_space]
    test eax, eax
    jz 1f
    lea r13, [rip + d_softline]
1:  PRINT N_F0, K_tag
    mov r14, rax
    DMARK r15
    DPUSH r14
    PRINT N_F4, K_typeParameters
    DPUSH rax
    DPUSH r13
    DPUSHL d_line_suffix_boundary
    DPUSH r12
    DARRAY r15
    test r12, r12
    jz 9f
    cmp byte ptr [r12], DK_LABEL
    jne 9f
    mov rdi, [r12 + DL_LABEL]
    or rdi, LB_TAGGED
    mov rsi, rax
    call doc_label
9:  EPILOGUE
ENDF pjs_print_tagged_template_literal

# ptl_is_jest_trigger(node) -> eax: an Identifier matching /^[fx]?(?:describe|it|test)$/
FUNC ptl_is_jest_trigger
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 9f
    mov ecx, [rdi + N_START]
    mov edx, [rdi + N_END]
    mov rsi, [rip + g_text]
    movzx r8d, byte ptr [rsi + rcx]
    cmp r8d, 'f'
    je 1f
    cmp r8d, 'x'
    jne 2f
1:  inc ecx
2:  sub edx, ecx
    add rsi, rcx
    cmp edx, 2
    jne 3f
    cmp word ptr [rsi], 0x7469      # "it"
    sete al
    jmp 9f
3:  cmp edx, 4
    jne 4f
    cmp dword ptr [rsi], 0x74736574 # "test"
    sete al
    jmp 9f
4:  cmp edx, 8
    jne 9f
    mov rcx, 0x6562697263736564     # "describe"
    cmp [rsi], rcx
    sete al
9:  leave
    ret
ENDF ptl_is_jest_trigger

# ptl_is_jest_each_template_literal(node) -> eax (isJestEachTemplateLiteral);
# node is the path's top
FUNC ptl_is_jest_each_template_literal
    PROLOGUE
    mov rbx, rdi
    call path_parent
    mov r12, rax
    xor eax, eax
    test r12, r12
    jz 9f
    TYPE r12, T_TaggedTemplateExpression
    jne 8f
    cmp [r12 + N_F1], rbx
    jne 8f
    mov r13, [r12 + N_F0]           # tag
    TYPE r13, T_MemberExpression
    jne 8f
    mov rdi, [r13 + N_F1]
    lea rsi, [rip + s_each]
    call pjs_ident_is
    test eax, eax
    jz 8f
    mov r14, [r13 + N_F0]           # tag.object
    mov rdi, r14
    call ptl_is_jest_trigger
    test eax, eax
    jnz 9f
    TYPE r14, T_MemberExpression
    jne 8f
    mov rdi, [r14 + N_F1]
    lea rsi, [rip + s_only]
    call pjs_ident_is
    test eax, eax
    jnz 1f
    mov rdi, [r14 + N_F1]
    lea rsi, [rip + s_skip]
    call pjs_ident_is
    test eax, eax
    jz 8f
1:  mov rdi, [r14 + N_F0]
    call ptl_is_jest_trigger
    jmp 9f
8:  xor eax, eax
9:  EPILOGUE
ENDF ptl_is_jest_each_template_literal

# Jest each table cells: (ptr, len, width) records
.equ CELL_PTR, 0
.equ CELL_LEN, 8
.equ CELL_W, 16
.equ CELL_SIZE, 24

# ptl_cell_doc(cell, pad_to) -> rax: the cell padded with spaces to pad_to
# columns (no padding when pad_to is -1)
FUNC ptl_cell_doc
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + CELL_PTR]
    mov r14, [rbx + CELL_LEN]
    cmp r12, -1
    je 1f
    sub r12, [rbx + CELL_W]
    jle 1f
    lea rdi, [r14 + r12]
    call alloc
    mov r15, rax
    mov rdi, rax
    mov rsi, r13
    mov rdx, r14
    call memcpy
    lea rdi, [r15 + r14]
    mov al, ' '
    mov rcx, r12
    rep stosb
    mov r13, r15
    add r14, r12
1:  mov rdi, r13
    mov rsi, r14
    call doc_str
    EPILOGUE
ENDF ptl_cell_doc

# ptl_print_jest_each_template_literal(node) -> rax doc, or 0 for undefined
# (printJestEachTemplateLiteral)
# Locals: [rsp] header cells, [rsp+8] header count, [rsp+16] body cells,
# [rsp+24] row records (hasLineBreak, first cell, count), [rsp+32] row count,
# [rsp+40] column widths, [rsp+48] column count
FUNC ptl_print_jest_each_template_literal
    PROLOGUE 8
    mov rbx, rdi
    # headerNames = quasis[0].value.raw.trim().split(/\s*\|\s*/u)
    mov rax, [rbx + N_F0]
    mov rax, [rax + 8]
    mov r12d, [rax + N_START]
    mov r13d, [rax + N_END]
    mov rdi, [rip + g_text]
    mov rsi, r12
    mov rdx, r13
    call trim_start_bytes
    mov r12, rax
    mov rdi, [rip + g_text]
    mov rsi, r12
    mov rdx, r13
    call trim_end_bytes
    mov r13, rax
    # cells: at most one per byte plus one
    mov rax, r13
    sub rax, r12
    lea rdi, [rax + 1]
    imul rdi, rdi, CELL_SIZE
    call alloc
    mov [rsp], rax
    mov qword ptr [rsp + 8], 0
    xor r15d, r15d                  # some header is non-empty
    mov r14, r12                    # piece start
1:  mov rcx, r14
2:  cmp rcx, r13
    jae 3f
    mov rax, [rip + g_text]
    cmp byte ptr [rax + rcx], '|'
    je 3f
    inc rcx
    jmp 2b
3:  mov [rsp + 56], rcx             # piece end (a bar or the end)
    mov rdi, [rip + g_text]
    mov rsi, r14
    mov rdx, rcx
    call trim_start_bytes
    mov r14, rax
    mov rdi, [rip + g_text]
    mov rsi, r14
    mov rdx, [rsp + 56]
    call trim_end_bytes
    mov rcx, [rsp + 8]
    imul rcx, rcx, CELL_SIZE
    add rcx, [rsp]
    mov rdx, rax
    sub rdx, r14
    jz 4f
    mov r15d, 1
4:  mov rdi, [rip + g_text]
    add rdi, r14
    mov [rcx + CELL_PTR], rdi
    mov [rcx + CELL_LEN], rdx
    push rcx
    push rcx
    mov rsi, rdx
    call str_width
    pop rcx
    pop rcx
    mov [rcx + CELL_W], rax
    inc qword ptr [rsp + 8]
    mov r14, [rsp + 56]
    cmp r14, r13
    jae 5f
    inc r14                         # past the bar
    jmp 1b
5:  cmp qword ptr [rsp + 8], 1
    ja 6f
    test r15d, r15d
    jnz 6f
    xor eax, eax
    jmp 99f
    # print the expressions with __inJestEach
6:  mov qword ptr [rip + g_in_jest_each], 1
    mov edi, N_F1
    mov esi, K_expressions
    xor edx, edx
    call print_map
    mov qword ptr [rip + g_in_jest_each], 0
    mov r12, rax                    # expression docs
    mov r13, [r12]                  # count
    lea rdi, [r13 + 1]
    imul rdi, rdi, CELL_SIZE
    call alloc
    mov [rsp + 16], rax
    # "${" + printDocToString(doc, {printWidth: Infinity, endOfLine: "lf"}) + "}"
    xor r14d, r14d
7:  cmp r14, r13
    jae 8f
    mov rdi, [r12 + 8 + r14*8]
    mov esi, EOL_LF
    call ptl_print_flat
    mov [rsp + 56], rax
    mov r15, rdx
    lea rdi, [rdx + 3]
    call alloc
    mov word ptr [rax], 0x7b24      # "${"
    mov byte ptr [rax + r15 + 2], '}'
    mov rbx, rax
    lea rdi, [rax + 2]
    mov rsi, [rsp + 56]
    mov rdx, r15
    call memcpy
    mov rcx, r14
    imul rcx, rcx, CELL_SIZE
    add rcx, [rsp + 16]
    mov [rcx + CELL_PTR], rbx
    add r15, 3
    mov [rcx + CELL_LEN], r15
    mov [rsp + 56], rcx
    mov rdi, rbx
    mov rsi, r15
    call str_width
    mov rcx, [rsp + 56]
    mov [rcx + CELL_W], rax
    inc r14
    jmp 7b
    # rows: (hasLineBreak, first cell, count) records
8:  call path_value
    mov rbx, rax
    lea rdi, [r13 + 2]
    imul rdi, rdi, 24
    call alloc
    mov [rsp + 24], rax
    mov qword ptr [rsp + 32], 1     # one empty row
    mov r14, 1                      # quasi index
81: mov rax, [rbx + N_F0]
    cmp r14, [rax]
    jae 85f
    mov rcx, [rsp + 32]
    dec rcx
    imul rcx, rcx, 24
    add rcx, [rsp + 24]             # the last row
    inc qword ptr [rcx + 16]
    lea rax, [r14 - 1]
    imul rax, rax, CELL_SIZE
    add rax, [rsp + 16]
    mov [rsp + 56], rcx
    mov rdi, [rax + CELL_PTR]
    mov rsi, [rax + CELL_LEN]
    call ptl_has_lf
    mov rcx, [rsp + 56]
    test eax, eax
    jz 82f
    mov qword ptr [rcx], 1
82: mov rax, [rbx + N_F0]
    mov rax, [rax + 8 + r14*8]
    mov edi, [rax + N_START]
    mov esi, [rax + N_END]
    call has_newline_in_range
    test eax, eax
    jz 84f
    mov rcx, [rsp + 32]
    imul rcx, rcx, 24
    add rcx, [rsp + 24]
    mov qword ptr [rcx], 0
    mov [rcx + 8], r14              # its first cell is expression r14
    mov qword ptr [rcx + 16], 0
    inc qword ptr [rsp + 32]
84: inc r14
    jmp 81b
    # maxColumnCount and the widths of rows without a line break
85: mov rax, [rsp + 8]
    xor ecx, ecx
86: cmp rcx, [rsp + 32]
    jae 87f
    mov rdx, rcx
    imul rdx, rdx, 24
    add rdx, [rsp + 24]
    mov rdx, [rdx + 16]
    cmp rdx, rax
    cmovg rax, rdx
    inc rcx
    jmp 86b
87: mov [rsp + 48], rax
    lea rdi, [rax*8 + 8]
    call alloc
    mov [rsp + 40], rax
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 40]
    call ptl_widen
    xor r14d, r14d
88: cmp r14, [rsp + 32]
    jae 89f
    mov rcx, r14
    imul rcx, rcx, 24
    add rcx, [rsp + 24]
    inc r14
    cmp qword ptr [rcx], 0
    jne 88b
    mov rdi, [rcx + 8]
    imul rdi, rdi, CELL_SIZE
    add rdi, [rsp + 16]
    mov rsi, [rcx + 16]
    mov rdx, [rsp + 40]
    call ptl_widen
    jmp 88b
    # the table: rows joined by hardline, cells by " | "
89: DMARK r12
    DPUSHL d_hardline
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    xor edx, edx
    mov rcx, [rsp + 40]
    call ptl_row_doc
    DPUSH rax
    xor r14d, r14d
90: cmp r14, [rsp + 32]
    jae 91f
    mov rcx, r14
    imul rcx, rcx, 24
    add rcx, [rsp + 24]
    inc r14
    cmp qword ptr [rcx + 16], 0
    je 90b
    mov rdi, [rcx + 8]
    imul rdi, rdi, CELL_SIZE
    add rdi, [rsp + 16]
    mov rsi, [rcx + 16]
    mov rdx, [rcx]
    mov [rsp + 56], rdi
    DPUSHL d_hardline
    mov rdi, [rsp + 56]
    mov rsi, [rcx + 16]
    mov rdx, [rcx]
    mov rcx, [rsp + 40]
    call ptl_row_doc
    DPUSH rax
    jmp 90b
91: DARRAY r12
    INDENT_RAX
    mov r13, rax
    DMARK r12
    DPUSHL d_line_suffix_boundary
    DPUSHL ps_backtick
    DPUSH r13
    DPUSHL d_hardline
    DPUSHL ps_backtick
    DARRAY r12
99: EPILOGUE
ENDF ptl_print_jest_each_template_literal

# ptl_widen(cells, count, widths): widths[i] = max(widths[i], width of cell i)
FUNC ptl_widen
    mov r8, rdx
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    mov rax, rcx
    imul rax, rax, CELL_SIZE
    mov rax, [rdi + rax + CELL_W]
    cmp rax, [r8 + rcx*8]
    jbe 2f
    mov [r8 + rcx*8], rax
2:  inc rcx
    jmp 1b
9:  leave
    ret
ENDF ptl_widen

# ptl_row_doc(cells, count, has_line_break, widths) -> rax: join(" | ",
# cells, each padded to its column's width unless the row has a line break)
FUNC ptl_row_doc
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov [rsp], rcx                  # widths
    DMARK r14
    xor r15d, r15d
1:  cmp r15, r12
    jae 9f
    test r15, r15
    jz 2f
    DPUSHL sd_bar_spaced
2:  mov rdi, r15
    imul rdi, rdi, CELL_SIZE
    add rdi, rbx
    mov rsi, -1
    test r13, r13
    jnz 3f
    mov rax, [rsp]
    mov rsi, [rax + r15*8]
3:  call ptl_cell_doc
    DPUSH rax
    inc r15
    jmp 1b
9:  DARRAY r14
    EPILOGUE
ENDF ptl_row_doc

