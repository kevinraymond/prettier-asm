# The estree printer (src/language-js/print/*.js) restricted to the node types
# JSON produces. The main print loop is in astdoc.s.
.include "defs.inc"

    .section .rodata
    .balign 8
# The estree printer's methods (src/language-js/printer.js), as far as the JSON
# node types need them.
    .globl estree_printer
estree_printer:
    .quad estree_print              # PR_PRINT
    .quad 0                         # PR_HAS_PRETTIER_IGNORE (estree checks in print)
    .quad 0                         # PR_WILL_PRINT_OWN_COMMENTS (not for JSON's nodes)
    .quad estree_print_comment      # PR_PRINT_COMMENT
    .quad estree_is_block_comment   # PR_IS_BLOCK_COMMENT
    .quad can_attach_comment        # PR_CAN_ATTACH_COMMENT
    .quad 0                         # PR_GET_COMMENT_CHILD_NODES (none for babel parsers)
    .quad visitor_keys              # PR_VISITOR_KEYS
    .quad VISITOR_KEYS_COUNT        # PR_VISITOR_COUNT
    .quad handlers_own_line         # PR_OWN_LINE
    .quad handlers_end_of_line      # PR_END_OF_LINE
    .quad handlers_remaining        # PR_REMAINING
    .quad 0                         # PR_IS_GAP (only for the flow parsers)

# printEstree dispatch: handler(node, args) -> doc
estree_handlers:
    .quad 0                         # 0
    .quad pe_json_root
    .quad pe_object
    .quad pe_array
    .quad pe_property
    .quad pe_unary
    .quad pe_string_literal
    .quad pe_numeric_literal
    .quad pe_null_literal
    .quad pe_boolean_literal
    .quad pe_identifier
    .quad pe_template_literal
    .quad pe_template_element
.equ ESTREE_HANDLERS, (. - estree_handlers) / 8

SDOC sd_lbrace, "{"
SDOC sd_rbrace, "}"
SDOC sd_lbracket, "["
SDOC sd_rbracket, "]"
SDOC sd_empty_array, "[]"
SDOC sd_comma, ","
SDOC sd_colon, ":"
SDOC sd_space1, " "
SDOC sd_null, "null"
SDOC sd_true, "true"
SDOC sd_false, "false"
SDOC sd_backtick, "`"
SDOC sd_lparen, "("
SDOC sd_rparen, ")"
SDOC sd_minus, "-"
SDOC sd_plus, "+"

    .text

# estree_print_root(root) -> rax doc
FUNC estree_print_root
    push rdi
    sub rsp, 8
    lea rax, [rip + estree_printer]
    mov [rip + g_printer], rax
    add rsp, 8
    pop rdi
    call print_ast_root
    leave
    ret
ENDF estree_print_root

# estree_print(node, args) -> rax doc (src/language-js/print/index.js)
FUNC estree_print
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    # isIgnored: a prettier-ignore comment attached to the node
    mov esi, CC_PrettierIgnore
    xor edx, edx
    call has_comment
    test eax, eax
    jz 1f
    mov rdi, rbx
    call print_ignored
    jmp 9f
1:  movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, ESTREE_HANDLERS
    jae 90f
    lea rcx, [rip + estree_handlers]
    mov rax, [rcx + rax*8]
    test rax, rax
    jz 90f
    mov rdi, rbx
    mov rsi, r12
    call rax
    # needsParens, decorators and leading semicolons never apply to JSON nodes
9:  pop r12
    pop rbx
    leave
    ret
90: REFUSE "node type not ported"
ENDF estree_print

# print_child(node, field_offset, key) -> rax: print(key) of the current node
FUNC print_child
    mov rdi, rsi
    mov esi, edx
    xor edx, edx
    call print_field
    leave
    ret
ENDF print_child

# ---------------------------------------------------------------- JsonRoot
# [printDanglingComments(path, options), print("node"), hardline]
FUNC pe_json_root
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call ss_mark
    mov r12, rax
    mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    mov rdi, rax
    call ss_push
    mov rdi, rbx
    mov esi, N_F0
    mov edx, K_node
    call print_child
    mov rdi, rax
    call ss_push
    lea rdi, [rip + d_hardline]
    call ss_push
    mov rdi, r12
    call ss_to_array
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pe_json_root

