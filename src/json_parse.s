# parseJson from src/language-json/parser-json.js: Babel's parseExpression
# followed by assertJsonNode, for the node types JSON allows. Builds Babel's
# node shapes and ranges so the estree printer and comment attachment see what
# Prettier sees.
.include "defs.inc"

.equ TK_EOF, 0
.equ TK_PUNCT, 1
.equ TK_STRING, 2
.equ TK_NUM, 3
.equ TK_NAME, 4
.equ TK_TEMPLATE, 5

    .section .rodata
s_true:      .ascii "true"
s_false:     .ascii "false"
s_null:      .ascii "null"
s_Infinity:  .ascii "Infinity"
s_NaN:       .ascii "NaN"
s_undefined: .ascii "undefined"
s_proto:     .ascii "__proto__"

# new_node(type, start, end) -> rax
FUNC new_node
    push rdi
    push rsi
    push rdx
    sub rsp, 8
    mov edi, NODE_SIZE
    call alloc
    add rsp, 8
    pop rdx
    pop rsi
    pop rdi
    mov [rax + N_TYPE], di
    mov [rax + N_START], esi
    mov [rax + N_END], edx
    leave
    ret
ENDF new_node

# tok_is(text, len) -> eax = 1 if the current token's text equals it
FUNC tok_is
    mov rcx, [rip + g_tok_end]
    sub rcx, [rip + g_tok_start]
    cmp rcx, rsi
    jne 1f
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + g_text]
    add rdi, [rip + g_tok_start]
    call mem_eq
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF tok_is

.macro TOK_IS label, len
    lea rdi, [rip + \label]
    mov esi, \len
    call tok_is
.endm

# is_punct(c) -> eax
FUNC is_punct
    xor eax, eax
    cmp qword ptr [rip + g_tok_type], TK_PUNCT
    jne 1f
    cmp [rip + g_tok_val], rdi
    sete al
1:  leave
    ret
ENDF is_punct

    .bss
    .balign 8
g_depth: .quad 0

# Prettier runs out of stack on deeply nested input (about 200 nested objects
# with Node 22's default stack), and the limit moves with the Node version.
# Nesting deeper than MAX_DEPTH is refused.
.equ MAX_DEPTH, 100

# enter_nesting()
FUNC enter_nesting
    inc qword ptr [rip + g_depth]
    cmp qword ptr [rip + g_depth], MAX_DEPTH
    ja 9f
    leave
    ret
9:  REFUSE "nesting deeper than 100 (Prettier may run out of stack)"
ENDF enter_nesting

# json_parse() -> rax = JsonRoot
FUNC json_parse
    push rbx
    push r12
    mov qword ptr [rip + g_pos], 0
    mov qword ptr [rip + g_comments], 0
    call lex_next
    cmp qword ptr [rip + g_tok_type], TK_EOF
    jne 1f
    # only comments: jsonc parses it as an empty program (allowEmpty)
    cmp qword ptr [rip + g_parser], P_JSONC
    jne 90f
    xor ebx, ebx
    jmp 2f
1:  call parse_value
    mov rbx, rax
    cmp qword ptr [rip + g_tok_type], TK_EOF
    jne 91f
2:  cmp qword ptr [rip + g_parser], P_JSON_STRINGIFY
    jne 3f
    cmp qword ptr [rip + g_comments], 0
    jne 92f
3:  mov edi, T_JsonRoot
    xor esi, esi
    mov rdx, [rip + g_text_len]
    call new_node
    mov [rax + N_F0], rbx
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "empty JSON (Prettier reports an error)"
91: REFUSE "unexpected token after the JSON value"
92: REFUSE "comment in json-stringify (Prettier reports an error)"
ENDF json_parse

# parse_value() -> rax = node; leaves the next token in g_tok_*.
FUNC parse_value
    push rbx
    push r12
    push r13
    push r14
    mov rax, [rip + g_tok_type]
    cmp rax, TK_PUNCT
    je 10f
    cmp rax, TK_STRING
    je 20f
    cmp rax, TK_NUM
    je 30f
    cmp rax, TK_NAME
    je 40f
    cmp rax, TK_TEMPLATE
    je 50f
    jmp 90f
10: mov rax, [rip + g_tok_val]
    cmp al, '{'
    je 11f
    cmp al, '['
    je 12f
    cmp al, '-'
    je 13f
    cmp al, '+'
    je 13f
    jmp 90f
11: call enter_nesting
    call parse_object
    dec qword ptr [rip + g_depth]
    jmp 99f
12: call enter_nesting
    call parse_array
    dec qword ptr [rip + g_depth]
    jmp 99f
    # unary + or -: the argument must be a number, Infinity or NaN
13: mov r12, rax
    mov r13, [rip + g_tok_start]
    call lex_next
    mov rax, [rip + g_tok_type]
    cmp rax, TK_NUM
    je 14f
    cmp rax, TK_NAME
    jne 91f
    TOK_IS s_Infinity, 8
    test eax, eax
    jnz 15f
    TOK_IS s_NaN, 3
    test eax, eax
    jz 91f
15: mov edi, T_Identifier
    jmp 16f
14: mov edi, T_NumericLiteral
16: mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov r14, rax
    mov edi, T_UnaryExpression
    mov rsi, r13
    mov rdx, [rip + g_tok_end]
    call new_node
    mov [rax + N_F0], r14
    mov [rax + N_F1], r12
    mov rbx, rax
    call lex_next
    mov rax, rbx
    jmp 99f
