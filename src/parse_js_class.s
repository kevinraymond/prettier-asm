# JS functions, arrow functions, methods and classes.
.include "defs.inc"
.include "parse_js.inc"

.equ PN_PTR, 0              # private name entry: name pointer
.equ PN_LEN, 8
.equ PN_KIND, 12            # Babel's class element type: 1 set, 2 get, 4 static
.equ PN_LONE, 16            # 1 while an accessor has no partner
.equ PN_SIZE, 24
.equ PN_MAX, 4096


    .bss
    .balign 8
    .globl g_priv_count
g_priv_count: .quad 0
g_priv:       .space PN_SIZE * PN_MAX

    .section .rodata
s_constructor: .ascii "constructor"
s_prototype:   .ascii "prototype"
    .text

# jpf_function(node, flags) -> rax: FunctionDeclaration or FunctionExpression. The node holds its
# start and NA_ASYNC; `function` has been consumed. flags: 1 declaration, 2 the id may be left
# out (export default).
FUNC jpf_function
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    TT_IS J_STAR
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_GENERATOR
1:  test r12d, 1
    jz 3f
    # declaration: the id is read in the enclosing context
    test r12d, 2
    jz 2f
    TT_IS J_NAME
    jne 3f
    mov rax, [rip + g_jt_kw]
    test rax, rax
    jz 2f
    cmp rax, KW_LAST_RESERVED
    jbe 3f
2:  mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
3:  mov r13, [rip + g_px]
    mov r14, [rip + g_param_errors]
    push qword ptr [rip + g_ts]
    sub rsp, 8
    and qword ptr [rip + g_ts], ~TS_ARROW_PARAMS
    mov rdi, rbx
    call jpf_enter_function
    test r12d, 1
    jnz 4f
    call ts_tok_is_ident
    test eax, eax
    jz 4f
    mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
4:  IF_NOT_TS 41f
    mov edi, 1                          # TP_CONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
41: mov rdi, rbx
    call jpf_params
    mov rdi, rbx
    call jpf_body_ts
    cmp word ptr [rbx + N_TYPE], T_TSDeclareFunction
    jne 42f
    test dword ptr [rbx + N_ATTR], NA_GENERATOR
    jnz 90f
    test dword ptr [rbx + N_ATTR], NA_DECLARE
    jz 42f
    test dword ptr [rbx + N_ATTR], NA_ASYNC
    jnz 90f
42: mov [rip + g_px], r13
    mov [rip + g_param_errors], r14
    add rsp, 8
    pop rax
    and eax, TS_ARROW_PARAMS
    or [rip + g_ts], rax
    FINISH rbx
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "rejected by Prettier's typescript parser: a generator or async function signature"
ENDF jpf_function

# jpf_body_ts(node): TypeScript's parseFunctionBodyAndFinish: a return type, then the body, or
# none for a declaration or class method that ends there (TSDeclareFunction, TSDeclareMethod)
FUNC jpf_body_ts
    push rbx
    sub rsp, 8
    mov rbx, rdi
    IF_NOT_TS 8f
    TT_IS J_COLON
    jne 1f
    mov edi, J_COLON
    call jts_type_or_predicate_annotation
    mov [rbx + N_F5], rax
1:  movzx eax, word ptr [rbx + N_TYPE]
    mov ecx, T_TSDeclareFunction
    cmp eax, T_FunctionDeclaration
    je 2f
    mov ecx, T_TSDeclareMethod
    cmp eax, T_ClassMethod
    je 2f
    cmp eax, T_ClassPrivateMethod
    jne 8f
2:  TT_IS J_LBRACE
    je 3f
    push rcx
    sub rsp, 8
    call js_is_line_terminator
    add rsp, 8
    pop rcx
    test eax, eax
    jz 3f
    mov [rbx + N_TYPE], cx
    jmp 9f
3:  cmp ecx, T_TSDeclareFunction
    jne 4f
    test qword ptr [rip + g_ts], TS_AMBIENT
    jnz 90f
4:  test dword ptr [rbx + N_ATTR], NA_ABSTRACT
    jnz 91f
