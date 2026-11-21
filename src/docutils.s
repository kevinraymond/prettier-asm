# Doc utilities from src/document/utils.js and the builders of
# src/document/builders.js that doc.s does not have.
#
# Callbacks are a function pointer and a context pointer passed side by side;
# the function gets the context in rdi and its other arguments after it:
#   map_doc        fn(ctx, doc) -> rax doc
#   traverse_doc   on_enter(ctx, doc) -> eax 1 to visit the children, 0 to skip
#                  them (Prettier's `return false`); on_exit(ctx, doc) or 0
#   find_in_doc    fn(ctx, doc) -> rax result, edx 1 when the result is defined
#   inherit_label  fn(ctx, doc) -> rax doc
.include "defs.inc"

# map state record
.equ MS_MAP, 0
.equ MS_FN, 8
.equ MS_CTX, 16
.equ MS_SIZE, 24

    .section .rodata
SDOC sd_space_u, " "
    .text

# ---------------------------------------------------------------- builders
# doc_group_ex(contents, flags, id) -> rax: group(contents, {shouldBreak, id})
# flags: GF_BREAK for shouldBreak. id: a group id record or 0.
FUNC doc_group_ex
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, GROUP_SIZE
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_GROUP
    mov [rax + G_CONTENTS], rdi
    and esi, GF_BREAK | GF_PROPAGATED
    test rdx, rdx
    jz 1f
    or esi, GF_HAS_ID
1:  mov [rax + G_FLAGS], sil
    mov [rax + G_ID], rdx
    leave
    ret
ENDF doc_group_ex

# doc_group_id_new() -> rax: a fresh group id (Symbol(...))
FUNC doc_group_id_new
    mov edi, GID_SIZE
    call alloc
    mov byte ptr [rax], DK_GROUP_ID
    leave
    ret
ENDF doc_group_id_new

# doc_conditional_group(states, flags, id) -> rax: conditionalGroup(states,
# {shouldBreak, id}); states is an array doc with at least one item.
FUNC doc_conditional_group
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov rdi, [rbx + DA_ITEMS]
    call doc_group_ex
    mov [rax + G_EXPANDED], rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF doc_conditional_group

# doc_dedent(contents) -> rax: align(-1, contents)
FUNC doc_dedent
    mov rdx, rdi
    mov edi, AK_NUMBER
    mov rsi, -1
    call doc_align
    leave
    ret
ENDF doc_dedent

# doc_dedent_to_root(contents) -> rax: align(-Infinity, contents)
FUNC doc_dedent_to_root
    mov rdx, rdi
    mov edi, AK_NEG_INF
    xor esi, esi
    call doc_align
    leave
    ret
ENDF doc_dedent_to_root

# doc_mark_as_root(contents) -> rax: align({type: "root"}, contents)
FUNC doc_mark_as_root
    mov rdx, rdi
    mov edi, AK_ROOT
    xor esi, esi
    call doc_align
    leave
    ret
ENDF doc_mark_as_root

# doc_align_n(n, contents) -> rax: align(n, contents) for a number n
FUNC doc_align_n
    mov rdx, rsi
    mov rsi, rdi
    mov edi, AK_NUMBER
    call doc_align
    leave
    ret
ENDF doc_align_n

# doc_align_str(string_doc, contents) -> rax: align("...", contents)
FUNC doc_align_str
    mov rdx, rsi
    mov rsi, rdi
    mov edi, AK_STRING
    call doc_align
    leave
    ret
ENDF doc_align_str

# doc_label_or(label, contents) -> rax: label(label, contents), which is
# contents itself when label is falsy (0)
FUNC doc_label_or
    mov rax, rsi
    test rdi, rdi
    jz 1f
    call doc_label
1:  leave
    ret
ENDF doc_label_or

# doc_join(separator, vec) -> rax: join(separator, docs) for a VEC of docs
FUNC doc_join
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r14, [r12]
    lea rdi, [r14*2 + 1]
    lea rdi, [rdi*8]
    call alloc
    mov r13, rax
    mov byte ptr [r13], DK_ARRAY
    xor ecx, ecx                    # source index
    xor edx, edx                    # target index
