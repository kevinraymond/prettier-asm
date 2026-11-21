# The estree printer for JavaScript: the printer record (src/language-js/printer.js)
# and print (src/language-js/print/index.js): prettier-ignore, the estree
# dispatch, then parentheses and the leading semicolon.
.include "pjs.inc"

# The comment methods are ported in src/pjs_comments*.s. A hook that is not
# linked in is 0; pjs_print_root refuses a file with comments then.
    .weak pjs_will_print_own_comments, pjs_print_comment, pjs_is_block_comment
    .weak pjs_can_attach_comment, pjs_get_comment_child_nodes
    .weak pjs_handlers_own_line, pjs_handlers_end_of_line, pjs_handlers_remaining
    .weak pjs_is_gap

    .section .rodata
    .balign 8
    .globl pjs_printer
pjs_printer:
    .quad pjs_print                     # PR_PRINT
    .quad 0                             # PR_HAS_PRETTIER_IGNORE
    .quad pjs_will_print_own_comments   # PR_WILL_PRINT_OWN_COMMENTS
    .quad pjs_print_comment             # PR_PRINT_COMMENT
    .quad pjs_is_block_comment          # PR_IS_BLOCK_COMMENT
    .quad pjs_can_attach_comment        # PR_CAN_ATTACH_COMMENT
    .quad pjs_get_comment_child_nodes   # PR_GET_COMMENT_CHILD_NODES
    .quad ast_visitor_keys              # PR_VISITOR_KEYS
    .quad T_COUNT                       # PR_VISITOR_COUNT
    .quad pjs_handlers_own_line         # PR_OWN_LINE
    .quad pjs_handlers_end_of_line      # PR_END_OF_LINE
    .quad pjs_handlers_remaining        # PR_REMAINING
    .quad pjs_is_gap                    # PR_IS_GAP

# Shared string docs of the JS printer.
GSDOC ps_semi, ";"
GSDOC ps_comma, ","
GSDOC ps_space, " "
GSDOC ps_lparen, "("
GSDOC ps_rparen, ")"
GSDOC ps_lbrace, "{"
GSDOC ps_rbrace, "}"
GSDOC ps_lbracket, "["
GSDOC ps_rbracket, "]"
GSDOC ps_dot, "."
GSDOC ps_colon, ":"
GSDOC ps_question, "?"
GSDOC ps_qdot, "?."
GSDOC ps_ellipsis, "..."
GSDOC ps_hash, "#"
GSDOC ps_star, "*"
GSDOC ps_eq_spaced, " = "
GSDOC ps_empty_braces, "{}"
GSDOC ps_empty_brackets, "[]"
GSDOC ps_empty_parens, "()"
GSDOC ps_double_backtick, "``"
GSDOC ps_backtick, "`"

    .text

# pjs_print_root(file) -> rax doc: printAstToDoc for the babel AST: attach the
# comments, print from the root, check that every comment was printed.
FUNC pjs_print_root
    PROLOGUE
    mov rbx, rdi
    lea rax, [rip + pjs_printer]
    mov [rip + g_printer], rax
    call pjs_options_check
    mov rax, [rip + g_comments]
    test rax, rax
    jz 1f
    cmp dword ptr [rax], 0
    je 1f
    lea r12, [rip + pjs_printer]
    cmp qword ptr [r12 + PR_PRINT_COMMENT], 0
    je 90f
    cmp qword ptr [r12 + PR_IS_BLOCK_COMMENT], 0
    je 90f
    cmp qword ptr [r12 + PR_CAN_ATTACH_COMMENT], 0
    je 90f
    cmp qword ptr [r12 + PR_WILL_PRINT_OWN_COMMENTS], 0
    je 90f
    cmp qword ptr [r12 + PR_OWN_LINE], 0
    je 90f
    cmp qword ptr [r12 + PR_END_OF_LINE], 0
    je 90f
    cmp qword ptr [r12 + PR_REMAINING], 0
    je 90f
1:  mov rdi, rbx
    call attach_comments
    call pjs_check_ts_comments
    mov rdi, rbx
    call print_ast_root
    mov rbx, rax
    call ensure_all_comments_printed
    mov rax, rbx
    EPILOGUE
90: REFUSE "printer: comments (handle-comments.js, printComment) not linked"
ENDF pjs_print_root

# pjs_options_check(): options the printer reads but does not port (none left)
FUNC pjs_options_check
    leave
    ret