8:  mov rdi, rbx
    call jpf_body
9:  add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: function implementation in an ambient context"
91: REFUSE "syntax error: abstract method with an implementation"
ENDF jpf_body_ts

# jpf_enter_function(node): context for a non-arrow function from its async and generator bits
FUNC jpf_enter_function
    mov eax, CX_FUNC
    test dword ptr [rdi + N_ATTR], NA_ASYNC
    jz 1f
    or eax, CX_AWAIT
1:  test dword ptr [rdi + N_ATTR], NA_GENERATOR
    jz 2f
    or eax, CX_YIELD
2:  mov [rip + g_px], rax
    leave
    ret
ENDF jpf_enter_function

# jpf_params(node): `( params )` into F1. Yield and await expressions are refused in the
# parameters of generators and async functions.
FUNC jpf_params
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r14, [rip + g_px]
    test r14, CX_AWAIT | CX_YIELD
    jz 1f
    or qword ptr [rip + g_px], CX_GEN_PARAMS
1:  EXPECT J_LPAREN
    IF_NOT_TS 11f
    mov edi, 2
    cmp word ptr [rbx + N_TYPE], T_ClassMethod
    jne 12f
    cmp qword ptr [rbx + N_F3], KD_CONSTRUCTOR
    jne 12f
    mov edi, 6
12: call jts_binding_list
    mov [rbx + N_F1], rax
    mov [rip + g_px], r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
11: call ss_mark
    mov r12, rax
    xor r13d, r13d
2:  TT_IS J_RPAREN
    je 8f
    test r13d, r13d
    jz 3f
    EXPECT J_COMMA
    TT_IS J_RPAREN
    je 8f
3:  inc r13d
    TT_IS J_ELLIPSIS
    jne 4f
    call jpp_rest_element
    mov rdi, rax
    call ss_push
    mov edi, ')'
    call jpp_comma_after_rest
    jmp 8f
4:  xor eax, eax                        # decorators (UnsupportedParameterDecorator, allowed)
    TT_IS J_AT
    jne 41f
    call jpd_decorators
41: push rax
    sub rsp, 8
    call jpp_binding_element
    add rsp, 8
    pop rcx
    test rcx, rcx
    jz 42f
    mov [rax + N_F6], rcx
42: mov rdi, rax
    call ss_push
    jmp 2b
8:  NEXT
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F1], rax
    mov [rip + g_px], r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: parameter after a rest parameter"
ENDF jpf_params

# js_params_simple(vec) -> eax = 1 if every parameter is an Identifier
FUNC js_params_simple
    xor ecx, ecx
1:  cmp rcx, [rdi]
    jae 8f
    mov rax, [rdi + 8 + rcx*8]
    cmp word ptr [rax + N_TYPE], T_TSParameterProperty
    jne 2f
    mov rax, [rax + N_F0]
2:  cmp word ptr [rax + N_TYPE], T_Identifier
    jne 9f
    inc rcx
    jmp 1b
8:  mov eax, 1
    leave
    ret
9:  xor eax, eax
    leave
    ret
ENDF js_params_simple

# jpf_body(node): the block body of a function into F2, with directives. Labels of enclosing
# functions are not visible.
FUNC jpf_body
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rip + g_label_base]
    mov rax, [rip + g_label_count]
    mov [rip + g_label_base], rax
    mov r14, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    TT_IS J_LBRACE
    jne 90f
    NODE T_BlockStatement, [rip + g_jt_start]
    mov r13, rax
    NEXT
    mov edi, J_RBRACE
    mov esi, 1
    call jps_block_body
    mov [r13 + N_F0], rax
    mov [r13 + N_F1], rdx
    FINISH r13
    mov [rbx + N_F2], r13
    mov rdi, [r13 + N_F1]
    call jps_has_use_strict
    test eax, eax
    jz 1f
    mov rdi, [rbx + N_F1]
    call js_params_simple
    test eax, eax
    jz 91f