1:  cmp rcx, r14
    jae 3f
    test rcx, rcx
    jz 2f
    mov [r13 + DA_ITEMS + rdx*8], rbx
    inc rdx
2:  mov rax, [r12 + 8 + rcx*8]
    mov [r13 + DA_ITEMS + rdx*8], rax
    inc rdx
    inc rcx
    jmp 1b
3:  mov [r13 + DA_COUNT], edx
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF doc_join

# add_alignment_to_doc(doc, size, tab_width) -> rax (addAlignmentToDoc)
FUNC add_alignment_to_doc
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, rbx
    test r12, r12
    jle 9f
    mov rax, r12
    xor edx, edx
    div r13
    mov r14, rax                    # Math.floor(size / tabWidth)
1:  test r14, r14
    jz 2f
    mov rdi, rbx
    call doc_indent
    mov rbx, rax
    dec r14
    jmp 1b
2:  mov rax, r12
    xor edx, edx
    div r13
    mov rdi, rdx                    # size % tabWidth
    mov rsi, rbx
    call doc_align_n
    mov rdi, rax
    call doc_dedent_to_root
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF add_alignment_to_doc

# ---------------------------------------------------------------- small helpers
# doc_is_str(doc) -> eax: typeof doc === "string" (0 is "")
FUNC doc_is_str
    mov eax, 1
    test rdi, rdi
    jz 1f
    xor eax, eax
    cmp byte ptr [rdi], DK_STR
    sete al
1:  leave
    ret
ENDF doc_is_str

# doc_str_concat(a, b) -> rax: a + b for string docs (0 is "")
FUNC doc_str_concat
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    call is_empty_str
    test eax, eax
    jz 1f
    mov rax, r12
    jmp 9f
1:  mov rdi, r12
    call is_empty_str
    test eax, eax
    jz 2f
    mov rax, rbx
    jmp 9f
2:  mov r13d, [rbx + DS_LEN]
    mov r14d, [r12 + DS_LEN]
    lea rdi, [r13 + r14]
    call alloc
    push rax
    sub rsp, 8
    mov rdi, rax
    mov rsi, [rbx + DS_PTR]
    mov rcx, r13
    rep movsb
    mov rsi, [r12 + DS_PTR]
    mov rcx, r14
    rep movsb
    add rsp, 8
    pop rdi
    lea rsi, [r13 + r14]
    call doc_str
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF doc_str_concat

# doc_copy(doc, size) -> rax: a copy of a doc record of the given size
FUNC doc_copy
    push rdi
    push rsi
    mov rdi, rsi
    call alloc
    pop rcx
    pop rsi
    mov rdi, rax
    rep movsb
    leave
    ret
ENDF doc_copy

# doc_record_size(doc) -> rax: size of a container record (not arrays)
FUNC doc_record_size
    movzx eax, byte ptr [rdi]
    lea rcx, [rip + record_sizes]
    movzx eax, byte ptr [rcx + rax]
    leave
    ret
ENDF doc_record_size

    .section .rodata
record_sizes:
    .byte 0, DS_SIZE, 0, 16, DAL_SIZE, GROUP_SIZE, FILL_SIZE, IB_SIZE
    .byte IIB_SIZE, 8, 16, 8, 8, 8, DL_SIZE, 8, GID_SIZE
    .text

# doc_copy_with_contents(doc, contents) -> rax: {...doc, contents}
FUNC doc_copy_with_contents
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call doc_record_size
    mov rdi, rbx
    mov rsi, rax
    call doc_copy
    mov [rax + D_CONTENTS], r12
    cmp byte ptr [rax], DK_GROUP
    jne 1f
    mov dword ptr [rax + G_VISIT_GEN], 0
1:  pop r12
    pop rbx
    leave
    ret
ENDF doc_copy_with_contents

# ---------------------------------------------------------------- mapDoc
# map_doc(doc, fn, ctx) -> rax
FUNC map_doc
    push rbx
    push r12
    push r13
    sub rsp, MS_SIZE + 16
    mov rbx, rdi
    mov [rsp + MS_FN], rsi
    mov [rsp + MS_CTX], rdx
    # a string is mapped directly
    call doc_is_str
    test eax, eax
    jz 1f
    mov rdi, [rsp + MS_CTX]
    mov rsi, rbx
    call [rsp + MS_FN]
    jmp 9f
