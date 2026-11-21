# Doc builders (src/document/builders.js) and utilities (src/document/utils.js).
# Docs are records in the arena; a pointer is the doc's identity, so shared
# subtrees stay shared. 0 stands for the empty string doc.
.include "defs.inc"

    .data
    .balign 8
    .globl d_line, d_softline, d_hardline_nb, d_literalline_nb, d_break_parent
    .globl d_hardline, d_literalline, d_line_suffix_boundary, d_trim, d_cursor
d_line:            .byte DK_LINE, 0, 0, 0, 0, 0, 0, 0
d_softline:        .byte DK_LINE, LF_SOFT, 0, 0, 0, 0, 0, 0
d_hardline_nb:     .byte DK_LINE, LF_HARD, 0, 0, 0, 0, 0, 0
d_literalline_nb:  .byte DK_LINE, LF_HARD | LF_LITERAL, 0, 0, 0, 0, 0, 0
d_break_parent:    .byte DK_BREAK_PARENT, 0, 0, 0, 0, 0, 0, 0
d_line_suffix_boundary: .byte DK_LINE_SUFFIX_BOUNDARY, 0, 0, 0, 0, 0, 0, 0
d_trim:            .byte DK_TRIM, 0, 0, 0, 0, 0, 0, 0
d_cursor:          .byte DK_CURSOR, 0, 0, 0, 0, 0, 0, 0
# hardline = [hardlineWithoutBreakParent, breakParent]
d_hardline:        .byte DK_ARRAY, 0, 0, 0
                   .long 2
                   .quad d_hardline_nb, d_break_parent
d_literalline:     .byte DK_ARRAY, 0, 0, 0
                   .long 2
                   .quad d_literalline_nb, d_break_parent

    .bss
    .balign 8
    .globl g_propagate_gen
g_propagate_gen: .quad 0
g_prop_groups:   .quad 0

# doc_str(ptr, len) -> rax: string doc (the bytes are not copied)
FUNC doc_str
    push rdi
    push rsi
    mov edi, DS_SIZE
    call alloc
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_STR
    mov [rax + DS_LEN], esi
    mov [rax + DS_PTR], rdi
    push rax
    sub rsp, 8
    call str_width
    mov rcx, rax
    add rsp, 8
    pop rax
    mov [rax + DS_WIDTH], rcx
    leave
    ret
ENDF doc_str

# doc_text(start, end) -> rax: string doc of g_text[start:end]
FUNC doc_text
    sub rsi, rdi
    add rdi, [rip + g_text]
    call doc_str
    leave
    ret
ENDF doc_text

# doc_wrap(kind, contents) -> rax: indent / line-suffix / generic one-child doc
FUNC doc_wrap
    push rdi
    push rsi
    mov edi, 16
    call alloc
    pop rsi
    pop rdi
    mov [rax], dil
    mov [rax + D_CONTENTS], rsi
    leave
    ret
ENDF doc_wrap

# doc_indent(contents) -> rax
FUNC doc_indent
    mov rsi, rdi
    mov edi, DK_INDENT
    call doc_wrap
    leave
    ret
ENDF doc_indent

# doc_line_suffix(contents) -> rax
FUNC doc_line_suffix
    mov rsi, rdi
    mov edi, DK_LINE_SUFFIX
    call doc_wrap
    leave
    ret
ENDF doc_line_suffix

# doc_align(align_kind, n, contents) -> rax
FUNC doc_align
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, DAL_SIZE
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_ALIGN
    mov [rax + 1], dil
    mov [rax + D_CONTENTS], rdx
    mov [rax + DAL_N], rsi
    leave
    ret
ENDF doc_align

# doc_group(contents, should_break) -> rax
FUNC doc_group
    push rdi
    push rsi
    mov edi, GROUP_SIZE
    call alloc
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_GROUP
    mov [rax + G_CONTENTS], rdi
    test esi, esi
    jz 1f
    mov byte ptr [rax + G_FLAGS], GF_BREAK
1:  leave
    ret
ENDF doc_group

# doc_group_with_id() -> rax: a group with an id whose contents are set later
# (ifBreak/indentIfBreak inside it refer to it by pointer).
FUNC doc_group_with_id
    mov edi, GROUP_SIZE
    call alloc
    mov byte ptr [rax], DK_GROUP
    mov byte ptr [rax + G_FLAGS], GF_HAS_ID
    mov [rax + G_ID], rax
    leave
    ret
ENDF doc_group_with_id

# doc_fill(parts_array) -> rax
FUNC doc_fill
    push rdi
    sub rsp, 8
    mov edi, FILL_SIZE
    call alloc
    add rsp, 8
    pop rdi
    mov byte ptr [rax], DK_FILL
    mov [rax + FILL_PARTS], rdi
    leave
    ret
ENDF doc_fill