1:  mov [rip + g_label_base], r12
    mov [rip + g_px], r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: { expected"
91: REFUSE "syntax error: use strict with non-simple parameters"
ENDF jpf_body

# jpf_arrow(start, params VEC, async) -> rax: ArrowFunctionExpression; `=>` has been consumed
FUNC jpf_arrow
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13d, edx
    NODE T_ArrowFunctionExpression, rdi
    mov rbx, rax
    test r13d, r13d
    jz 1f
    or dword ptr [rbx + N_ATTR], NA_ASYNC
1:  mov [rbx + N_F1], r12
    mov rdi, r12
    xor esi, esi
    call jpp_to_assignable_list
    xor r14d, r14d
2:  cmp r14, [r12]
    jae 3f
    mov rdi, [r12 + 8 + r14*8]
    mov esi, 1
    call jpp_check_lval
    inc r14
    jmp 2b
3:  push qword ptr [rip + g_param_errors]
    push qword ptr [rip + g_ts]
    and qword ptr [rip + g_ts], ~TS_ARROW_PARAMS
    mov r14, [rip + g_px]
    mov rax, r14
    and eax, CX_CLASS_INIT | CX_NO_IN | CX_STATIC_BLOCK
    or eax, CX_FUNC
    test r13d, r13d
    jz 4f
    or eax, CX_AWAIT
4:  mov [rip + g_px], rax
    TT_IS J_LBRACE
    jne 5f
    mov rdi, rbx
    call jpf_body
    jmp 6f
5:  xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F2], rax
6:  mov [rip + g_px], r14
    pop rax
    and eax, TS_ARROW_PARAMS
    or [rip + g_ts], rax
    pop qword ptr [rip + g_param_errors]
    FINISH rbx
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpf_arrow

# jpf_method(node, generator, async) -> rax: parameters and body of an object or class method
FUNC jpf_method
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    test esi, esi
    jz 1f
    or dword ptr [rbx + N_ATTR], NA_GENERATOR
1:  test edx, edx
    jz 2f
    or dword ptr [rbx + N_ATTR], NA_ASYNC
2:  mov r13, [rip + g_px]
    mov r14, [rip + g_param_errors]
    mov rdi, rbx
    call jpf_enter_function
    mov rdi, rbx
    call jpf_params
    mov rdi, rbx
    call jpf_body_ts
    mov [rip + g_px], r13
    mov [rip + g_param_errors], r14
    FINISH rbx
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jpf_method

# jpf_check_accessor_params(method): a getter takes no parameter, a setter one that is not a rest
FUNC jpf_check_accessor_params
    mov rax, [rdi + N_F1]
    mov rcx, [rax]
    IF_NOT_TS 2f
    test rcx, rcx
    jz 2f
    push rdi
    push rax
    push rcx
    sub rsp, 8
    mov rdi, [rax + 8]
    call ts_is_this_param
    mov edx, eax
    add rsp, 8
    pop rcx
    pop rax
    pop rdi
    test edx, edx
    jz 2f
    dec rcx
    add rax, 8                          # the parameters after `this`
2:  cmp qword ptr [rdi + N_F3], KD_GET
    jne 1f
    test rcx, rcx
    jnz 90f
    leave
    ret
1:  cmp rcx, 1
    jne 90f
    mov rax, [rax + 8]
    cmp word ptr [rax + N_TYPE], T_RestElement
    je 90f
    leave
    ret
90: REFUSE "syntax error: getter or setter arity"
ENDF jpf_check_accessor_params

# ---------------------------------------------------------------- classes
# jpf_class(node, is_statement, optional_id) -> rax: `class` is the current token
FUNC jpf_class
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    NEXT
    IF_NOT_TS 11f
    KW_IS KW_IMPLEMENTS                 # TypeScript's parseClassId: `class implements X`
    jne 11f
    test r12d, r12d
    jz 3f
    test r13d, r13d
    jnz 3f
11: TT_IS J_NAME
    jne 2f
    mov rax, [rip + g_jt_kw]
    test rax, rax
    jz 1f
    cmp rax, KW_LAST_RESERVED
    jbe 2f