1:  mov edi, 64
    call ptrmap_new
    mov [rsp + MS_MAP], rax
    mov rdi, rsp
    mov rsi, rbx
    call md_rec
9:  add rsp, MS_SIZE + 16
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF map_doc

# md_rec(state, doc) -> rax: mapped doc, once per doc
FUNC md_rec
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 1f
    mov rdi, [rbx + MS_MAP]
    mov rsi, r12
    call ptrmap_get
    test edx, edx
    jnz 9f
1:  mov rdi, rbx
    mov rsi, r12
    call md_process
    test r12, r12
    jz 9f
    mov r13, rax
    mov rdi, [rbx + MS_MAP]
    mov rsi, r12
    mov rdx, r13
    call ptrmap_put
    mov rax, r13
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF md_rec

# md_array(state, array) -> rax: a new array of the mapped items
FUNC md_array
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r14d, [r12 + DA_COUNT]
    lea rdi, [r14*8 + DA_ITEMS]
    call alloc
    mov r13, rax
    mov byte ptr [r13], DK_ARRAY
    mov [r13 + DA_COUNT], r14d
    xor r14d, r14d
1:  cmp r14d, [r12 + DA_COUNT]
    jae 9f
    mov rdi, rbx
    mov rsi, [r12 + DA_ITEMS + r14*8]
    call md_rec
    mov [r13 + DA_ITEMS + r14*8], rax
    inc r14d
    jmp 1b
9:  mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF md_array

# md_process(state, doc) -> rax
FUNC md_process
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz 80f
    movzx eax, byte ptr [r12]
    cmp eax, DK_ARRAY
    je 10f
    cmp eax, DK_FILL
    je 20f
    cmp eax, DK_IF_BREAK
    je 30f
    cmp eax, DK_GROUP
    je 40f
    cmp eax, DK_ALIGN
    je 50f
    cmp eax, DK_INDENT
    je 50f
    cmp eax, DK_INDENT_IF_BREAK
    je 50f
    cmp eax, DK_LABEL
    je 50f
    cmp eax, DK_LINE_SUFFIX
    je 50f
    cmp eax, DK_GROUP_ID
    je 90f
    cmp eax, DK_COUNT
    jae 90f
    jmp 80f
10: mov rdi, rbx
    mov rsi, r12
    call md_array
    mov r12, rax
    jmp 80f
20: mov rdi, rbx
    mov rsi, [r12 + FILL_PARTS]
    call md_array
    mov r13, rax
    mov rdi, r12
    mov esi, FILL_SIZE
    call doc_copy
    mov [rax + FILL_PARTS], r13
    mov r12, rax
    jmp 80f
30: mov rdi, rbx
    mov rsi, [r12 + IB_BREAK]
    call md_rec
    mov r13, rax
    mov rdi, rbx
    mov rsi, [r12 + IB_FLAT]
    call md_rec
    mov r14, rax
    mov rdi, r12
    mov esi, IB_SIZE
    call doc_copy
    mov [rax + IB_BREAK], r13
    mov [rax + IB_FLAT], r14
    mov r12, rax
    jmp 80f
40: mov r13, [r12 + G_EXPANDED]
    test r13, r13
    jz 41f
    mov rdi, rbx
    mov rsi, r13
    call md_array
    mov r13, rax
    mov r14, [r13 + DA_ITEMS]
    jmp 42f
41: mov rdi, rbx
    mov rsi, [r12 + G_CONTENTS]
    call md_rec
    mov r14, rax
42: mov rdi, r12
    mov rsi, r14
    call doc_copy_with_contents
    mov [rax + G_EXPANDED], r13
    mov r12, rax
    jmp 80f
50: mov rdi, rbx
    mov rsi, [r12 + D_CONTENTS]
    call md_rec
    mov rdi, r12
    mov rsi, rax
    call doc_copy_with_contents
    mov r12, rax
80: mov rdi, [rbx + MS_CTX]
    mov rsi, r12
    call [rbx + MS_FN]
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "invalid doc in mapDoc"
ENDF md_process

