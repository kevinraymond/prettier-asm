# JS parser: entry point, shared helpers and statements. Builds the AST that Prettier's `babel`
# parser hands the printer: Babel's node shapes and ranges with Prettier's parse options
# (sourceType module, createParenthesizedExpressions, errorRecovery with Prettier's list of
# allowed errors), then Prettier's postprocess (parse_js_post.s). Syntax Babel rejects, and
# syntax that needs a plugin or proposal, is refused.
# Function names follow Babel's: jps_* statements, jpe_* expressions (parse_js_expr.s), jpp_*
# patterns (parse_js_pat.s), jpf_* functions and classes (parse_js_class.s), jpm_* modules
# (parse_js_module.s).
.include "defs.inc"
.include "parse_js.inc"

.equ MAX_JS_DEPTH, 1500

    .bss
    .balign 8
    .globl g_px, g_label_count, g_label_base, g_js_depth, g_default_exported, g_bind_lexical
    .globl g_ts, g_js_trap
g_ts:               .quad 0     # TS_* bits
g_js_trap:          .quad 0     # innermost js_try record, or 0
g_px:               .quad 0     # CX_* context bits
g_label_count:      .quad 0
g_label_base:       .quad 0     # first label entry visible in the current function
g_js_depth:         .quad 0
g_default_exported: .quad 0
g_bind_lexical:     .quad 0     # 1 while reading the names of a let or const declaration
g_labels:           .space LB_SIZE * LB_MAX

    .text

# js_node(type, start) -> rax: a zeroed node with type and start.
FUNC js_node
    push rdi
    push rsi
    mov edi, NODE_SIZE
    call alloc
    pop rsi
    pop rdi
    mov [rax + N_TYPE], di
    mov [rax + N_START], esi
    leave
    ret
ENDF js_node

# js_clone(node) -> rax: a copy (Babel's cloneIdentifier and cloneStringLiteral).
FUNC js_clone
    push rdi
    sub rsp, 8
    mov edi, NODE_SIZE
    call alloc
    add rsp, 8
    pop rsi
    mov rdi, rax
    mov ecx, NODE_SIZE / 8
    rep movsq
    leave
    ret
ENDF js_clone

FUNC js_syntax_error
    REFUSE "syntax error"
ENDF js_syntax_error

# ---------------------------------------------------------------- tryParse
# A js_try record lives on js_try's stack: the previous record, js_try's frame pointer, then the
# parser state from js_state_save.
.equ TR_PREV, 0
.equ TR_RBP, 8
.equ TR_STATE, 16
.equ ST_SIZE, 256
.equ TR_SIZE, TR_STATE + ST_SIZE

# js_state_save(buf) / js_state_restore(buf): everything Babel's state.clone() covers that this
# parser keeps: the token, the comment count, the context bits, labels, the expression error
# record, private names and the scratch stack. Nodes allocated since stay in the arena.
FUNC js_state_save
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call jl_save
    lea rdi, [rbx + 112]
    lea rsi, [rip + js_state_vars]
1:  mov rax, [rsi]
    test rax, rax
    jz 2f
    mov rax, [rax]
    mov [rdi], rax
    add rdi, 8
    add rsi, 8
    jmp 1b
2:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_state_save

FUNC js_state_restore
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call jl_restore
    lea rdi, [rbx + 112]
    lea rsi, [rip + js_state_vars]
1:  mov rax, [rsi]
    test rax, rax
    jz 2f
    mov rcx, [rdi]
    mov [rax], rcx
    add rdi, 8
    add rsi, 8
    jmp 1b
2:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_state_restore

    .section .data.rel.ro, "aw"
    .balign 8
js_state_vars:
    .quad g_ts, g_px, g_label_count, g_label_base, g_js_depth, g_default_exported, g_bind_lexical
    .quad g_potential_arrow_at, g_param_errors, g_err_shorthand, g_err_proto, g_err_optparam
    .quad g_priv_count, g_ss_ptr, 0
    .text

# js_try(fn, a, b, c) -> rax, edx: calls fn(a, b, c) as Babel's tryParse runs a callback. edx is
# TRY_OK with fn's result in rax; TRY_THROWN after a syntax error and TRY_ABORTED after
# js_abort, both with the parser state as it was before the call and rax 0.
FUNC js_try
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, TR_SIZE + 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    lea rdi, [rsp + TR_STATE]
    call js_state_save
    mov rax, [rip + g_js_trap]
    mov [rsp + TR_PREV], rax
    mov [rsp + TR_RBP], rbp
    mov [rip + g_js_trap], rsp
    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    call r12
    mov rcx, [rsp + TR_PREV]
    mov [rip + g_js_trap], rcx
    mov edx, TRY_OK
    jmp 9f
    # js_unwind arrives here with rsp at the record and ebx the status
js_try_unwound:
    lea rdi, [rsp + TR_STATE]
    call js_state_restore
    mov rcx, [rsp + TR_PREV]
    mov [rip + g_js_trap], rcx
    xor eax, eax
    mov edx, ebx
9:  add rsp, TR_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_try

# js_unwind(status): back to the innermost js_try, which returns status in edx
FUNC js_unwind
    mov ebx, edi
    mov rsp, [rip + g_js_trap]
    mov rbp, [rsp + TR_RBP]
    jmp js_try_unwound
ENDF js_unwind

# js_refuse(reason): the parser's REFUSE. A syntax error inside js_try unwinds to it.
    .section .rodata
s_syntax_error_prefix: .ascii "syntax error"
    .text
FUNC js_refuse
    cmp qword ptr [rip + g_js_trap], 0
    je 9f
    push rdi
    sub rsp, 8
    lea rsi, [rip + s_syntax_error_prefix]
    mov edx, 12
    call mem_eq
    add rsp, 8
    pop rdi
    test eax, eax
    jz 9f
    mov edi, TRY_THROWN
    call js_unwind
9:  call refuse
ENDF js_refuse