1:  mov qword ptr [rip + g_bind_lexical], 1
    mov edi, 1
    call js_ident
    mov qword ptr [rip + g_bind_lexical], 0
    mov [rbx + N_F0], rax
    jmp 21f
2:  test r12d, r12d
    jz 21f
    test r13d, r13d
    jz 90f
21: IF_NOT_TS 3f
    mov edi, 3                          # TP_INOUTCONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
3:  KW_IS KW_EXTENDS
    jne 4f
    NEXT
    mov r14, [rip + g_px]
    and qword ptr [rip + g_px], ~CX_NO_IN
    xor edi, edi
    call jpe_expr_subscripts
    mov [rbx + N_F1], rax
    mov [rip + g_px], r14
    IF_NOT_TS 4f
    TT_IS J_LT
    je 31f
    TT_IS J_SHL
    jne 4f
    REFUSE "rejected by Prettier's typescript parser: `<<` opening the superclass's type arguments"
31: call jts_type_arguments_in_expression
    mov [rbx + N_F3], rax
4:  IF_NOT_TS 41f
    KW_IS KW_IMPLEMENTS
    jne 41f
    NEXT
    call jts_heritage_clause
    mov [rbx + N_F5], rax
41: xor edi, edi
    cmp qword ptr [rbx + N_F1], 0
    setne dil
    call jpf_class_body
    mov [rbx + N_F2], rax
    FINISH rbx
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: class name expected"
ENDF jpf_class

# jpf_class_body(has_super) -> rax: ClassBody at `{`
FUNC jpf_class_body
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r14d, edi
    shl r14d, 1                         # bit 0 had a constructor, bit 1 has a superclass
    TT_IS J_LBRACE
    jne 90f
    NODE T_ClassBody, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    mov r13, [rip + g_priv_count]
    mov [rsp], r13                      # private names of this class start here
    call ss_mark
    mov r12, rax
    xor r15d, r15d                      # decorators read for the next member
1:  TT_IS J_RBRACE
    je 8f
    TT_IS J_SEMI
    jne 2f
    test r15, r15
    jnz 91f
    NEXT
    jmp 1b
2:  TT_IS J_AT
    jne 3f
    call jpd_decorators
    mov r15, rax
    jmp 1b
3:  TT_IS J_EOF
    je 92f
    mov rdi, [rsp]
    mov esi, r14d
    mov rdx, r15
    call jpf_class_member
    mov r14d, edx
    xor r15d, r15d
    mov rdi, rax
    call ss_push
    jmp 1b
8:  test r15, r15
    jnz 91f
    NEXT
    mov rax, [rsp]
    mov [rip + g_priv_count], rax
    mov rdi, r12
    call ss_to_vec
    mov [rbx + N_F0], rax
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
90: REFUSE "syntax error: { expected"
91: REFUSE "syntax error: decorators before `;` or `}`"
92: REFUSE "syntax error: unterminated class body"
ENDF jpf_class_body

# js_name_is_constructor(key) -> eax: Identifier `constructor` or StringLiteral "constructor"
FUNC js_name_is_constructor
    push rbx
    sub rsp, 8
    mov rbx, rdi
    cmp word ptr [rbx + N_TYPE], T_Identifier
    jne 1f
    lea rsi, [rip + s_constructor]
    mov edx, 11
    call js_node_text_is
    jmp 9f
1:  xor eax, eax
    cmp word ptr [rbx + N_TYPE], T_StringLiteral
    jne 9f
    cmp qword ptr [rbx + N_F1], 11
    jne 9f
    mov rdi, [rbx + N_F0]
    lea rsi, [rip + s_constructor]
    mov edx, 11
    call mem_eq
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF js_name_is_constructor

# jpf_element_name(member): the key of a class member (private names allowed)
FUNC jpf_element_name
    push rbx
    push r12
    mov rbx, rdi
    test dword ptr [rbx + N_ATTR], NA_STATIC
    jz 2f
    # static prototype
    TT_IS J_NAME
    je 1f
    TT_IS J_STRING
    jne 2f
    cmp qword ptr [rip + g_jt_len], 9
    jne 2f
    mov rdi, [rip + g_jt_val]
    lea rsi, [rip + s_prototype]
    mov edx, 9
    call mem_eq
    test eax, eax
    jnz 90f
    jmp 2f
