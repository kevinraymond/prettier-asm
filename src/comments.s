# Comments. The generic part ports src/main/comments/ (attach.js, print.js,
# utils.js) and reaches the language through the printer record (g_printer,
# PR_*). The estree part ports what JSON's node types need of
# src/language-js/comments/ and src/language-js/print/comment.js.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_root
g_root:      .quad 0        # the AST attach_comments was given
g_ties:      .quad 0        # LIST of comments waiting for breakTies

    .section .rodata
    .balign 8
s_type:      .ascii "type"
s_satisfies: .ascii "satisfies"
s_prettier_ignore: .ascii "prettier-ignore"
SDOC sd_open_block, "/*"
SDOC sd_close_block, "*/"
SDOC sd_space, " "

    .text

# ================================================================ attach.js
# printer_can_attach(node) -> eax
FUNC printer_can_attach
    mov rax, [rip + g_printer]
    mov rax, [rax + PR_CAN_ATTACH_COMMENT]
    call rax
    leave
    ret
ENDF printer_can_attach

# push_kid(list, child) -> rax = list: the child, or its own sorted children
# when comments cannot attach to it.
FUNC push_kid
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    mov rdi, rbx
    call printer_can_attach
    test eax, eax
    jz 1f
    mov rdi, r12
    mov rsi, rbx
    call list_push
    jmp 9f
1:  mov rdi, rbx
    call get_sorted_child_nodes
    test rax, rax
    jz 8f
    mov rbx, rax
    xor ecx, ecx
2:  cmp ecx, [rbx]
    jae 8f
    push rcx
    sub rsp, 8
    mov rdi, r12
    mov rsi, [rbx + 8 + rcx*8]
    call list_push
    mov r12, rax
    add rsp, 8
    pop rcx
    inc ecx
    jmp 2b
8:  mov rax, r12
9:  pop r12
    pop rbx
    leave
    ret
ENDF push_kid

# node_push_kids(list, node) -> rax = list: getCommentChildNodes, or the
# children by visitor keys
FUNC node_push_kids
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov rbx, rsi
    mov r15, [rip + g_printer]
    mov rax, [r15 + PR_GET_COMMENT_CHILD_NODES]
    test rax, rax
    jz 10f
    mov rdi, rbx
    call rax
    test rax, rax
    jz 10f
    mov r14, rax
    xor r13d, r13d
1:  cmp r13, [r14]
    jae 9f
    mov rsi, [r14 + 8 + r13*8]
    inc r13
    test rsi, rsi
    jz 1b
    mov rdi, r12
    call push_kid
    mov r12, rax
    jmp 1b
10: movzx eax, word ptr [rbx + N_TYPE]
    cmp rax, [r15 + PR_VISITOR_COUNT]
    jae 9f
    mov rcx, [r15 + PR_VISITOR_KEYS]
    mov r13, [rcx + rax*8]
    test r13, r13
    jz 9f
11: movzx eax, byte ptr [r13]
    test eax, eax
    jz 9f
    inc r13
    test eax, VK_VEC
    jnz 13f
    mov rsi, [rbx + rax]
    test rsi, rsi
    jz 11b
    mov rdi, r12
    call push_kid
    mov r12, rax
    jmp 11b
13: and eax, VK_VEC - 1
    mov r14, [rbx + rax]            # VEC
    test r14, r14
    jz 11b
    xor r15d, r15d
14: cmp r15, [r14]
    jae 15f
    mov rsi, [r14 + 8 + r15*8]
    inc r15
    test rsi, rsi
    jz 14b
    mov rdi, r12
    call push_kid
    mov r12, rax
    jmp 14b
15: mov r15, [rip + g_printer]
    jmp 11b
9:  mov rax, r12
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF node_push_kids

# get_sorted_child_nodes(node) -> rax = LIST (or 0 when empty); cached per node.
# Stable sort by (start, end), as Array#sort is.
FUNC get_sorted_child_nodes
    push rbx
    push r12
    mov rbx, rdi
    test word ptr [rbx + N_FLAGS], NF_KIDS_CACHED
    jz 1f
    mov rax, [rbx + N_KIDS]
    jmp 9f
1:  xor r12d, r12d
    mov rax, [rip + g_printer]
    cmp qword ptr [rax + PR_CAN_ATTACH_COMMENT], 0
    je 8f
    xor edi, edi
    mov rsi, rbx
    call node_push_kids
    mov r12, rax
    test r12, r12
    jz 8f
    mov ecx, 1
2:  cmp ecx, [r12]
    jae 8f
    mov r8, [r12 + 8 + rcx*8]       # key node
    mov edx, ecx
3:  test edx, edx
    jz 5f
    mov r9, [r12 + 8 + rdx*8 - 8]
    mov eax, [r9 + N_START]
    cmp eax, [r8 + N_START]
    jb 5f
    ja 4f
    mov eax, [r9 + N_END]
    cmp eax, [r8 + N_END]
    jbe 5f
4:  mov [r12 + 8 + rdx*8], r9
    dec edx
    jmp 3b
5:  mov [r12 + 8 + rdx*8], r8
    inc ecx
    jmp 2b
8:  mov [rbx + N_KIDS], r12
    or word ptr [rbx + N_FLAGS], NF_KIDS_CACHED
    mov rax, r12
9:  pop r12
    pop rbx
    leave
    ret
ENDF get_sorted_child_nodes

# expression_index_for(quasis, start) -> rax (findExpressionIndexForComment)
FUNC expression_index_for
    dec rsi                         # locStart(...) - 1
    mov ecx, 1
