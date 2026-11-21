# The canonical doc text (written by --debug-doc and by tests/stage3/infra/
# doc-text.mjs from Prettier's docs), its reader, and --debug-doc-eval, which
# runs the commands of a test file against the doc printer and the doc utils.
#
# Canonical form: arrays are flattened into their parent, empty strings
# dropped, adjacent strings merged; an array left with one item is that item
# and one with none is "". Containers referenced more than once are written
# `$N=(...)` the first time and `$N` after; group ids are `#N`, both numbered in
# order of first appearance. See README.md for the grammar.
.include "defs.inc"

.macro OUTS text
    .pushsection .rodata.dd, "a"
.Louts\@: .ascii "\text"
.Louts_end\@:
    .popsection
    lea rdi, [rip + .Louts\@]
    mov esi, .Louts_end\@ - .Louts\@
    call out_raw
.endm

    .bss
    .balign 8
g_dd_refs:      .quad 0     # doc -> count (low 32 bits) | label (high 32 bits)
g_dd_ids:       .quad 0     # group id record -> number
g_dd_next_lab:  .quad 0
g_dd_next_id:   .quad 0
g_wp:           .quad 0     # wire cursor
g_we:           .quad 0     # wire end
g_wp_labels:    .quad 0     # N -> doc
g_wp_ids:       .quad 0     # N -> group id record
    .globl g_cur_doc, g_debug_doc
g_cur_doc:      .quad 0
g_debug_doc:    .quad 0     # --debug-doc given
    .globl g_dd_exact
g_dd_exact:     .quad 0     # 1: arrays and strings as they are

    .section .rodata
hex_digits: .ascii "0123456789abcdef"

    .text

# out_dec(n): signed decimal
FUNC out_dec
    sub rsp, 32
    mov rax, rdi
    lea rsi, [rsp + 31]
    xor r8d, r8d
    test rax, rax
    jns 1f
    neg rax
    mov r8d, 1
1:  mov ecx, 10
2:  xor edx, edx
    div rcx
    add dl, '0'
    mov [rsi], dl
    dec rsi
    test rax, rax
    jnz 2b
    test r8d, r8d
    jz 3f
    mov byte ptr [rsi], '-'
    dec rsi
3:  inc rsi
    lea rdx, [rsp + 32]
    sub rdx, rsi
    mov rdi, rsi
    mov rsi, rdx
    call out_raw
    leave
    ret
ENDF out_dec

# out_json_body(ptr, len): string bytes escaped as JSON.stringify does
FUNC out_json_body
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov r13, rdi                    # start of the pending run
1:  cmp rbx, r12
    jae 8f
    movzx eax, byte ptr [rbx]
    cmp al, '"'
    je 2f
    cmp al, '\\'
    je 2f
    cmp al, 0x20
    jb 2f
    inc rbx
    jmp 1b
2:  mov rdi, r13
    mov rsi, rbx
    sub rsi, r13
    call out_raw
    movzx eax, byte ptr [rbx]
    inc rbx
    mov r13, rbx
    mov r14d, eax
    mov edi, '\\'
    call out_byte
    mov eax, r14d
    lea rcx, [rip + json_short]
    movzx edi, byte ptr [rcx + rax]
    test edi, edi
    jz 3f
    call out_byte
    jmp 1b
3:  mov edi, 'u'
    call out_byte
    mov edi, '0'
    call out_byte
    mov edi, '0'
    call out_byte
    lea rcx, [rip + hex_digits]
    mov eax, r14d
    shr eax, 4
    movzx edi, byte ptr [rcx + rax]
    call out_byte
    lea rcx, [rip + hex_digits]
    mov eax, r14d
    and eax, 15
    movzx edi, byte ptr [rcx + rax]
    call out_byte
    jmp 1b
8:  mov rdi, r13
    mov rsi, r12
    sub rsi, r13
    call out_raw
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF out_json_body

    .section .rodata
# escape letter for bytes below 0x20 and for '"' and '\', or 0 for \u00XX
json_short:
    .byte 0,0,0,0,0,0,0,0, 'b','t','n',0,'f','r',0,0
    .byte 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    .byte 0,0,'"',0,0,0,0,0, 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0, 0,0,0,0,'\\',0,0,0
    .text

# is_empty_str(doc) -> eax: doc is "" (0 or a string of length 0)
FUNC is_empty_str
    mov eax, 1
    test rdi, rdi
    jz 1f
    xor eax, eax
    cmp byte ptr [rdi], DK_STR
    jne 1f
    cmp dword ptr [rdi + DS_LEN], 0
    sete al
1:  leave
    ret
ENDF is_empty_str

# ---------------------------------------------------------------- dump
# doc_dump(doc): the canonical text of doc, appended to the output buffer.
FUNC doc_dump
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov edi, 1024
    call ptrmap_new
    mov [rip + g_dd_refs], rax
    mov edi, 64
    call ptrmap_new
    mov [rip + g_dd_ids], rax
    mov qword ptr [rip + g_dd_next_lab], 0
    mov qword ptr [rip + g_dd_next_id], 0
    mov rdi, rbx
    call dd_count
    mov rdi, rbx
    call dd_emit
    add rsp, 8
    pop rbx
    leave
    ret
ENDF doc_dump

# dd_count(doc): counts references to containers, visiting each once
FUNC dd_count
    push rbx
    push r12
    mov rbx, rdi
1:  test rbx, rbx
    jz 9f
    movzx eax, byte ptr [rbx]
    cmp eax, DK_ARRAY
    jne 3f
    cmp qword ptr [rip + g_dd_exact], 0
    jne 3f
5:  xor r12d, r12d
2:  cmp r12d, [rbx + DA_COUNT]
    jae 9f
    mov rdi, [rbx + DA_ITEMS + r12*8]
    inc r12d
    call dd_count
    jmp 2b
3:  call dd_is_container
    test eax, eax
    jz 9f
    mov rdi, [rip + g_dd_refs]
    mov rsi, rbx
    call ptrmap_slot
    inc dword ptr [rax]
    test edx, edx
    jnz 9f
    movzx eax, byte ptr [rbx]
    cmp eax, DK_ARRAY
    je 5b
    cmp eax, DK_GROUP
    je 20f
    cmp eax, DK_FILL
    je 30f
    cmp eax, DK_IF_BREAK
    je 40f
    mov rbx, [rbx + D_CONTENTS]
    jmp 1b
20: mov r12, [rbx + G_EXPANDED]
    test r12, r12
    jz 21f
    mov rdi, [rbx + G_CONTENTS]
    cmp rdi, [r12 + DA_ITEMS]
    je 22f
    call dd_count
22: mov rbx, r12
    jmp 5b                          # each state
21: mov rbx, [rbx + G_CONTENTS]
    jmp 1b
30: mov rbx, [rbx + FILL_PARTS]
    jmp 5b
40: mov rdi, [rbx + IB_BREAK]
    call dd_count
    mov rbx, [rbx + IB_FLAT]
    jmp 1b
9:  pop r12
    pop rbx
    leave
    ret
ENDF dd_count

# dd_is_container: rbx doc -> eax. Leaf, no frame; preserves all but rax.
dd_is_container:
    movzx eax, byte ptr [rbx]
    cmp eax, DK_ARRAY
    jne 2f
    cmp qword ptr [rip + g_dd_exact], 0
    jne 1f
2:  cmp eax, DK_INDENT
    je 1f
    cmp eax, DK_ALIGN
    je 1f
    cmp eax, DK_GROUP
    je 1f
    cmp eax, DK_FILL
    je 1f
    cmp eax, DK_IF_BREAK
    je 1f
    cmp eax, DK_INDENT_IF_BREAK
    je 1f
    cmp eax, DK_LINE_SUFFIX
    je 1f
    cmp eax, DK_LABEL
    je 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

# dd_flatten(doc): pushes the non-empty items of doc, arrays flattened
FUNC dd_flatten
    push rbx
    push r12
    mov rbx, rdi
    mov rdi, rbx
    call is_empty_str
    test eax, eax
    jnz 9f
    cmp byte ptr [rbx], DK_ARRAY
    je 1f
    mov rdi, rbx
    call ss_push
    jmp 9f
1:  xor r12d, r12d
2:  cmp r12d, [rbx + DA_COUNT]
    jae 9f
    mov rdi, [rbx + DA_ITEMS + r12*8]
    inc r12d
    call dd_flatten
    jmp 2b
9:  pop r12
    pop rbx
    leave
    ret
ENDF dd_flatten