# js_abort(): Babel's abort() inside a tryParse callback
FUNC js_abort
    mov edi, TRY_ABORTED
    call js_unwind
ENDF js_abort

# js_lookahead(fn, a, b) -> rax: fn(a, b) with the parser state restored afterwards (Babel's
# tsLookAhead). A syntax error inside unwinds past it, as Babel's exception does.
FUNC js_lookahead
    push rbx
    push r12
    push r13
    push r14
    sub rsp, ST_SIZE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rsp
    call js_state_save
    mov rdi, r13
    mov rsi, r14
    call r12
    mov rbx, rax
    mov rdi, rsp
    call js_state_restore
    mov rax, rbx
    add rsp, ST_SIZE
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_lookahead

# js_try_parse(fn, a, b) -> rax: Babel's tsTryParse: fn(a, b); when it returns 0 the parser state is
# put back as it was.
FUNC js_try_parse
    push rbx
    push r12
    push r13
    push r14
    sub rsp, ST_SIZE
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rsp
    call js_state_save
    mov rdi, r13
    mov rsi, r14
    call r12
    mov rbx, rax
    test rax, rax
    jnz 1f
    mov rdi, rsp
    call js_state_restore
1:  mov rax, rbx
    add rsp, ST_SIZE
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_try_parse

# js_expect(type): refuses unless the current token has that type, then advances.
FUNC js_expect
    cmp [rip + g_jt_type], rdi
    jne 1f
    call jl_next
    leave
    ret
1:  REFUSE "syntax error: unexpected token"
ENDF js_expect

# js_eat(type) -> eax = 1 if the current token had that type (and was consumed)
FUNC js_eat
    xor eax, eax
    cmp [rip + g_jt_type], rdi
    jne 1f
    call jl_next
    mov eax, 1
1:  leave
    ret
ENDF js_eat

# js_can_insert_semicolon() -> eax: EOF, `}` or a line break before the current token
FUNC js_can_insert_semicolon
    mov eax, 1
    TT_IS J_EOF
    je 1f
    TT_IS J_RBRACE
    je 1f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 1f
    xor eax, eax
1:  leave
    ret
ENDF js_can_insert_semicolon

# js_is_line_terminator() -> eax: eats `;`, or says ASI applies
FUNC js_is_line_terminator
    TT_IS J_SEMI
    jne 1f
    call jl_next
    mov eax, 1
    leave
    ret
1:  call js_can_insert_semicolon
    leave
    ret
ENDF js_is_line_terminator

# js_semicolon(): a `;` or automatic semicolon insertion
FUNC js_semicolon
    call js_is_line_terminator
    test eax, eax
    jz 1f
    leave
    ret
1:  REFUSE "syntax error: missing semicolon"
ENDF js_semicolon

# js_tok_text_is(cstr, len) -> eax = 1 if the current token's text is that
FUNC js_tok_text_is
    mov rcx, [rip + g_jt_end]
    sub rcx, [rip + g_jt_start]
    cmp rcx, rsi
    jne 1f
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, [rip + g_text]
    add rdi, [rip + g_jt_start]
    call mem_eq
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF js_tok_text_is

# js_node_text_is(node, cstr, len) -> eax = 1 if the node's source text is that
FUNC js_node_text_is
    mov ecx, [rdi + N_END]
    sub ecx, [rdi + N_START]
    cmp rcx, rdx
    jne 1f
    mov eax, [rdi + N_START]
    mov rdi, [rip + g_text]
    add rdi, rax
    call mem_eq
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF js_node_text_is

# js_ident_check(binding): checks the current J_NAME token as an identifier reference
# (binding 0) or binding (1), as Babel's checkReservedWord does, refusing what Babel reports.
# Strict mode reserved words are identifiers here: Babel reports them with an error code
# Prettier allows. `let` is refused as a lexical binding (g_bind_lexical).
FUNC js_ident_check
    TT_IS J_NAME
    jne 90f
    mov rsi, rdi
    mov rdi, [rip + g_jt_kw]
    call js_word_check
    leave
    ret
90: REFUSE "syntax error: unexpected token"
ENDF js_ident_check

# js_word_check(kw, binding): the checks of js_ident_check for a word with keyword id kw
# (0 for a plain identifier).
FUNC js_word_check
    mov rax, rdi
    mov edi, esi
    test rax, rax
    jz 9f
    cmp rax, KW_LAST_RESERVED
    jbe 90f
    cmp rax, KW_YIELD
    jne 2f
    test qword ptr [rip + g_px], CX_YIELD
    jnz 91f
    jmp 9f
2:  cmp rax, KW_AWAIT
    jne 3f
    test qword ptr [rip + g_px], CX_AWAIT | CX_STATIC_BLOCK
    jnz 92f
    inc qword ptr [rip + g_param_errors]
    jmp 9f
3:  cmp rax, KW_LET
    jne 1f
    test edi, edi
    jz 9f
    cmp qword ptr [rip + g_bind_lexical], 0
    jne 93f
1:  cmp rax, KW_ARGUMENTS
    jne 9f
    test qword ptr [rip + g_px], CX_CLASS_INIT
    jnz 94f
9:  leave
    ret
90: REFUSE "syntax error: reserved word as an identifier"
91: REFUSE "syntax error: yield as an identifier in a generator"
92: REFUSE "syntax error: await as an identifier in an async function or static block"
93: REFUSE "syntax error: let as a lexical binding name"
94: REFUSE "syntax error: arguments in a class field"
ENDF js_word_check

# js_ident(binding) -> rax: Identifier from the current token (checked), advances.
FUNC js_ident
    call js_ident_check
    call js_ident_name
    leave
    ret
ENDF js_ident

# js_ident_name() -> rax: Identifier from any J_NAME token (Babel's liberal parseIdentifier).
FUNC js_ident_name
    push rbx
    sub rsp, 8
    TT_IS J_NAME
    jne 90f
    NODE T_Identifier, [rip + g_jt_start]
    mov rbx, rax
    mov rax, [rip + g_jt_end]
    mov [rbx + N_END], eax
    NEXT
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: identifier expected"
ENDF js_ident_name