# doc_if_break(break_contents, flat_contents, group_id) -> rax
FUNC doc_if_break
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, IB_SIZE
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_IF_BREAK
    mov [rax + IB_BREAK], rdi
    mov [rax + IB_FLAT], rsi
    mov [rax + IB_GROUP], rdx
    leave
    ret
ENDF doc_if_break

# doc_indent_if_break(contents, group_id, negate) -> rax
FUNC doc_indent_if_break
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, IIB_SIZE
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_INDENT_IF_BREAK
    mov [rax + IIB_NEGATE], dl
    mov [rax + IIB_CONTENTS], rdi
    mov [rax + IIB_GROUP], rsi
    leave
    ret
ENDF doc_indent_if_break

# doc_label(label, contents) -> rax
FUNC doc_label
    push rdi
    push rsi
    mov edi, 24
    call alloc
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_LABEL
    mov [rax + D_CONTENTS], rsi
    mov [rax + 16], rdi
    leave
    ret
ENDF doc_label

# doc_array2(a, b) -> rax: [a, b]
FUNC doc_array2
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call ss_mark
    push rax
    sub rsp, 8
    mov rdi, rbx
    call ss_push
    mov rdi, r12
    call ss_push
    add rsp, 8
    pop rdi
    call ss_to_array
    pop r12
    pop rbx
    leave
    ret
ENDF doc_array2

# doc_array3(a, b, c) -> rax: [a, b, c]
FUNC doc_array3
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call ss_mark
    mov r14, rax
    mov rdi, rbx
    call ss_push
    mov rdi, r12
    call ss_push
    mov rdi, r13
    call ss_push
    mov rdi, r14
    call ss_to_array
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF doc_array3

# replace_end_of_line(ptr, len, replacement) -> rax:
# join(replacement, text.split("\n")) as replaceEndOfLine does for a string.
FUNC replace_end_of_line
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r15, rdx
    call ss_mark
    mov [rsp], rax
    xor r13d, r13d                  # piece start
    xor r14d, r14d                  # cursor
1:  cmp r14, r12
    jae 3f
    cmp byte ptr [rbx + r14], 10
    je 2f
    inc r14
    jmp 1b
2:  lea rdi, [rbx + r13]
    mov rsi, r14
    sub rsi, r13
    call doc_str
    mov rdi, rax
    call ss_push
    mov rdi, r15
    call ss_push
    inc r14
    mov r13, r14
    jmp 1b
3:  lea rdi, [rbx + r13]
    mov rsi, r14
    sub rsi, r13
    call doc_str
    mov rdi, rax
    call ss_push
    mov rdi, [rsp]
    call ss_to_array_keep
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF replace_end_of_line

# ---------------------------------------------------------------- propagateBreaks
# Walks the doc like traverseDoc(doc, onEnter, onExit, true). A group is
# entered once (visited marker per call); a shared group still counts for every
# parent it appears under, as in Prettier.

# Kinds propagateBreaks has to visit: the others have no groups or breakParent.
.equ PROP_KINDS, (1 << DK_ARRAY) | (1 << DK_INDENT) | (1 << DK_ALIGN) | (1 << DK_GROUP) | (1 << DK_FILL) | (1 << DK_IF_BREAK) | (1 << DK_INDENT_IF_BREAK) | (1 << DK_LINE_SUFFIX) | (1 << DK_BREAK_PARENT) | (1 << DK_LABEL)
# PPUSH reg: push the doc in reg (r10d = PROP_KINDS) unless it is "" or a leaf
.macro PPUSH reg
    test \reg, \reg
    jz .Lpp\@
    movzx edx, byte ptr [\reg]
    bt r10d, edx
    jnc .Lpp\@
    mov [rsi], \reg
    add rsi, 8
.Lpp\@:
.endm

# propagate_breaks(doc)
# Docs to visit go on the scratch stack (an odd pointer is a group's exit
# marker), the open groups on a stack in the R_FITS region. Calls nothing.
FUNC propagate_breaks
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    inc qword ptr [rip + g_propagate_gen]
    mov r15, [rip + g_propagate_gen]
    mov r13, [rip + g_prop_groups]
    test r13, r13
    jnz 1f
    push rdi
    sub rsp, 8
    mov rdi, R_FITS
    call region_base
    add rsp, 8
    pop rdi
    add rax, REGION_SIZE / 4
    mov [rip + g_prop_groups], rax
    mov r13, rax                    # open groups: base
1:  mov r14, r13                    # open groups: top
    mov r12, [rip + g_ss_ptr]       # docs: base
    mov rsi, r12                    # docs: top
    mov [rsi], rdi
    add rsi, 8
    lea r11, [rip + prop_dispatch]
    mov r10d, PROP_KINDS
2:  cmp rsi, r12
    jbe 90f
    sub rsi, 8
    mov rbx, [rsi]
    test rbx, rbx
    jz 2b
    test bl, 1
    jnz 50f
    movzx eax, byte ptr [rbx]
    jmp [r11 + rax*8]
    # array: parts in reverse