# dd_emit(doc): a doc in canonical form
FUNC dd_emit
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    cmp qword ptr [rip + g_dd_exact], 0
    je 10f
    mov rbx, rdi
    call is_empty_str
    test eax, eax
    jz 11f
    OUTS "\"\""
    jmp 19f
11: cmp byte ptr [rbx], DK_STR
    je 12f
    mov rdi, rbx
    call dd_emit_one
    jmp 19f
12: mov edi, '"'
    call out_byte
    mov rdi, [rbx + DS_PTR]
    mov esi, [rbx + DS_LEN]
    call out_json_body
    mov edi, '"'
    call out_byte
    jmp 19f
10: call ss_mark
    mov r12, rax                    # items start
    call dd_flatten
    mov r13, [rip + g_ss_ptr]       # items end
    # count the items after merging strings
    xor r14d, r14d
    xor ecx, ecx                    # previous was a string
    mov rax, r12
1:  cmp rax, r13
    jae 3f
    mov rdx, [rax]
    add rax, 8
    cmp byte ptr [rdx], DK_STR
    jne 2f
    test ecx, ecx
    jnz 1b
    mov ecx, 1
    inc r14
    jmp 1b
2:  xor ecx, ecx
    inc r14
    jmp 1b
3:  test r14, r14
    jnz 4f
    OUTS "\"\""
    jmp 9f
4:  cmp r14, 1
    je 5f
    mov edi, '['
    call out_byte
5:  mov r15, r12
    xor ebx, ebx                    # items written
6:  cmp r15, r13
    jae 8f
    test rbx, rbx
    jz 61f
    mov edi, ' '
    call out_byte
61: inc rbx
    mov rdi, [r15]
    cmp byte ptr [rdi], DK_STR
    je 7f
    add r15, 8
    call dd_emit_one
    jmp 6b
    # a run of strings, as one
7:  mov edi, '"'
    call out_byte
71: cmp r15, r13
    jae 72f
    mov rax, [r15]
    cmp byte ptr [rax], DK_STR
    jne 72f
    add r15, 8
    mov rdi, [rax + DS_PTR]
    mov esi, [rax + DS_LEN]
    call out_json_body
    jmp 71b
72: mov edi, '"'
    call out_byte
    jmp 6b
8:  cmp r14, 1
    je 9f
    mov edi, ']'
    call out_byte
9:  mov [rip + g_ss_ptr], r12
19: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF dd_emit

# dd_emit_id(id): `#N`
FUNC dd_emit_id
    push rbx
    sub rsp, 8
    mov rsi, rdi
    mov rdi, [rip + g_dd_ids]
    call ptrmap_slot
    mov rbx, rax
    test edx, edx
    jnz 1f
    inc qword ptr [rip + g_dd_next_id]
    mov rcx, [rip + g_dd_next_id]
    mov [rbx], rcx
1:  mov edi, '#'
    call out_byte
    mov rdi, [rbx]
    call out_dec
    add rsp, 8
    pop rbx
    leave
    ret
ENDF dd_emit_id

# dd_emit_one(doc): a doc that is neither an array nor a string
FUNC dd_emit_one
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    movzx eax, byte ptr [rbx]
    cmp eax, DK_LINE
    je 50f
    call dd_is_container
    test eax, eax
    jz 60f
    # shared container: $N= the first time, $N after
    mov rdi, [rip + g_dd_refs]
    mov rsi, rbx
    call ptrmap_slot
    mov r12, rax
    cmp dword ptr [r12], 1
    jbe 10f
    mov eax, [r12 + 4]
    test eax, eax
    jz 1f
    mov edi, '$'
    call out_byte
    mov edi, [r12 + 4]
    call out_dec
    jmp 99f
1:  inc qword ptr [rip + g_dd_next_lab]
    mov rax, [rip + g_dd_next_lab]
    mov [r12 + 4], eax
    mov edi, '$'
    call out_byte
    mov edi, [r12 + 4]
    call out_dec
    mov edi, '='
    call out_byte
10: movzx eax, byte ptr [rbx]
    cmp eax, DK_ARRAY
    je 15f
    cmp eax, DK_INDENT
    je 11f
    cmp eax, DK_ALIGN
    je 12f
    cmp eax, DK_GROUP
    je 20f
    cmp eax, DK_FILL
    je 30f
    cmp eax, DK_IF_BREAK
    je 40f
    cmp eax, DK_INDENT_IF_BREAK
    je 45f
    cmp eax, DK_LINE_SUFFIX
    je 13f
    # label
    OUTS "(label \""
    mov rdi, [rbx + DL_LABEL]
    call dd_label_text
    OUTS "\" "
    jmp 19f
11: OUTS "(indent "
    jmp 19f
15: mov edi, '['
    call out_byte
    xor r13d, r13d
16: cmp r13d, [rbx + DA_COUNT]
    jae 17f
    test r13d, r13d
    jz 161f
    mov edi, ' '
    call out_byte
161: mov rdi, [rbx + DA_ITEMS + r13*8]
    inc r13d
    call dd_emit
    jmp 16b
17: mov edi, ']'
    call out_byte
    jmp 99f
13: OUTS "(lsuffix "
    jmp 19f
12: OUTS "(align "
    movzx eax, byte ptr [rbx + 1]
    cmp eax, AK_NUMBER
    jne 121f
    mov rdi, [rbx + DAL_N]
    call out_dec
    jmp 129f
121: cmp eax, AK_STRING
    jne 122f
    mov edi, '"'
    call out_byte
    mov rax, [rbx + DAL_N]
    mov rdi, [rax + DS_PTR]
    mov esi, [rax + DS_LEN]
    call out_json_body
    mov edi, '"'
    call out_byte
    jmp 129f
122: cmp eax, AK_NEG_INF
    jne 123f
    OUTS "-inf"
    jmp 129f
123: cmp eax, AK_ROOT
    jne 124f
    OUTS "root"
    jmp 129f
124: OUTS "-1"
129: mov edi, ' '
    call out_byte
    # contents, then ")"
19: mov rdi, [rbx + D_CONTENTS]
    call dd_emit
    jmp 98f
20: cmp qword ptr [rbx + G_EXPANDED], 0
    jne 21f
    OUTS "(group"
    jmp 22f
21: mov rax, [rbx + G_EXPANDED]
    mov rax, [rax + DA_ITEMS]
    cmp rax, [rbx + G_CONTENTS]
    jne 211f
    OUTS "(cgroup"
    jmp 22f
211: OUTS "(cgroup*"
22: movzx eax, byte ptr [rbx + G_FLAGS]
    test al, GF_BREAK
    jz 24f
    test al, GF_PROPAGATED
    jz 23f
    OUTS " pbreak"
    jmp 24f
23: OUTS " break"
24: mov rdi, [rbx + G_ID]
    test rdi, rdi
    jz 25f
    push rdi
    sub rsp, 8
    mov edi, ' '
    call out_byte
    add rsp, 8
    pop rdi
    call dd_emit_id
25: mov r12, [rbx + G_EXPANDED]
    test r12, r12
    jnz 26f
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + G_CONTENTS]
    call dd_emit
    jmp 98f
26: mov rax, [r12 + DA_ITEMS]
    cmp rax, [rbx + G_CONTENTS]
    je 261f
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + G_CONTENTS]
    call dd_emit
261: xor r13d, r13d
27: cmp r13d, [r12 + DA_COUNT]
    jae 98f
    mov edi, ' '
    call out_byte
    mov rdi, [r12 + DA_ITEMS + r13*8]
    inc r13d
    call dd_emit
    jmp 27b
30: OUTS "(fill"
    mov r12, [rbx + FILL_PARTS]
    mov r13d, [rbx + FILL_OFFSET]
31: cmp r13d, [r12 + DA_COUNT]
    jae 98f
    mov edi, ' '
    call out_byte
    mov rdi, [r12 + DA_ITEMS + r13*8]
    inc r13d
    call dd_emit
    jmp 31b
40: OUTS "(ifbreak "
    mov rdi, [rbx + IB_BREAK]
    call dd_emit
    mov edi, ' '
    call out_byte
    mov rdi, [rbx + IB_FLAT]
    call dd_emit
    mov rdi, [rbx + IB_GROUP]
    test rdi, rdi
    jz 98f
    push rdi
    sub rsp, 8
    mov edi, ' '
    call out_byte
    add rsp, 8
    pop rdi
    call dd_emit_id
    jmp 98f
45: OUTS "(iib "
    test byte ptr [rbx + IIB_NEGATE], 1
    jz 46f
    OUTS "negate "