# ---------------------------------------------------------------- literals
FUNC pe_null_literal
    lea rax, [rip + sd_null]
    leave
    ret
ENDF pe_null_literal

FUNC pe_boolean_literal
    lea rax, [rip + sd_true]
    cmp qword ptr [rdi + N_F0], 0
    jne 1f
    lea rax, [rip + sd_false]
1:  leave
    ret
ENDF pe_boolean_literal

FUNC pe_identifier
    mov esi, [rdi + N_END]
    mov edi, [rdi + N_START]
    call doc_text
    leave
    ret
ENDF pe_identifier

# replaceEndOfLine(printString(node.extra.raw, options))
FUNC pe_string_literal
    mov esi, [rdi + N_END]
    sub esi, [rdi + N_START]
    mov eax, [rdi + N_START]
    mov rdi, [rip + g_text]
    add rdi, rax
    call print_string
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    leave
    ret
ENDF pe_string_literal

# printNumber(node.extra.raw)
FUNC pe_numeric_literal
    mov esi, [rdi + N_END]
    sub esi, [rdi + N_START]
    mov eax, [rdi + N_START]
    mov rdi, [rip + g_text]
    add rdi, rax
    call print_number
    mov rdi, rax
    mov rsi, rdx
    call doc_str
    leave
    ret
ENDF pe_numeric_literal

# [lineSuffixBoundary, "`", print(quasis[0]), "`"] (no expressions in JSON)
FUNC pe_template_literal
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov rax, [rbx + N_F1]
    cmp qword ptr [rax], 0
    jne 90f
    call ss_mark
    mov r12, rax
    lea rdi, [rip + d_line_suffix_boundary]
    call ss_push
    lea rdi, [rip + sd_backtick]
    call ss_push
    mov rdi, [rbx + N_F0]
    xor esi, esi
    mov edx, K_quasis
    xor ecx, ecx
    call print_elem
    mov rdi, rax
    call ss_push
    lea rdi, [rip + sd_backtick]
    call ss_push
    mov rdi, r12
    call ss_to_array
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "template literal with expressions"
ENDF pe_template_literal

# replaceEndOfLine(node.value.raw)
FUNC pe_template_element
    mov esi, [rdi + N_END]
    sub esi, [rdi + N_START]
    mov eax, [rdi + N_START]
    mov rdi, [rip + g_text]
    add rdi, rax
    lea rdx, [rip + d_literalline]
    call replace_end_of_line
    leave
    ret
ENDF pe_template_element

# ---------------------------------------------------------------- UnaryExpression
# [operator, hasComment(argument) ? group(["(", indent([softline, arg]), softline, ")"]) : arg]
FUNC pe_unary
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    call ss_mark
    mov r12, rax
    lea rdi, [rip + sd_minus]
    cmp byte ptr [rbx + N_F1], '-'
    je 1f
    lea rdi, [rip + sd_plus]
1:  call ss_push
    mov rdi, rbx
    mov esi, N_F0
    mov edx, K_argument
    call print_child
    mov r13, rax
    mov rdi, [rbx + N_F0]
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jz 2f
    lea rdi, [rip + d_softline]
    mov rsi, r13
    call doc_array2
    mov rdi, rax
    call doc_indent
    mov r13, rax
    call ss_mark
    mov r14, rax
    lea rdi, [rip + sd_lparen]
    call ss_push
    mov rdi, r13
    call ss_push
    lea rdi, [rip + d_softline]
    call ss_push
    lea rdi, [rip + sd_rparen]
    call ss_push
    mov rdi, r14
    call ss_to_array
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov r13, rax
2:  mov rdi, r13
    call ss_push
    mov rdi, r12
    call ss_to_array
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pe_unary