1:  cmp rcx, [rdi]
    jae 8f
    mov rax, [rdi + 8 + rcx*8]
    mov eax, [rax + N_START]
    cmp rsi, rax
    jl 7f
    inc rcx
    jmp 1b
7:  lea rax, [rcx - 1]
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF expression_index_for

# decorate_comment(node, comment, enclosing): sets the comment's enclosing,
# preceding and following nodes
FUNC decorate_comment
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov [rsp], rdx                  # enclosing
    mov qword ptr [rsp + 8], 0      # preceding
    mov qword ptr [rsp + 16], 0     # following
    mov rdi, rbx
    call get_sorted_child_nodes
    mov r13, rax
    xor r14d, r14d                  # left
    xor r15d, r15d                  # right
    test r13, r13
    jz 8f
    mov r15d, [r13]
1:  cmp r14, r15
    jae 8f
    lea rax, [r14 + r15]
    shr rax, 1
    mov rcx, [r13 + 8 + rax*8]      # child
    mov r8d, [rcx + N_START]
    mov r9d, [rcx + N_END]
    mov r10d, [r12 + CM_START]
    mov r11d, [r12 + CM_END]
    cmp r8d, r10d
    ja 2f
    cmp r11d, r9d
    ja 2f
    # the comment is inside the child
    mov rdi, rcx
    mov rsi, r12
    mov rdx, rcx
    call decorate_comment
    jmp 9f
2:  cmp r9d, r10d
    ja 3f
    mov [rsp + 8], rcx
    lea r14, [rax + 1]
    jmp 1b
3:  cmp r11d, r8d
    ja 90f
    mov [rsp + 16], rcx
    mov r15, rax
    jmp 1b
    # comments in one expression of a template literal stay with it
8:  mov rax, [rsp]
    test rax, rax
    jz 81f
    cmp word ptr [rax + N_TYPE], T_TemplateLiteral
    jne 81f
    mov r13, [rax + N_F0]           # quasis
    mov rdi, r13
    mov esi, [r12 + CM_START]
    call expression_index_for
    mov r14, rax
    mov rcx, [rsp + 8]
    test rcx, rcx
    jz 82f
    mov rdi, r13
    mov esi, [rcx + N_START]
    call expression_index_for
    cmp rax, r14
    je 82f
    mov qword ptr [rsp + 8], 0
82: mov rcx, [rsp + 16]
    test rcx, rcx
    jz 81f
    mov rdi, r13
    mov esi, [rcx + N_START]
    call expression_index_for
    cmp rax, r14
    je 81f
    mov qword ptr [rsp + 16], 0
81: mov rax, [rsp]
    mov [r12 + CM_ENCL], rax
    mov rax, [rsp + 8]
    mov [r12 + CM_PREC], rax
    mov rax, [rsp + 16]
    mov [r12 + CM_FOLL], rax
9:  add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "comment overlaps a node"
ENDF decorate_comment

# ---------------------------------------------------------------- utils.js
# add_comment_to(node, comment, flags)
FUNC add_comment_to
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    and byte ptr [r12 + CM_FLAGS], ~(CF_LEADING | CF_TRAILING | CF_PRINTED)
    or [r12 + CM_FLAGS], dl
    mov rdi, [rbx + N_COMMENTS]
    mov rsi, r12
    call list_push
    mov [rbx + N_COMMENTS], rax
    pop r12
    pop rbx
    leave
    ret
ENDF add_comment_to

# add_leading(node, comment) / add_trailing(node, comment) /
# add_dangling(node, comment, marker): marker 0 for none
FUNC add_leading
    mov edx, CF_LEADING
    call add_comment_to
    leave
    ret
ENDF add_leading

FUNC add_trailing
    mov edx, CF_TRAILING
    call add_comment_to
    leave
    ret
ENDF add_trailing

FUNC add_dangling
    test rdx, rdx
    jz 1f
    mov [rsi + CM_MARKER], rdx
1:  xor edx, edx
    call add_comment_to
    leave
    ret
ENDF add_dangling

# comment_at(i) -> rax
FUNC comment_at
    mov rax, [rip + g_comments]
    mov rax, [rax + 8 + rdi*8]
    leave
    ret
ENDF comment_at

# is_own_line_comment(i) -> eax
FUNC is_own_line_comment
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call comment_at
    mov r12, rax
    mov r13d, [r12 + CM_START]      # start
    cmp qword ptr [r12 + CM_PREC], 0
    je 8f
    mov r14, rbx
1:  dec r14
    js 8f
    mov rdi, r14
    call comment_at
    mov rcx, [rax + CM_PREC]
    cmp rcx, [r12 + CM_PREC]
    jne 8f
    push rax
    sub rsp, 8
    mov edi, [rax + CM_END]
    mov esi, r13d
    call is_all_empty_no_newline
    add rsp, 8
    pop rcx
    test eax, eax
    jz 8f
    mov r13d, [rcx + CM_START]
    jmp 1b
8:  mov edi, r13d
    mov esi, 1
    call has_newline
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_own_line_comment

# is_end_of_line_comment(i) -> eax
FUNC is_end_of_line_comment
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call comment_at
    mov r12, rax
    mov r13d, [r12 + CM_END]
    cmp qword ptr [r12 + CM_FOLL], 0
    je 8f
    mov r14, rbx
1:  inc r14
    mov rax, [rip + g_comments]
    cmp r14d, [rax]
    jae 8f
    mov rdi, r14
    call comment_at
    mov rcx, [rax + CM_FOLL]
    cmp rcx, [r12 + CM_FOLL]
    jne 8f
    push rax
    sub rsp, 8
    mov edi, r13d
    mov esi, [rax + CM_START]
    call is_all_empty_no_newline
    add rsp, 8
    pop rcx
    test eax, eax
    jz 8f
    mov r13d, [rcx + CM_END]
    jmp 1b