46: mov rdi, [rbx + IIB_GROUP]
    test rdi, rdi
    jz 47f
    call dd_emit_id
    mov edi, ' '
    call out_byte
47: mov rdi, [rbx + IIB_CONTENTS]
    call dd_emit
98: mov edi, ')'
    call out_byte
    jmp 99f
50: movzx eax, byte ptr [rbx + 1]
    test al, LF_LITERAL
    jz 51f
    OUTS "lit"
    jmp 99f
51: test al, LF_HARD
    jz 52f
    OUTS "hard"
    jmp 99f
52: test al, LF_SOFT
    jz 53f
    OUTS "soft"
    jmp 99f
53: OUTS "line"
    jmp 99f
60: movzx eax, byte ptr [rbx]
    cmp eax, DK_BREAK_PARENT
    jne 61f
    OUTS "bp"
    jmp 99f
61: cmp eax, DK_LINE_SUFFIX_BOUNDARY
    jne 62f
    OUTS "lsb"
    jmp 99f
62: cmp eax, DK_TRIM
    jne 63f
    OUTS "trim"
    jmp 99f
63: cmp eax, DK_CURSOR
    jne 64f
    OUTS "cursor"
    jmp 99f
64: REFUSE "invalid doc in dump"
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF dd_emit_one

# dd_label_text(bits): sorted key=value pairs, comma separated
FUNC dd_label_text
    push rbx
    push r12
    mov rbx, rdi
    xor r12d, r12d                  # pairs written
    test ebx, LB_EMBED
    jz 1f
    call 80f
    OUTS "embed=true"
1:  test ebx, LB_HUG_FALSE
    jz 2f
    call 80f
    OUTS "hug=false"
2:  test ebx, LB_HUG_TRUE
    jz 3f
    call 80f
    OUTS "hug=true"
3:  test ebx, LB_MEMBER_CHAIN
    jz 4f
    call 80f
    OUTS "memberChain=true"
4:  test ebx, LB_TAGGED
    jz 5f
    call 80f
    OUTS "tagged=true"
5:  pop r12
    pop rbx
    leave
    ret
    # comma before every pair but the first (called with one extra push)
80: test r12d, r12d
    jz 81f
    sub rsp, 8
    mov edi, ','
    call out_byte
    add rsp, 8
81: inc r12d
    ret
ENDF dd_label_text

# ---------------------------------------------------------------- wire reader
# wp_ws(): skip blanks
FUNC wp_ws
    mov rax, [rip + g_wp]
    mov rcx, [rip + g_we]
1:  cmp rax, rcx
    jae 2f
    movzx edx, byte ptr [rax]
    cmp dl, ' '
    je 3f
    cmp dl, 10
    je 3f
    cmp dl, 9
    je 3f
    cmp dl, 13
    jne 2f
3:  inc rax
    jmp 1b
2:  mov [rip + g_wp], rax
    leave
    ret
ENDF wp_ws

# wp_peek() -> eax: next byte after blanks, or -1 at the end
FUNC wp_peek
    call wp_ws
    mov rax, [rip + g_wp]
    cmp rax, [rip + g_we]
    jae 1f
    movzx eax, byte ptr [rax]
    leave
    ret
1:  mov eax, -1
    leave
    ret
ENDF wp_peek

# wp_expect(c)
FUNC wp_expect
    push rdi
    sub rsp, 8
    call wp_peek
    add rsp, 8
    pop rdi
    cmp eax, edi
    jne 9f
    inc qword ptr [rip + g_wp]
    leave
    ret
9:  REFUSE "doc wire: unexpected character"
ENDF wp_expect

# wp_word() -> rax = ptr, rdx = len: letters, digits, '-', '_', '.'
FUNC wp_word
    call wp_ws
    mov rax, [rip + g_wp]
    mov rcx, [rip + g_we]
    mov rdx, rax
1:  cmp rdx, rcx
    jae 2f
    movzx r8d, byte ptr [rdx]
    cmp r8b, '-'
    je 3f
    cmp r8b, '_'
    je 3f
    cmp r8b, '.'
    je 3f
    cmp r8b, '0'
    jb 2f
    cmp r8b, '9'
    jbe 3f
    or r8b, 0x20
    cmp r8b, 'a'
    jb 2f
    cmp r8b, 'z'
    ja 2f
3:  inc rdx
    jmp 1b
2:  mov [rip + g_wp], rdx
    sub rdx, rax
    leave
    ret
ENDF wp_word

# wp_word_is(ptr, len, cstr) -> eax
FUNC wp_word_is
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rdx
    call strlen
    cmp rax, r12
    jne 8f
    mov rsi, rdi
    mov rdi, rbx
    mov rdx, r12
    call mem_eq
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF wp_word_is

# wp_int() -> rax: a decimal integer, "inf" (PW_INFINITY) or "-inf" (its negation)
FUNC wp_int
    call wp_word
    test rdx, rdx
    jz 9f
    xor r8d, r8d
    cmp byte ptr [rax], '-'
    jne 1f
    mov r8d, 1
    inc rax
    dec rdx
1:  cmp rdx, 3
    jne 2f
    cmp word ptr [rax], 'i' | ('n' << 8)
    jne 2f
    cmp byte ptr [rax + 2], 'f'
    jne 2f
    mov rax, PW_INFINITY
    jmp 5f
2:  mov rsi, rax
    lea rdi, [rax + rdx]
    xor eax, eax
    test rdx, rdx
    jz 9f
3:  cmp rsi, rdi
    jae 5f
    movzx ecx, byte ptr [rsi]
    sub ecx, '0'
    cmp ecx, 9
    ja 9f
    imul rax, rax, 10
    add rax, rcx
    inc rsi
    jmp 3b
5:  test r8d, r8d
    jz 6f
    neg rax
6:  leave
    ret
9:  REFUSE "doc wire: expected a number"
ENDF wp_int

# wp_hex4(ptr) -> eax, or -1
FUNC wp_hex4
    xor eax, eax
    xor ecx, ecx
1:  cmp ecx, 4
    jae 9f
    movzx edx, byte ptr [rdi + rcx]
    inc ecx
    shl eax, 4
    cmp dl, '0'
    jb 8f
    cmp dl, '9'
    ja 2f
    sub dl, '0'
    or al, dl
    jmp 1b
2:  or dl, 0x20
    cmp dl, 'a'
    jb 8f
    cmp dl, 'f'
    ja 8f
    sub dl, 'a' - 10
    or al, dl
    jmp 1b
8:  mov eax, -1
9:  leave
    ret
ENDF wp_hex4

# wp_string() -> rax = ptr, rdx = len: a JSON string, decoded to UTF-8
FUNC wp_string
    push rbx
    push r12
    push r13
    push r14
    mov edi, '"'
    call wp_expect
    mov rbx, [rip + g_wp]
    mov r14, [rip + g_we]
    # the decoded text is never longer than the source up to the closing quote
    mov rdi, rbx
6:  cmp rdi, r14
    jae 7f
    movzx eax, byte ptr [rdi]
    inc rdi
    cmp al, '"'
    je 7f
    cmp al, '\\'
    jne 6b
    inc rdi
    jmp 6b
7:  sub rdi, rbx
    call alloc
    mov r12, rax                    # start
    mov r13, rax                    # write cursor
1:  cmp rbx, r14
    jae 90f
    movzx eax, byte ptr [rbx]
    inc rbx
    cmp al, '"'
    je 8f
    cmp al, '\\'
    je 2f
    mov [r13], al
    inc r13
    jmp 1b
2:  cmp rbx, r14
    jae 90f
    movzx eax, byte ptr [rbx]
    inc rbx
    lea rcx, [rip + json_unescape]
    cmp al, 'u'
    je 3f
    cmp eax, 128
    jae 90f
    movzx ecx, byte ptr [rcx + rax]
    test ecx, ecx
    jz 90f
    mov [r13], cl
    inc r13
    jmp 1b
3:  lea rax, [rbx + 4]
    cmp rax, r14
    ja 90f
    mov rdi, rbx
    call wp_hex4
    test eax, eax
    js 90f
    add rbx, 4
    cmp eax, 0xD800
    jb 5f
    cmp eax, 0xDFFF
    ja 5f
    cmp eax, 0xDC00
    jae 90f                         # lone low surrogate
    # a high surrogate must be followed by \uDC00..\uDFFF
    lea rcx, [rbx + 6]
    cmp rcx, r14
    ja 90f
    cmp word ptr [rbx], '\\' | ('u' << 8)
    jne 90f
    push rax
    sub rsp, 8
    lea rdi, [rbx + 2]
    call wp_hex4
    add rsp, 8
    pop rcx
    cmp eax, 0xDC00
    jb 90f
    cmp eax, 0xDFFF
    ja 90f
    add rbx, 6
    sub ecx, 0xD800
    shl ecx, 10
    sub eax, 0xDC00
    add eax, ecx
    add eax, 0x10000