20: mov edi, T_StringLiteral
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov rcx, [rip + g_tok_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_tok_len]
    mov [rax + N_F1], rcx
    jmp 98f
30: mov edi, T_NumericLiteral
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    jmp 98f
40: TOK_IS s_true, 4
    test eax, eax
    jz 41f
    mov edi, T_BooleanLiteral
    mov ebx, 1
    jmp 47f
41: TOK_IS s_false, 5
    test eax, eax
    jz 42f
    mov edi, T_BooleanLiteral
    xor ebx, ebx
    jmp 47f
42: TOK_IS s_null, 4
    test eax, eax
    jz 43f
    mov edi, T_NullLiteral
    jmp 47f
43: TOK_IS s_Infinity, 8
    test eax, eax
    jnz 46f
    TOK_IS s_NaN, 3
    test eax, eax
    jnz 46f
    TOK_IS s_undefined, 9
    test eax, eax
    jz 92f
46: mov edi, T_Identifier
47: mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov [rax + N_F0], rbx
    jmp 98f
    # template literal: TemplateElement range excludes the backticks
50: mov edi, T_TemplateElement
    mov rsi, [rip + g_tok_raw_start]
    mov rdx, [rip + g_tok_raw_end]
    call new_node
    mov rcx, [rip + g_tok_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_tok_len]
    mov [rax + N_F1], rcx
    mov rbx, rax
    call ss_mark
    mov r12, rax
    mov rdi, rbx
    call ss_push
    mov rdi, r12
    call ss_to_vec
    mov rbx, rax
    call ss_mark
    mov rdi, rax
    call ss_to_vec
    mov r12, rax
    mov edi, T_TemplateLiteral
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov [rax + N_F0], rbx
    mov [rax + N_F1], r12
98: mov rbx, rax
    call lex_next
    mov rax, rbx
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "expression not allowed in JSON"
91: REFUSE "unary operator on something other than a number"
92: REFUSE "identifier not allowed in JSON"
ENDF parse_value

# parse_object() at `{` -> rax = ObjectExpression
FUNC parse_object
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, [rip + g_tok_start]
    call ss_mark
    mov r13, rax
    xor r15d, r15d                  # __proto__ keys seen
    call lex_next
1:  mov edi, '}'
    call is_punct
    test eax, eax
    jnz 9f
    # key
    mov rax, [rip + g_tok_type]
    cmp rax, TK_STRING
    je 2f
    cmp rax, TK_NUM
    je 3f
    cmp rax, TK_NAME
    je 4f
    jmp 90f
2:  mov edi, T_StringLiteral
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov rcx, [rip + g_tok_val]
    mov [rax + N_F0], rcx
    mov rcx, [rip + g_tok_len]
    mov [rax + N_F1], rcx
    mov r14, rax
    cmp rcx, 9
    jne 5f
    mov rdi, [rax + N_F0]
    lea rsi, [rip + s_proto]
    mov edx, 9
    call mem_eq
    add r15, rax
    jmp 5f
3:  mov edi, T_NumericLiteral
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov r14, rax
    jmp 5f
4:  mov edi, T_Identifier
    mov rsi, [rip + g_tok_start]
    mov rdx, [rip + g_tok_end]
    call new_node
    mov r14, rax
    TOK_IS s_proto, 9
    add r15, rax
5:  cmp r15, 1
    ja 92f
    call lex_next
    mov edi, ':'
    call is_punct
    test eax, eax
    jz 91f
    call lex_next
    call parse_value
    mov rbx, rax
    mov edi, T_ObjectProperty
    mov esi, [r14 + N_START]
    mov edx, [rbx + N_END]
    call new_node
    mov [rax + N_F0], r14
    mov [rax + N_F1], rbx
    mov rdi, rax
    call ss_push
    mov edi, ','
    call is_punct
    test eax, eax
    jz 6f
    call lex_next
    jmp 1b
6:  mov edi, '}'
    call is_punct
    test eax, eax
    jz 93f
9:  mov rdi, r13
    call ss_to_vec
    mov rbx, rax
    mov edi, T_ObjectExpression
    mov rsi, r12
    mov rdx, [rip + g_tok_end]
    call new_node
    mov [rax + N_F0], rbx
    mov rbx, rax
    call lex_next
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "object key not allowed in JSON"
91: REFUSE "object member is not a key: value pair"
92: REFUSE "duplicate __proto__ key (Babel reports an error)"
93: REFUSE "expected , or } in object"
ENDF parse_object

# parse_array() at `[` -> rax = ArrayExpression
FUNC parse_array
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_tok_start]
    call ss_mark
    mov r13, rax
    call lex_next
1:  mov edi, ']'
    call is_punct
    test eax, eax
    jnz 9f
    mov edi, ','
    call is_punct
    test eax, eax
    jz 2f
    xor edi, edi                    # hole
    call ss_push
    call lex_next
    jmp 1b
2:  call parse_value
    mov rdi, rax
    call ss_push
    mov edi, ','
    call is_punct
    test eax, eax
    jz 3f
    call lex_next
    jmp 1b
3:  mov edi, ']'
    call is_punct
    test eax, eax
    jz 90f
9:  mov rdi, r13
    call ss_to_vec
    mov rbx, rax
    mov edi, T_ArrayExpression
    mov rsi, r12
    mov rdx, [rip + g_tok_end]
    call new_node
    mov [rax + N_F0], rbx
    mov rbx, rax
    call lex_next
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "expected , or ] in array"
ENDF parse_array