8:  mov edi, r13d
    xor esi, esi
    call has_newline
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_end_of_line_comment

# run_handlers(table, comment, is_last) -> eax = 1 if one attached the comment
FUNC run_handlers
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz 8f
1:  mov rax, [rbx]
    test rax, rax
    jz 8f
    mov rdi, r12
    mov rsi, r13
    call rax
    test eax, eax
    jnz 9f
    add rbx, 8
    jmp 1b
8:  xor eax, eax
9:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF run_handlers

# attach_comments(root) (attachComments)
FUNC attach_comments
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rip + g_root], rdi
    mov qword ptr [rip + g_ties], 0
    mov rbx, [rip + g_comments]
    test rbx, rbx
    jz 99f
    cmp dword ptr [rbx], 0
    je 99f
    mov r15, [rip + g_printer]
    cmp qword ptr [r15 + PR_CAN_ATTACH_COMMENT], 0
    je 99f
    xor r12d, r12d
1:  cmp r12d, [rbx]
    jae 2f
    mov rdi, [rip + g_root]
    mov rsi, [rbx + 8 + r12*8]
    xor edx, edx
    call decorate_comment
    inc r12
    jmp 1b
2:  xor r12d, r12d
3:  cmp r12d, [rbx]
    jae 50f
    mov r13, [rbx + 8 + r12*8]
    # isLastComment
    mov eax, [rbx]
    dec eax
    xor r14d, r14d
    cmp eax, r12d
    sete r14b
    mov rdi, r12
    call is_own_line_comment
    test eax, eax
    jz 20f
    mov byte ptr [r13 + CM_PLACEMENT], PL_OWNLINE
    mov rdi, [r15 + PR_OWN_LINE]
    mov rsi, r13
    mov rdx, r14
    call run_handlers
    test eax, eax
    jnz 40f
    mov rdi, [r13 + CM_FOLL]
    test rdi, rdi
    jnz 31f
    mov rdi, [r13 + CM_PREC]
    test rdi, rdi
    jnz 32f
    jmp 33f
20: mov rdi, r12
    call is_end_of_line_comment
    test eax, eax
    jz 25f
    mov byte ptr [r13 + CM_PLACEMENT], PL_ENDOFLINE
    mov rdi, [r15 + PR_END_OF_LINE]
    mov rsi, r13
    mov rdx, r14
    call run_handlers
    test eax, eax
    jnz 40f
    mov rdi, [r13 + CM_PREC]
    test rdi, rdi
    jnz 32f
    mov rdi, [r13 + CM_FOLL]
    test rdi, rdi
    jnz 31f
    jmp 33f
25: mov byte ptr [r13 + CM_PLACEMENT], PL_REMAINING
    mov rdi, [r15 + PR_REMAINING]
    mov rsi, r13
    mov rdx, r14
    call run_handlers
    test eax, eax
    jnz 40f
    mov rax, [r13 + CM_PREC]
    test rax, rax
    jz 27f
    cmp qword ptr [r13 + CM_FOLL], 0
    je 27f
    # a tie: break the pending ties first when their following node differs
    mov rcx, [rip + g_ties]
    test rcx, rcx
    jz 26f
    mov edx, [rcx]
    test edx, edx
    jz 26f
    mov rdx, [rcx + rdx*8]          # last tie
    mov rax, [rdx + CM_FOLL]
    cmp rax, [r13 + CM_FOLL]
    je 26f
    call break_ties
26: mov rdi, [rip + g_ties]
    mov rsi, r13
    call list_push
    mov [rip + g_ties], rax
    jmp 40f
27: mov rdi, [r13 + CM_PREC]
    test rdi, rdi
    jnz 32f
    mov rdi, [r13 + CM_FOLL]
    test rdi, rdi
    jnz 31f
33: mov rdi, [r13 + CM_ENCL]
    test rdi, rdi
    jnz 34f
    mov rdi, [rip + g_root]
34: mov rsi, r13
    xor edx, edx
    call add_dangling
    jmp 40f
31: mov rsi, r13
    call add_leading
    jmp 40f
32: mov rsi, r13
    call add_trailing
40: inc r12
    jmp 3b
50: call break_ties
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF attach_comments

# gap_ok(start, end) -> eax: printer.isGap?.(gap) ?? /^[\s(]*$/u.test(gap)
FUNC gap_ok
    push rdi
    push rsi
    mov rax, [rip + g_printer]
    mov rax, [rax + PR_IS_GAP]
    test rax, rax
    jz 1f
    call rax
    test eax, eax
    jns 9f
1:  mov rdi, [rsp + 8]
    mov rsi, [rsp]
    call is_gap_text
9:  leave
    ret
ENDF gap_ok

# break_ties(): attaches the pending tied comments
FUNC break_ties
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, [rip + g_ties]
    test rbx, rbx
    jz 99f
    mov r15d, [rbx]                 # tie count
    test r15d, r15d
    jz 99f
    mov rax, [rbx + 8]
    mov r12, [rax + CM_PREC]
    mov r13, [rax + CM_FOLL]
    mov r14d, [r13 + N_START]       # gapEndPos
    # indexOfFirstLeadingComment
1:  test r15d, r15d
    jz 3f
    mov rax, [rbx + 8 + r15*8 - 8]
    mov edi, [rax + CM_END]
    mov esi, r14d
    push rax
    sub rsp, 8
    call gap_ok
    add rsp, 8
    pop rcx
    test eax, eax
    jz 3f
    mov r14d, [rcx + CM_START]
    dec r15d
    jmp 1b