# js_enter_depth() / js_leave_depth(): nesting guard
FUNC js_enter_depth
    inc qword ptr [rip + g_js_depth]
    cmp qword ptr [rip + g_js_depth], MAX_JS_DEPTH
    ja 9f
    leave
    ret
9:  REFUSE "nesting too deep"
ENDF js_enter_depth

# ---------------------------------------------------------------- flow pragma
    .section .rodata
s_flow: .ascii "flow"
s_at_flow: .ascii "@flow"
s_at_noflow: .ascii "@noflow"
    .text

# js_check_flow_pragma(): refuses when the text before the first token holds @flow or
# @noflow as a word (Prettier then parses with babel-flow). Runs after jl_init.
FUNC js_check_flow_pragma
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_text]
    mov r13, [rip + g_jt_start]         # first token
    xor ebx, ebx
    mov rax, [rip + g_comments]         # after an interpreter directive
    test rax, rax
    jz 1f
    cmp dword ptr [rax], 0
    je 1f
    mov rax, [rax + 8]
    cmp byte ptr [rax + CM_TYPE], CT_INTERPRETER
    jne 1f
    mov ebx, [rax + CM_END]
1:  lea rax, [rbx + 5]
    cmp rax, r13
    ja 9f
    cmp byte ptr [r12 + rbx], '@'
    jne 5f
    lea rcx, [rbx + 1]
    cmp dword ptr [r12 + rcx], 0x776f6c66   # "flow"
    je 2f
    lea rax, [rbx + 7]
    cmp rax, r13
    ja 5f
    cmp word ptr [r12 + rcx], 0x6f6e        # "no"
    jne 5f
    cmp dword ptr [r12 + rcx + 2], 0x776f6c66
    jne 5f
    add rcx, 2
2:  add rcx, 4                          # after "flow": no word character may follow
    cmp rcx, [rip + g_text_len]
    jae 90f
    movzx eax, byte ptr [r12 + rcx]
    cmp al, 0x80
    jae 90f
    lea rdx, [rip + js_char_class]
    movzx edx, byte ptr [rdx + rax]
    cmp edx, 3
    jne 21f
    cmp al, '$'
    je 90f
    jmp 5f
21: cmp edx, 4
    je 5f
    jmp 90f
5:  inc rbx
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "Flow pragma (Prettier uses babel-flow)"
ENDF js_check_flow_pragma

# ---------------------------------------------------------------- entry
# js_parse(flags) -> rax = File. flags: JS_SRC_SCRIPT for sourceType script (.cjs, .cts),
# JS_SRC_TS for TypeScript (Babel's typescript plugin), as js_source_is_script returns them.
FUNC js_parse
    push rbx
    push r12
    push r13
    push r14
    mov qword ptr [rip + g_ts], 0
    test edi, JS_SRC_TS
    jz 2f
    mov qword ptr [rip + g_ts], TS_ON
2:  and edi, JS_SRC_SCRIPT
    mov [rip + g_js_script], rdi
    mov qword ptr [rip + g_js_trap], 0
    mov qword ptr [rip + g_px], CX_AWAIT
    test rdi, rdi
    jz 1f
    mov qword ptr [rip + g_px], 0
1:  mov qword ptr [rip + g_label_count], 0
    mov qword ptr [rip + g_label_base], 0
    mov qword ptr [rip + g_js_depth], 0
    mov qword ptr [rip + g_default_exported], 0
    call jpe_reset
    call jl_init
    call js_check_flow_pragma
    NODE T_Program, 0
    mov r12, rax
    mov edi, J_EOF
    mov esi, 1                          # directives
    call jps_block_body
    mov [r12 + N_F0], rax
    mov [r12 + N_F1], rdx
    mov rax, [rip + g_text_len]
    mov [r12 + N_END], eax
    mov qword ptr [r12 + N_F2], KD_MODULE
    cmp qword ptr [rip + g_js_script], 0
    je 2f
    mov qword ptr [r12 + N_F2], KD_SCRIPT
2:  NODE T_File, 0
    mov rbx, rax
    mov rax, [rip + g_text_len]
    mov [rbx + N_END], eax
    mov [rbx + N_F0], r12
    mov rdi, rbx
    call js_postprocess
    IF_NOT_TS 3f
    mov rdi, rbx
    xor esi, esi
    call jts_check_param_decorators
3:  mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF js_parse

# ---------------------------------------------------------------- statement lists
# jps_block_body(end, directives) -> rax = body VEC, rdx = directives VEC (0 when not allowed).
# Parses statements up to the end token and consumes it. With directives, leading
# expression statements that are a bare string literal become Directive nodes.
FUNC jps_block_body
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi                        # end token
    mov r13d, esi                       # 1 while still in the directive prologue
    xor r15d, r15d                      # directives VEC
    call ss_mark
    mov r14, rax
1:  cmp [rip + g_jt_type], r12
    je 8f
    TT_IS J_EOF
    je 90f
    mov edi, 1                          # declarations allowed
    call jps_statement
    mov rbx, rax
    test r13d, r13d
    jz 5f
    # a directive: ExpressionStatement with an unparenthesized StringLiteral
    cmp word ptr [rbx + N_TYPE], T_ExpressionStatement
    jne 4f
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_StringLiteral
    jne 4f
    mov word ptr [rbx + N_TYPE], T_Directive
    mov word ptr [rax + N_TYPE], T_DirectiveLiteral
    mov rdi, rbx
    call ss_push
    jmp 1b
4:  xor r13d, r13d                      # prologue over: directives so far become a VEC
    mov rdi, r14
    call ss_to_vec
    mov r15, rax
    call ss_mark
    mov r14, rax
5:  mov rdi, rbx
    call ss_push
    jmp 1b