5:  mov rdi, r13
    mov esi, eax
    call utf8_encode
    add r13, rax
    jmp 1b
8:  mov [rip + g_wp], rbx
    mov rax, r12
    mov rdx, r13
    sub rdx, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "doc wire: bad string"
ENDF wp_string

    .section .rodata
json_unescape:
    .space '"', 0
    .byte '"'
    .space '/' - '"' - 1, 0
    .byte '/'
    .space '\\' - '/' - 1, 0
    .byte '\\'
    .space 'b' - '\\' - 1, 0
    .byte 8
    .space 'f' - 'b' - 1, 0
    .byte 12
    .space 'n' - 'f' - 1, 0
    .byte 10
    .space 'r' - 'n' - 1, 0
    .byte 13
    .space 't' - 'r' - 1, 0
    .byte 9
    .space 128 - 't' - 1, 0
    .text

# utf8_encode(dst, cp) -> rax = bytes written
FUNC utf8_encode
    cmp esi, 0x80
    jae 1f
    mov [rdi], sil
    mov eax, 1
    leave
    ret
1:  cmp esi, 0x800
    jae 2f
    mov eax, esi
    shr eax, 6
    or al, 0xC0
    mov [rdi], al
    mov eax, esi
    and al, 0x3F
    or al, 0x80
    mov [rdi + 1], al
    mov eax, 2
    leave
    ret
2:  cmp esi, 0x10000
    jae 3f
    mov eax, esi
    shr eax, 12
    or al, 0xE0
    mov [rdi], al
    mov eax, esi
    shr eax, 6
    and al, 0x3F
    or al, 0x80
    mov [rdi + 1], al
    mov eax, esi
    and al, 0x3F
    or al, 0x80
    mov [rdi + 2], al
    mov eax, 3
    leave
    ret
3:  mov eax, esi
    shr eax, 18
    or al, 0xF0
    mov [rdi], al
    mov eax, esi
    shr eax, 12
    and al, 0x3F
    or al, 0x80
    mov [rdi + 1], al
    mov eax, esi
    shr eax, 6
    and al, 0x3F
    or al, 0x80
    mov [rdi + 2], al
    mov eax, esi
    and al, 0x3F
    or al, 0x80
    mov [rdi + 3], al
    mov eax, 4
    leave
    ret
ENDF utf8_encode

# wp_id() -> rax: the group id record for `#N`
FUNC wp_id
    push rbx
    sub rsp, 8
    mov edi, '#'
    call wp_expect
    call wp_int
    mov rsi, rax
    mov rdi, [rip + g_wp_ids]
    call ptrmap_slot
    mov rbx, rax
    test edx, edx
    jnz 1f
    mov edi, GID_SIZE
    call alloc
    mov byte ptr [rax], DK_GROUP_ID
    mov [rbx], rax
1:  mov rax, [rbx]
    add rsp, 8
    pop rbx
    leave
    ret
ENDF wp_id

# wp_options(po): W TW TABS EOL into a print options record
FUNC wp_options
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call wp_int
    mov [rbx + PO_WIDTH], rax
    call wp_int
    mov [rbx + PO_TAB_WIDTH], rax
    call wp_int
    mov [rbx + PO_USE_TABS], rax
    call wp_word
    mov qword ptr [rbx + PO_EOL], EOL_LF
    cmp rdx, 4
    jne 1f
    mov qword ptr [rbx + PO_EOL], EOL_CRLF
    jmp 2f
1:  cmp word ptr [rax], 'c' | ('r' << 8)
    jne 2f
    mov qword ptr [rbx + PO_EOL], EOL_CR
2:  add rsp, 8
    pop rbx
    leave
    ret
ENDF wp_options

# wp_doc() -> rax: one doc
FUNC wp_doc
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, PO_SIZE + 8
    call wp_peek
    cmp eax, '"'
    je 10f
    cmp eax, '['
    je 20f
    cmp eax, '$'
    je 30f
    cmp eax, '('
    je 40f
    # leaf keyword
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea r13, [rip + leaf_words]
1:  mov rdx, [r13]
    test rdx, rdx
    jz 90f
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    test eax, eax
    jnz 2f
    add r13, 16
    jmp 1b
2:  mov rax, [r13 + 8]
    jmp 99f
10: call wp_string
    xor ecx, ecx
    test rdx, rdx
    jz 11f
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    mov rcx, rax
11: mov rax, rcx
    jmp 99f
20: inc qword ptr [rip + g_wp]
    call ss_mark
    mov rbx, rax
21: call wp_peek
    cmp eax, ']'
    je 22f
    call wp_doc
    mov rdi, rax
    call ss_push
    jmp 21b
22: inc qword ptr [rip + g_wp]
    mov rdi, rbx
    call ss_to_array_keep
    jmp 99f
    # $N= definition or $N reference
30: inc qword ptr [rip + g_wp]
    call wp_int
    mov rbx, rax
    mov rax, [rip + g_wp]
    cmp rax, [rip + g_we]
    jae 31f
    cmp byte ptr [rax], '='
    jne 31f
    inc qword ptr [rip + g_wp]
    call wp_doc
    mov r12, rax
    mov rdi, [rip + g_wp_labels]
    mov rsi, rbx
    mov rdx, r12
    call ptrmap_put
    mov rax, r12
    jmp 99f
31: mov rdi, [rip + g_wp_labels]
    mov rsi, rbx
    call ptrmap_get
    test edx, edx
    jz 90f
    jmp 99f
40: inc qword ptr [rip + g_wp]
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea r13, [rip + head_words]
41: mov rdx, [r13]
    test rdx, rdx
    jz 90f
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    test eax, eax
    jnz 42f
    add r13, 16
    jmp 41b
42: call [r13 + 8]
    mov rbx, rax
    mov edi, ')'
    call wp_expect
    mov rax, rbx
99: add rsp, PO_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "doc wire: unknown word"
ENDF wp_doc

# Container readers: called after the head word, return the doc; the ")" is
# read by wp_doc.
FUNC wh_indent
    call wp_doc
    mov rdi, rax
    call doc_indent
    leave
    ret
ENDF wh_indent

FUNC wh_lsuffix
    call wp_doc
    mov rdi, rax
    call doc_line_suffix
    leave
    ret
ENDF wh_lsuffix

FUNC wh_align
    push rbx
    push r12
    call wp_peek
    cmp eax, '"'
    je 3f
    call wp_word
    mov rbx, rax
    mov r12, rdx
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + s_root]
    call wp_word_is
    test eax, eax
    jz 1f
    mov ebx, AK_ROOT
    xor r12d, r12d
    jmp 5f
1:  mov rdi, rbx
    mov rsi, r12
    lea rdx, [rip + s_neg_inf]
    call wp_word_is
    test eax, eax
    jz 2f
    mov ebx, AK_NEG_INF
    xor r12d, r12d
    jmp 5f
    # a number: read it again from its start
2:  mov [rip + g_wp], rbx
    call wp_int
    mov r12, rax
    mov ebx, AK_NUMBER
    jmp 5f
3:  call wp_string
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    mov r12, rax
    mov ebx, AK_STRING
5:  call wp_doc
    mov edi, ebx
    mov rsi, r12
    mov rdx, rax
    call doc_align
    pop r12
    pop rbx
    leave
    ret
ENDF wh_align

# wh_group_flags() -> rax = GF_* flags, rdx = id record or 0
FUNC wh_group_flags
    push rbx
    push r12
    push r13
    push r14
    xor ebx, ebx
    xor r12d, r12d
1:  call wp_peek
    cmp eax, '#'
    jne 2f
    call wp_id
    mov r12, rax
    or ebx, GF_HAS_ID
    jmp 1b
2:  cmp eax, 'b'
    je 3f
    cmp eax, 'p'
    jne 9f
3:  mov r13, [rip + g_wp]
    call wp_word
    mov rdi, rax
    mov rsi, rdx
    mov r14, rax
    lea rdx, [rip + s_break]
    call wp_word_is
    test eax, eax
    jz 4f
    or ebx, GF_BREAK
    jmp 1b
4:  mov rdi, r14
    mov rsi, [rip + g_wp]
    sub rsi, r14
    lea rdx, [rip + s_pbreak]
    call wp_word_is
    test eax, eax
    jz 5f
    or ebx, GF_BREAK | GF_PROPAGATED
    jmp 1b
    # not a flag (a leaf word such as "bp"): put it back