3:  xor ecx, ecx
4:  cmp ecx, [rbx]
    jae 6f
    push rcx
    sub rsp, 8
    mov rsi, [rbx + 8 + rcx*8]
    cmp ecx, r15d
    jae 5f
    mov rdi, r12
    call add_trailing
    jmp 51f
5:  mov rdi, r13
    call add_leading
51: add rsp, 8
    pop rcx
    inc ecx
    jmp 4b
6:  mov rdi, r12
    call sort_node_comments
    mov rdi, r13
    call sort_node_comments
    mov dword ptr [rbx], 0
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF break_ties

# sort_node_comments(node): stable sort of node.comments by start
FUNC sort_node_comments
    mov r10, [rdi + N_COMMENTS]
    test r10, r10
    jz 9f
    mov ecx, 1
2:  cmp ecx, [r10]
    jae 9f
    mov r8, [r10 + 8 + rcx*8]
    mov edx, ecx
3:  test edx, edx
    jz 5f
    mov r9, [r10 + 8 + rdx*8 - 8]
    mov eax, [r9 + CM_START]
    cmp eax, [r8 + CM_START]
    jbe 5f
    mov [r10 + 8 + rdx*8], r9
    dec edx
    jmp 3b
5:  mov [r10 + 8 + rdx*8], r8
    inc ecx
    jmp 2b
9:  leave
    ret
ENDF sort_node_comments

# ================================================================ queries
# (CommentCheckFlags and hasComment/getComments of language-js/utils, which
# only look at the comment records.)

# comment_matches(comment, flags, index, count) -> eax (getCommentTestFunction)
FUNC comment_matches
    push rbx
    mov rbx, rdi
    movzx eax, byte ptr [rbx + CM_FLAGS]
    test esi, CC_Leading
    jz 1f
    test al, CF_LEADING
    jz 8f
1:  test esi, CC_Trailing
    jz 2f
    test al, CF_TRAILING
    jz 8f
2:  test esi, CC_Dangling
    jz 3f
    test al, CF_LEADING | CF_TRAILING
    jnz 8f
3:  test esi, CC_Block
    jz 4f
    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK
    jne 8f
4:  test esi, CC_Line
    jz 5f
    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK      # a line comment or a hashbang
    je 8f
5:  test esi, CC_First
    jz 6f
    test edx, edx
    jnz 8f
6:  test esi, CC_Last
    jz 7f
    dec ecx
    cmp edx, ecx
    jne 8f
7:  test esi, CC_PrettierIgnore
    jz 71f
    mov rdi, rbx
    call is_prettier_ignore_comment
    test eax, eax
    jz 8f
71: mov eax, 1
    pop rbx
    leave
    ret
8:  xor eax, eax
    pop rbx
    leave
    ret
ENDF comment_matches

# has_comment(node, flags, predicate_or_0) -> eax: hasComment(node, flags, fn);
# the predicate gets the comment.
FUNC has_comment
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov rbx, [rdi + N_COMMENTS]
    test rbx, rbx
    jz 9f
    mov r12d, esi
    mov r13, rdx
    xor r14d, r14d
1:  cmp r14d, [rbx]
    jae 8f
    mov r15, [rbx + 8 + r14*8]
    mov rdi, r15
    mov esi, r12d
    mov edx, r14d
    mov ecx, [rbx]
    call comment_matches
    test eax, eax
    jz 3f
    test r13, r13
    jz 7f
    mov rdi, r15
    call r13
    test eax, eax
    jnz 7f
3:  inc r14d
    jmp 1b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF has_comment

# get_comments(node, flags, predicate_or_0) -> rax: VEC (getComments)
FUNC get_comments
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, esi
    mov r13, rdx
    call ss_mark
    mov [rsp], rax
    xor ebx, ebx
    test rdi, rdi
    jz 8f
    mov rbx, [rdi + N_COMMENTS]
    test rbx, rbx
    jz 8f
    xor r14d, r14d
1:  cmp r14d, [rbx]
    jae 8f
    mov r15, [rbx + 8 + r14*8]
    mov rdi, r15
    mov esi, r12d
    mov edx, r14d
    mov ecx, [rbx]
    call comment_matches
    test eax, eax
    jz 3f
    test r13, r13
    jz 2f
    mov rdi, r15
    call r13
    test eax, eax
    jz 3f
2:  mov rdi, r15
    call ss_push
3:  inc r14d
    jmp 1b
8:  mov rdi, [rsp]
    call ss_to_vec
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF get_comments

# comment_value(comment) -> rax = start, rdx = end of comment.value in g_text
FUNC comment_value
    mov eax, [rdi + CM_START]
    mov edx, [rdi + CM_END]
    add eax, 2
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    jne 1f
    sub edx, 2
1:  leave
    ret
ENDF comment_value

# is_prettier_ignore_comment(comment) -> eax: value.trim() === "prettier-ignore"
# && !comment.unignore
FUNC is_prettier_ignore_comment
    push rbx
    push r12
    test byte ptr [rdi + CM_FLAGS], CF_UNIGNORE
    jnz 8f
    call comment_value
    mov rbx, rax
    mov r12, rdx
    mov rdi, [rip + g_text]
    mov rsi, rbx
    call trim_start_bytes
    mov rbx, rax
    mov rdi, [rip + g_text]
    mov rsi, rbx
    mov rdx, r12
    call trim_end_bytes
    sub rax, rbx
    cmp rax, 15
    jne 8f
    mov rdi, [rip + g_text]
    add rdi, rbx
    lea rsi, [rip + s_prettier_ignore]
    mov edx, 15
    call mem_eq
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF is_prettier_ignore_comment