1:  KW_IS KW_PROTOTYPE
    je 90f
2:  TT_IS J_PRIVATE
    jne 3f
    mov rax, [rip + g_jt_end]
    sub rax, [rip + g_jt_start]
    cmp rax, 12
    jne 21f
    mov rdi, [rip + g_text]
    add rdi, [rip + g_jt_start]
    inc rdi
    lea rsi, [rip + s_constructor]
    mov edx, 11
    call mem_eq
    test eax, eax
    jnz 91f
21: call jpe_private_name
    mov [rbx + N_F0], rax
    jmp 9f
3:  mov rdi, rbx
    call jpe_property_name
9:  pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: static prototype"
91: REFUSE "syntax error: #constructor"
ENDF jpf_element_name

# jpf_declare_private(name PrivateName, element_type): Babel's declarePrivateName; base in rdx
FUNC jpf_declare_private
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12d, esi                       # element type
    mov r15, rdx                        # first entry of this class
    mov rax, [rdi + N_F0]               # the Identifier
    mov r13d, [rax + N_START]
    add r13, [rip + g_text]             # name pointer
    mov r14d, [rax + N_END]
    sub r14d, [rax + N_START]           # length
    mov rbx, r15
1:  cmp rbx, [rip + g_priv_count]
    jae 5f
    imul rcx, rbx, PN_SIZE
    lea rdi, [rip + g_priv]
    add rdi, rcx
    cmp [rdi + PN_LEN], r14d
    jne 2f
    push rdi
    sub rsp, 8
    mov rdi, [rdi + PN_PTR]
    mov rsi, r13
    mov edx, r14d
    call mem_eq
    add rsp, 8
    pop rdi
    test eax, eax
    jnz 3f
2:  inc rbx
    jmp 1b
    # same name: only a getter and setter pair of the same staticness is allowed
3:  test r12d, 3
    jz 90f
    cmp dword ptr [rdi + PN_LONE], 0
    je 90f
    mov eax, [rdi + PN_KIND]
    mov ecx, eax
    xor ecx, r12d
    test ecx, 4
    jnz 90f
    and eax, 3
    mov ecx, r12d
    and ecx, 3
    cmp eax, ecx
    je 90f
    mov dword ptr [rdi + PN_LONE], 0
    jmp 9f
5:  mov rbx, [rip + g_priv_count]
    cmp rbx, PN_MAX
    jae 91f
    imul rcx, rbx, PN_SIZE
    lea rdi, [rip + g_priv]
    add rdi, rcx
    mov [rdi + PN_PTR], r13
    mov [rdi + PN_LEN], r14d
    mov [rdi + PN_KIND], r12d
    xor eax, eax
    test r12d, 3
    setnz al
    mov [rdi + PN_LONE], eax
    inc qword ptr [rip + g_priv_count]
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "syntax error: duplicate private name"
91: REFUSE "too many private names"
ENDF jpf_declare_private

# jpf_class_member(private_base, flags, decorators VEC or 0) -> rax = member, edx = flags. flags:
# 1 the class had a constructor, 2 the class has a superclass. In TypeScript the member's
# modifiers come first (Babel's parseClassMember override), and `declare` makes the member an
# ambient context.
FUNC jpf_class_member
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov [rsp], rdi                      # private base
    mov [rsp + 8], rsi                  # flags
    mov [rsp + 16], rdx                 # decorators
    mov qword ptr [rsp + 32], 0         # TypeScript modifiers
    TS_SAVE [rsp + 24]
    NODE T_ClassMethod, [rip + g_jt_start]
    mov rbx, rax
    mov rdx, [rsp + 16]
    test rdx, rdx
    jz 101f
    mov [rbx + N_F6], rdx
    mov rax, [rdx + 8]
    mov eax, [rax + N_START]
    mov [rbx + N_START], eax