5:  mov [rip + g_wp], r13
9:  mov eax, ebx
    mov rdx, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF wh_group_flags

FUNC wh_group
    push rbx
    push r12
    call wh_group_flags
    mov rbx, rax
    mov r12, rdx
    call wp_doc
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov [rax + G_FLAGS], bl
    mov [rax + G_ID], r12
    pop r12
    pop rbx
    leave
    ret
ENDF wh_group

FUNC wh_cgroup
    push rbx
    push r12
    push r13
    push r14
    xor r14d, r14d                  # explicit contents
    mov rax, [rip + g_wp]
    cmp byte ptr [rax], '*'
    jne 3f
    inc qword ptr [rip + g_wp]
    mov r14d, 1
3:  call wh_group_flags
    mov rbx, rax
    mov r12, rdx
    test r14d, r14d
    jz 4f
    call wp_doc
    mov r14, rax
4:  call ss_mark
    mov r13, rax
1:  call wp_peek
    cmp eax, ')'
    je 2f
    call wp_doc
    mov rdi, rax
    call ss_push
    jmp 1b
2:  mov rdi, r13
    call ss_to_array_keep
    mov r13, rax
    mov rdi, [r13 + DA_ITEMS]
    test r14, r14
    jz 5f
    mov rdi, r14
5:  xor esi, esi
    call doc_group
    mov [rax + G_FLAGS], bl
    mov [rax + G_ID], r12
    mov [rax + G_EXPANDED], r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF wh_cgroup

FUNC wh_fill
    push rbx
    sub rsp, 8
    call ss_mark
    mov rbx, rax
1:  call wp_peek
    cmp eax, ')'
    je 2f
    call wp_doc
    mov rdi, rax
    call ss_push
    jmp 1b
2:  mov rdi, rbx
    call ss_to_array_keep
    mov rdi, rax
    call doc_fill
    add rsp, 8
    pop rbx
    leave
    ret
ENDF wh_fill

FUNC wh_ifbreak
    push rbx
    push r12
    push r13
    sub rsp, 8
    call wp_doc
    mov rbx, rax
    call wp_doc
    mov r12, rax
    xor r13d, r13d
    call wp_peek
    cmp eax, '#'
    jne 1f
    call wp_id
    mov r13, rax
1:  mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call doc_if_break
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF wh_ifbreak

FUNC wh_iib
    push rbx
    push r12
    push r13
    sub rsp, 8
    xor ebx, ebx                    # negate
    xor r12d, r12d                  # id
    call wp_peek
    cmp eax, 'n'
    jne 1f
    mov r13, [rip + g_wp]
    call wp_word
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + s_negate]
    call wp_word_is
    test eax, eax
    jnz 11f
    mov [rip + g_wp], r13
    jmp 1f
11: mov ebx, 1
1:  call wp_peek
    cmp eax, '#'
    jne 2f
    call wp_id
    mov r12, rax
2:  call wp_doc
    mov rdi, rax
    mov rsi, r12
    mov edx, ebx
    call doc_indent_if_break
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF wh_iib

FUNC wh_label
    push rbx
    push r12
    push r13
    push r14
    call wp_string
    # key=value pairs separated by commas
    mov r12, rax
    lea r13, [rax + rdx]
    xor ebx, ebx
1:  cmp r12, r13
    jae 5f
    mov r14, r12
2:  cmp r14, r13
    jae 3f
    cmp byte ptr [r14], ','
    je 3f
    inc r14
    jmp 2b
3:  lea rcx, [rip + label_words]
4:  mov rdx, [rcx]
    test rdx, rdx
    jz 90f
    push rcx
    sub rsp, 8
    mov rdi, r12
    mov rsi, r14
    sub rsi, r12
    call wp_word_is
    add rsp, 8
    pop rcx
    test eax, eax
    jnz 41f
    add rcx, 16
    jmp 4b
41: or rbx, [rcx + 8]
    lea r12, [r14 + 1]
    jmp 1b
5:  call wp_doc
    mov rdi, rbx
    mov rsi, rax
    call doc_label
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "doc wire: unknown label"
ENDF wh_label

# (tostr W TW TABS EOL D): printDocToString(D).formatted, as a string doc
FUNC wh_tostr
    push rbx
    sub rsp, PO_SIZE + 8
    mov rdi, rsp
    call wp_options
    call wp_doc
    mov rdi, rax
    mov rsi, rsp
    call print_doc_to_string
    xor ebx, ebx
    test rdx, rdx
    jz 1f
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    mov rbx, rax
1:  mov rax, rbx
    add rsp, PO_SIZE + 8
    pop rbx
    leave
    ret
ENDF wh_tostr

    .section .rodata
s_root:     .asciz "root"
s_neg_inf:  .asciz "-inf"
s_break:    .asciz "break"
s_pbreak:   .asciz "pbreak"
s_negate:   .asciz "negate"
w_line:     .asciz "line"
w_soft:     .asciz "soft"
w_hard:     .asciz "hard"
w_lit:      .asciz "lit"
w_bp:       .asciz "bp"
w_lsb:      .asciz "lsb"
w_trim:     .asciz "trim"
w_cursor:   .asciz "cursor"
w_indent:   .asciz "indent"
w_align:    .asciz "align"
w_group:    .asciz "group"
w_cgroup:   .asciz "cgroup"
w_fill:     .asciz "fill"
w_ifbreak:  .asciz "ifbreak"
w_iib:      .asciz "iib"
w_lsuffix:  .asciz "lsuffix"
w_label:    .asciz "label"
w_tostr:    .asciz "tostr"
l_embed:    .asciz "embed=true"
l_hug_f:    .asciz "hug=false"
l_hug_t:    .asciz "hug=true"
l_member:   .asciz "memberChain=true"
l_tagged:   .asciz "tagged=true"
    .balign 8
leaf_words:
    .quad w_line, d_line
    .quad w_soft, d_softline
    .quad w_hard, d_hardline_nb
    .quad w_lit, d_literalline_nb
    .quad w_bp, d_break_parent
    .quad w_lsb, d_line_suffix_boundary
    .quad w_trim, d_trim
    .quad w_cursor, d_cursor
    .quad 0, 0
head_words:
    .quad w_indent, wh_indent
    .quad w_align, wh_align
    .quad w_group, wh_group
    .quad w_cgroup, wh_cgroup
    .quad w_fill, wh_fill
    .quad w_ifbreak, wh_ifbreak
    .quad w_iib, wh_iib
    .quad w_lsuffix, wh_lsuffix
    .quad w_label, wh_label
    .quad w_tostr, wh_tostr
    .quad 0, 0
label_words:
    .quad l_embed, LB_EMBED
    .quad l_hug_f, LB_HUG_FALSE
    .quad l_hug_t, LB_HUG_TRUE
    .quad l_member, LB_MEMBER_CHAIN
    .quad l_tagged, LB_TAGGED
    .quad 0, 0
    .text

# wire_reset(): new label and id tables for the next doc
FUNC wire_reset
    mov edi, 1024
    call ptrmap_new
    mov [rip + g_wp_labels], rax
    mov edi, 64
    call ptrmap_new
    mov [rip + g_wp_ids], rax
    leave
    ret
ENDF wire_reset

# ---------------------------------------------------------------- eval mode
# out_take(start) -> rax = ptr, rdx = len: the output written since start,
# moved to the arena and removed from the output buffer
FUNC out_take
    push rbx
    push r12
    mov rbx, rdi
    mov r12, [rip + g_out_ptr]
    sub r12, rbx
    mov rsi, r12
    call alloc_copy
    mov [rip + g_out_ptr], rbx
    mov rdx, r12
    pop r12
    pop rbx
    leave
    ret
ENDF out_take

# out_block(ptr, len): "<len>\n<bytes>\n"
FUNC out_block
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call out_dec
    mov edi, 10
    call out_byte
    mov rdi, rbx
    mov rsi, r12
    call out_raw
    mov edi, 10
    call out_byte
    pop r12
    pop rbx
    leave
    ret
ENDF out_block

# debug_eval_file(cstr_path): runs every command in the file, writes the
# results to stdout, exits.
FUNC debug_eval_file
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, PO_SIZE + 8
    call read_file
    test rax, rax
    jnz 90f
    call out_init
    mov rax, [rip + g_input]
    mov [rip + g_wp], rax
    add rax, [rip + g_input_len]
    mov [rip + g_we], rax
    call wire_reset