# ---------------------------------------------------------------- ObjectProperty
# printProperty -> printAssignment(path, options, print, printPropertyKey(), ":", "value")
FUNC pe_property
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    call print_property_key
    mov r12, rax                    # leftDoc
    # chooseLayout for JSON: break-after-operator when the value has a
    # leading own-line comment, else never-break-after-operator
    mov rdi, [rbx + N_F1]
    mov esi, CC_Leading
    lea rdx, [rip + comment_has_newline_after]
    call has_comment
    mov r15d, eax
    # rightDoc = print("value", { assignmentLayout }) (not cached)
    mov edi, AL_NEVER_BREAK_AFTER_OPERATOR
    test r15d, r15d
    jz 3f
    mov edi, AL_BREAK_AFTER_OPERATOR
3:  call args_for_layout
    mov rdx, rax
    mov edi, N_F1
    mov esi, K_value
    call print_field
    mov r13, rax
    mov rdi, r12
    xor esi, esi
    call doc_group
    mov r12, rax
    call ss_mark
    mov r14, rax
    mov rdi, r12
    call ss_push
    lea rdi, [rip + sd_colon]
    call ss_push
    test r15d, r15d
    jnz 1f
    # group([group(leftDoc), operator, " ", rightDoc])
    lea rdi, [rip + sd_space1]
    call ss_push
    mov rdi, r13
    call ss_push
    jmp 2f
    # group([group(leftDoc), operator, group(indent([line, rightDoc]))])
1:  lea rdi, [rip + d_line]
    mov rsi, r13
    call doc_array2
    mov rdi, rax
    call doc_indent
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov rdi, rax
    call ss_push
2:  mov rdi, r14
    call ss_to_array
    mov rdi, rax
    xor esi, esi
    call doc_group
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pe_property

# comment_has_newline_after(comment) -> eax: hasNewline(text, locEnd(comment))
FUNC comment_has_newline_after
    mov edi, [rdi + CM_END]
    xor esi, esi
    call has_newline
    leave
    ret
ENDF comment_has_newline_after

# print_property_key(property) -> rax (printPropertyKey)
FUNC print_property_key
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # key
    # quoteProps "consistent": does any string key of this object need its
    # quotes? Computed once per object.
    cmp qword ptr [rip + g_quote_props], QP_CONSISTENT
    jne 1f
    mov edi, 1
    call path_node
    mov rdi, rax
    call compute_needs_quote_props
1:  # shouldQuotePropertyKey: an identifier or simple number key, and json,
    # jsonc, or "consistent" with needsQuoteProps
    movzx eax, word ptr [r12 + N_TYPE]
    cmp eax, T_Identifier
    je 11f
    cmp eax, T_NumericLiteral
    jne 30f
    mov edi, [r12 + N_START]
    add rdi, [rip + g_text]
    mov esi, [r12 + N_END]
    sub esi, [r12 + N_START]
    call print_number
    mov r13, rax
    mov r14, rdx
    mov rdi, r13
    mov rsi, r14
    call is_simple_number
    test eax, eax
    jz 30f
    mov rdi, r13
    mov rsi, r14
    call simple_number_is_canonical
    test eax, eax
    jz 30f
    jmp 12f
11: mov r13d, [r12 + N_START]
    add r13, [rip + g_text]
    mov r14d, [r12 + N_END]
    sub r14d, [r12 + N_START]
12: call quote_json_keys
    test eax, eax
    jnz 13f
    cmp qword ptr [rip + g_quote_props], QP_CONSISTENT
    jne 30f
    mov edi, 1
    call path_node
    test word ptr [rax + N_FLAGS], NF_QUOTE_PROPS
    jz 30f
    # printString(JSON.stringify(name)): the text needs no escaping, so the
    # result is the text in the enclosing quote: `"`, or `'` for json5 with
    # singleQuote
13: lea rdi, [r14 + 2]
    call alloc
    mov r15, rax
    mov ecx, '"'
    cmp qword ptr [rip + g_parser], P_JSON5
    jne 14f
    cmp qword ptr [rip + g_single_quote], 0
    je 14f
    mov ecx, 0x27
14: mov [r15], cl
    mov [r15 + r14 + 1], cl
    lea rdi, [r15 + 1]
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov rdi, r15
    lea rsi, [r14 + 2]
    call doc_str
    jmp 50f
    # isStringKeySafeToUnquote and quoteProps "as-needed", or "consistent"
    # without needsQuoteProps