8:  test r13d, r13d
    jz 9f
    mov rdi, r14
    call ss_to_vec
    mov r15, rax
    call ss_mark
    mov r14, rax
9:  NEXT
    mov rdi, r14
    call ss_to_vec
    mov rdx, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unexpected end of input"
ENDF jps_block_body

# jps_has_use_strict(directives VEC) -> eax = 1 if one of them is "use strict"
    .section .rodata
s_use_strict: .ascii "\"use strict\""
s_use_strict_sq: .ascii "'use strict'"
    .text
FUNC jps_has_use_strict
    push rbx
    push r12
    mov rbx, rdi
    xor r12d, r12d
    test rbx, rbx
    jz 8f
1:  cmp r12, [rbx]
    jae 8f
    mov rdi, [rbx + 8 + r12*8]
    mov rdi, [rdi + N_F0]
    push rdi
    sub rsp, 8
    lea rsi, [rip + s_use_strict]
    mov edx, 12
    call js_node_text_is
    add rsp, 8
    pop rdi
    test eax, eax
    jnz 9f
    lea rsi, [rip + s_use_strict_sq]
    mov edx, 12
    call js_node_text_is
    test eax, eax
    jnz 9f
    inc r12
    jmp 1b
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF jps_has_use_strict

# jps_block() -> rax = BlockStatement at `{`
FUNC jps_block
    push rbx
    sub rsp, 8
    TT_IS J_LBRACE
    jne 90f
    NODE T_BlockStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    mov edi, J_RBRACE
    xor esi, esi
    call jps_block_body
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: { expected"
ENDF jps_block

# ---------------------------------------------------------------- labels
# js_label_push(name_start, name_len, kind, stmt_start)
FUNC js_label_push
    mov rax, [rip + g_label_count]
    cmp rax, LB_MAX
    jae 9f
    shl rax, 4
    lea r8, [rip + g_labels]
    add r8, rax
    mov [r8 + LB_START], edi
    mov [r8 + LB_LEN], esi
    mov [r8 + LB_KIND], edx
    mov [r8 + LB_STMT], ecx
    inc qword ptr [rip + g_label_count]
    leave
    ret
9:  REFUSE "too many nested labels"
ENDF js_label_push

FUNC js_label_pop
    dec qword ptr [rip + g_label_count]
    leave
    ret
ENDF js_label_pop

# js_loop_push(): Babel's loopLabel
FUNC js_loop_push
    mov edi, -1
    xor esi, esi
    mov edx, 1
    mov ecx, -1
    call js_label_push
    leave
    ret
ENDF js_loop_push

# js_label_eq(entry, name_start, name_len) -> eax = 1 if the entry's name is that
FUNC js_label_eq
    xor eax, eax
    cmp dword ptr [rdi + LB_START], -1
    je 9f
    cmp [rdi + LB_LEN], edx
    jne 9f
    mov r8, [rip + g_text]
    mov ecx, [rdi + LB_START]
    lea rdi, [r8 + rcx]
    add rsi, r8
    call mem_eq
9:  leave
    ret
ENDF js_label_eq

# ---------------------------------------------------------------- statements
# jps_statement(allow_declaration) -> rax = statement node
FUNC jps_statement
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r15d, edi
    call js_enter_depth
    mov qword ptr [rsp], 0              # decorators
    TT_IS J_AT
    jne 1f
    call jpd_decorators
    mov [rsp], rax
    KW_IS KW_EXPORT                     # parseDecorators: export or a class must follow
    je 1f
    KW_IS KW_CLASS
    je 1f
    IF_NOT_TS 92f
    KW_IS KW_ABSTRACT
    jne 92f
    call ts_is_lookahead_class
    test eax, eax
    jz 92f
1:  mov r12, [rip + g_jt_start]         # statement start
    mov rax, [rip + g_jt_type]
    cmp rax, J_NAME
    je 10f
    cmp rax, J_LBRACE
    je 20f
    cmp rax, J_SEMI
    je 21f
    jmp 50f

10: IF_NOT_TS 11f
    mov rdi, r12
    call jts_statement_start
    test rax, rax
    jnz 99f
11: mov rax, [rip + g_jt_kw]
    cmp rax, KW_BREAK
    je 30f
    cmp rax, KW_CONTINUE
    je 30f
    cmp rax, KW_IF
    je 31f
    cmp rax, KW_RETURN
    je 32f
    cmp rax, KW_VAR
    je 33f
    cmp rax, KW_CONST
    je 34f
    cmp rax, KW_LET
    je 35f
    cmp rax, KW_FUNCTION
    je 36f
    cmp rax, KW_FOR
    je 37f
    cmp rax, KW_WHILE
    je 38f
    cmp rax, KW_DO
    je 39f
    cmp rax, KW_THROW
    je 40f
    cmp rax, KW_TRY
    je 41f
    cmp rax, KW_SWITCH
    je 42f
    cmp rax, KW_CLASS
    je 43f
    cmp rax, KW_IMPORT
    je 44f
    cmp rax, KW_EXPORT
    je 45f
    cmp rax, KW_ASYNC
    je 46f
    cmp rax, KW_WITH
    je 47f
    cmp rax, KW_DEBUGGER
    je 48f
    cmp rax, KW_USING
    je 49f
    cmp rax, KW_AWAIT
    je 491f
    jmp 50f

20: call jps_block
    jmp 99f
21: NODE T_EmptyStatement, r12
    mov rbx, rax
    NEXT
    FINISH rbx
    mov rax, rbx
    jmp 99f
30: call jps_break_continue
    jmp 99f
31: call jps_if
    jmp 99f
32: call jps_return
    jmp 99f
33: mov edi, KD_VAR
    call jps_var_statement
    jmp 99f
34: test r15d, r15d
    jz 93f
    mov edi, KD_CONST
    call jps_var_statement
    jmp 99f
    # let: a declaration when a binding follows (Babel's parseStatementContent)
35: mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '['
    je 351f
    test r15d, r15d
    jnz 352f
    test ecx, ecx
    jnz 50f                             # `let` then a line break: an expression
352: cmp eax, '{'
    je 351f
    mov rdi, rdx
    call jps_starts_binding_ident
    test eax, eax
    jz 50f
351: test r15d, r15d
    jz 93f
    mov edi, KD_LET
    call jps_var_statement
    jmp 99f
36: mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '.'
    je 50f                              # function.sent: refused in the expression
    test r15d, r15d
    jnz 361f
    cmp qword ptr [rip + g_js_script], 0
    jne 96f
361:
    NODE T_FunctionDeclaration, r12
    mov rbx, rax
    NEXT
    mov rdi, rbx
    mov esi, 1                          # declaration
    call jpf_function
    jmp 99f
37: call jps_for
    jmp 99f
38: NODE T_WhileStatement, r12
    mov rbx, rax
    NEXT
    call jps_paren_expression
    mov [rbx + N_F0], rax
    call js_loop_push
    xor edi, edi
    call jps_statement
    mov [rbx + N_F1], rax
    call js_label_pop
    FINISH rbx
    mov rax, rbx
    jmp 99f
39: NODE T_DoWhileStatement, r12
    mov rbx, rax
    NEXT
    call js_loop_push
    xor edi, edi
    call jps_statement
    mov [rbx + N_F1], rax
    call js_label_pop
    KW_IS KW_WHILE
    jne 90f
    NEXT
    call jps_paren_expression
    mov [rbx + N_F0], rax
    mov edi, J_SEMI
    call js_eat
    FINISH rbx
    mov rax, rbx
    jmp 99f
40: NODE T_ThrowStatement, r12
    mov rbx, rax
    NEXT
    cmp qword ptr [rip + g_jt_nl], 0
    jne 90f
    xor edi, edi
    call jpe_expression
    mov [rbx + N_F0], rax
    call js_semicolon
    FINISH rbx
    mov rax, rbx
    jmp 99f
41: call jps_try
    jmp 99f
42: call jps_switch
    jmp 99f
43: test r15d, r15d
    jz 90f
    NODE T_ClassDeclaration, r12
    mov rdi, rax
    mov esi, 1                          # statement
    xor edx, edx                        # id required
    call jpf_class
    mov rdi, rax
    mov rsi, [rsp]
    call js_take_decorators
    jmp 99f
44: mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '('
    je 50f
    cmp eax, '.'
    je 50f
    call jpm_import
    jmp 99f
45: mov rdi, [rsp]
    call jpm_export
    jmp 99f
    # async function
46: call jps_is_async_function
    test eax, eax
    jz 50f
    test r15d, r15d
    jz 94f
    NODE T_FunctionDeclaration, r12
    mov rbx, rax
    or dword ptr [rbx + N_ATTR], NA_ASYNC
    NEXT
    NEXT
    mov rdi, rbx
    mov esi, 1
    call jpf_function
    jmp 99f
47: NODE T_WithStatement, r12
    mov rbx, rax
    NEXT
    call jps_paren_expression
    mov [rbx + N_F0], rax
    xor edi, edi
    call jps_statement
    mov [rbx + N_F1], rax
    FINISH rbx
    mov rax, rbx
    jmp 99f
48: NODE T_DebuggerStatement, r12
    mov rbx, rax
    NEXT
    call js_semicolon
    FINISH rbx
    mov rax, rbx
    jmp 99f
    # using x = ...: explicit resource management
49: mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 50f
    cmp eax, '{'
    je 95f
    mov rdi, rdx
    call jps_starts_binding_ident
    test eax, eax
    jnz 95f
    jmp 50f
    # await using x = ...
491: call js_using_follows
    test eax, eax
    jnz 95f
    jmp 50f

    # expression statement or labeled statement
50: mov r13, [rip + g_jt_type]          # start token type
    mov r14, [rip + g_jt_kw]
    xor edi, edi
    call jpe_expression
    mov rbx, rax
    cmp r13, J_NAME
    jne 51f
    cmp r14, 0
    je 52f
    cmp r14, KW_LAST_RESERVED
    jbe 51f
52: cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 51f
    TT_IS J_COLON
    jne 51f
    NEXT
    mov rdi, r12
    mov rsi, rbx
    call jps_labeled
    jmp 99f
51: IF_NOT_TS 53f
    cmp r13, J_NAME
    jne 53f
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 53f
    mov rdi, r12
    mov rsi, r14
    mov rdx, [rsp]
    call jts_expression_statement
    test rax, rax
    jnz 99f
53: cmp qword ptr [rsp], 0
    jne 92f
    NODE T_ExpressionStatement, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    call js_semicolon
    FINISH rbx
    mov rax, rbx

99: dec qword ptr [rip + g_js_depth]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unexpected token"
92: REFUSE "syntax error: decorators before something other than a class"
93: REFUSE "syntax error: lexical declaration in a single-statement context"
94: REFUSE "syntax error: async function in a single-statement context"
95: REFUSE "using declaration (explicit resource management)"
96: REFUSE "function declaration in a single-statement context (sourceType script)"
ENDF jps_statement

# js_take_decorators(class, decorators VEC or 0) -> rax: Babel's maybeTakeDecorators: decorators
# read before the class go first in its list, and the class starts at the first one
FUNC js_take_decorators
    mov rax, rdi
    test rsi, rsi
    jz 9f
    cmp qword ptr [rax + N_F6], 0
    jne 90f
    mov [rax + N_F6], rsi
    mov rcx, [rsi + 8]
    mov ecx, [rcx + N_START]
    mov [rax + N_START], ecx
9:  leave
    ret
90: REFUSE "syntax error: decorators both before and after export"
ENDF js_take_decorators

# jps_starts_binding_ident(pos) -> eax: Babel's chStartsBindingIdentifier: an identifier
# starts at pos and is not the word `in` or `instanceof`.
FUNC jps_starts_binding_ident
    xor eax, eax
    cmp rdi, [rip + g_text_len]
    jae 9f
    mov rsi, [rip + g_text]
    movzx ecx, byte ptr [rsi + rdi]
    cmp cl, '\\'
    je 8f
    cmp cl, 0x80
    jae 8f
    lea rdx, [rip + js_char_class]
    cmp byte ptr [rdx + rcx], 3
    jne 9f
    # `in` or `instanceof` followed by a non-identifier character
    cmp cl, 'i'
    jne 8f
    lea r8, [rdi + 2]
    cmp r8, [rip + g_text_len]
    ja 8f
    cmp byte ptr [rsi + rdi + 1], 'n'
    jne 8f
    lea r9, [rdi + 10]
    cmp r9, [rip + g_text_len]
    ja 3f
    mov r10, 0x65636e6174736e69         # "instance"
    cmp [rsi + rdi], r10
    jne 3f
    cmp word ptr [rsi + rdi + 8], 0x666f  # "of"
    jne 3f
    mov r8, r9
3:  cmp r8, [rip + g_text_len]
    jae 9f
    movzx ecx, byte ptr [rsi + r8]
    cmp cl, 0x80
    jae 8f
    cmp cl, '\\'
    je 8f
    movzx ecx, byte ptr [rdx + rcx]
    cmp ecx, 3
    je 8f
    cmp ecx, 4
    je 8f
    jmp 9f
8:  mov eax, 1
9:  leave
    ret
ENDF jps_starts_binding_ident

# js_using_follows() -> eax: the word `using` follows the current token on the same line
FUNC js_using_follows
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 8f
    mov rsi, [rip + g_text]
    lea rcx, [rdx + 5]
    cmp rcx, [rip + g_text_len]
    ja 8f
    cmp dword ptr [rsi + rdx], 0x6e697375   # "usin"
    jne 8f
    cmp byte ptr [rsi + rdx + 4], 'g'
    jne 8f
    mov eax, 1
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF js_using_follows

# jps_is_async_function() -> eax: the current token is `async` and `function` follows on the
# same line.
FUNC jps_is_async_function
    xor eax, eax
    KW_IS KW_ASYNC
    jne 9f
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    test ecx, ecx
    jnz 8f
    mov rsi, [rip + g_text]
    lea rcx, [rdx + 8]
    cmp rcx, [rip + g_text_len]
    ja 8f
    mov r8, 0x6e6f6974636e7566          # "function"
    cmp [rsi + rdx], r8
    jne 8f
    cmp rcx, [rip + g_text_len]
    jae 7f
    movzx ecx, byte ptr [rsi + rcx]
    cmp cl, 0x80
    jae 8f
    lea rdx, [rip + js_char_class]
    movzx ecx, byte ptr [rdx + rcx]
    cmp ecx, 3
    je 8f
    cmp ecx, 4
    je 8f
7:  mov eax, 1
    leave
    ret
8:  xor eax, eax
9:  leave
    ret
ENDF jps_is_async_function

# jps_paren_expression() -> rax: `( Expression )`
FUNC jps_paren_expression
    push rbx
    sub rsp, 8
    EXPECT J_LPAREN
    call jpe_expression_allow_in
    mov rbx, rax
    EXPECT J_RPAREN
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jps_paren_expression

# jps_labeled(start, label Identifier) -> rax = LabeledStatement. The `:` is consumed.
FUNC jps_labeled
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    # a label of the same name in scope is an error
    mov r14, [rip + g_label_base]
1:  cmp r14, [rip + g_label_count]
    jae 2f
    mov rdi, r14
    shl rdi, 4
    lea rax, [rip + g_labels]
    add rdi, rax
    mov esi, [r13 + N_START]
    mov edx, [r13 + N_END]
    sub edx, esi
    call js_label_eq
    test eax, eax
    jnz 90f
    inc r14
    jmp 1b
    # kind: loop or switch statement next
2:  xor r15d, r15d
    KW_IS KW_FOR
    je 3f
    KW_IS KW_WHILE
    je 3f
    KW_IS KW_DO
    je 3f
    KW_IS KW_SWITCH
    jne 4f
    mov r15d, 2
    jmp 4f
3:  mov r15d, 1
    # labels of an enclosing labeled statement that starts here take the same kind
4:  mov rcx, [rip + g_label_count]
5:  cmp rcx, [rip + g_label_base]
    jbe 6f
    dec rcx
    mov rax, rcx
    shl rax, 4
    lea rdx, [rip + g_labels]
    add rdx, rax
    cmp [rdx + LB_STMT], r12d
    jne 6f
    mov rax, [rip + g_jt_start]
    mov [rdx + LB_STMT], eax
    mov [rdx + LB_KIND], r15d
    jmp 5b
6:  mov edi, [r13 + N_START]
    mov esi, [r13 + N_END]
    sub esi, edi
    mov edx, r15d
    mov rcx, [rip + g_jt_start]
    call js_label_push
    NODE T_LabeledStatement, r12
    mov rbx, rax
    mov [rbx + N_F0], r13
    xor edi, edi
    call jps_statement
    mov [rbx + N_F1], rax
    call js_label_pop
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: duplicate label"
ENDF jps_labeled

# jps_break_continue() -> rax
FUNC jps_break_continue
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    xor r12d, r12d
    KW_IS KW_BREAK
    sete r12b                           # 1 for break
    mov edi, T_ContinueStatement
    test r12d, r12d
    jz 1f
    mov edi, T_BreakStatement
1:  mov rsi, [rip + g_jt_start]
    call js_node
    mov rbx, rax
    NEXT
    call js_is_line_terminator
    test eax, eax
    jnz 2f
    xor edi, edi
    call js_ident
    mov [rbx + N_F0], rax
    call js_semicolon
    # verifyBreakContinue
2:  mov r13, [rip + g_label_base]
3:  cmp r13, [rip + g_label_count]
    jae 90f
    mov r14, r13
    shl r14, 4
    lea rax, [rip + g_labels]
    add r14, rax
    mov rax, [rbx + N_F0]
    test rax, rax
    jz 4f
    mov rdi, r14
    mov esi, [rax + N_START]
    mov edx, [rax + N_END]
    sub edx, esi
    call js_label_eq
    test eax, eax
    jz 6f
4:  mov eax, [r14 + LB_KIND]
    test eax, eax
    jz 5f
    test r12d, r12d
    jnz 8f
    cmp eax, 1
    je 8f
5:  cmp qword ptr [rbx + N_F0], 0
    je 6f
    test r12d, r12d
    jnz 8f
6:  inc r13
    jmp 3b
8:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: illegal break or continue"
ENDF jps_break_continue

# jps_if() -> rax
FUNC jps_if
    push rbx
    sub rsp, 8
    NODE T_IfStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call jps_paren_expression
    mov [rbx + N_F0], rax
    xor edi, edi
    call jps_statement
    mov [rbx + N_F1], rax
    KW_IS KW_ELSE
    jne 1f
    NEXT
    xor edi, edi
    call jps_statement
    mov [rbx + N_F2], rax
1:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jps_if

# jps_return() -> rax
FUNC jps_return
    push rbx
    sub rsp, 8
    test qword ptr [rip + g_px], CX_NO_RETURN
    jnz 90f
    NODE T_ReturnStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call js_is_line_terminator
    test eax, eax
    jnz 1f
    xor edi, edi
    call jpe_expression
    mov [rbx + N_F0], rax
    call js_semicolon
1:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: return in a static block"
ENDF jps_return

# jps_var_statement(kind) -> rax: var, let or const declaration statement
FUNC jps_var_statement
    push rbx
    push r12
    mov r12, rdi
    NODE T_VariableDeclaration, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call jps_var
    call js_semicolon
    FINISH rbx
    IF_NOT_TS 1f
    mov rdi, rbx
    call jts_check_ambient_var
1:  mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jps_var_statement

# jps_var(node, kind, is_for): the declarators of a VariableDeclaration
FUNC jps_var
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rbx + N_F1], r12
    call ss_mark
    mov r14, rax