1:  call wp_peek
    cmp eax, -1
    je 80f
    mov edi, '('
    call wp_expect
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea r13, [rip + command_words]
2:  mov rdx, [r13]
    test rdx, rdx
    jz 91f
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    test eax, eax
    jnz 3f
    add r13, 16
    jmp 2b
3:  call [r13 + 8]
    mov edi, ')'
    call wp_expect
    jmp 1b
80: mov rdx, [rip + g_out_ptr]
    mov rsi, [rip + g_out_base]
    sub rdx, rsi
    mov edi, 1
    call write_all
    xor edi, edi
    call sys_exit
90: REFUSE "cannot read the eval file"
91: REFUSE "doc wire: unknown command"
ENDF debug_eval_file

# (doc D)
FUNC wc_doc
    call wire_reset
    call wp_doc
    mov [rip + g_cur_doc], rax
    leave
    ret
ENDF wc_doc

# (print W TW TABS EOL)
FUNC wc_print
    sub rsp, PO_SIZE
    mov rdi, rsp
    call wp_options
    mov rdi, [rip + g_cur_doc]
    mov rsi, rsp
    call print_doc_to_string
    mov rdi, rax
    mov rsi, rdx
    call out_block
    leave
    ret
ENDF wc_print

# (bench N W TW TABS EOL): print N times, write nothing
FUNC wc_bench
    push rbx
    sub rsp, PO_SIZE + 8
    call wp_int
    mov rbx, rax
    mov rdi, rsp
    call wp_options
1:  test rbx, rbx
    jz 2f
    dec rbx
    mov rdi, [rip + g_cur_doc]
    mov rsi, rsp
    call print_run
    mov [rip + g_out_ptr], rax
    jmp 1b
2:  add rsp, PO_SIZE + 8
    pop rbx
    leave
    ret
ENDF wc_bench

# (dumpx): exact form
FUNC wc_dumpx
    mov qword ptr [rip + g_dd_exact], 1
    call wc_dump
    mov qword ptr [rip + g_dd_exact], 0
    leave
    ret
ENDF wc_dumpx

# (dump)
FUNC wc_dump
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_out_ptr]
    mov rdi, [rip + g_cur_doc]
    call doc_dump
    mov rdi, rbx
    call out_take
    mov rdi, rax
    mov rsi, rdx
    call out_block
    add rsp, 8
    pop rbx
    leave
    ret
ENDF wc_dump

# (util NAME): the current doc becomes NAME(current doc)
FUNC wc_util
    push rbx
    push r12
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea rcx, [rip + util_words]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 9f
    push rcx
    sub rsp, 8
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    add rsp, 8
    pop rcx
    test eax, eax
    jnz 2f
    add rcx, 16
    jmp 1b
2:  mov rdi, [rip + g_cur_doc]
    xor esi, esi
    call [rcx + 8]
    mov [rip + g_cur_doc], rax
    pop r12
    pop rbx
    leave
    ret
9:  REFUSE "doc wire: unknown util"
ENDF wc_util

# (pred NAME): "true" or "false" for NAME(current doc)
FUNC wc_pred
    push rbx
    push r12
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea rcx, [rip + pred_words]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 9f
    push rcx
    sub rsp, 8
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    add rsp, 8
    pop rcx
    test eax, eax
    jnz 2f
    add rcx, 16
    jmp 1b
2:  mov rdi, [rip + g_cur_doc]
    call [rcx + 8]
    lea rdi, [rip + s_true]
    mov esi, 4
    test eax, eax
    jnz 3f
    lea rdi, [rip + s_false]
    mov esi, 5
3:  call out_block
    pop r12
    pop rbx
    leave
    ret
9:  REFUSE "doc wire: unknown predicate"
ENDF wc_pred

# util_alignment(doc) -> rax: addAlignmentToDoc(doc, 7, 3)
FUNC util_alignment
    mov esi, 7
    mov edx, 3
    call add_alignment_to_doc
    leave
    ret
ENDF util_alignment

# util_propagate(doc) -> rax = doc, its groups broken as printing would
FUNC util_propagate
    push rdi
    sub rsp, 8
    call propagate_breaks
    add rsp, 8
    pop rax
    leave
    ret
ENDF util_propagate

# util_map_identity(doc) -> rax: mapDoc(doc, d => d)
FUNC util_map_identity
    lea rsi, [rip + identity_fn]
    xor edx, edx
    call map_doc
    leave
    ret
ENDF util_map_identity

FUNC identity_fn
    mov rax, rsi
    leave
    ret
ENDF identity_fn

# util_label_wrap(doc) -> rax: inheritLabel(doc, d => [d, "!"])
FUNC util_label_wrap
    lea rsi, [rip + label_wrap_fn]
    xor edx, edx
    call inherit_label
    leave
    ret
ENDF util_label_wrap

FUNC label_wrap_fn
    push rsi
    sub rsp, 8
    mov edi, DA_ITEMS + 16
    call alloc
    add rsp, 8
    pop rsi
    mov byte ptr [rax], DK_ARRAY
    mov dword ptr [rax + DA_COUNT], 2
    mov [rax + DA_ITEMS], rsi
    lea rcx, [rip + sd_bang]
    mov [rax + DA_ITEMS + 8], rcx
    leave
    ret
ENDF label_wrap_fn

# util_find_string(doc) -> rax: findInDoc(doc, d => typeof d === "string" && d !== "" ? d : undefined, "none")
FUNC util_find_string
    lea rsi, [rip + find_string_fn]
    xor edx, edx
    lea rcx, [rip + sd_none]
    call find_in_doc
    leave
    ret
ENDF util_find_string

FUNC find_string_fn
    xor edx, edx
    xor eax, eax
    test rsi, rsi
    jz 9f
    cmp byte ptr [rsi], DK_STR
    jne 9f
    cmp dword ptr [rsi + DS_LEN], 0
    je 9f
    mov rax, rsi
    mov edx, 1
9:  leave
    ret
ENDF find_string_fn

    .section .rodata
SDOC sd_bang, "!"
SDOC sd_none, "none"
s_true:     .ascii "true"
s_false:    .ascii "false"
u_clean:    .asciz "cleanDoc"
u_strip:    .asciz "stripTrailingHardline"
u_remove:   .asciz "removeLines"
u_reol:     .asciz "replaceEndOfLine"
u_prop:     .asciz "propagateBreaks"
u_map:      .asciz "mapDoc"
u_label:    .asciz "inheritLabel"
u_find:     .asciz "findInDoc"
u_align:    .asciz "addAlignmentToDoc"
p_will:     .asciz "willBreak"
p_can:      .asciz "canBreak"
p_empty:    .asciz "isEmptyDoc"
    .balign 8
util_words:
    .quad u_clean, clean_doc
    .quad u_strip, strip_trailing_hardline
    .quad u_remove, remove_lines
    .quad u_reol, replace_end_of_line_doc
    .quad u_prop, util_propagate
    .quad u_map, util_map_identity
    .quad u_label, util_label_wrap
    .quad u_find, util_find_string
    .quad u_align, util_alignment
    .quad 0, 0
pred_words:
    .quad p_will, will_break
    .quad p_can, can_break
    .quad p_empty, is_empty_doc
    .quad 0, 0

    .section .rodata
c_doc:      .asciz "doc"
c_print:    .asciz "print"
c_bench:    .asciz "bench"
c_dump:     .asciz "dump"
c_dumpx:    .asciz "dumpx"
c_util:     .asciz "util"
c_pred:     .asciz "pred"
    .balign 8
    .globl command_words
command_words:
    .quad c_doc, wc_doc
    .quad c_print, wc_print
    .quad c_bench, wc_bench
    .quad c_dump, wc_dump
    .quad c_dumpx, wc_dumpx
    .quad c_util, wc_util
    .quad c_pred, wc_pred
    .quad c_text, wc_text
    .quad c_t, wc_t
    .quad c_pathwalk, wc_pathwalk
    .quad 0, 0
    .text


# ---------------------------------------------------------------- text helper tests
# (text "...") sets the text the helpers read; (t NAME args...) writes one
# helper's result: an integer, "false" for IDX_FALSE, "true"/"false" for
# predicates, or a string.

# out_int_block(n): n, or "false" for IDX_FALSE
FUNC out_int_block
    push rbx
    sub rsp, 8
    mov rbx, [rip + g_out_ptr]
    mov rax, IDX_FALSE
    cmp rdi, rax
    jne 1f
    OUTS "false"
    jmp 2f