# is_js_space: al = byte -> eax = 1 for ASCII whitespace (\t \n \v \f \r space).
# Leaf routine without a frame; preserves everything but rax.
    .globl is_js_space
is_js_space:
    cmp al, ' '
    je 1f
    cmp al, 9
    jb 2f
    cmp al, 13
    ja 2f
1:  mov eax, 1
    ret
2:  xor eax, eax
    ret

# ================================================================ print.js
# print_comment_here() -> rax: printComment: the comment at the top of the
# path, marked printed, printed by the printer
FUNC print_comment_here
    call path_value
    or byte ptr [rax + CM_FLAGS], CF_PRINTED
    mov rdi, rax
    mov rcx, [rip + g_printer]
    call [rcx + PR_PRINT_COMMENT]
    leave
    ret
ENDF print_comment_here

# printer_is_block(comment) -> eax: printer.isBlockComment?.(comment)
FUNC printer_is_block
    mov rax, [rip + g_printer]
    mov rax, [rax + PR_IS_BLOCK_COMMENT]
    test rax, rax
    jz 1f
    call rax
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF printer_is_block

# print_leading_comment() -> rax: printLeadingComment for the comment at the
# top of the path
FUNC print_leading_comment
    push rbx
    push r12
    push r13
    push r14
    call path_value
    mov rbx, rax
    call ss_mark
    mov r13, rax
    call print_comment_here
    mov rdi, rax
    call ss_push
    mov rdi, rbx
    call printer_is_block
    test eax, eax
    jz 3f
    mov edi, [rbx + CM_END]
    xor esi, esi
    call has_newline
    test eax, eax
    jz 2f
    mov edi, [rbx + CM_START]
    mov esi, 1
    call has_newline
    lea rdi, [rip + d_line]
    test eax, eax
    jz 1f
    lea rdi, [rip + d_hardline]
1:  call ss_push
    jmp 4f
2:  lea rdi, [rip + sd_space]
    call ss_push
    jmp 4f
3:  lea rdi, [rip + d_hardline]
    call ss_push
4:  mov edi, [rbx + CM_END]
    xor esi, esi
    call skip_spaces
    mov rdi, rax
    xor esi, esi
    call skip_newline
    mov r8, IDX_FALSE
    cmp rax, r8
    je 5f
    mov rdi, rax
    xor esi, esi
    call has_newline
    test eax, eax
    jz 5f
    lea rdi, [rip + d_hardline]
    call ss_push
5:  mov rdi, r13
    call ss_to_array_keep
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_leading_comment

# print_trailing_comment(prev_state) -> rax doc, rdx state: printTrailingComment
# for the comment at the top of the path. State bits: 1 = hasLineSuffix,
# 2 = isBlock; 0 for no previous comment.
FUNC print_trailing_comment
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    call path_value
    mov rbx, rax
    call print_comment_here
    mov r13, rax                    # printed
    mov rdi, rbx
    call printer_is_block
    xor r14d, r14d
    test eax, eax
    jz 1f
    mov r14d, 2                     # isBlock
1:  mov eax, r12d
    and eax, 3
    cmp eax, 1                      # previousComment.hasLineSuffix && !isBlock
    je 2f
    mov edi, [rbx + CM_START]
    mov esi, 1
    call has_newline
    test eax, eax
    jz 5f
    # lineSuffix([hardline, isLineBeforeEmpty ? hardline : "", printed])
2:  mov edi, [rbx + CM_START]
    call is_previous_line_empty
    xor esi, esi
    test eax, eax
    jz 3f
    lea rsi, [rip + d_hardline]
3:  lea rdi, [rip + d_hardline]
    mov rdx, r13
    call doc_array3_keep
    mov rdi, rax
    call doc_line_suffix
    or r14d, 1
    jmp 9f
5:  test r14d, 2
    jz 6f
    test r12d, 1
    jz 7f
    # [lineSuffix([" ", printed]), breakParent]
6:  lea rdi, [rip + sd_space]
    mov rsi, r13
    call doc_array2
    mov rdi, rax
    call doc_line_suffix
    mov rdi, rax
    lea rsi, [rip + d_break_parent]
    call doc_array2
    or r14d, 1
    jmp 9f
7:  lea rdi, [rip + sd_space]
    mov rsi, r13
    call doc_array2
9:  mov rdx, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_trailing_comment

# doc_array3_keep(a, b, c) -> rax: [a, b, c] with "" kept
FUNC doc_array3_keep
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, DA_ITEMS + 24
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov byte ptr [rax], DK_ARRAY
    mov dword ptr [rax + DA_COUNT], 3
    mov [rax + DA_ITEMS], rdi
    mov [rax + DA_ITEMS + 8], rsi
    mov [rax + DA_ITEMS + 16], rdx
    leave
    ret
ENDF doc_array3_keep

# Separately state (on the stack of print_comments_separately)
.equ SEP_LEAD, 0            # scratch mark of the leading parts
.equ SEP_TRAIL, 8           # LIST of trailing parts
.equ SEP_STATE, 16          # printTrailingComment state
.equ SEP_SIZE, 24