1:  NODE T_VariableDeclarator, [rip + g_jt_start]
    mov r15, rax
    xor eax, eax
    cmp r12, KD_VAR
    setne al
    mov [rip + g_bind_lexical], rax
    call jpp_binding_atom
    mov qword ptr [rip + g_bind_lexical], 0
    mov [r15 + N_F0], rax
    IF_NOT_TS 11f
    mov rdi, r15
    call jts_var_id
11: TT_IS J_EQ
    jne 3f
    NEXT
    test r13d, r13d
    jz 2f
    call jpe_maybe_assign_disallow_in
    jmp 21f
2:  call jpe_maybe_assign_allow_in
21: mov [r15 + N_F1], rax
3:  FINISH r15
    test dword ptr [r15 + N_ATTR], NA_DEFINITE
    jz 31f
    cmp qword ptr [r15 + N_F1], 0       # typescript-estree: `x!` needs a type and no initializer
    jne 92f
    mov rax, [r15 + N_F0]
    cmp qword ptr [rax + N_F5], 0
    je 92f
31: mov rdi, r15
    call ss_push
    TT_IS J_COMMA
    jne 4f
    NEXT
    jmp 1b
4:  mov rdi, r14
    call ss_to_vec
    mov [rbx + N_F0], rax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
92: REFUSE "rejected by Prettier's typescript parser: a definite assignment assertion with an initializer or without a type"
ENDF jps_var