1:  call out_dec
2:  mov rdi, rbx
    call out_take
    mov rdi, rax
    mov rsi, rdx
    call out_block
    add rsp, 8
    pop rbx
    leave
    ret
ENDF out_int_block

# out_bool_block(b)
FUNC out_bool_block
    lea rax, [rip + s_true]
    mov esi, 4
    test edi, edi
    jnz 1f
    lea rax, [rip + s_false]
    mov esi, 5
1:  mov rdi, rax
    call out_block
    leave
    ret
ENDF out_bool_block

# (text "...")
FUNC wc_text
    call wp_string
    mov [rip + g_text], rax
    mov [rip + g_text_len], rdx
    leave
    ret
ENDF wc_text

# (t NAME ...)
FUNC wc_t
    push rbx
    push r12
    call wp_word
    mov rbx, rax
    mov r12, rdx
    lea rcx, [rip + t_words]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 9f
    push rcx
    sub rsp, 8
    mov rdi, rbx
    mov rsi, r12
    call wp_word_is
    add rsp, 8
    pop rcx
    test eax, eax
    jnz 2f
    add rcx, 16
    jmp 1b
2:  call [rcx + 8]
    pop r12
    pop rbx
    leave
    ret
9:  REFUSE "doc wire: unknown text helper"
ENDF wc_t

# int helper with (I B): skip SET I B
FUNC tt_skip
    push rbx
    push r12
    call wp_int
    mov rbx, rax                    # set: 1 spaces, 2 to line end, 3 all but newline, 4 whitespace
    call wp_int
    mov r12, rax
    call wp_int
    mov rsi, rax
    mov rdi, r12
    cmp rbx, 4
    je 1f
    mov rdx, rbx
    call skip_set
    jmp 2f
1:  call skip_whitespace
2:  mov rdi, rax
    call out_int_block
    pop r12
    pop rbx
    leave
    ret
ENDF tt_skip

# tt_ib(fn): reads I B, writes fn(I, B) as an integer
FUNC tt_ib
    push rbx
    push r12
    mov rbx, rdi
    call wp_int
    mov r12, rax
    call wp_int
    mov rdi, r12
    mov rsi, rax
    call rbx
    mov rdi, rax
    call out_int_block
    pop r12
    pop rbx
    leave
    ret
ENDF tt_ib

# tt_ib_bool(fn): reads I B, writes fn(I, B) as a boolean
FUNC tt_ib_bool
    push rbx
    push r12
    mov rbx, rdi
    call wp_int
    mov r12, rax
    call wp_int
    mov rdi, r12
    mov rsi, rax
    call rbx
    mov edi, eax
    call out_bool_block
    pop r12
    pop rbx
    leave
    ret
ENDF tt_ib_bool

FUNC tt_skip_newline
    lea rdi, [rip + skip_newline]
    call tt_ib
    leave
    ret
ENDF tt_skip_newline

FUNC tt_skip_inline_comment
    call wp_int
    mov rdi, rax
    call skip_inline_comment
    mov rdi, rax
    call out_int_block
    leave
    ret
ENDF tt_skip_inline_comment

FUNC tt_skip_trailing_comment
    call wp_int
    mov rdi, rax
    call skip_trailing_comment
    mov rdi, rax
    call out_int_block
    leave
    ret
ENDF tt_skip_trailing_comment

FUNC tt_has_newline
    lea rdi, [rip + has_newline]
    call tt_ib_bool
    leave
    ret
ENDF tt_has_newline

FUNC tt_has_spaces
    lea rdi, [rip + has_spaces]
    call tt_ib_bool
    leave
    ret
ENDF tt_has_spaces

FUNC tt_has_newline_in_range
    lea rdi, [rip + has_newline_in_range]
    call tt_ib_bool
    leave
    ret
ENDF tt_has_newline_in_range

FUNC tt_is_next_line_empty
    call wp_int
    mov rdi, rax
    call is_next_line_empty
    mov edi, eax
    call out_bool_block
    leave
    ret
ENDF tt_is_next_line_empty

FUNC tt_is_previous_line_empty
    call wp_int
    mov rdi, rax
    call is_previous_line_empty
    mov edi, eax
    call out_bool_block
    leave
    ret
ENDF tt_is_previous_line_empty

FUNC tt_next_index
    call wp_int
    mov rdi, rax
    call next_nonspace_noncomment_index
    mov rdi, rax
    call out_int_block
    leave
    ret
ENDF tt_next_index

# nextChar I: the character, as UTF-8 ("" for none)
FUNC tt_next_char
    sub rsp, 16
    call wp_int
    mov rdi, rax
    call next_nonspace_noncomment_char
    xor edx, edx
    test eax, eax
    js 1f
    mov rdi, rsp
    mov esi, eax
    call utf8_encode
    mov rdx, rax
1:  mov rdi, rsp
    mov rsi, rdx
    call out_block
    leave
    ret
ENDF tt_next_char

# alignmentSize "S" TW START
FUNC tt_alignment_size
    push rbx
    push r12
    push r13
    push r14
    call wp_string
    mov rbx, rax
    mov r12, rdx
    call wp_int
    mov r13, rax
    call wp_int
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call get_alignment_size
    mov rdi, rax
    call out_int_block
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF tt_alignment_size

# indentSize "S" TW
FUNC tt_indent_size
    push rbx
    push r12
    call wp_string
    mov rbx, rax
    mov r12, rdx
    call wp_int
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    call get_indent_size
    mov rdi, rax
    call out_int_block
    pop r12
    pop rbx
    leave
    ret
ENDF tt_indent_size

# tt_two_strings(fn): "TEXT" "SEARCH" -> fn(text, len, search, slen) as an integer
FUNC tt_two_strings
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r15, rdi
    call wp_string
    mov rbx, rax
    mov r12, rdx
    call wp_string
    mov rdi, rbx
    mov rsi, r12
    mov rcx, rdx
    mov rdx, rax
    call r15
    mov rdi, rax
    call out_int_block
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF tt_two_strings

FUNC tt_max_count
    lea rdi, [rip + get_max_continuous_count]
    call tt_two_strings
    leave
    ret
ENDF tt_max_count

FUNC tt_min_not_present
    lea rdi, [rip + get_min_not_present_continuous_count]
    call tt_two_strings
    leave
    ret
ENDF tt_min_not_present

# preferredQuote "S" PREFER_SINGLE
FUNC tt_preferred_quote
    push rbx
    push r12
    call wp_string
    mov rbx, rax
    mov r12, rdx
    call wp_int
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    call preferred_quote
    sub rsp, 16
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    call out_block
    add rsp, 16
    pop r12
    pop rbx
    leave
    ret
ENDF tt_preferred_quote

# makeString "RAW" "QUOTE"
FUNC tt_make_string
    push rbx
    push r12
    call wp_string
    mov rbx, rax
    mov r12, rdx
    call wp_string
    movzx edx, byte ptr [rax]
    mov rdi, rbx
    mov rsi, r12
    call make_string
    mov rdi, rax
    mov rsi, rdx
    call out_block
    pop r12
    pop rbx
    leave
    ret
ENDF tt_make_string

# stringWidth "S"
FUNC tt_string_width
    call wp_string
    mov rdi, rax
    mov rsi, rdx
    call str_width
    mov rdi, rax
    call out_int_block
    leave
    ret
ENDF tt_string_width

    .section .rodata
t_skip:     .asciz "skip"
t_skipnl:   .asciz "skipNewline"
t_skipic:   .asciz "skipInlineComment"
t_skiptc:   .asciz "skipTrailingComment"
t_hasnl:    .asciz "hasNewline"
t_hassp:    .asciz "hasSpaces"
t_hasnlr:   .asciz "hasNewlineInRange"
t_nle:      .asciz "isNextLineEmpty"
t_ple:      .asciz "isPreviousLineEmpty"
t_nidx:     .asciz "nextIndex"
t_nchar:    .asciz "nextChar"
t_align:    .asciz "alignmentSize"
t_indent:   .asciz "indentSize"
t_maxc:     .asciz "maxCount"
t_minnp:    .asciz "minNotPresent"
t_pquote:   .asciz "preferredQuote"
t_mkstr:    .asciz "makeString"
t_width:    .asciz "stringWidth"
c_text:     .asciz "text"
c_t:        .asciz "t"
    .balign 8