# print_comments_separately(node) -> rax = leading, rdx = trailing, ecx = 1
# when there are comments to print (printCommentsSeparately). With ecx = 0
# the result is Prettier's {} or {leading: "", trailing: ""}; with ecx = 1
# leading and trailing are arrays of the printed parts.
FUNC print_comments_separately
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, SEP_SIZE
    mov rbx, rdi
    xor ecx, ecx
    test rbx, rbx
    jz 99f
    mov r12, [rbx + N_COMMENTS]
    test r12, r12
    jz 99f
    # any comment not ignored?
    xor ecx, ecx
1:  cmp ecx, [r12]
    jae 99f
    mov rax, [r12 + 8 + rcx*8]
    inc ecx
    test byte ptr [rax + CM_FLAGS], CF_IGNORED
    jnz 1b
    # leading parts on the scratch stack, trailing parts in a list
    call ss_mark
    mov [rsp + SEP_LEAD], rax
    mov qword ptr [rsp + SEP_TRAIL], 0
    mov qword ptr [rsp + SEP_STATE], 0
    lea rdi, [rip + pcs_one]
    mov rsi, rsp
    mov edx, K_comments
    mov rcx, r12
    call path_each_vec_node
    mov rdi, [rsp + SEP_LEAD]
    call ss_to_array_keep
    mov r13, rax
    # trailing list -> array
    mov r14, [rsp + SEP_TRAIL]
    xor r15d, r15d
    test r14, r14
    jz 2f
    mov r15d, [r14]
2:  lea rdi, [r15*8 + DA_ITEMS]
    call alloc
    mov byte ptr [rax], DK_ARRAY
    mov [rax + DA_COUNT], r15d
    test r15d, r15d
    jz 3f
    lea rdi, [rax + DA_ITEMS]
    lea rsi, [r14 + 8]
    mov ecx, r15d
    rep movsq
3:  mov rdx, rax
    mov rax, r13
    mov ecx, 1
    jmp 100f
99: xor eax, eax
    xor edx, edx
    xor ecx, ecx
100: add rsp, SEP_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_comments_separately

# pcs_one(state, comment, index): one comment of printCommentsSeparately
FUNC pcs_one
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    movzx eax, byte ptr [r12 + CM_FLAGS]
    test al, CF_IGNORED
    jnz 9f
    test al, CF_LEADING
    jz 1f
    call print_leading_comment
    mov rdi, rax
    call ss_push
    jmp 9f
1:  test al, CF_TRAILING
    jz 9f
    mov rdi, [rbx + SEP_STATE]
    call print_trailing_comment
    mov [rbx + SEP_STATE], rdx
    mov rdi, [rbx + SEP_TRAIL]
    mov rsi, rax
    call list_push
    mov [rbx + SEP_TRAIL], rax
9:  pop r12
    pop rbx
    leave
    ret
ENDF pcs_one

# path_each_vec_node(fn, ctx, key, list): path.each over a node's list (the
# node is the current path value)
FUNC path_each_vec_node
    call path_each_vec
    leave
    ret
ENDF path_each_vec_node

# print_comments(node, doc) -> rax: printComments: inheritLabel(doc, doc =>
# [leading, doc, trailing]), or doc when the node has no comments to print.
# The node must be the path's top value.
FUNC print_comments
    push rbx
    push r12
    sub rsp, 16
    mov r12, rsi
    call print_comments_separately
    test ecx, ecx
    jz 8f
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rdi, r12
    lea rsi, [rip + pc_wrap]
    mov rdx, rsp
    call inherit_label
    jmp 9f
8:  mov rax, r12
9:  add rsp, 16
    pop r12
    pop rbx
    leave
    ret
ENDF print_comments

# pc_wrap(ctx = {leading, trailing}, doc) -> rax: [leading, doc, trailing]
FUNC pc_wrap
    mov rdx, [rdi + 8]
    mov rdi, [rdi]
    call doc_array3_keep
    leave
    ret
ENDF pc_wrap

# Dangling state
.equ DS2_PARTS, 0           # scratch mark
.equ DS2_MARKER, 8
.equ DS2_FILTER, 16
.equ DS2_CTX, 24
.equ DS2_COUNT, 32
.equ DS2_SIZE, 40

# print_dangling_comments_ex(flags, marker, filter, filter_ctx) -> rax:
# printDanglingComments(path, options, {indent, marker, filter}) for the
# path's top node. flags: DC_INDENT. filter(filter_ctx, comment) -> eax, or 0.
FUNC print_dangling_comments_ex
    push rbx
    push r12
    sub rsp, DS2_SIZE + 8
    mov ebx, edi
    mov [rsp + DS2_MARKER], rsi
    mov [rsp + DS2_FILTER], rdx
    mov [rsp + DS2_CTX], rcx
    mov qword ptr [rsp + DS2_COUNT], 0
    call path_value
    xor r12d, r12d
    test rax, rax
    jz 9f
    mov rcx, [rax + N_COMMENTS]
    test rcx, rcx
    jz 9f
    cmp dword ptr [rcx], 0
    je 9f
    push rcx
    sub rsp, 8
    call ss_mark
    add rsp, 8
    pop rcx
    mov [rsp + DS2_PARTS], rax
    lea rdi, [rip + pdc_one]
    mov rsi, rsp
    mov edx, K_comments
    call path_each_vec_node
    cmp qword ptr [rsp + DS2_COUNT], 0
    jne 1f
    mov rax, [rsp + DS2_PARTS]
    mov [rip + g_ss_ptr], rax
    jmp 9f
    # join(hardline, parts)
1:  mov rdi, [rsp + DS2_PARTS]
    call ss_to_array_keep
    mov r12, rax
    test ebx, DC_INDENT
    jz 9f
    lea rdi, [rip + d_hardline]
    mov rsi, r12
    call doc_array2
    mov rdi, rax
    call doc_indent
    mov r12, rax