101: IF_TS 100f
    KW_IS KW_STATIC
    jne 10f
    # `static` as a name, a static block, or the static modifier
    call js_ident_name
    mov r12, rax
    TT_IS J_LPAREN
    jne 1f
    mov [rbx + N_F0], r12
    mov qword ptr [rbx + N_F3], KD_METHOD
    xor esi, esi
    xor edx, edx
    jmp 60f
1:  TT_IS J_EQ
    je 2f
    TT_IS J_SEMI
    je 2f
    TT_IS J_RBRACE
    jne 3f
2:  mov [rbx + N_F0], r12
    xor r15d, r15d
    jmp 70f
3:  TT_IS J_LBRACE
    jne 4f
    cmp qword ptr [rsp + 16], 0
    jne 96f
    mov word ptr [rbx + N_TYPE], T_StaticBlock
    NEXT
    mov r12, [rip + g_label_base]
    mov rax, [rip + g_label_count]
    mov [rip + g_label_base], rax
    mov r13, [rip + g_px]
    mov qword ptr [rip + g_px], CX_CLASS_INIT | CX_STATIC_BLOCK | CX_NO_RETURN
    mov edi, J_RBRACE
    xor esi, esi
    call jps_block_body
    mov [rbx + N_F0], rax
    mov [rip + g_px], r13
    mov [rip + g_label_base], r12
    FINISH rbx
    jmp 99f
4:  or dword ptr [rbx + N_ATTR], NA_STATIC
    jmp 10f
    # TypeScript: modifiers, then a static block, an index signature or a member
100: mov rdi, rbx
    mov esi, M_DECLARE | M_ACCESS | M_OVERRIDE | M_ABSTRACT | M_READONLY | M_STATIC
    mov edx, M_IN | M_OUT
    mov ecx, 1
    call jts_modifiers
    mov [rsp + 32], rax
    KW_IS KW_STATIC
    jne 102f
    call ts_lookahead_char
    cmp eax, '{'
    jne 102f
    cmp qword ptr [rsp + 32], 0
    jne 97f
    NEXT
    jmp 3b
102: test qword ptr [rsp + 32], M_DECLARE
    jz 103f
    or qword ptr [rip + g_ts], TS_AMBIENT
103: mov rdi, rbx
    call jts_try_index_signature
    test rax, rax
    jz 104f
    test qword ptr [rsp + 32], M_ABSTRACT | M_ACCESS | M_DECLARE | M_OVERRIDE
    jnz 98f
    cmp qword ptr [rsp + 16], 0
    jne 98f
    jmp 99f
104: test qword ptr [rsp + 32], M_OVERRIDE
    jz 10f
    test qword ptr [rsp + 8], 2
    jz 98f
10: TT_IS J_STAR
    jne 20f
    # *name() {}
    NEXT
    mov qword ptr [rbx + N_F3], KD_METHOD
    mov rdi, rbx
    call jpf_element_name
    mov rdi, rbx
    call jpf_post_member_name
    mov esi, 1
    xor edx, edx
    jmp 50f
20: xor r15d, r15d                      # word of the key token, when an identifier
    TT_IS J_NAME
    jne 21f
    mov r15, [rip + g_jt_kw]
21: mov rdi, rbx
    call jpf_element_name
    mov rdi, rbx
    call jpf_post_member_name
    TT_IS J_LPAREN
    je 22f
    IF_NOT_TS 30f
    TT_IS J_LT
    jne 30f
22: mov qword ptr [rbx + N_F3], KD_METHOD
    xor esi, esi
    xor edx, edx
    jmp 50f
30: TT_IS J_EQ
    je 70f
    TT_IS J_SEMI
    je 70f
    TT_IS J_RBRACE
    je 70f
    IF_NOT_TS 301f
    TT_IS J_BANG
    je 70f
    TT_IS J_COLON
    je 70f
301: cmp r15, KW_ASYNC
    jne 31f
    call js_can_insert_semicolon
    test eax, eax
    jnz 70f
    test dword ptr [rbx + N_ATTR], NA_OPTIONAL
    jnz 93f
    xor r12d, r12d
    TT_IS J_STAR
    jne 302f
    NEXT
    mov r12d, 1