t_words:
    .quad t_skip, tt_skip
    .quad t_skipnl, tt_skip_newline
    .quad t_skipic, tt_skip_inline_comment
    .quad t_skiptc, tt_skip_trailing_comment
    .quad t_hasnl, tt_has_newline
    .quad t_hassp, tt_has_spaces
    .quad t_hasnlr, tt_has_newline_in_range
    .quad t_nle, tt_is_next_line_empty
    .quad t_ple, tt_is_previous_line_empty
    .quad t_nidx, tt_next_index
    .quad t_nchar, tt_next_char
    .quad t_align, tt_alignment_size
    .quad t_indent, tt_indent_size
    .quad t_maxc, tt_max_count
    .quad t_minnp, tt_min_not_present
    .quad t_pquote, tt_preferred_quote
    .quad t_mkstr, tt_make_string
    .quad t_width, tt_string_width
    .quad 0, 0
    .text


# ---------------------------------------------------------------- path tests
# (pathwalk) parses the current text as json5 and walks the AST with
# path.call and path.each, writing one line per node of what the path API
# says there (see tests/stage3/infra/path-eval.mjs).
FUNC wc_pathwalk
    push rbx
    push r12
    mov qword ptr [rip + g_parser], P_JSON5
    mov rbx, [rip + g_out_ptr]
    call json_parse
    mov r12, rax
    mov rdi, rax
    call path_init
    xor edi, edi
    mov rsi, r12
    mov rdx, -1
    call pw_visit
    call path_pop
    mov rdi, rbx
    call out_take
    mov rdi, rax
    mov rsi, rdx
    call out_block
    pop r12
    pop rbx
    leave
    ret
ENDF wc_pathwalk

# pw_type(node) -> rax: its type, 0 for none
FUNC pw_type
    xor eax, eax
    test rdi, rdi
    jz 1f
    movzx eax, word ptr [rdi + N_TYPE]
1:  leave
    ret
ENDF pw_type

# pw_num(n): " n"
FUNC pw_num
    push rdi
    sub rsp, 8
    mov edi, ' '
    call out_byte
    add rsp, 8
    pop rdi
    call out_dec
    leave
    ret
ENDF pw_num

# pw_visit(ctx, node, index)
FUNC pw_visit
    push rbx
    push r12
    mov rbx, rsi
    test rbx, rbx
    jz 9f
    movzx edi, word ptr [rbx + N_TYPE]
    call out_dec
    call path_key
    mov edi, eax
    call pw_num
    call path_index
    mov rdi, rax
    call pw_num
    call path_is_first
    mov edi, eax
    call pw_num
    call path_is_last
    mov edi, eax
    call pw_num
    call path_previous
    mov rdi, rax
    call pw_type
    mov rdi, rax
    call pw_num
    call path_next
    mov rdi, rax
    call pw_type
    mov rdi, rax
    call pw_num
    call path_parent
    mov rdi, rax
    call pw_type
    mov rdi, rax
    call pw_num
    call path_grandparent
    mov rdi, rax
    call pw_type
    mov rdi, rax
    call pw_num
    call path_siblings
    mov rdi, -1
    test rax, rax
    jz 1f
    mov edi, [rax]
1:  call pw_num
    lea r12, [rip + pw_match_lists]
2:  mov rdi, [r12]
    test rdi, rdi
    jz 3f
    mov rsi, [r12 + 8]
    call path_match
    mov edi, eax
    call pw_num
    add r12, 16
    jmp 2b
3:  lea rdi, [rip + pw_is_object]
    xor esi, esi
    call path_find_ancestor
    mov rdi, -1
    test rax, rax
    jz 4f
    mov edi, [rax + N_START]
4:  call pw_num
    call path_parent
    xor edi, edi
    test rax, rax
    jz 5f
    lea rdi, [rip + pw_value_type]
    xor esi, esi
    xor edx, edx
    call path_call_parent
    mov rdi, rax
5:  call pw_num
    mov edi, 10
    call out_byte
    # children
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_JsonRoot
    je 10f
    cmp eax, T_ObjectExpression
    je 11f
    cmp eax, T_ArrayExpression
    je 12f
    cmp eax, T_ObjectProperty
    je 13f
    cmp eax, T_UnaryExpression
    je 10f
    cmp eax, T_TemplateLiteral
    je 14f
    jmp 9f
10: mov edx, K_node
    cmp word ptr [rbx + N_TYPE], T_JsonRoot
    je 101f
    mov edx, K_argument
101: cmp qword ptr [rbx + N_F0], 0
    je 9f
    lea rdi, [rip + pw_visit]
    xor esi, esi
    mov ecx, N_F0
    call path_call
    jmp 9f
11: lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_properties
    mov ecx, N_F0
    call path_each
    jmp 9f
12: lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_elements
    mov ecx, N_F0
    call path_each
    jmp 9f
13: lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_key
    mov ecx, N_F0
    call path_call
    lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_value
    mov ecx, N_F1
    call path_call
    jmp 9f
14: lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_quasis
    mov ecx, N_F0
    call path_each
    lea rdi, [rip + pw_visit]
    xor esi, esi
    mov edx, K_expressions
    mov ecx, N_F1
    call path_each
9:  pop r12
    pop rbx
    leave
    ret
ENDF pw_visit

# pw_value_type(ctx, node) -> rax: path.node.type inside callParent
FUNC pw_value_type
    call path_value
    mov rdi, rax
    call pw_type
    leave
    ret
ENDF pw_value_type

FUNC pw_is_object
    xor eax, eax
    cmp word ptr [rsi + N_TYPE], T_ObjectExpression
    sete al
    leave
    ret
ENDF pw_is_object

# match predicates (node, key, index)
FUNC pm_literal
    movzx ecx, word ptr [rdi + N_TYPE]
    xor eax, eax
    cmp ecx, T_StringLiteral
    je 1f
    cmp ecx, T_NumericLiteral
    je 1f
    cmp ecx, T_NullLiteral
    je 1f
    cmp ecx, T_BooleanLiteral
    je 1f
    cmp ecx, T_Identifier
    je 1f
    cmp ecx, T_TemplateLiteral
    jne 2f
1:  mov eax, 1
2:  leave
    ret
ENDF pm_literal

FUNC pm_property
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectProperty
    sete al
    leave
    ret
ENDF pm_property

FUNC pm_value_of_property
    xor eax, eax
    cmp esi, K_value
    jne 1f
    cmp word ptr [rdi + N_TYPE], T_ObjectProperty
    sete al
1:  leave
    ret
ENDF pm_value_of_property

FUNC pm_first_property
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_ObjectExpression
    jne 1f
    cmp esi, K_properties
    jne 1f
    test rdx, rdx
    sete al
1:  leave
    ret
ENDF pm_first_property

FUNC pm_elements_from1
    xor eax, eax
    cmp esi, K_elements
    jne 1f
    cmp rdx, 1
    setge al
1:  leave
    ret
ENDF pm_elements_from1

FUNC pm_root
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_JsonRoot
    sete al
    leave
    ret
ENDF pm_root

    .section .rodata
    .balign 8
pw_l1: .quad pm_literal, pm_property
pw_l2: .quad 0, pm_value_of_property, pm_first_property
pw_l3: .quad 0, pm_elements_from1
pw_l4: .quad 0, 0, pm_root
pw_match_lists:
    .quad pw_l1, 2
    .quad pw_l2, 3
    .quad pw_l3, 2
    .quad pw_l4, 3
    .quad 0, 0
c_pathwalk: .asciz "pathwalk"
    .text

# ---------------------------------------------------------------- flags
# debug_main(argc, argv): `--debug-doc-eval <file>` runs the file and exits.
FUNC debug_main
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov ebx, 1
1:  cmp rbx, r12
    jae 9f
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_eval]
    call cstr_eq
    test rax, rax
    jnz 2f
    inc rbx
    jmp 1b
2:  inc rbx
    cmp rbx, r12
    jae 9f
    mov rdi, [r13 + rbx*8]
    call debug_eval_file
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF debug_main

# debug_flag(arg) -> rax = 1 when arg is a debug flag this module takes:
# --debug-doc, or --debug-doc-exact for the exact form
FUNC debug_flag
    push rdi
    sub rsp, 8
    lea rsi, [rip + s_flag_dump]
    call cstr_eq
    test rax, rax
    jnz 1f
    mov rdi, [rsp + 8]
    lea rsi, [rip + s_flag_exact]
    call cstr_eq
    test rax, rax
    jz 9f
    mov qword ptr [rip + g_dd_exact], 1
1:  mov qword ptr [rip + g_debug_doc], 1
    mov eax, 1
9:  leave
    ret
ENDF debug_flag

    .section .rodata
s_flag_eval: .asciz "--debug-doc-eval"
s_flag_dump: .asciz "--debug-doc"
s_flag_exact: .asciz "--debug-doc-exact"