9:  mov rax, r12
    add rsp, DS2_SIZE + 8
    pop r12
    pop rbx
    leave
    ret
ENDF print_dangling_comments_ex

# pdc_one(state, comment, index)
FUNC pdc_one
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    test byte ptr [r12 + CM_FLAGS], CF_LEADING | CF_TRAILING
    jnz 9f
    mov rax, [r12 + CM_MARKER]
    cmp rax, [rbx + DS2_MARKER]
    jne 9f
    mov rax, [rbx + DS2_FILTER]
    test rax, rax
    jz 1f
    mov rdi, [rbx + DS2_CTX]
    mov rsi, r12
    call rax
    test eax, eax
    jz 9f
1:  cmp qword ptr [rbx + DS2_COUNT], 0
    je 2f
    lea rdi, [rip + d_hardline]
    call ss_push
2:  inc qword ptr [rbx + DS2_COUNT]
    call print_comment_here
    mov rdi, rax
    call ss_push
9:  pop r12
    pop rbx
    leave
    ret
ENDF pdc_one

# print_dangling_comments(node, indent_flag) -> rax: printDanglingComments
# with {indent} and no marker or filter. node must be the path's top value.
FUNC print_dangling_comments
    mov edi, esi
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call print_dangling_comments_ex
    leave
    ret
ENDF print_dangling_comments

# ensure_all_comments_printed(): Prettier throws for a comment it did not
# print; refuse instead.
FUNC ensure_all_comments_printed
    mov rcx, [rip + g_comments]
    test rcx, rcx
    jz 9f
    xor edx, edx
1:  cmp edx, [rcx]
    jae 9f
    mov rax, [rcx + 8 + rdx*8]
    test byte ptr [rax + CM_FLAGS], CF_PRINTED | CF_IGNORED
    jz 90f
    inc edx
    jmp 1b
9:  leave
    ret
90: REFUSE "a comment would not be printed (Prettier reports an error)"
ENDF ensure_all_comments_printed

# ================================================================ estree
# The estree printer's comment methods for JSON's node types.

    .section .rodata
# Visitor keys: per node type, field offsets (| VK_VEC for a VEC), 0-terminated,
# in the format of ast_visitor_keys.
vk_none:     .byte 0
vk_root:     .byte N_F0, 0
vk_vec0:     .byte N_F0 | VK_VEC, 0
vk_prop:     .byte N_F0, N_F1, 0
vk_unary:    .byte N_F0, 0
vk_template: .byte N_F0 | VK_VEC, N_F1 | VK_VEC, 0
    .balign 8
    .globl visitor_keys, VISITOR_KEYS_COUNT
visitor_keys:
    .quad vk_none       # 0
    .quad vk_root       # JsonRoot
    .quad vk_vec0       # ObjectExpression
    .quad vk_vec0       # ArrayExpression
    .quad vk_prop       # ObjectProperty
    .quad vk_unary      # UnaryExpression
    .quad vk_none       # StringLiteral
    .quad vk_none       # NumericLiteral
    .quad vk_none       # NullLiteral
    .quad vk_none       # BooleanLiteral
    .quad vk_none       # Identifier
    .quad vk_template   # TemplateLiteral
    .quad vk_none       # TemplateElement
.equ VISITOR_KEYS_COUNT, (. - visitor_keys) / 8

# Comment handlers, tried in order. Only the ones that can match JSON's node
# types are listed.
    .globl handlers_own_line, handlers_end_of_line, handlers_remaining
handlers_own_line:
    .quad 0
handlers_end_of_line:
    .quad handle_closure_type_cast_comments
    .quad handle_property_comments
    .quad 0
handlers_remaining:
    .quad 0
    .text

# can_attach_comment(node) -> eax (canAttachComment)
FUNC can_attach_comment
    movzx ecx, word ptr [rdi + N_TYPE]
    xor eax, eax
    cmp ecx, T_TemplateElement
    je 1f
    cmp ecx, T_EmptyStatement
    je 1f
    mov eax, 1
1:  leave
    ret
ENDF can_attach_comment

# estree_is_block_comment(comment) -> eax
FUNC estree_is_block_comment
    xor eax, eax
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    sete al
    leave
    ret
ENDF estree_is_block_comment

# handleClosureTypeCastComments
FUNC handle_closure_type_cast_comments
    push rbx
    push r12
    mov rbx, rdi
    cmp qword ptr [rbx + CM_FOLL], 0
    je 8f
    mov rdi, rbx
    call is_type_cast_comment
    test eax, eax
    jz 8f
    mov rdi, [rbx + CM_FOLL]
    mov rsi, rbx
    call add_leading
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF handle_closure_type_cast_comments

# handlePropertyComments
FUNC handle_property_comments
    mov rax, [rdi + CM_ENCL]
    test rax, rax
    jz 8f
    cmp word ptr [rax + N_TYPE], T_ObjectProperty
    jne 8f
    mov rsi, rdi
    mov rdi, rax
    call add_leading
    mov eax, 1
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF handle_property_comments

# is_type_cast_comment(comment) -> eax: a block comment whose value starts
# with `*` and has @type or @satisfies followed by a word boundary.
FUNC is_type_cast_comment
    push rbx
    push r12
    push r13
    push r14
    cmp byte ptr [rdi + CM_TYPE], CT_BLOCK
    jne 8f
    mov r12, [rip + g_text]
    mov ebx, [rdi + CM_START]
    add ebx, 2                      # value start
    mov r13d, [rdi + CM_END]
    sub r13d, 2                     # value end
    cmp ebx, r13d
    jae 8f
    cmp byte ptr [r12 + rbx], '*'
    jne 8f
    mov r14, rbx