ENDF pjs_options_check

# pjs_print(node, args) -> rax doc: print of print/index.js
FUNC pjs_print
    PROLOGUE 2
    mov rbx, rdi
    mov r12, rsi
    # printEmbeddedLanguages ran before printing; its result replaces print
    TYPE rbx, T_TemplateLiteral
    jne 1f
    cmp qword ptr [rip + g_embedded_off], 0
    jne 1f
    mov rdi, rbx
    call pjs_embed
    test rax, rax
    jnz 99f
    # printWithoutParentheses: isIgnored, then printEstree
1:  call pjs_is_ignored
    test eax, eax
    jz 2f
    mov rdi, rbx
    call print_ignored
    jmp 3f
2:  mov rdi, rbx
    mov rsi, r12
    call pjs_print_estree
3:  mov r13, rax
    test r13, r13
    jz 99f
    # shouldPrintDirectly: class members print their own decorators and
    # never need parentheses
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ClassMethod
    je 98f
    cmp eax, T_ClassPrivateMethod
    je 98f
    cmp eax, T_ClassProperty
    je 98f
    cmp eax, T_ClassPrivateProperty
    je 98f
    cmp eax, T_ClassAccessorProperty
    je 98f
    cmp eax, T_TSDeclareMethod
    je 98f
    mov rdi, rbx
    call pjs_get_decorators
    mov [rsp], rax                  # hasDecorators
    mov rdi, rbx
    call pjs_print_decorators
    mov [rsp + 8], rax              # decoratorsDoc
    cmp qword ptr [rsp], 0
    je 4f
    TYPE rbx, T_ClassExpression
    je 4f
    # group([decoratorsDoc, doc])
    mov rdi, r13
    lea rsi, [rip + pjs_print_wrap_group]
    mov rdx, [rsp + 8]
    call inherit_label
    jmp 99f
4:  call pjs_needs_parens
    mov r14d, eax
    call pjs_should_print_leading_semicolon
    mov r15d, eax
    shl r14d, 1
    or r14d, r15d
    jnz 5f
    cmp qword ptr [rsp + 8], 0
    je 98f
    # flags: bit 0 needsSemi, bit 1 needsParens, bit 2 a decorated ClassExpression
5:  cmp qword ptr [rsp], 0
    je 6f
    TYPE rbx, T_ClassExpression
    jne 6f
    or r14d, 4
6:  mov edi, 16
    call alloc
    mov [rax], r14
    mov rcx, [rsp + 8]
    mov [rax + 8], rcx
    mov rdi, r13
    lea rsi, [rip + pjs_print_wrap]
    mov rdx, rax
    call inherit_label
    jmp 99f
98: mov rax, r13
99: EPILOGUE
ENDF pjs_print

# pjs_print_wrap_group(decorators_doc, doc) -> rax: group([decoratorsDoc, doc])
FUNC pjs_print_wrap_group
    call doc_array2
    mov rdi, rax
    xor esi, esi
    call doc_group
    leave
    ret
ENDF pjs_print_wrap_group

# pjs_print_wrap(ctx, doc) -> rax: [needsSemi ? ";" : "", needsParens ? "(" : "",
# needsParens && isClassExpression && hasDecorators ? [indent([line,
# decoratorsDoc, doc]), line] : [decoratorsDoc, doc], needsParens ? ")" : ""];
# ctx: flags (bit 0 needsSemi, bit 1 needsParens, bit 2 decorated
# ClassExpression), then decoratorsDoc
FUNC pjs_print_wrap
    PROLOGUE
    mov rbx, [rdi]
    mov r14, [rdi + 8]
    mov r12, rsi
    DMARK r13
    test ebx, 1
    jz 1f
    DPUSHL ps_semi
1:  test ebx, 2
    jz 2f
    DPUSHL ps_lparen
    mov eax, ebx
    and eax, 6
    cmp eax, 6
    jne 2f
    DMARK r15
    DPUSHL d_line
    DPUSH r14
    DPUSH r12
    DARRAY r15
    INDENT_RAX
    DPUSH rax
    DPUSHL d_line
    jmp 21f
2:  mov rdi, r14
    mov rsi, r12
    call doc_array2
    DPUSH rax
21: test ebx, 2
    jz 3f
    DPUSHL ps_rparen
3:  DARRAY r13
    EPILOGUE
ENDF pjs_print_wrap