# jps_for() -> rax: for, for-in, for-of, for await
FUNC jps_for
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    NODE T_ForStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call js_loop_push
    xor r12d, r12d                      # 1 after `await`
    KW_IS KW_AWAIT
    jne 1f
    test qword ptr [rip + g_px], CX_AWAIT
    jz 1f
    mov r12d, 1
    NEXT
1:  EXPECT J_LPAREN
    TT_IS J_SEMI
    jne 2f
    test r12d, r12d
    jnz 90f
    mov rdi, rbx
    xor esi, esi
    call jps_for_rest
    jmp 99f
2:  KW_IS KW_USING
    je 95f
    KW_IS KW_AWAIT
    jne 21f
    call js_using_follows
    test eax, eax
    jnz 95f
21: xor r13d, r13d                      # starts with let
    KW_IS KW_VAR
    je 3f
    KW_IS KW_CONST
    je 3f
    KW_IS KW_LET
    jne 5f
    mov r13d, 1
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    cmp eax, '['
    je 3f
    cmp eax, '{'
    je 3f
    mov rdi, rdx
    call jps_starts_binding_ident
    test eax, eax
    jz 5f
    # declaration
3:  mov r14, KD_VAR
    KW_IS KW_CONST
    jne 31f
    mov r14, KD_CONST