# ---------------------------------------------------------------- cleanDoc
# clean_doc(doc) -> rax
FUNC clean_doc
    lea rsi, [rip + clean_doc_fn]
    xor edx, edx
    call map_doc
    leave
    ret
ENDF clean_doc

# clean_doc_fn(ctx, doc) -> rax (cleanDocFn)
FUNC clean_doc_fn
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rsi
    mov rax, rbx
    test rbx, rbx
    jz 99f
    movzx eax, byte ptr [rbx]
    cmp eax, DK_FILL
    je 10f
    cmp eax, DK_GROUP
    je 20f
    cmp eax, DK_ALIGN
    je 30f
    cmp eax, DK_INDENT
    je 30f
    cmp eax, DK_INDENT_IF_BREAK
    je 30f
    cmp eax, DK_LINE_SUFFIX
    je 30f
    cmp eax, DK_IF_BREAK
    je 40f
    cmp eax, DK_ARRAY
    je 50f
    jmp 98f
    # fill: every part ""
10: mov r12, [rbx + FILL_PARTS]
    xor r13d, r13d
11: cmp r13d, [r12 + DA_COUNT]
    jae 97f
    mov rdi, [r12 + DA_ITEMS + r13*8]
    inc r13d
    call is_empty_str
    test eax, eax
    jnz 11b
    jmp 98f
    # group
20: mov rdi, [rbx + G_CONTENTS]
    call is_empty_str
    test eax, eax
    jz 21f
    cmp qword ptr [rbx + G_ID], 0
    jne 21f
    test byte ptr [rbx + G_FLAGS], GF_BREAK
    jnz 21f
    cmp qword ptr [rbx + G_EXPANDED], 0
    je 97f
    # remove a nested only group
21: mov rax, [rbx + G_CONTENTS]
    test rax, rax
    jz 98f
    cmp byte ptr [rax], DK_GROUP
    jne 98f
    mov rcx, [rax + G_ID]
    cmp rcx, [rbx + G_ID]
    jne 98f
    movzx ecx, byte ptr [rax + G_FLAGS]
    movzx edx, byte ptr [rbx + G_FLAGS]
    xor ecx, edx
    test ecx, GF_BREAK | GF_PROPAGATED
    jnz 98f
    mov rcx, [rax + G_EXPANDED]
    cmp rcx, [rbx + G_EXPANDED]
    jne 98f
    jmp 99f
30: mov rdi, [rbx + D_CONTENTS]
    call is_empty_str
    test eax, eax
    jnz 97f
    jmp 98f
40: mov rdi, [rbx + IB_FLAT]
    call is_empty_str
    test eax, eax
    jz 98f
    mov rdi, [rbx + IB_BREAK]
    call is_empty_str
    test eax, eax
    jnz 97f
    jmp 98f
    # array: flatten one level, concatenate strings
50: call ss_mark
    mov r12, rax                    # parts
    xor r13d, r13d
51: cmp r13d, [rbx + DA_COUNT]
    jae 60f
    mov r14, [rbx + DA_ITEMS + r13*8]
    inc r13d
    mov rdi, r14
    call is_empty_str
    test eax, eax
    jnz 51b
    # [currentPart, ...restParts]
    xor r15d, r15d                  # rest index
    cmp byte ptr [r14], DK_ARRAY
    jne 52f
    cmp dword ptr [r14 + DA_COUNT], 0
    je 51b
    mov [rsp], r14
    mov r14, [r14 + DA_ITEMS]
    mov r15d, 1
52: mov rdi, r14
    call doc_is_str
    test eax, eax
    jz 54f
    mov rax, [rip + g_ss_ptr]
    cmp rax, r12
    jbe 54f
    mov rdi, [rax - 8]
    call doc_is_str
    test eax, eax
    jz 54f
    mov rax, [rip + g_ss_ptr]
    mov rdi, [rax - 8]
    mov rsi, r14
    call doc_str_concat
    mov rcx, [rip + g_ss_ptr]
    mov [rcx - 8], rax
    jmp 55f
54: mov rdi, r14
    call ss_push