30: mov rdi, rbx
    call string_key_safe_to_unquote
    test eax, eax
    jz 40f
    mov rax, [rip + g_quote_props]
    cmp rax, QP_AS_NEEDED
    je 31f
    cmp rax, QP_CONSISTENT
    jne 40f
    mov edi, 1
    call path_node
    test word ptr [rax + N_FLAGS], NF_QUOTE_PROPS
    jnz 40f
31: mov edi, [r12 + N_START]
    inc edi
    mov esi, [r12 + N_END]
    dec esi
    call doc_text
    jmp 50f
    # print("key")
40: mov rdi, r12
    mov esi, K_key
    mov edx, -1
    xor ecx, ecx
    call main_print
    jmp 99f
    # path.call(keyPath => printComments(keyPath, prop, options), "key")
50: mov r13, rax
    mov rdi, r12
    mov esi, K_key
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    mov rsi, r13
    call print_comments
    call path_pop
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_property_key

# quote_json_keys() -> eax: the parser is json or jsonc
FUNC quote_json_keys
    xor eax, eax
    mov rcx, [rip + g_parser]
    cmp rcx, P_JSON
    je 1f
    cmp rcx, P_JSONC
    jne 2f
1:  mov eax, 1
2:  leave
    ret
ENDF quote_json_keys

# string_key_safe_to_unquote(property) -> eax (isStringKeySafeToUnquote):
# not json or jsonc, a string key, and printString keeps the value, which for
# an ES5 identifier name means the raw text between the quotes is the name.
# The number case only applies to the babel parsers.
FUNC string_key_safe_to_unquote
    push rbx
    sub rsp, 8
    mov rbx, [rdi + N_F0]
    call quote_json_keys
    test eax, eax
    jnz 8f
    cmp word ptr [rbx + N_TYPE], T_StringLiteral
    jne 8f
    mov edi, [rbx + N_START]
    inc edi
    add rdi, [rip + g_text]
    mov esi, [rbx + N_END]
    sub esi, [rbx + N_START]
    sub esi, 2
    call is_es5_identifier_name
    jmp 9f
8:  xor eax, eax
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF string_key_safe_to_unquote

# compute_needs_quote_props(object): needsQuoteProps for quoteProps
# "consistent": some string key cannot be unquoted.
FUNC compute_needs_quote_props
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    test word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS_SET
    jnz 9f
    or word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS_SET
    mov r12, [rbx + N_F0]
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 9f
    mov r14, [r12 + 8 + r13*8]
    inc r13
    mov rax, [r14 + N_F0]
    cmp word ptr [rax + N_TYPE], T_StringLiteral
    jne 1b
    mov rdi, r14
    call string_key_safe_to_unquote
    test eax, eax
    jnz 1b
    or word ptr [rbx + N_FLAGS], NF_QUOTE_PROPS
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF compute_needs_quote_props

# is_es5_identifier_name(ptr, len) -> eax (is-es5-identifier-name): the
# first UTF-16 unit an identifier start, the others identifier parts.
FUNC is_es5_identifier_name
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    xor eax, eax
    test r12, r12
    jz 99f
    xor r13d, r13d                  # byte index
    mov r14d, 1                     # next unit is the first
1:  cmp r13, r12
    jae 98f
    movzx eax, byte ptr [rbx + r13]
    cmp eax, 0x80
    jae 3f
    inc r13
    mov edi, eax
    test r14d, r14d
    jz 2f
    call is_ident_start
    jmp 21f
2:  call is_ident_part
21: xor r14d, r14d
    test eax, eax
    jz 99f
    jmp 1b
    # decode one code point into UTF-16 units
3:  cmp eax, 0xE0
    jae 4f
    and eax, 0x1F
    shl eax, 6
    movzx ecx, byte ptr [rbx + r13 + 1]
    and ecx, 0x3F
    or eax, ecx
    add r13, 2
    jmp 6f
4:  cmp eax, 0xF0
    jae 5f
    and eax, 0x0F
    shl eax, 12
    movzx ecx, byte ptr [rbx + r13 + 1]
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    movzx ecx, byte ptr [rbx + r13 + 2]
    and ecx, 0x3F
    or eax, ecx
    add r13, 3
    jmp 6f
    # astral: a surrogate pair; no surrogate is in either table