31: KW_IS KW_LET
    jne 32f
    mov r14, KD_LET
32: NODE T_VariableDeclaration, [rip + g_jt_start]
    mov r15, rax
    NEXT
    mov rdi, r15
    mov rsi, r14
    mov edx, 1
    call jps_var
    FINISH r15
    KW_IS KW_IN
    je 33f
    KW_IS KW_OF
    jne 34f
33: mov rax, [r15 + N_F0]
    cmp qword ptr [rax], 1
    jne 34f
    mov rdi, rbx
    mov rsi, r15
    mov edx, r12d
    call jps_for_in
    jmp 99f
34: test r12d, r12d
    jnz 90f
    mov rdi, rbx
    mov rsi, r15
    call jps_for_rest
    jmp 99f
    # expression
5:  xor r14d, r14d
    KW_IS KW_ASYNC
    sete r14b
    call jpe_errors_save
    mov [rsp], rax
    mov [rsp + 8], rdx
    mov rax, [rip + g_px]
    mov [rsp + 16], rax
    or qword ptr [rip + g_px], CX_NO_IN
    mov edi, 1                          # REF
    call jpe_expression
    mov r15, rax
    mov rax, [rsp + 16]
    mov [rip + g_px], rax
    KW_IS KW_OF
    jne 6f
    test r13d, r13d
    jnz 96f
    test r12d, r12d
    jnz 7f
    test r14d, r14d
    jz 7f
    cmp word ptr [r15 + N_TYPE], T_Identifier
    je 97f
    jmp 7f