55: test r15d, r15d
    jz 51b
    mov rax, [rsp]
56: cmp r15d, [rax + DA_COUNT]
    jae 51b
    mov rdi, [rax + DA_ITEMS + r15*8]
    inc r15d
    call ss_push
    mov rax, [rsp]
    jmp 56b
60: mov rax, [rip + g_ss_ptr]
    sub rax, r12
    jz 61f
    cmp rax, 8
    je 62f
    mov rdi, r12
    call ss_to_array_keep
    jmp 99f
61: mov [rip + g_ss_ptr], r12
    jmp 97f
62: mov rax, [r12]
    mov [rip + g_ss_ptr], r12
    jmp 99f
97: xor eax, eax
    jmp 99f
98: mov rax, rbx
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF clean_doc_fn

# ---------------------------------------------------------------- stripTrailingHardline
# strip_trailing_hardline(doc) -> rax
FUNC strip_trailing_hardline
    call clean_doc
    mov rdi, rax
    call sth_doc
    leave
    ret
ENDF strip_trailing_hardline

# sth_parts(array) -> rax: stripTrailingHardlineFromParts
FUNC sth_parts
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, [rbx + DA_COUNT]
    # parts.length -= 2 while they end in a line and a breakParent
1:  cmp r12d, 2
    jb 2f
    mov rax, [rbx + DA_ITEMS + r12*8 - 16]
    test rax, rax
    jz 2f
    cmp byte ptr [rax], DK_LINE
    jne 2f
    mov rax, [rbx + DA_ITEMS + r12*8 - 8]
    test rax, rax
    jz 2f
    cmp byte ptr [rax], DK_BREAK_PARENT
    jne 2f
    sub r12d, 2
    jmp 1b
2:  lea rdi, [r12*8 + DA_ITEMS]
    call alloc
    mov r13, rax
    mov byte ptr [r13], DK_ARRAY
    mov [r13 + DA_COUNT], r12d
    lea rdi, [r13 + DA_ITEMS]
    lea rsi, [rbx + DA_ITEMS]
    mov ecx, r12d
    rep movsq
    test r12d, r12d
    jz 9f
    mov rdi, [r13 + DA_ITEMS + r12*8 - 8]
    call sth_doc
    mov [r13 + DA_ITEMS + r12*8 - 8], rax
9:  mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF sth_parts

# sth_doc(doc) -> rax: stripTrailingHardlineFromDoc
FUNC sth_doc
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov rax, rbx
    test rbx, rbx
    jz 99f
    movzx eax, byte ptr [rbx]
    cmp eax, DK_INDENT
    je 10f
    cmp eax, DK_INDENT_IF_BREAK
    je 10f
    cmp eax, DK_GROUP
    je 10f
    cmp eax, DK_LINE_SUFFIX
    je 10f
    cmp eax, DK_LABEL
    je 10f
    cmp eax, DK_IF_BREAK
    je 20f
    cmp eax, DK_FILL
    je 30f
    cmp eax, DK_ARRAY
    je 40f
    cmp eax, DK_STR
    je 50f
    mov rax, rbx
    jmp 99f
10: mov rdi, [rbx + D_CONTENTS]
    call sth_doc
    mov rdi, rbx
    mov rsi, rax
    call doc_copy_with_contents
    jmp 99f
20: mov rdi, [rbx + IB_BREAK]
    call sth_doc
    mov r12, rax
    mov rdi, [rbx + IB_FLAT]
    call sth_doc
    mov r13, rax
    mov rdi, rbx
    mov esi, IB_SIZE
    call doc_copy
    mov [rax + IB_BREAK], r12
    mov [rax + IB_FLAT], r13
    jmp 99f
30: mov rdi, [rbx + FILL_PARTS]
    call sth_parts
    mov r12, rax
    mov rdi, rbx
    mov esi, FILL_SIZE
    call doc_copy
    mov [rax + FILL_PARTS], r12
    jmp 99f
40: mov rdi, rbx
    call sth_parts
    jmp 99f
    # trimNewlinesEnd
50: mov rsi, [rbx + DS_PTR]
    mov ecx, [rbx + DS_LEN]
    mov edx, ecx