5:  xor eax, eax
    jmp 99f
6:  mov edi, eax
    lea rsi, [rip + es5_id_part]
    mov edx, [rip + es5_id_part_count]
    test r14d, r14d
    jz 7f
    lea rsi, [rip + es5_id_start]
    mov edx, [rip + es5_id_start_count]
7:  call in_ranges
    jmp 21b
98: mov eax, 1
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_es5_identifier_name

# ---------------------------------------------------------------- ObjectExpression
# printObject for ObjectExpression
FUNC pe_object
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # properties VEC
    # print every property first
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 2f
    mov rdi, r12
    mov rsi, r13
    mov edx, K_properties
    xor ecx, ecx
    call print_elem
    inc r13
    jmp 1b
2:  cmp qword ptr [r12], 0
    jne 10f
    # no properties
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 3f
    call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbrace]
    call ss_push
    lea rdi, [rip + sd_rbrace]
    call ss_push
    mov rdi, r13
    call ss_to_array
    jmp 99f
    # group([ "{", printDanglingComments(indent), softline, "}" ]), then group(content)
3:  call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbrace]
    call ss_push
    mov rdi, rbx
    mov esi, 1
    call print_dangling_comments
    mov rdi, rax
    call ss_push
    lea rdi, [rip + d_softline]
    call ss_push
    lea rdi, [rip + sd_rbrace]
    call ss_push
    mov rdi, r13
    call ss_to_array
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov rdi, rax
    xor esi, esi
    call doc_group
    jmp 99f
    # shouldBreak: objectWrap "preserve" and a newline between `{` and the
    # first property
10: mov qword ptr [rsp], 0
    cmp qword ptr [rip + g_object_wrap], OW_PRESERVE
    jne 101f
    mov rax, [r12 + 8]
    mov edi, [rbx + N_START]
    mov esi, [rax + N_START]
    call has_newline_in_range
    mov [rsp], rax
101: lea rax, [rip + d_line]
    cmp qword ptr [rip + g_bracket_spacing], 0
    jne 102f
    lea rax, [rip + d_softline]
102: mov [rsp + 8], rax              # line or softline
    # parts inside indent: [line, ...props]
    call ss_mark
    mov r14, rax
    mov rdi, [rsp + 8]
    call ss_push
    xor r13d, r13d
    xor r15d, r15d                  # previous property needs a blank line
11: cmp r13, [r12]
    jae 15f
    test r13, r13
    jz 12f
    lea rdi, [rip + sd_comma]
    call ss_push
    lea rdi, [rip + d_line]
    call ss_push
    test r15d, r15d
    jz 12f
    lea rdi, [rip + d_hardline]
    call ss_push
12: mov rax, [r12 + 8 + r13*8]
    mov rdi, [rax + N_DOC]
    xor esi, esi
    call doc_group
    mov rdi, rax
    call ss_push
    mov rax, [r12 + 8 + r13*8]
    mov edi, [rax + N_END]
    call is_next_line_empty
    mov r15d, eax
    inc r13
    jmp 11b
15: mov rdi, r14
    call ss_to_array
    mov rdi, rax
    call doc_indent
    mov r14, rax
    call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbrace]
    call ss_push
    mov rdi, r14
    call ss_push
    # ifBreak(shouldPrintComma ? "," : "")
    call should_print_comma
    xor edi, edi
    test eax, eax
    jz 16f
    lea rdi, [rip + sd_comma]
16: xor esi, esi
    xor edx, edx
    call doc_if_break
    mov rdi, rax
    call ss_push
    mov rdi, [rsp + 8]
    call ss_push
    lea rdi, [rip + sd_rbrace]
    call ss_push
    mov rdi, r13
    call ss_to_array
    mov rdi, rax
    mov rsi, [rsp]
    call doc_group
99: add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pe_object

# ---------------------------------------------------------------- ArrayExpression
# printArray for ArrayExpression
FUNC pe_array
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov rbx, rdi
    mov r12, [rbx + N_F0]           # elements VEC
    cmp qword ptr [r12], 0
    jne 10f
    # printEmptyArrayElements
    mov rdi, rbx
    mov esi, CC_Dangling
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 3f
    call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbracket]
    call ss_push
    lea rdi, [rip + sd_rbracket]
    call ss_push
    mov rdi, r13
    call ss_to_array
    jmp 99f