302: mov qword ptr [rbx + N_F3], KD_METHOD
    mov rdi, rbx
    call jpf_element_name
    mov rdi, rbx
    call jpf_post_member_name
    mov esi, r12d
    mov edx, 1
    jmp 50f
31: cmp r15, KW_GET
    je 32f
    cmp r15, KW_SET
    jne 33f
32: mov qword ptr [rbx + N_F3], KD_GET
    cmp r15, KW_GET
    je 321f
    mov qword ptr [rbx + N_F3], KD_SET
321: mov rdi, rbx
    call jpf_element_name
    xor esi, esi
    xor edx, edx
    jmp 50f
33: cmp r15, KW_ACCESSOR
    jne 34f
    call js_can_insert_semicolon
    test eax, eax
    jnz 34f
    mov rdi, rbx
    call jpf_element_name
    jmp 80f
34: call js_can_insert_semicolon
    test eax, eax
    jnz 70f
    jmp 93f

    # method: esi generator, edx async
50: mov r12d, esi
    mov r13d, edx
    IF_NOT_TS 501f
    mov edi, 1                          # TP_CONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
    test dword ptr [rbx + N_ATTR], NA_DECLARE
    jz 501f
    cmp qword ptr [rbx + N_F3], KD_GET
    je 98f
    cmp qword ptr [rbx + N_F3], KD_SET
    je 98f
501: mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_PrivateName
    jne 55f
    mov word ptr [rbx + N_TYPE], T_ClassPrivateMethod
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call jpf_method
    cmp word ptr [rbx + N_TYPE], T_TSDeclareMethod
    je 58f
    # declare: get 2, set 1, static adds 4
    xor esi, esi
    cmp qword ptr [rbx + N_F3], KD_GET
    jne 51f
    mov esi, 2
51: cmp qword ptr [rbx + N_F3], KD_SET
    jne 52f
    mov esi, 1
52: test esi, esi
    jz 53f
    test dword ptr [rbx + N_ATTR], NA_STATIC
    jz 53f
    or esi, 4
53: mov rdi, [rbx + N_F0]
    mov rdx, [rsp]
    call jpf_declare_private
    jmp 58f
    # public method: constructor checks
55: test dword ptr [rbx + N_ATTR], NA_STATIC | NA_COMPUTED
    jnz 57f
    mov rdi, [rbx + N_F0]
    call js_name_is_constructor
    test eax, eax
    jz 57f
    cmp qword ptr [rbx + N_F3], KD_METHOD
    jne 94f
    test r12d, r12d
    jnz 94f
    test r13d, r13d
    jnz 94f
    IF_TS 56f
    test qword ptr [rsp + 8], 1
    jnz 95f
56: test dword ptr [rbx + N_ATTR], NA_OVERRIDE
    jnz 98f
    or qword ptr [rsp + 8], 1
    mov qword ptr [rbx + N_F3], KD_CONSTRUCTOR
57: mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    call jpf_method
58: cmp word ptr [rbx + N_TYPE], T_TSDeclareMethod
    jne 582f
    mov rdi, rbx
    call jpf_check_overload
582: cmp qword ptr [rbx + N_F3], KD_GET
    je 59f
    cmp qword ptr [rbx + N_F3], KD_SET
    jne 99f
59: mov rdi, rbx
    call jpf_check_accessor_params
    jmp 99f
60: mov rdi, rbx                        # method named static
    call jpf_method
    jmp 99f

    # property
70: mov rax, [rbx + N_F0]
    mov word ptr [rbx + N_TYPE], T_ClassProperty
    cmp word ptr [rax + N_TYPE], T_PrivateName
    jne 71f
    mov word ptr [rbx + N_TYPE], T_ClassPrivateProperty
    IF_NOT_TS 701f
    test dword ptr [rbx + N_ATTR], NA_ABSTRACT
    jnz 98f
    cmp qword ptr [rbx + N_F7], 0
    jne 98f