51: test edx, edx
    jz 52f
    movzx eax, byte ptr [rsi + rdx - 1]
    cmp al, 10
    je 53f
    cmp al, 13
    jne 52f
53: dec edx
    jmp 51b
52: mov rax, rbx
    cmp edx, ecx
    je 99f
    xor eax, eax
    test edx, edx
    jz 99f
    mov rdi, rsi
    mov esi, edx
    call doc_str
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF sth_doc

# ---------------------------------------------------------------- removeLines, replaceEndOfLine
# remove_lines(doc) -> rax
FUNC remove_lines
    lea rsi, [rip + remove_lines_fn]
    xor edx, edx
    call map_doc
    leave
    ret
ENDF remove_lines

FUNC remove_lines_fn
    mov rax, rsi
    test rsi, rsi
    jz 9f
    movzx ecx, byte ptr [rsi]
    cmp ecx, DK_LINE
    jne 2f
    movzx ecx, byte ptr [rsi + 1]
    test ecx, LF_HARD
    jnz 9f
    xor eax, eax
    test ecx, LF_SOFT
    jnz 9f
    lea rax, [rip + sd_space_u]
    jmp 9f
2:  cmp ecx, DK_IF_BREAK
    jne 9f
    mov rax, [rsi + IB_FLAT]
9:  leave
    ret
ENDF remove_lines_fn

# replace_end_of_line_doc(doc, replacement) -> rax: replaceEndOfLine(doc,
# replacement); replacement 0 means literalline.
FUNC replace_end_of_line_doc
    test rsi, rsi
    jnz 1f
    lea rsi, [rip + d_literalline]
1:  mov rdx, rsi
    lea rsi, [rip + reol_fn]
    call map_doc
    leave
    ret
ENDF replace_end_of_line_doc

FUNC reol_fn
    mov rax, rsi
    test rsi, rsi
    jz 1f
    cmp byte ptr [rsi], DK_STR
    jne 9f
    mov rdx, rdi
    mov rdi, [rsi + DS_PTR]
    mov esi, [rsi + DS_LEN]
    call replace_end_of_line
    jmp 9f
1:  mov rdx, rdi
    xor edi, edi
    xor esi, esi
    call replace_end_of_line
9:  leave
    ret
ENDF reol_fn

# ---------------------------------------------------------------- traverse, find
# traverse_doc(doc, on_enter, on_exit, ctx, traverse_conditional_groups)
# The docs stack is the scratch stack; an odd entry is an exit marker.
FUNC traverse_doc
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r13, rsi                    # on_enter
    mov r14, rdx                    # on_exit
    mov r15, rcx                    # ctx
    mov [rsp], r8                   # traverse conditional groups
    mov rbx, rdi
    call ss_mark
    mov r12, rax
    mov rdi, rbx
    call ss_push
1:  mov rax, [rip + g_ss_ptr]
    cmp rax, r12
    jbe 90f
    sub rax, 8
    mov rbx, [rax]
    mov [rip + g_ss_ptr], rax
    test bl, 1
    jz 2f
    # exit marker
    dec rbx
    lea rax, [rip + empty_marker]
    cmp rbx, rax
    jne 22f
    xor ebx, ebx
22: mov rdi, r15
    mov rsi, rbx
    call r14
    jmp 1b
2:  test r14, r14
    jz 3f
    lea rdi, [rbx + 1]
    test rbx, rbx
    jnz 21f
    # "" has no address: exit markers need one
    lea rdi, [rip + empty_marker + 1]
21: call ss_push
3:  test r13, r13
    jz 4f
    mov rdi, r15
    mov rsi, rbx
    call r13
    test eax, eax
    jz 1b
4:  test rbx, rbx
    jz 1b
    movzx eax, byte ptr [rbx]
    cmp eax, DK_ARRAY
    je 10f
    cmp eax, DK_FILL
    je 11f
    cmp eax, DK_IF_BREAK
    je 12f
    cmp eax, DK_GROUP
    je 13f
    cmp eax, DK_ALIGN
    je 14f
    cmp eax, DK_INDENT
    je 14f
    cmp eax, DK_INDENT_IF_BREAK
    je 14f
    cmp eax, DK_LABEL
    je 14f
    cmp eax, DK_LINE_SUFFIX
    je 14f
    jmp 1b