6:  KW_IS KW_IN
    jne 8f
7:  mov rdi, r15
    mov esi, 1
    call jpp_to_assignable
    mov rdi, r15
    xor esi, esi
    call jpp_check_lval
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    mov rdi, rbx
    mov rsi, r15
    mov edx, r12d
    call jps_for_in
    jmp 99f
8:  call jpe_errors_check
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call jpe_errors_restore
    test r12d, r12d
    jnz 90f
    mov rdi, rbx
    mov rsi, r15
    call jps_for_rest
99: add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: unexpected token in for"
95: REFUSE "using declaration (explicit resource management)"
96: REFUSE "syntax error: for (let of ...)"
97: REFUSE "syntax error: for (async of ...)"
ENDF jps_for

# jps_for_rest(node, init) -> rax: the rest of `for (init; test; update) body`
FUNC jps_for_rest
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov [rbx + N_F0], rsi
    EXPECT J_SEMI
    TT_IS J_SEMI
    je 1f
    call jpe_expression_allow_in
    mov [rbx + N_F1], rax
1:  EXPECT J_SEMI
    TT_IS J_RPAREN
    je 2f
    call jpe_expression_allow_in
    mov [rbx + N_F2], rax
2:  EXPECT J_RPAREN
    xor edi, edi
    call jps_statement
    mov [rbx + N_F3], rax
    call js_label_pop
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jps_for_rest

# jps_for_in(node, left, await) -> rax: the rest of a for-in or for-of statement
FUNC jps_for_in
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor r14d, r14d
    KW_IS KW_IN
    sete r14b                           # 1 for in
    NEXT
    mov word ptr [rbx + N_TYPE], T_ForOfStatement
    test r14d, r14d
    jz 1f
    mov word ptr [rbx + N_TYPE], T_ForInStatement
    test r13d, r13d
    jnz 90f
    jmp 2f
1:  test r13d, r13d
    jz 2f
    or dword ptr [rbx + N_ATTR], NA_AWAIT
2:  cmp word ptr [r12 + N_TYPE], T_AssignmentPattern
    je 90f
    mov [rbx + N_F0], r12
    test r14d, r14d
    jz 3f
    call jpe_expression_allow_in
    jmp 4f
3:  call jpe_maybe_assign_allow_in
4:  mov [rbx + N_F1], rax
    EXPECT J_RPAREN
    xor edi, edi
    call jps_statement
    mov [rbx + N_F2], rax
    call js_label_pop
    FINISH rbx
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: invalid for-in or for-of"
ENDF jps_for_in

# jps_switch() -> rax
FUNC jps_switch
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    NODE T_SwitchStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call jps_paren_expression
    mov [rbx + N_F0], rax
    EXPECT J_LBRACE
    mov edi, -1
    xor esi, esi
    mov edx, 2
    mov ecx, -1
    call js_label_push
    call ss_mark
    mov r12, rax                        # cases
    xor r15d, r15d                      # saw default
1:  TT_IS J_RBRACE
    je 8f
    KW_IS KW_CASE
    je 2f
    KW_IS KW_DEFAULT
    jne 90f
2:  NODE T_SwitchCase, [rip + g_jt_start]
    mov r13, rax
    KW_IS KW_CASE
    jne 3f
    NEXT
    call jpe_expression_allow_in
    mov [r13 + N_F0], rax
    jmp 4f
3:  test r15d, r15d
    jnz 91f
    mov r15d, 1
    NEXT
4:  EXPECT J_COLON
    call ss_mark
    mov r14, rax
5:  TT_IS J_RBRACE
    je 6f
    KW_IS KW_CASE
    je 6f
    KW_IS KW_DEFAULT
    je 6f
    TT_IS J_EOF
    je 90f
    mov edi, 1
    call jps_statement
    mov rdi, rax
    call ss_push
    jmp 5b
6:  mov rdi, r14
    call ss_to_vec
    mov [r13 + N_F1], rax
    FINISH r13
    mov rdi, r13
    call ss_push
    jmp 1b
8:  NEXT
    call js_label_pop
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F1], rax
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: in switch"
91: REFUSE "syntax error: multiple defaults in switch"
ENDF jps_switch

# jps_try() -> rax
FUNC jps_try
    push rbx
    push r12
    NODE T_TryStatement, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call jps_block
    mov [rbx + N_F0], rax
    KW_IS KW_CATCH
    jne 2f
    NODE T_CatchClause, [rip + g_jt_start]
    mov r12, rax
    NEXT
    TT_IS J_LPAREN
    jne 1f
    NEXT
    call jpp_binding_atom
    mov [r12 + N_F0], rax
    IF_NOT_TS 11f
    call jts_try_type_annotation
    test rax, rax
    jz 11f
    mov rdi, [r12 + N_F0]
    mov [rdi + N_F5], rax
    mov rsi, [rip + g_jt_last_end]
    call js_extend_end
11: EXPECT J_RPAREN
1:  call jps_block
    mov [r12 + N_F1], rax
    FINISH r12
    mov [rbx + N_F1], r12
2:  KW_IS KW_FINALLY
    jne 3f
    NEXT
    call jps_block
    mov [rbx + N_F2], rax
3:  mov rax, [rbx + N_F1]
    or rax, [rbx + N_F2]
    jz 90f
    FINISH rbx
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: try without catch or finally"
ENDF jps_try