3:  call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbracket]
    call ss_push
    mov rdi, rbx
    mov esi, 1
    call print_dangling_comments
    mov rdi, rax
    call ss_push
    lea rdi, [rip + d_softline]
    call ss_push
    lea rdi, [rip + sd_rbracket]
    call ss_push
    mov rdi, r13
    call ss_to_array
    mov rdi, rax
    xor esi, esi
    call doc_group
    jmp 99f

10: call doc_group_with_id
    mov [rsp], rax                  # the array group (its own id)
    # shouldBreak: more than one element, all objects (or all arrays) with
    # more than one entry each
    xor r15d, r15d
    cmp qword ptr [r12], 1
    jbe 14f
    xor r13d, r13d
11: cmp r13, [r12]
    jae 13f
    mov rax, [r12 + 8 + r13*8]
    test rax, rax
    jz 14f
    movzx ecx, word ptr [rax + N_TYPE]
    cmp ecx, T_ObjectExpression
    je 12f
    cmp ecx, T_ArrayExpression
    jne 14f
12: lea rdx, [r13 + 1]
    cmp rdx, [r12]
    jae 121f
    mov rdx, [r12 + 8 + rdx*8]
    test rdx, rdx
    jz 14f
    cmp cx, [rdx + N_TYPE]
    jne 14f
121: mov rdx, [rax + N_F0]
    cmp qword ptr [rdx], 1
    jbe 14f
    inc r13
    jmp 11b
13: mov r15d, 1
14: mov [rsp + 8], r15              # shouldBreak
    mov rdi, rbx
    call is_concisely_printed_array
    mov [rsp + 16], rax             # concise
    # trailingComma
    mov rcx, [r12]
    mov rax, [r12 + rcx*8]          # last element
    test rax, rax
    jnz 15f
    lea rax, [rip + sd_comma]       # forced for a trailing hole
    jmp 17f
15: call should_print_comma
    test eax, eax
    jz 17f
    lea rdi, [rip + sd_comma]
    xor esi, esi
    xor edx, edx
    cmp qword ptr [rsp + 16], 0
    je 16f
    mov rdx, [rsp]
16: call doc_if_break
17: mov [rsp + 24], rax             # trailingComma doc
    # indent([softline, elements..., danglingComments])
    call ss_mark
    mov r14, rax
    lea rdi, [rip + d_softline]
    call ss_push
    cmp qword ptr [rsp + 16], 0
    je 20f
    mov rdi, rbx
    mov rsi, [rsp + 24]
    call print_array_elements_concisely
    mov rdi, rax
    call ss_push
    jmp 21f
20: mov rdi, rbx
    call print_array_elements
    mov rdi, rax
    call ss_push
    mov rdi, [rsp + 24]
    call ss_push
21: mov rdi, rbx
    xor esi, esi
    call print_dangling_comments
    mov rdi, rax
    call ss_push
    mov rdi, r14
    call ss_to_array
    mov rdi, rax
    call doc_indent
    mov r14, rax
    call ss_mark
    mov r13, rax
    lea rdi, [rip + sd_lbracket]
    call ss_push
    mov rdi, r14
    call ss_push
    lea rdi, [rip + d_softline]
    call ss_push
    lea rdi, [rip + sd_rbracket]
    call ss_push
    mov rdi, r13
    call ss_to_array
    mov rcx, [rsp]
    mov [rcx + G_CONTENTS], rax
    cmp qword ptr [rsp + 8], 0
    je 22f
    or byte ptr [rcx + G_FLAGS], GF_BREAK
22: mov rax, rcx
99: add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pe_array

# is_concisely_printed_array(node) -> eax
FUNC is_concisely_printed_array
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [rdi + N_F0]
    xor eax, eax
    cmp qword ptr [rbx], 1
    jbe 9f
    xor r12d, r12d