1:  cmp r14, r13
    jae 8f
    cmp byte ptr [r12 + r14], '@'
    jne 5f
    lea rdi, [r12 + r14 + 1]
    lea rax, [r14 + 5]
    cmp rax, r13
    ja 3f
    lea rsi, [rip + s_type]
    mov edx, 4
    call mem_eq
    test eax, eax
    jz 3f
    lea rdi, [r14 + 5]
    jmp 4f
3:  lea rax, [r14 + 10]
    cmp rax, r13
    ja 5f
    lea rdi, [r12 + r14 + 1]
    lea rsi, [rip + s_satisfies]
    mov edx, 9
    call mem_eq
    test eax, eax
    jz 5f
    lea rdi, [r14 + 10]
    # word boundary after the keyword
4:  cmp rdi, r13
    jae 7f
    movzx edi, byte ptr [r12 + rdi]
    call is_ident_part
    cmp dil, '$'
    jne 41f
    xor eax, eax                    # \b treats $ as a non-word character
41: test eax, eax
    jz 7f
5:  inc r14
    jmp 1b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_type_cast_comment

# estree_print_comment(comment) -> rax doc (printComment of
# src/language-js/print/comment.js)
FUNC estree_print_comment
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rip + g_text]
    mov r13d, [rbx + CM_START]
    mov r14d, [rbx + CM_END]
    cmp byte ptr [rbx + CM_TYPE], CT_LINE
    jne 10f
    # line comment: the source text, trimEnd
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call trim_end_bytes
    mov edi, r13d
    mov rsi, rax
    call doc_text
    jmp 99f
10: mov rdi, rbx
    call is_indentable_block_comment
    test eax, eax
    jnz 20f
    # ["/*", replaceEndOfLine(value), "*/"]
    lea rdi, [r12 + r13 + 2]
    mov esi, r14d
    sub esi, r13d
    sub esi, 4
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    lea rdi, [rip + sd_open_block]
    mov rsi, rax
    lea rdx, [rip + sd_close_block]
    call doc_array3
    jmp 99f
20: mov rdi, rbx
    call print_indentable_block_comment
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF estree_print_comment

# is_indentable_block_comment(comment) -> eax: the lines of `*${value}*`
# are more than one and each line.trimStart() starts with "*".
FUNC is_indentable_block_comment
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_text]
    mov ebx, [rdi + CM_START]
    inc ebx                         # the `*` of `/*` stands for the added "*"
    mov r13d, [rdi + CM_END]
    dec r13d                        # include the `*` of `*/`
    xor r14d, r14d                  # newline count
1:  # one line: [rbx, next "\n" or r13)
    mov rcx, rbx
2:  cmp ecx, r13d
    jae 3f
    cmp byte ptr [r12 + rcx], 10
    je 3f
    inc ecx
    jmp 2b
3:  push rcx
    sub rsp, 8
    mov rdi, r12
    mov rsi, rbx
    mov rdx, rcx
    call trim_start_bytes
    add rsp, 8
    pop rcx
    cmp rax, rcx
    jae 8f
    cmp byte ptr [r12 + rax], '*'
    jne 8f
    cmp ecx, r13d
    jae 4f
    inc r14d
    lea ebx, [ecx + 1]
    jmp 1b
4:  xor eax, eax
    test r14d, r14d
    setnz al
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_indentable_block_comment

# print_indentable_block_comment(comment) -> rax
# ["/*", join(hardline, lines.map((line, i) => i === 0 ? line.trimEnd() :
#   " " + (i < lines.length - 1 ? line.trim() : line.trimStart()))), "*/"]
FUNC print_indentable_block_comment
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, [rip + g_text]
    mov ebx, [rdi + CM_START]
    add ebx, 2                      # value start
    mov r13d, [rdi + CM_END]
    sub r13d, 2                     # value end
    call ss_mark
    mov [rsp], rax
    lea rdi, [rip + sd_open_block]
    call ss_push
    call ss_mark
    mov [rsp + 8], rax              # join parts
    mov qword ptr [rsp + 16], 0     # line index
    mov r14, rbx                    # line start
1:  mov r15, r14                    # line end
2:  cmp r15d, r13d
    jae 3f
    cmp byte ptr [r12 + r15], 10
    je 3f
    inc r15
    jmp 2b
3:  cmp qword ptr [rsp + 16], 0
    jne 4f
    # first line: trimEnd
    mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    call trim_end_bytes
    mov rdi, r14
    mov rsi, rax
    jmp 6f
4:  mov rdi, r12
    mov rsi, r14
    mov rdx, r15
    call trim_start_bytes
    mov rbx, rax
    mov rsi, r15
    cmp r15d, r13d
    jae 5f
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r15
    call trim_end_bytes
    mov rsi, rax
5:  push rsi
    sub rsp, 8
    lea rdi, [rip + sd_space]
    call ss_push
    add rsp, 8
    pop rsi
    mov rdi, rbx
6:  call doc_text
    mov rdi, rax
    call ss_push
    cmp r15d, r13d
    jae 7f
    lea rdi, [rip + d_hardline]
    call ss_push
    lea r14, [r15 + 1]
    inc qword ptr [rsp + 16]
    jmp 1b
7:  mov rdi, [rsp + 8]
    call ss_to_array
    mov rdi, rax
    call ss_push
    lea rdi, [rip + sd_close_block]
    call ss_push
    mov rdi, [rsp]
    call ss_to_array
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_indentable_block_comment