10: mov rax, rbx
    jmp 15f
11: mov rax, [rbx + FILL_PARTS]
15: mov ecx, [rax + DA_COUNT]
16: test ecx, ecx
    jz 1b
    dec ecx
    mov rdi, [rax + DA_ITEMS + rcx*8]
    push rax
    push rcx
    call ss_push
    pop rcx
    pop rax
    jmp 16b
12: mov rdi, [rbx + IB_FLAT]
    call ss_push
    mov rdi, [rbx + IB_BREAK]
    call ss_push
    jmp 1b
13: mov rax, [rbx + G_EXPANDED]
    test rax, rax
    jz 14f
    cmp qword ptr [rsp], 0
    jne 15b
14: mov rdi, [rbx + D_CONTENTS]
    call ss_push
    jmp 1b
90: mov [rip + g_ss_ptr], r12
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF traverse_doc

    .data
    .balign 8
empty_marker: .quad 0
    .text

# find_in_doc(doc, fn, ctx, default) -> rax
FUNC find_in_doc
    push rbx
    sub rsp, 40
    mov [rsp], rsi                  # fn
    mov [rsp + 8], rdx              # ctx
    mov [rsp + 16], rcx             # result
    mov qword ptr [rsp + 24], 0     # found
    mov rsi, rsp
    lea rsi, [rip + fid_enter]
    xor edx, edx
    mov rcx, rsp
    xor r8d, r8d
    call traverse_doc
    mov rax, [rsp + 16]
    add rsp, 40
    pop rbx
    leave
    ret
ENDF find_in_doc

# fid_enter(state, doc) -> eax
FUNC fid_enter
    push rbx
    sub rsp, 8
    mov rbx, rdi
    xor eax, eax
    cmp qword ptr [rbx + 24], 0
    jne 9f
    mov rdi, [rbx + 8]
    call [rbx]
    test edx, edx
    jz 8f
    mov [rbx + 16], rax
    mov qword ptr [rbx + 24], 1
8:  mov eax, 1
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF fid_enter

# will_break(doc) -> eax, can_break(doc) -> eax
FUNC will_break
    mov esi, 1
    call doc_find
    leave
    ret
ENDF will_break

FUNC can_break
    mov esi, 2
    call doc_find
    leave
    ret
ENDF can_break

# is_empty_doc(doc) -> eax (isEmptyDoc)
FUNC is_empty_doc
    sub rsp, 16
    mov qword ptr [rsp], 1
    lea rsi, [rip + ied_enter]
    xor edx, edx
    mov rcx, rsp
    xor r8d, r8d
    call traverse_doc
    mov rax, [rsp]
    leave
    ret
ENDF is_empty_doc

FUNC ied_enter
    mov eax, 1
    test rsi, rsi
    jz 9f
    movzx ecx, byte ptr [rsi]
    cmp ecx, DK_STR
    jne 1f
    cmp dword ptr [rsi + DS_LEN], 0
    je 9f
    jmp 2f
1:  cmp ecx, DK_TRIM
    je 2f
    cmp ecx, DK_LINE_SUFFIX_BOUNDARY
    je 2f
    cmp ecx, DK_LINE
    je 2f
    cmp ecx, DK_BREAK_PARENT
    jne 9f
2:  mov qword ptr [rdi], 0
    xor eax, eax
9:  leave
    ret
ENDF ied_enter

# inherit_label(doc, fn, ctx) -> rax
FUNC inherit_label
    push rbx
    push r12
    test rdi, rdi
    jz 1f
    cmp byte ptr [rdi], DK_LABEL
    jne 1f
    mov rbx, rdi
    mov rax, rsi
    mov rdi, rdx
    mov rsi, [rbx + D_CONTENTS]
    call rax
    mov rdi, rbx
    mov rsi, rax
    call doc_copy_with_contents
    jmp 9f
1:  mov rax, rsi
    mov rsi, rdi
    mov rdi, rdx
    call rax
9:  pop r12
    pop rbx
    leave
    ret
ENDF inherit_label