1:  cmp r12, [rbx]
    jae 8f
    mov r13, [rbx + 8 + r12*8]
    test r13, r13
    jz 7f
    movzx eax, word ptr [r13 + N_TYPE]
    cmp eax, T_NumericLiteral
    je 2f
    cmp eax, T_UnaryExpression
    jne 7f
    mov rax, [r13 + N_F0]
    cmp word ptr [rax + N_TYPE], T_NumericLiteral
    jne 7f
    mov rdi, rax
    xor esi, esi
    xor edx, edx
    call has_comment
    test eax, eax
    jnz 7f
2:  mov rdi, r13
    mov esi, CC_Trailing | CC_Line
    lea rdx, [rip + comment_not_after_newline]
    call has_comment
    test eax, eax
    jnz 7f
    inc r12
    jmp 1b
7:  xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF is_concisely_printed_array

# comment_not_after_newline(comment) -> eax: !hasNewline(text, locStart, backwards)
FUNC comment_not_after_newline
    mov edi, [rdi + CM_START]
    mov esi, 1
    call has_newline
    xor eax, 1
    leave
    ret
ENDF comment_not_after_newline

# is_line_after_element_empty(node) -> eax
FUNC is_line_after_element_empty
    push rbx
    sub rsp, 8
    mov ebx, [rdi + N_END]
1:  mov rdi, rbx
    call char_at
    cmp eax, ','
    je 2f
    lea rdi, [rbx + 1]
    call skip_trailing_comment
    mov rdi, rax
    call skip_inline_comment
    mov rbx, rax
    mov r8, IDX_FALSE
    cmp rax, r8
    je 90f
    cmp rax, [rip + g_text_len]
    jg 90f
    jmp 1b
2:  mov rdi, rbx
    call is_next_line_empty
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "no comma after an array element"
ENDF is_line_after_element_empty

# print_array_elements(array) -> rax doc
FUNC print_array_elements
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + N_F0]
    call ss_mark
    mov r15, rax
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 9f
    mov r14, [r12 + 8 + r13*8]
    test r14, r14
    jz 2f
    mov rdi, r12
    mov rsi, r13
    mov edx, K_elements
    xor ecx, ecx
    call print_elem
    mov rdi, rax
    xor esi, esi
    call doc_group
    mov rdi, rax
    call ss_push
2:  inc r13
    cmp r13, [r12]
    jae 9f
    # [",", line, node && isLineAfterElementEmpty ? softline : ""]
    lea rdi, [rip + sd_comma]
    call ss_push
    lea rdi, [rip + d_line]
    call ss_push
    test r14, r14
    jz 1b
    mov rdi, r14
    call is_line_after_element_empty
    test eax, eax
    jz 1b
    lea rdi, [rip + d_softline]
    call ss_push
    jmp 1b
9:  mov rdi, r15
    call ss_to_array
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_array_elements

# print_array_elements_concisely(array, trailing_comma) -> rax: fill(parts)
FUNC print_array_elements_concisely
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, [rbx + N_F0]
    mov [rsp], rsi
    call ss_mark
    mov r15, rax                    # fill parts
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 9f
    mov r14, [r12 + 8 + r13*8]
    mov rdi, r12
    mov rsi, r13
    mov edx, K_elements
    xor ecx, ecx
    call print_elem
    # [print(), isLast ? trailingComma : ","]
    lea rcx, [r13 + 1]
    lea rsi, [rip + sd_comma]
    cmp rcx, [r12]
    jb 2f
    mov rsi, [rsp]
2:  mov rdi, rax
    call doc_array2
    mov rdi, rax
    call ss_push
    inc r13
    cmp r13, [r12]
    jae 9f
    mov rdi, r14
    call is_line_after_element_empty
    test eax, eax
    jz 3f
    lea rdi, [rip + d_hardline]
    lea rsi, [rip + d_hardline]
    call doc_array2
    jmp 5f
3:  mov rdi, [r12 + 8 + r13*8]
    mov esi, CC_Leading | CC_Line
    xor edx, edx
    call has_comment
    lea rdi, [rip + d_line]
    test eax, eax
    jz 4f
    lea rdi, [rip + d_hardline]
4:  mov rax, rdi
5:  mov rdi, rax
    call ss_push
    jmp 1b
9:  mov rdi, r15
    call ss_to_array_keep
    mov rdi, rax
    call doc_fill
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_array_elements_concisely