701: mov rdi, rax
    xor esi, esi
    mov rdx, [rsp]
    call jpf_declare_private
71: IF_NOT_TS 73f
    mov rdi, rbx
    call jpf_property_annotation
    test dword ptr [rbx + N_ATTR], NA_ABSTRACT
    jz 73f
    TT_IS J_EQ
    je 98f
73: TT_IS J_EQ
    jne 72f
    NEXT
    mov r13, [rip + g_px]
    mov rax, r13
    and eax, CX_FUNC | CX_STATIC_BLOCK
    or eax, CX_CLASS_INIT
    mov [rip + g_px], rax
    xor edi, edi
    call jpe_maybe_assign
    mov [rbx + N_F1], rax
    mov [rip + g_px], r13
72: call js_semicolon
    FINISH rbx
    mov qword ptr [rbx + N_F3], 0
    jmp 99f

    # accessor property (decorator auto accessors)
80: mov word ptr [rbx + N_TYPE], T_ClassAccessorProperty
    mov rax, [rbx + N_F0]
    cmp word ptr [rax + N_TYPE], T_PrivateName
    jne 81f
    mov rdi, rax
    xor esi, esi
    mov rdx, [rsp]
    call jpf_declare_private
81: IF_NOT_TS 73b
    mov rdi, rbx
    call jpf_property_annotation
    test dword ptr [rbx + N_ATTR], NA_OPTIONAL
    jnz 98f
    jmp 73b

99: TS_RESTORE TS_AMBIENT, [rsp + 24]
    cmp qword ptr [rsp + 16], 0
    je 991f
    cmp qword ptr [rbx + N_F3], KD_CONSTRUCTOR
    je 96f
991: mov rax, rbx
    mov rdx, [rsp + 8]
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
93: REFUSE "syntax error: in class body"
94: REFUSE "syntax error: invalid constructor"
95: REFUSE "syntax error: duplicate constructor"
96: REFUSE "syntax error: decorators on a constructor or static block"
97: REFUSE "syntax error: modifiers on a static block"
98: REFUSE "syntax error: modifier not allowed on this class member"
ENDF jpf_class_member

# jpf_check_overload(method): what typescript-estree rejects in a method without a body and
# babel-ts accepts: decorators, and parameter properties in a constructor overload
FUNC jpf_check_overload
    cmp qword ptr [rdi + N_F6], 0
    jne 90f
    cmp qword ptr [rdi + N_F3], KD_CONSTRUCTOR
    jne 9f
    mov rax, [rdi + N_F1]
    xor ecx, ecx
1:  cmp rcx, [rax]
    jae 9f
    mov rdx, [rax + 8 + rcx*8]
    inc rcx
    cmp word ptr [rdx + N_TYPE], T_TSParameterProperty
    jne 1b
    REFUSE "rejected by Prettier's typescript parser: a parameter property in a constructor overload"
9:  leave
    ret
90: REFUSE "rejected by Prettier's typescript parser: a decorator on a method overload"
ENDF jpf_check_overload

# jpf_post_member_name(member): TypeScript's parsePostMemberNameModifiers: `?` after the name
FUNC jpf_post_member_name
    IF_NOT_TS 9f
    TT_IS J_QUESTION
    jne 1f
    NEXT
    or dword ptr [rdi + N_ATTR], NA_OPTIONAL
1:  TT_IS J_LPAREN
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_READONLY | NA_DECLARE
    jnz 90f
9:  leave
    ret
90: REFUSE "syntax error: readonly or declare on a method"
ENDF jpf_post_member_name

# jpf_property_annotation(prop): parseClassPropertyAnnotation: `!` or `?`, then a type
FUNC jpf_property_annotation
    push rbx
    sub rsp, 8
    mov rbx, rdi
    test dword ptr [rbx + N_ATTR], NA_OPTIONAL
    jnz 2f
    TT_IS J_BANG
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_DEFINITE
    jmp 2f
1:  TT_IS J_QUESTION
    jne 2f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_OPTIONAL
2:  call jts_try_type_annotation
    mov [rbx + N_F5], rax
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpf_property_annotation