10: mov ecx, [rbx + DA_COUNT]
11: test ecx, ecx
    jz 2b
    dec ecx
    mov rax, [rbx + DA_ITEMS + rcx*8]
    PPUSH rax
    jmp 11b
    # group: exit marker, then the contents unless visited
20: lea rax, [rbx + 1]
    mov [rsi], rax
    add rsi, 8
    mov [r14], rbx
    add r14, 8
    cmp [rbx + G_VISIT_GEN], r15d
    je 2b
    mov [rbx + G_VISIT_GEN], r15d
    mov rax, [rbx + G_EXPANDED]
    test rax, rax
    jnz 21f
    mov rax, [rbx + G_CONTENTS]
21: PPUSH rax
    jmp 2b
    # breakParent
30: call 60f
    jmp 2b
40: mov rax, [rbx + FILL_PARTS]
    PPUSH rax
    jmp 2b
41: mov rax, [rbx + IB_FLAT]
    PPUSH rax
    mov rax, [rbx + IB_BREAK]
    PPUSH rax
    jmp 2b
42: mov rax, [rbx + D_CONTENTS]
    PPUSH rax
    jmp 2b
    # group exit
50: sub r14, 8
    mov rax, [r14]
    test byte ptr [rax + G_FLAGS], GF_BREAK
    jz 2b
    call 60f
    jmp 2b
    # breakParentGroup(groupStack)
60: cmp r14, r13
    jbe 61f
    mov rax, [r14 - 8]
    cmp qword ptr [rax + G_EXPANDED], 0
    jne 61f
    test byte ptr [rax + G_FLAGS], GF_BREAK
    jnz 61f
    or byte ptr [rax + G_FLAGS], GF_BREAK | GF_PROPAGATED
61: ret
90: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF propagate_breaks

    .section .rodata
    .balign 8
prop_dispatch:
    .quad 2b, 2b, 10b, 42b, 42b, 20b, 40b, 41b, 42b, 2b, 42b, 2b, 30b, 2b, 42b, 2b, 2b
    .text

# ---------------------------------------------------------------- willBreak / canBreak
# doc_find(doc, mode) -> eax: mode 1 = willBreak (broken group, hard line,
# breakParent), mode 2 = canBreak (any line). Walks like findInDoc (groups by
# contents only).
FUNC doc_find
    push rbx
    push r12
    push r13
    push r14
    mov r13d, esi
    call ss_mark
    mov r12, rax
    call ss_push
1:  mov rax, [rip + g_ss_ptr]
    cmp rax, r12
    jbe 8f
    sub rax, 8
    mov rbx, [rax]
    mov [rip + g_ss_ptr], rax
    test rbx, rbx
    jz 1b
    movzx eax, byte ptr [rbx]
    cmp al, DK_LINE
    jne 2f
    cmp r13d, 2
    je 9f
    test byte ptr [rbx + 1], LF_HARD
    jnz 9f
    jmp 1b
2:  cmp r13d, 1
    jne 3f
    cmp al, DK_BREAK_PARENT
    je 9f
    cmp al, DK_GROUP
    jne 3f
    test byte ptr [rbx + G_FLAGS], GF_BREAK
    jnz 9f
3:  cmp al, DK_ARRAY
    je 10f
    cmp al, DK_FILL
    je 11f
    cmp al, DK_IF_BREAK
    je 12f
    cmp al, DK_GROUP
    je 13f
    cmp al, DK_INDENT
    je 14f
    cmp al, DK_ALIGN
    je 14f
    cmp al, DK_INDENT_IF_BREAK
    je 14f
    cmp al, DK_LABEL
    je 14f
    cmp al, DK_LINE_SUFFIX
    je 14f
    jmp 1b
10: mov ecx, [rbx + DA_COUNT]
15: test ecx, ecx
    jz 1b
    dec ecx
    mov rdi, [rbx + DA_ITEMS + rcx*8]
    push rcx
    sub rsp, 8
    call ss_push
    add rsp, 8
    pop rcx
    jmp 15b
11: mov rdi, [rbx + FILL_PARTS]
    call ss_push
    jmp 1b
12: mov rdi, [rbx + IB_FLAT]
    call ss_push
    mov rdi, [rbx + IB_BREAK]
    call ss_push
    jmp 1b
13: mov rdi, [rbx + G_EXPANDED]
    test rdi, rdi
    jz 14f
    mov rdi, [rbx + G_CONTENTS]
    call ss_push
    jmp 1b
14: mov rdi, [rbx + D_CONTENTS]
    call ss_push
    jmp 1b
8:  xor eax, eax
    jmp 7f
9:  mov eax, 1
7:  mov [rip + g_ss_ptr], r12
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF doc_find
