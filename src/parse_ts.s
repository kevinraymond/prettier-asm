# TypeScript types, after Babel's typescript plugin (packages/babel-parser/src/plugins/typescript):
# type annotations, type parameters and arguments, signatures, type members, modifiers and
# decorators. Function names follow Babel's: jts_union_type is tsParseUnionTypeOrHigher.
# Types are parsed with TS_IN_TYPE set (Babel's state.inType), so the lexer reads `<` and `>` as
# one-character tokens.
.include "defs.inc"
.include "parse_js.inc"


# Type parameter modifier sets for jts_type_parameters
.equ TP_CONST, 1            # tsParseConstModifier
.equ TP_INOUT, 2            # tsParseInOutModifiers
.equ TP_INOUTCONST, 3       # tsParseInOutConstModifiers

    .section .rodata
    .balign 8
# keyword id, modifier bit
ts_modifier_words:
    .quad KW_PUBLIC, M_PUBLIC, KW_PRIVATE, M_PRIVATE, KW_PROTECTED, M_PROTECTED
    .quad KW_DECLARE, M_DECLARE, KW_ABSTRACT, M_ABSTRACT, KW_OVERRIDE, M_OVERRIDE
    .quad KW_READONLY, M_READONLY, KW_STATIC, M_STATIC, KW_IN, M_IN, KW_OUT, M_OUT
    .quad KW_CONST, M_CONST, 0
# keyword id, node type (keywordTypeFromName, plus void and null)
ts_keyword_types:
    .quad KW_ANY, T_TSAnyKeyword, KW_BOOLEAN, T_TSBooleanKeyword, KW_BIGINT, T_TSBigIntKeyword
    .quad KW_NEVER, T_TSNeverKeyword, KW_NUMBER, T_TSNumberKeyword, KW_OBJECT, T_TSObjectKeyword
    .quad KW_STRING, T_TSStringKeyword, KW_SYMBOL, T_TSSymbolKeyword, KW_UNDEFINED, T_TSUndefinedKeyword
    .quad KW_UNKNOWN, T_TSUnknownKeyword, KW_VOID, T_TSVoidKeyword, KW_NULL, T_TSNullKeyword, 0
s_new: .ascii "new"
s_class: .ascii "class"
    .text

# ---------------------------------------------------------------- token helpers
# ts_tok_is_ident() -> eax: Babel's tokenIsIdentifier for the current token: a word that is not a
# reserved word (`enum` counts: Babel reads it as a contextual keyword).
FUNC ts_tok_is_ident
    xor eax, eax
    TT_IS J_NAME
    jne 9f
    mov rcx, [rip + g_jt_kw]
    test rcx, rcx
    jz 8f
    cmp rcx, KW_ENUM
    je 8f
    cmp rcx, KW_LAST_RESERVED
    jbe 9f
8:  mov eax, 1
9:  leave
    ret
ENDF ts_tok_is_ident

# ts_lookahead_char() -> eax: Babel's lookaheadCharCode (-1 at the end), ecx = 1 when a line break
# comes first (hasFollowingLineBreak)
FUNC ts_lookahead_char
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    leave
    ret
ENDF ts_lookahead_char

# ts_lookahead_word(ptr, len) -> eax: Babel's isLookaheadContextual: the next token is that word
FUNC ts_lookahead_word
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rip + g_jt_end]
    call jl_next_char
    mov rbx, rdx                        # next token start
    xor eax, eax
    lea rcx, [rbx + r13]
    cmp rcx, [rip + g_text_len]
    ja 9f
    mov rdi, [rip + g_text]
    add rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call mem_eq
    test eax, eax
    jz 9f
    lea rcx, [rbx + r13]                # no identifier character may follow
    xor eax, eax
    cmp rcx, [rip + g_text_len]
    jae 8f
    mov rdi, [rip + g_text]
    movzx edx, byte ptr [rdi + rcx]
    cmp edx, 0x80
    jae 9f
    cmp edx, '\\'
    je 9f
    lea rdi, [rip + js_char_class]
    movzx edx, byte ptr [rdi + rdx]
    cmp edx, 3
    je 9f
    cmp edx, 4
    je 9f
8:  mov eax, 1
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ts_lookahead_word

# ts_is_lookahead_new() -> eax / ts_is_lookahead_class() -> eax
FUNC ts_is_lookahead_new
    lea rdi, [rip + s_new]
    mov esi, 3
    call ts_lookahead_word
    leave
    ret
ENDF ts_is_lookahead_new

FUNC ts_is_lookahead_class
    lea rdi, [rip + s_class]
    mov esi, 5
    call ts_lookahead_word
    leave
    ret
ENDF ts_is_lookahead_class

# js_extend_end(node, end): resetEndLocation. An Identifier keeps its name length in F7.
FUNC js_extend_end
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 1f
    cmp qword ptr [rdi + N_F7], 0
    jne 1f
    mov eax, [rdi + N_END]
    sub eax, [rdi + N_START]
    mov [rdi + N_F7], rax
1:  mov [rdi + N_END], esi
    leave
    ret
ENDF js_extend_end

# ts_with(set, clear, fn, a, b) -> rax: fn(a, b) with the g_ts bits `set` set and `clear` cleared;
# those bits are put back afterwards (tsInType, tsInDisallowConditionalTypesContext, ...).
FUNC ts_with
    ENTER5 8
    mov rbx, [rip + g_ts]
    mov r12, rdi
    or r12, rsi                         # bits to put back
    or [rip + g_ts], rdi
    not rsi
    and [rip + g_ts], rsi
    mov rax, rdx
    mov rdi, rcx
    mov rsi, r8
    call rax
    mov rcx, [rip + g_ts]
    mov rdx, r12
    not rdx
    and rcx, rdx
    and rbx, r12
    or rcx, rbx
    mov [rip + g_ts], rcx
    LEAVE5 8
ENDF ts_with

# ---------------------------------------------------------------- annotations
# jts_type_annotation(start, eat_colon) -> rax: TSTypeAnnotation (tsParseTypeAnnotation). start -1
# is the current token's start.
FUNC jts_type_annotation
    ENTER5 8
    mov r13d, esi
    cmp rdi, -1
    jne 1f
    mov rdi, [rip + g_jt_start]
1:  NODE T_TSTypeAnnotation, rdi
    mov rbx, rax
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    test r13d, r13d
    jz 2f
    EXPECT J_COLON
2:  call jts_type
    mov [rbx + N_F5], rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_annotation

# jts_try_type_annotation() -> rax: a TSTypeAnnotation at `:`, or 0
FUNC jts_try_type_annotation
    xor eax, eax
    TT_IS J_COLON
    jne 9f
    mov rdi, -1
    mov esi, 1
    call jts_type_annotation
9:  leave
    ret
ENDF jts_try_type_annotation

# jts_type_in() -> rax: tsInType(tsParseType)
FUNC jts_type_in
    ENTER5 8
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    call jts_type
    mov rbx, rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_in

# jts_next_then_type() -> rax: tsNextThenParseType: the current token, then a type, in type mode
FUNC jts_next_then_type
    ENTER5 8
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    NEXT
    call jts_type
    mov rbx, rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    mov rax, rbx
    LEAVE5 8
ENDF jts_next_then_type

# jts_eat_then_type(token) -> rax: tsEatThenParseType: a type after the token, or 0 without it.
# token J_NAME | (KW << 8) stands for a word.
FUNC jts_eat_then_type
    xor eax, eax
    cmp rdi, 0xff
    ja 1f
    cmp [rip + g_jt_type], rdi
    jne 9f
    jmp 2f
1:  TT_IS J_NAME
    jne 9f
    shr rdi, 8
    cmp [rip + g_jt_kw], rdi
    jne 9f
2:  call jts_next_then_type
9:  leave
    ret
ENDF jts_eat_then_type

# jts_type_or_predicate_annotation(token) -> rax: TSTypeAnnotation after `:` or `=>`, where a type
# predicate (`x is T`, `asserts x`, `asserts x is T`, `this is T`) may stand
# (tsParseTypeOrTypePredicateAnnotation).
FUNC jts_type_or_predicate_annotation
    ENTER5 24
    mov r15, rdi
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    NODE T_TSTypeAnnotation, [rip + g_jt_start]
    mov rbx, rax                        # t
    mov rdi, r15
    call js_expect
    NODE T_TSTypePredicate, [rip + g_jt_start]
    mov r12, rax                        # node
    lea rdi, [rip + jts_predicate_asserts]
    call js_try_parse
    mov r13, rax                        # asserts
    test r13, r13
    jz 3f
    KW_IS KW_THIS
    jne 3f
    call jts_this_type_or_predicate
    cmp word ptr [rax + N_TYPE], T_TSThisType
    jne 2f
    mov [r12 + N_F0], rax
    or dword ptr [r12 + N_ATTR], NA_ASSERTS
    FINISH r12
    mov [rbx + N_F5], r12
    jmp 8f
2:  mov ecx, [r12 + N_START]            # resetStartLocationFromNode(thisTypePredicate, node)
    mov [rax + N_START], ecx
    or dword ptr [rax + N_ATTR], NA_ASSERTS
    mov [rbx + N_F5], rax
    jmp 8f
3:  xor r14d, r14d                      # typePredicateVariable
    call ts_tok_is_ident
    test eax, eax
    jz 4f
    lea rdi, [rip + jts_predicate_prefix]
    call js_try_parse
    mov r14, rax
4:  test r14, r14
    jnz 5f
    test r13, r13
    jnz 41f
    mov esi, [rbx + N_START]
    mov rdi, rsi
    xor esi, esi
    call jts_type_annotation            # tsParseTypeAnnotation(false, t)
    mov rbx, rax
    jmp 9f
41: xor edi, edi
    call js_ident
    mov [r12 + N_F0], rax
    or dword ptr [r12 + N_ATTR], NA_ASSERTS
    FINISH r12
    mov [rbx + N_F5], r12
    jmp 8f
5:  mov rdi, -1
    xor esi, esi
    call jts_type_annotation
    mov [r12 + N_F5], rax
    mov [r12 + N_F0], r14
    test r13, r13
    jz 51f
    or dword ptr [r12 + N_ATTR], NA_ASSERTS
51: FINISH r12
    mov [rbx + N_F5], r12
8:  FINISH rbx
9:  TS_RESTORE TS_IN_TYPE, [rsp]
    mov rax, rbx
    LEAVE5 24
ENDF jts_type_or_predicate_annotation

# jts_predicate_asserts() -> rax: tsParseTypePredicateAsserts: `asserts` followed by an
# identifier or `this` (consumed when 1)
FUNC jts_predicate_asserts
    xor eax, eax
    KW_IS KW_ASSERTS
    jne 9f
    NEXT
    KW_IS KW_THIS
    je 8f
    call ts_tok_is_ident
    test eax, eax
    jz 9f
8:  mov eax, 1
9:  leave
    ret
ENDF jts_predicate_asserts

# jts_predicate_prefix() -> rax: tsParseTypePredicatePrefix: `x is`, giving the Identifier x
FUNC jts_predicate_prefix
    push rbx
    sub rsp, 8
    xor edi, edi
    call js_ident
    mov rbx, rax
    xor eax, eax
    KW_IS KW_IS
    jne 9f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    NEXT
    mov rax, rbx
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_predicate_prefix

# ---------------------------------------------------------------- types
# jts_type() -> rax: tsParseType (in type mode)
FUNC jts_type
    ENTER5 8
    call js_enter_depth
    call jts_non_conditional_type
    mov rbx, rax
    test qword ptr [rip + g_ts], TS_NO_COND
    jnz 9f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    KW_IS KW_EXTENDS
    jne 9f
    NEXT
    mov esi, [rbx + N_START]
    NODE T_TSConditionalType, rsi
    mov r12, rax
    mov [r12 + N_F0], rbx
    mov edi, TS_NO_COND
    xor esi, esi
    lea rdx, [rip + jts_non_conditional_type]
    call ts_with
    mov [r12 + N_F1], rax
    EXPECT J_QUESTION
    xor edi, edi
    mov esi, TS_NO_COND
    lea rdx, [rip + jts_type]
    call ts_with
    mov [r12 + N_F2], rax
    EXPECT J_COLON
    xor edi, edi
    mov esi, TS_NO_COND
    lea rdx, [rip + jts_type]
    call ts_with
    mov [r12 + N_F3], rax
    FINISH r12
    mov rbx, r12
9:  dec qword ptr [rip + g_js_depth]
    mov rax, rbx
    LEAVE5 8
ENDF jts_type

# jts_non_conditional_type() -> rax: tsParseNonConditionalType
FUNC jts_non_conditional_type
    push rbx
    sub rsp, 8
    call jts_is_start_of_function_type
    test eax, eax
    jz 1f
    mov edi, T_TSFunctionType
    xor esi, esi
    call jts_function_type
    jmp 9f
1:  KW_IS KW_NEW
    jne 2f
    mov edi, T_TSConstructorType
    xor esi, esi
    call jts_function_type
    jmp 9f
2:  KW_IS KW_ABSTRACT
    jne 3f
    call ts_is_lookahead_new
    test eax, eax
    jz 3f
    mov edi, T_TSConstructorType
    mov esi, 1
    call jts_function_type
    jmp 9f
3:  mov edi, T_TSUnionType
    call jts_union_or_intersection
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_non_conditional_type

# jts_is_start_of_function_type() -> eax
FUNC jts_is_start_of_function_type
    mov eax, 1
    TT_IS J_LT
    je 9f
    xor eax, eax
    TT_IS J_LPAREN
    jne 9f
    lea rdi, [rip + jts_unambiguous_function_type]
    call js_lookahead
9:  leave
    ret
ENDF jts_is_start_of_function_type

# jts_unambiguous_function_type() -> eax: tsIsUnambiguouslyStartOfFunctionType (at `(`)
FUNC jts_unambiguous_function_type
    NEXT
    mov eax, 1
    TT_IS J_RPAREN
    je 9f
    TT_IS J_ELLIPSIS
    je 9f
    call jts_skip_parameter_start
    test eax, eax
    jz 8f
    mov eax, 1
    TT_IS J_COLON
    je 9f
    TT_IS J_COMMA
    je 9f
    TT_IS J_QUESTION
    je 9f
    TT_IS J_EQ
    je 9f
    TT_IS J_RPAREN
    jne 8f
    NEXT
    mov eax, 1
    TT_IS J_ARROW
    je 9f
8:  xor eax, eax
9:  leave
    ret
ENDF jts_unambiguous_function_type

# jts_skip_parameter_start() -> eax: tsSkipParameterStart
FUNC jts_skip_parameter_start
    call ts_tok_is_ident
    test eax, eax
    jnz 1f
    KW_IS KW_THIS
    jne 2f
1:  NEXT
    mov eax, 1
    jmp 9f
2:  TT_IS J_LBRACE
    je 3f
    TT_IS J_LBRACK
    jne 8f
3:  lea rdi, [rip + jpp_binding_atom]
    call js_try
    xor eax, eax
    cmp edx, TRY_OK
    sete al
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF jts_skip_parameter_start

# jts_function_type(type, abstract) -> rax: TSFunctionType or TSConstructorType
# (tsParseFunctionOrConstructorType)
FUNC jts_function_type
    ENTER5 8
    mov r12d, edi
    mov r13d, esi
    NODE r12d, [rip + g_jt_start]
    mov rbx, rax
    cmp r12d, T_TSConstructorType
    jne 2f
    test r13d, r13d
    jz 1f
    or dword ptr [rbx + N_ATTR], NA_ABSTRACT
    NEXT
1:  NEXT
2:  xor edi, edi
    mov esi, TS_NO_COND
    lea rdx, [rip + jts_fill_signature]
    mov ecx, J_ARROW
    mov r8, rbx
    call ts_with
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_function_type

# jts_fill_signature(return_token, node): tsFillSignature: type parameters, `( parameters )` in F1
# and the return type in F5 (required after `=>`, optional after `:`)
FUNC jts_fill_signature
    ENTER5 8
    mov r12, rdi
    mov rbx, rsi
    mov edi, TP_CONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
    EXPECT J_LPAREN
    mov edi, 2
    call jts_binding_list
    mov [rbx + N_F1], rax
    # parameters of a signature may not be defaults or parameter properties
    xor ecx, ecx
1:  cmp rcx, [rax]
    jae 2f
    mov rdx, [rax + 8 + rcx*8]
    cmp word ptr [rdx + N_TYPE], T_AssignmentPattern
    je 90f
    cmp word ptr [rdx + N_TYPE], T_TSParameterProperty
    je 90f
    inc rcx
    jmp 1b
2:  cmp r12, J_ARROW
    je 3f
    cmp [rip + g_jt_type], r12
    jne 9f
3:  mov rdi, r12
    call jts_type_or_predicate_annotation
    mov [rbx + N_F5], rax
9:  LEAVE5 8
90: REFUSE "syntax error: default or parameter property in a signature"
ENDF jts_fill_signature

# jts_union_or_intersection(type) -> rax: TSUnionType over intersections, or TSIntersectionType
# over type operators (tsParseUnionOrIntersectionType); a single type without a leading operator
# is returned as it is.
FUNC jts_union_or_intersection
    ENTER5 24
    mov r12d, edi
    mov r13d, J_PIPE
    cmp r12d, T_TSUnionType
    je 1f
    mov r13d, J_AMP
1:  NODE r12d, [rip + g_jt_start]
    mov rbx, rax
    xor r15d, r15d                      # leading operator
    cmp [rip + g_jt_type], r13
    jne 2f
    NEXT
    mov r15d, 1
2:  call ss_mark
    mov r14, rax
3:  cmp r12d, T_TSUnionType
    jne 4f
    mov edi, T_TSIntersectionType
    call jts_union_or_intersection
    jmp 5f
4:  call jts_type_operator
5:  mov rdi, rax
    call ss_push
    cmp [rip + g_jt_type], r13
    jne 6f
    NEXT
    jmp 3b
6:  mov rdi, r14
    call ss_to_vec
    cmp qword ptr [rax], 1
    jne 7f
    test r15d, r15d
    jnz 7f
    mov rax, [rax + 8]
    jmp 9f
7:  mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
9:  LEAVE5 24
ENDF jts_union_or_intersection

# jts_type_operator() -> rax: tsParseTypeOperatorOrHigher: keyof, unique, readonly, infer, or an
# array type
FUNC jts_type_operator
    ENTER5 8
    TT_IS J_NAME
    jne 5f
    mov rax, [rip + g_jt_kw]
    mov r12d, KD_KEYOF
    cmp rax, KW_KEYOF
    je 1f
    mov r12d, KD_UNIQUE
    cmp rax, KW_UNIQUE
    je 1f
    mov r12d, KD_READONLY
    cmp rax, KW_READONLY
    je 1f
    cmp rax, KW_INFER
    jne 5f
    call jts_infer_type
    jmp 9f
1:  NODE T_TSTypeOperator, [rip + g_jt_start]
    mov rbx, rax
    mov [rbx + N_F1], r12
    NEXT
    call jts_type_operator
    mov [rbx + N_F5], rax
    cmp r12d, KD_READONLY
    jne 2f
    cmp word ptr [rax + N_TYPE], T_TSTupleType
    je 2f
    cmp word ptr [rax + N_TYPE], T_TSArrayType
    jne 90f
2:  FINISH rbx
    mov rax, rbx
    jmp 9f
5:  xor edi, edi
    mov esi, TS_NO_COND
    lea rdx, [rip + jts_array_type]
    call ts_with
9:  LEAVE5 8
90: REFUSE "syntax error: readonly on a type that is not an array or tuple"
ENDF jts_type_operator

# jts_infer_type() -> rax: TSInferType at `infer`
FUNC jts_infer_type
    ENTER5 8
    NODE T_TSInferType, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    NODE T_TSTypeParameter, [rip + g_jt_start]
    mov r12, rax
    xor edi, edi
    call js_ident
    mov [r12 + N_F0], rax
    lea rdi, [rip + jts_infer_constraint]
    call js_try_parse
    mov [r12 + N_F1], rax
    FINISH r12
    mov [rbx + N_F0], r12
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_infer_type

# jts_infer_constraint() -> rax: tsParseConstraintForInferType, 0 when there is none
FUNC jts_infer_constraint
    ENTER5 8
    xor eax, eax
    KW_IS KW_EXTENDS
    jne 9f
    NEXT
    TS_SAVE [rsp]
    mov edi, TS_NO_COND
    xor esi, esi
    lea rdx, [rip + jts_type]
    call ts_with
    test qword ptr [rsp], TS_NO_COND
    jnz 9f
    TT_IS J_QUESTION
    jne 9f
    xor eax, eax
9:  LEAVE5 8
ENDF jts_infer_constraint

# jts_array_type() -> rax: tsParseArrayTypeOrHigher: T[] and T[K]
FUNC jts_array_type
    ENTER5 8
    mov r12, [rip + g_jt_start]
    call jts_non_array_type
    mov rbx, rax
1:  cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    TT_IS J_LBRACK
    jne 9f
    NEXT
    TT_IS J_RBRACK
    jne 2f
    NODE T_TSArrayType, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    NEXT
    FINISH rbx
    jmp 1b
2:  NODE T_TSIndexedAccessType, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    call jts_type
    mov [rbx + N_F1], rax
    EXPECT J_RBRACK
    FINISH rbx
    jmp 1b
9:  mov rax, rbx
    LEAVE5 8
ENDF jts_array_type

# jts_non_array_type() -> rax: tsParseNonArrayType
FUNC jts_non_array_type
    ENTER5 8
    mov rax, [rip + g_jt_type]
    cmp rax, J_STRING
    je 10f
    cmp rax, J_NUM
    je 10f
    cmp rax, J_BIGINT
    je 10f
    cmp rax, J_MINUS
    je 11f
    cmp rax, J_LBRACE
    je 20f
    cmp rax, J_LBRACK
    je 21f
    cmp rax, J_LPAREN
    je 22f
    cmp rax, J_TEMPLATE
    je 23f
    cmp rax, J_NAME
    jne 90f
    mov rax, [rip + g_jt_kw]
    cmp rax, KW_TRUE
    je 10f
    cmp rax, KW_FALSE
    je 10f
    cmp rax, KW_THIS
    je 12f
    cmp rax, KW_TYPEOF
    je 13f
    cmp rax, KW_IMPORT
    je 14f
    cmp rax, KW_VOID
    je 30f
    cmp rax, KW_NULL
    je 30f
    call ts_tok_is_ident
    test eax, eax
    jz 90f
    # keyword types, unless a `.` follows (then a qualified name)
30: mov rax, [rip + g_jt_kw]
    lea rcx, [rip + ts_keyword_types]
31: mov rdx, [rcx]
    test rdx, rdx
    jz 33f
    cmp rdx, rax
    je 32f
    add rcx, 16
    jmp 31b
32: mov rbx, [rcx + 8]
    call ts_lookahead_char
    cmp eax, '.'
    je 33f
    NODE ebx, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    FINISH rbx
    mov rax, rbx
    jmp 99f
33: call jts_type_reference
    jmp 99f
10: NODE T_TSLiteralType, [rip + g_jt_start]
    mov rbx, rax
    xor edi, edi
    call jpe_expr_atom
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    jmp 99f
11: call jl_peek
    cmp eax, J_NUM
    je 111f
    cmp eax, J_BIGINT
    jne 90f
111: NODE T_TSLiteralType, [rip + g_jt_start]
    mov rbx, rax
    xor edi, edi
    xor esi, esi
    call jpe_maybe_unary
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    jmp 99f
12: call jts_this_type_or_predicate
    jmp 99f
13: call jts_type_query
    jmp 99f
14: call jts_import_type
    jmp 99f
20: lea rdi, [rip + jts_is_start_of_mapped_type]
    call js_lookahead
    test eax, eax
    jz 201f
    call jts_mapped_type
    jmp 99f
201: NODE T_TSTypeLiteral, [rip + g_jt_start]
    mov rbx, rax
    call jts_object_type_members
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    jmp 99f
21: call jts_tuple_type
    jmp 99f
22: NODE T_TSParenthesizedType, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    call jts_type
    mov [rbx + N_F5], rax
    EXPECT J_RPAREN
    FINISH rbx
    mov rax, rbx
    jmp 99f
23: NODE T_TSLiteralType, [rip + g_jt_start]
    mov rbx, rax
    xor edi, edi
    call jpe_template
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
99: LEAVE5 8
90: REFUSE "syntax error: type expected"
ENDF jts_non_array_type

# jts_this_type_or_predicate() -> rax: TSThisType, or `this is T`
FUNC jts_this_type_or_predicate
    ENTER5 8
    NODE T_TSThisType, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    FINISH rbx
    KW_IS KW_IS
    jne 9f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    NEXT
    mov esi, [rbx + N_START]
    NODE T_TSTypePredicate, rsi
    mov r12, rax
    mov [r12 + N_F0], rbx
    mov rdi, -1
    xor esi, esi
    call jts_type_annotation
    mov [r12 + N_F5], rax
    FINISH r12
    mov rbx, r12
9:  mov rax, rbx
    LEAVE5 8
ENDF jts_this_type_or_predicate

# jts_entity_name(flags) -> rax: tsParseEntityName. flags: 1 allow reserved words (and `this`),
# 2 `this` as an Identifier.
FUNC jts_entity_name
    ENTER5 8
    mov r12d, edi
    test r12d, 1
    jz 2f
    KW_IS KW_THIS
    jne 1f
    test r12d, 2
    jnz 1f
    NODE T_ThisExpression, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    FINISH rbx
    jmp 3f
1:  call js_ident_name
    mov rbx, rax
    jmp 3f
2:  xor edi, edi
    call js_ident
    mov rbx, rax
3:  TT_IS J_DOT
    jne 9f
    NEXT
    mov esi, [rbx + N_START]
    NODE T_TSQualifiedName, rsi
    mov [rax + N_F0], rbx
    mov rbx, rax
    test r12d, 1
    jz 4f
    call js_ident_name
    jmp 5f
4:  xor edi, edi
    call js_ident
5:  mov [rbx + N_F1], rax
    FINISH rbx
    jmp 3b
9:  mov rax, rbx
    LEAVE5 8
ENDF jts_entity_name

# jts_type_reference() -> rax: TSTypeReference
FUNC jts_type_reference
    push rbx
    sub rsp, 8
    NODE T_TSTypeReference, [rip + g_jt_start]
    mov rbx, rax
    mov edi, 1
    call jts_entity_name
    mov [rbx + N_F0], rax
    cmp qword ptr [rip + g_jt_nl], 0
    jne 1f
    TT_IS J_LT
    jne 1f
    call jts_type_arguments
    mov [rbx + N_F4], rax
1:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_type_reference

# jts_type_query() -> rax: TSTypeQuery at `typeof`
FUNC jts_type_query
    push rbx
    sub rsp, 8
    NODE T_TSTypeQuery, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    KW_IS KW_IMPORT
    jne 1f
    call jts_import_type
    jmp 2f
1:  mov edi, 3
    call jts_entity_name
2:  mov [rbx + N_F0], rax
    cmp qword ptr [rip + g_jt_nl], 0
    jne 3f
    TT_IS J_LT
    jne 3f
    call jts_type_arguments
    mov [rbx + N_F4], rax
3:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_type_query

# jts_import_type() -> rax: TSImportType: import("x"), with options, a qualifier and arguments
FUNC jts_import_type
    ENTER5 8
    NODE T_TSImportType, [rip + g_jt_start]
    mov rbx, rax
    KW_IS KW_IMPORT
    jne 90f
    NEXT
    EXPECT J_LPAREN
    TT_IS J_STRING
    jne 90f
    call jpm_string
    mov [rbx + N_F0], rax
    TT_IS J_COMMA
    jne 1f
    NEXT
    call jts_import_type_options
    mov [rbx + N_F1], rax
1:  EXPECT J_RPAREN
    TT_IS J_DOT
    jne 2f
    NEXT
    mov edi, 3
    call jts_entity_name
    mov [rbx + N_F2], rax
2:  TT_IS J_LT
    jne 3f
    call jts_type_arguments
    mov [rbx + N_F4], rax
3:  FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: in an import type"
ENDF jts_import_type

# jts_import_type_options() -> rax: `{ with: { ... } }` as an ObjectExpression
FUNC jts_import_type_options
    ENTER5 8
    NODE T_ObjectExpression, [rip + g_jt_start]
    mov rbx, rax
    EXPECT J_LBRACE
    NODE T_ObjectProperty, [rip + g_jt_start]
    mov r12, rax
    KW_IS KW_WITH
    jne 90f
    call js_ident_name
    mov [r12 + N_F0], rax
    EXPECT J_COLON
    NODE T_ObjectExpression, [rip + g_jt_start]
    mov r13, rax
    EXPECT J_LBRACE
    call ss_mark
    mov r14, rax
1:  TT_IS J_RBRACE
    je 3f
    TT_IS J_STRING
    je 2f
    call ts_tok_is_ident
    test eax, eax
    jz 90f
2:  xor edi, edi
    call jpe_property
    mov rdi, rax
    call ss_push
    mov edi, J_COMMA
    call js_eat
    jmp 1b
3:  NEXT
    mov rdi, r14
    call ss_to_vec
    mov [r13 + N_F0], rax
    FINISH r13
    mov [r12 + N_F1], r13
    FINISH r12
    mov rdi, r12
    call js_vec1
    mov [rbx + N_F0], rax
    EXPECT J_RBRACE
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: in import type options"
ENDF jts_import_type_options

# jts_is_start_of_mapped_type() -> eax: tsIsStartOfMappedType (at `{`)
FUNC jts_is_start_of_mapped_type
    NEXT
    TT_IS J_PLUS
    je 1f
    TT_IS J_MINUS
    jne 2f
1:  NEXT
    xor eax, eax
    KW_IS KW_READONLY
    sete al
    jmp 9f
2:  KW_IS KW_READONLY
    jne 3f
    NEXT
3:  xor eax, eax
    TT_IS J_LBRACK
    jne 9f
    NEXT
    call ts_tok_is_ident
    test eax, eax
    jz 9f
    NEXT
    xor eax, eax
    KW_IS KW_IN
    sete al
9:  leave
    ret
ENDF jts_is_start_of_mapped_type

# jts_mapped_type() -> rax: TSMappedType, with key and constraint as Prettier's postprocess
# leaves them
FUNC jts_mapped_type
    ENTER5 8
    NODE T_TSMappedType, [rip + g_jt_start]
    mov rbx, rax
    EXPECT J_LBRACE
    mov rax, [rip + g_jt_type]
    cmp rax, J_PLUS
    je 1f
    cmp rax, J_MINUS
    jne 2f
1:  mov [rbx + N_F3], rax
    NEXT
    KW_IS KW_READONLY
    jne 90f
    NEXT
    jmp 3f
2:  KW_IS KW_READONLY
    jne 3f
    mov qword ptr [rbx + N_F3], 1
    NEXT
3:  EXPECT J_LBRACK
    xor edi, edi
    call js_ident
    mov [rbx + N_F0], rax
    KW_IS KW_IN
    jne 90f
    call jts_next_then_type
    mov [rbx + N_F1], rax
    KW_IS KW_AS
    jne 4f
    NEXT
    call jts_type
    mov [rbx + N_F2], rax
4:  EXPECT J_RBRACK
    mov rax, [rip + g_jt_type]
    cmp rax, J_PLUS
    je 5f
    cmp rax, J_MINUS
    jne 6f
5:  mov [rbx + N_F4], rax
    NEXT
    EXPECT J_QUESTION
    jmp 7f
6:  TT_IS J_QUESTION
    jne 7f
    mov qword ptr [rbx + N_F4], 1
    NEXT
7:  mov edi, J_COLON
    call jts_eat_then_type
    mov [rbx + N_F5], rax
    call js_semicolon
    EXPECT J_RBRACE
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: in a mapped type"
ENDF jts_mapped_type

# jts_tuple_type() -> rax: TSTupleType at `[`
FUNC jts_tuple_type
    push rbx
    sub rsp, 8
    NODE T_TSTupleType, [rip + g_jt_start]
    mov rbx, rax
    EXPECT J_LBRACK
    mov edi, J_RBRACK
    lea rsi, [rip + jts_tuple_element]
    call jts_delimited_list
    mov [rbx + N_F0], rax
    EXPECT J_RBRACK
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_tuple_type

# jts_tuple_element() -> rax: tsParseTupleElementType
FUNC jts_tuple_element
    ENTER5 24
    mov r12, [rip + g_jt_start]         # rest start
    xor r13d, r13d                      # rest
    TT_IS J_ELLIPSIS
    jne 1f
    mov r13d, 1
    NEXT
1:  mov r14, [rip + g_jt_start]         # start
    xor r15d, r15d                      # bit 0 labeled, bit 1 optional
    xor ebx, ebx                        # label
    mov qword ptr [rsp], 0              # type
    TT_IS J_NAME
    jne 5f
    call ts_lookahead_char
    cmp eax, ':'
    je 2f
    cmp eax, '?'
    je 3f
    jmp 5f
2:  call js_ident_name                  # label: type
    mov rbx, rax
    or r15d, 1
    EXPECT J_COLON
    call jts_type
    mov [rsp], rax
    jmp 7f
3:  or r15d, 2                          # word? or word?: type
    call jts_non_array_type
    mov [rsp], rax
    call ts_lookahead_char
    cmp eax, ':'
    jne 4f
    or r15d, 1
    NODE T_Identifier, r14
    mov rbx, rax
    FINISH rbx
    EXPECT J_QUESTION
    EXPECT J_COLON
    call jts_type
    mov [rsp], rax
    jmp 7f
4:  EXPECT J_QUESTION
    jmp 7f
5:  call jts_type
    mov [rsp], rax
    TT_IS J_QUESTION
    jne 51f
    NEXT
    or r15d, 2
51: TT_IS J_COLON
    jne 7f
    REFUSE "syntax error: tuple member label that is not an identifier"
7:  test r15d, 1
    jz 8f
    NODE T_TSNamedTupleMember, r14
    test r15d, 2
    jz 71f
    or dword ptr [rax + N_ATTR], NA_OPTIONAL
71: mov [rax + N_F0], rbx
    mov rcx, [rsp]
    mov [rax + N_F1], rcx
    mov [rsp], rax
    TT_IS J_QUESTION
    je 91f
    FINISH rax
    jmp 85f
8:  test r15d, 2
    jz 85f
    NODE T_TSOptionalType, r14
    mov rcx, [rsp]
    mov [rax + N_F5], rcx
    FINISH rax
    mov [rsp], rax
85: test r13d, r13d
    jz 9f
    NODE T_TSRestType, r12
    mov rcx, [rsp]
    mov [rax + N_F5], rcx
    FINISH rax
    mov [rsp], rax
9:  mov rax, [rsp]
    LEAVE5 24
91: REFUSE "syntax error: optional tuple member with `?` after the type"
ENDF jts_tuple_element

# jts_delimited_list(terminator, fn) -> rax = VEC: tsParseDelimitedList: elements from fn()
# separated by commas, up to the terminator token (not consumed)
FUNC jts_delimited_list
    ENTER5 8
    mov r12, rdi
    mov r13, rsi
    call ss_mark
    mov r14, rax
1:  cmp [rip + g_jt_type], r12
    je 8f
    call r13
    mov rdi, rax
    call ss_push
    TT_IS J_COMMA
    jne 2f
    NEXT
    jmp 1b
2:  cmp [rip + g_jt_type], r12
    je 8f
    EXPECT J_COMMA
8:  mov rdi, r14
    call ss_to_vec
    LEAVE5 8
ENDF jts_delimited_list

# ---------------------------------------------------------------- type parameters and arguments
# jts_try_type_parameters(set) -> rax: type parameters at `<`, or 0
FUNC jts_try_type_parameters
    xor eax, eax
    TT_IS J_LT
    jne 9f
    call jts_type_parameters
9:  leave
    ret
ENDF jts_try_type_parameters

# jts_type_parameters(set) -> rax: TSTypeParameterDeclaration at `<` (tsParseTypeParameters). set
# picks the modifiers: TP_CONST, TP_INOUT or TP_INOUTCONST.
FUNC jts_type_parameters
    ENTER5 8
    mov r12d, edi
    mov [rip + g_tp_set], r12
    NODE T_TSTypeParameterDeclaration, [rip + g_jt_start]
    mov rbx, rax
    TT_IS J_LT
    jne 90f
    NEXT
    mov edi, J_GT
    lea rsi, [rip + jts_type_parameter_item]
    call jts_delimited_list
    mov [rbx + N_F0], rax
    EXPECT J_GT
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: < expected"
ENDF jts_type_parameters

    .bss
    .balign 8
g_tp_set: .quad 0               # modifier set of the type parameter list being read
    .text

FUNC jts_type_parameter_item
    mov rdi, [rip + g_tp_set]
    call jts_type_parameter
    leave
    ret
ENDF jts_type_parameter_item

# jts_type_parameter(set) -> rax: TSTypeParameter (tsParseTypeParameter). Babel reads in, out
# and const (and, for TP_INOUT, the class member modifiers) and reports the ones the set lacks.
FUNC jts_type_parameter
    ENTER5 8
    mov r12, rdi
    NODE T_TSTypeParameter, [rip + g_jt_start]
    mov rbx, rax
    mov esi, M_CONST
    mov edx, M_IN | M_OUT
    cmp r12d, TP_CONST
    je 1f
    mov esi, M_IN | M_OUT
    mov edx, M_CONST | M_ACCESS | M_READONLY | M_DECLARE | M_ABSTRACT | M_OVERRIDE
    cmp r12d, TP_INOUT
    je 1f
    mov esi, M_IN | M_OUT | M_CONST
    mov edx, M_ACCESS | M_READONLY | M_DECLARE | M_ABSTRACT | M_OVERRIDE
1:  mov rdi, rbx
    xor ecx, ecx
    call jts_modifiers
    xor edi, edi
    call js_ident
    mov [rbx + N_F0], rax
    mov edi, J_NAME | (KW_EXTENDS << 8)
    call jts_eat_then_type
    mov [rbx + N_F1], rax
    mov edi, J_EQ
    call jts_eat_then_type
    mov [rbx + N_F2], rax
    mov [rip + g_tp_set], r12           # nested lists may have changed it
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_parameter

# jts_type_arguments() -> rax: TSTypeParameterInstantiation at `<` (tsParseTypeArguments)
FUNC jts_type_arguments
    ENTER5 8
    NODE T_TSTypeParameterInstantiation, [rip + g_jt_start]
    mov rbx, rax
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    EXPECT J_LT
    mov edi, J_GT
    lea rsi, [rip + jts_type]
    call jts_delimited_list
    mov [rbx + N_F0], rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    mov rax, [rbx + N_F0]
    cmp qword ptr [rax], 0
    je 1f
    test qword ptr [rip + g_ts], TS_IN_TYPE
    jnz 1f
    call jl_rescan_lt_gt
1:  EXPECT J_GT
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_arguments

# jts_type_arguments_in_expression() -> rax: tsParseTypeArgumentsInExpression: type arguments
# at `<` (or the first `<` of `<<`), or 0
FUNC jts_type_arguments_in_expression
    call jl_rescan_lt
    cmp eax, J_LT
    jne 8f
    call jts_type_arguments
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF jts_type_arguments_in_expression

# ---------------------------------------------------------------- modifiers
# jts_token_can_follow_modifier() -> eax: tsTokenCanFollowModifier
FUNC jts_token_can_follow_modifier
    mov eax, 1
    mov rcx, [rip + g_jt_type]
    cmp rcx, J_LBRACK
    je 9f
    cmp rcx, J_LBRACE
    je 9f
    cmp rcx, J_STAR
    je 9f
    cmp rcx, J_ELLIPSIS
    je 9f
    cmp rcx, J_PRIVATE
    je 9f
    cmp rcx, J_NAME
    je 9f
    cmp rcx, J_STRING
    je 9f
    cmp rcx, J_NUM
    je 9f
    cmp rcx, J_BIGINT
    je 9f
    xor eax, eax
9:  leave
    ret
ENDF jts_token_can_follow_modifier

# jts_next_can_follow_modifier() -> rax: tsNextTokenCanFollowModifier (advances)
FUNC jts_next_can_follow_modifier
    KW_IS KW_STATIC
    jne 1f
    NEXT
    call jts_token_can_follow_modifier
    jmp 9f
1:  NEXT
    xor eax, eax
    cmp qword ptr [rip + g_jt_nl], 0
    jne 9f
    call jts_token_can_follow_modifier
9:  leave
    ret
ENDF jts_next_can_follow_modifier

# jts_modifier(recognized, flags, seen) -> eax: tsParseModifier: the modifier bit of the current
# word when it is one of `recognized` and a modifier here (then it is consumed), else 0.
# flags 1: stop at a class static block.
FUNC jts_modifier
    ENTER5 8
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    xor ebx, ebx
    TT_IS J_NAME
    jne 9f
    mov rax, [rip + g_jt_kw]
    lea rcx, [rip + ts_modifier_words]
1:  mov rdx, [rcx]
    test rdx, rdx
    jz 9f
    cmp rdx, rax
    je 2f
    add rcx, 16
    jmp 1b
2:  mov rbx, [rcx + 8]
    test ebx, r12d
    jz 8f
    cmp rax, KW_STATIC
    jne 3f
    test r14d, M_STATIC
    jnz 8f
    test r13d, 1
    jz 3f
    call ts_lookahead_char
    cmp eax, '{'
    je 8f
3:  lea rdi, [rip + jts_next_can_follow_modifier]
    call js_try_parse
    test eax, eax
    jnz 9f
8:  xor ebx, ebx
9:  mov eax, ebx
    LEAVE5 8
ENDF jts_modifier

# jts_modifiers(node, recognized, disallowed, flags) -> eax = the modifiers read (tsParseModifiers).
# Sets the node's accessibility (F7) and its declare, abstract, override, readonly, static, in,
# out and const bits. Babel's errors for repeated, misordered, incompatible and disallowed
# modifiers are refused. flags 1: stop at a class static block.
FUNC jts_modifiers
    ENTER5 24
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov [rsp], rcx
    xor r14d, r14d                      # seen
1:  mov edi, r12d
    or edi, r13d
    mov rsi, [rsp]
    mov edx, r14d
    call jts_modifier
    test eax, eax
    jz 9f
    mov r15d, eax
    test r15d, M_ACCESS
    jz 3f
    test r14d, M_ACCESS
    jnz 90f
    test r14d, M_OVERRIDE | M_STATIC | M_READONLY
    jnz 91f
    mov eax, KD_PUBLIC
    cmp r15d, M_PUBLIC
    je 2f
    mov eax, KD_PRIVATE
    cmp r15d, M_PRIVATE
    je 2f
    mov eax, KD_PROTECTED
2:  mov [rbx + N_F7], rax
    jmp 7f
3:  test r15d, r14d
    jnz 92f
    cmp r15d, M_IN
    jne 4f
    test r14d, M_OUT
    jnz 91f
    jmp 7f
4:  cmp r15d, M_OUT
    je 7f
    cmp r15d, M_STATIC
    jne 41f
    test r14d, M_READONLY | M_OVERRIDE
    jnz 91f
    test r14d, M_ABSTRACT
    jnz 93f
41: cmp r15d, M_OVERRIDE
    jne 42f
    test r14d, M_READONLY
    jnz 91f
    test r14d, M_DECLARE
    jnz 93f
42: cmp r15d, M_ABSTRACT
    jne 43f
    test r14d, M_OVERRIDE
    jnz 91f
    test r14d, M_STATIC
    jnz 93f
43: cmp r15d, M_DECLARE
    jne 7f
    test r14d, M_OVERRIDE
    jnz 93f
7:  or r14d, r15d
    test r15d, r13d
    jnz 94f
    # the node's bits
    xor eax, eax
    cmp r15d, M_DECLARE
    jne 71f
    mov eax, NA_DECLARE
71: cmp r15d, M_ABSTRACT
    jne 72f
    mov eax, NA_ABSTRACT
72: cmp r15d, M_OVERRIDE
    jne 73f
    mov eax, NA_OVERRIDE
73: cmp r15d, M_READONLY
    jne 74f
    mov eax, NA_READONLY
74: cmp r15d, M_STATIC
    jne 75f
    mov eax, NA_STATIC
75: cmp r15d, M_IN
    jne 76f
    mov eax, NA_IN
76: cmp r15d, M_OUT
    jne 77f
    mov eax, NA_OUT
77: cmp r15d, M_CONST
    jne 78f
    mov eax, NA_CONST
78: or [rbx + N_ATTR], eax
    jmp 1b
9:  mov eax, r14d
    LEAVE5 24
90: REFUSE "syntax error: accessibility modifier already seen"
91: REFUSE "syntax error: modifiers out of order"
92: REFUSE "syntax error: duplicate modifier"
93: REFUSE "syntax error: incompatible modifiers"
94: REFUSE "syntax error: modifier not allowed here"
ENDF jts_modifiers

# ---------------------------------------------------------------- type members
# jts_object_type_members() -> rax = VEC: `{ members }` (tsParseObjectTypeMembers)
FUNC jts_object_type_members
    push rbx
    push r12
    EXPECT J_LBRACE
    call ss_mark
    mov rbx, rax
1:  TT_IS J_RBRACE
    je 2f
    call jts_type_member
    mov rdi, rax
    call ss_push
    jmp 1b
2:  mov rdi, rbx
    call ss_to_vec
    mov rbx, rax
    NEXT
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jts_object_type_members

# jts_member_semicolon(): tsParseTypeMemberSemicolon
FUNC jts_member_semicolon
    TT_IS J_COMMA
    jne 1f
    NEXT
    leave
    ret
1:  call js_is_line_terminator
    test eax, eax
    jnz 9f
    EXPECT J_SEMI
9:  leave
    ret
ENDF jts_member_semicolon

# jts_type_member() -> rax: tsParseTypeMember: call, construct, property, method and index
# signatures
FUNC jts_type_member
    ENTER5 8
    NODE T_TSPropertySignature, [rip + g_jt_start]
    mov rbx, rax
    TT_IS J_LPAREN
    je 1f
    TT_IS J_LT
    jne 2f
1:  mov word ptr [rbx + N_TYPE], T_TSCallSignatureDeclaration
    jmp 30f
2:  KW_IS KW_NEW
    jne 4f
    call js_ident_name
    mov r12, rax
    TT_IS J_LPAREN
    je 3f
    TT_IS J_LT
    jne 31f
3:  mov word ptr [rbx + N_TYPE], T_TSConstructSignatureDeclaration
30: mov edi, J_COLON
    mov rsi, rbx
    call jts_fill_signature
    call jts_member_semicolon
    FINISH rbx
    jmp 99f
31: mov [rbx + N_F0], r12
    mov rdi, rbx
    xor esi, esi
    call jts_property_or_method_signature
    jmp 99f
4:  mov rdi, rbx
    mov esi, M_READONLY
    mov edx, M_DECLARE | M_ABSTRACT | M_ACCESS | M_STATIC | M_OVERRIDE
    xor ecx, ecx
    call jts_modifiers
    mov rdi, rbx
    call jts_try_index_signature
    test rax, rax
    jnz 99f
    xor r12d, r12d                      # word of the key
    TT_IS J_NAME
    jne 5f
    mov r12, [rip + g_jt_kw]
5:  mov rdi, rbx
    call jpe_property_name
    test dword ptr [rbx + N_ATTR], NA_COMPUTED
    jnz 6f
    cmp r12, KW_GET
    je 51f
    cmp r12, KW_SET
    jne 6f
51: call jts_token_can_follow_modifier
    test eax, eax
    jz 6f
    mov rax, KD_GET
    cmp r12, KW_GET
    je 52f
    mov rax, KD_SET
52: mov [rbx + N_F3], rax
    mov rdi, rbx
    call jpe_property_name
    TT_IS J_LPAREN
    je 6f
    TT_IS J_LT
    jne 90f
6:  mov esi, [rbx + N_ATTR]
    and esi, NA_READONLY
    mov rdi, rbx
    call jts_property_or_method_signature
99: mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: ( expected"
ENDF jts_type_member

# jts_property_or_method_signature(node, readonly): tsParsePropertyOrMethodSignature
FUNC jts_property_or_method_signature
    ENTER5 8
    mov rbx, rdi
    mov r12d, esi
    TT_IS J_QUESTION
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_OPTIONAL
1:  TT_IS J_LPAREN
    je 2f
    TT_IS J_LT
    jne 5f
2:  test r12d, r12d
    jnz 90f
    mov word ptr [rbx + N_TYPE], T_TSMethodSignature
    cmp qword ptr [rbx + N_F3], 0
    je 3f
    TT_IS J_LT
    je 90f
3:  mov edi, J_COLON
    mov rsi, rbx
    call jts_fill_signature
    call jts_member_semicolon
    mov rax, [rbx + N_F1]
    mov rcx, [rax]
    cmp qword ptr [rbx + N_F3], KD_GET
    jne 31f
    test rcx, rcx
    jnz 90f
    jmp 4f
31: cmp qword ptr [rbx + N_F3], KD_SET
    jne 32f
    cmp rcx, 1
    jne 90f
    cmp qword ptr [rbx + N_F5], 0
    jne 90f
    mov rax, [rax + 8]
    cmp word ptr [rax + N_TYPE], T_RestElement
    je 90f
    cmp word ptr [rax + N_TYPE], T_Identifier
    jne 4f
    test dword ptr [rax + N_ATTR], NA_OPTIONAL
    jnz 90f
    mov rdi, rax
    call ts_is_this_param
    test eax, eax
    jnz 90f
    jmp 4f
32: mov qword ptr [rbx + N_F3], KD_METHOD
4:  FINISH rbx
    jmp 9f
5:  call jts_try_type_annotation
    mov [rbx + N_F5], rax
    call jts_member_semicolon
    FINISH rbx
9:  mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: invalid method signature"
ENDF jts_property_or_method_signature

# ts_is_this_param(node) -> eax: an Identifier named `this`
FUNC ts_is_this_param
    xor eax, eax
    cmp word ptr [rdi + N_TYPE], T_Identifier
    jne 9f
    mov rsi, [rip + g_text]
    mov ecx, [rdi + N_START]
    mov rdx, [rdi + N_F0]               # 1 + the name's offset, when the range starts earlier
    test rdx, rdx
    jz 2f
    lea ecx, [edx - 1]
2:  cmp dword ptr [rsi + rcx], 0x73696874   # "this"
    jne 9f
    mov rdx, [rdi + N_F7]
    test rdx, rdx
    jnz 1f
    mov edx, [rdi + N_END]
    sub edx, ecx
1:  cmp edx, 4
    jne 9f
    mov eax, 1
9:  leave
    ret
ENDF ts_is_this_param

# jts_index_signature_ahead() -> eax: tsIsUnambiguouslyIndexSignature (at `[`)
FUNC jts_index_signature_ahead
    NEXT
    call ts_tok_is_ident
    test eax, eax
    jz 9f
    NEXT
    xor eax, eax
    TT_IS J_COLON
    sete al
9:  leave
    ret
ENDF jts_index_signature_ahead

# jts_try_index_signature(node) -> rax: the node as a TSIndexSignature when `[name:` starts one
# (tsTryParseIndexSignature), else 0 with nothing read
FUNC jts_try_index_signature
    ENTER5 8
    mov rbx, rdi
    xor eax, eax
    TT_IS J_LBRACK
    jne 9f
    lea rdi, [rip + jts_index_signature_ahead]
    call js_lookahead
    test eax, eax
    jz 9f
    mov word ptr [rbx + N_TYPE], T_TSIndexSignature
    NEXT
    xor edi, edi
    call js_ident
    mov r12, rax
    mov rdi, -1
    mov esi, 1
    call jts_type_annotation
    mov [r12 + N_F5], rax
    mov rdi, r12
    mov rsi, [rip + g_jt_last_end]
    call js_extend_end
    EXPECT J_RBRACK
    mov rdi, r12
    call js_vec1
    mov [rbx + N_F1], rax
    call jts_try_type_annotation
    mov [rbx + N_F5], rax
    call jts_member_semicolon
    FINISH rbx
    mov rax, rbx
9:  LEAVE5 8
ENDF jts_try_index_signature

# ---------------------------------------------------------------- binding lists
# jts_binding_list(flags) -> rax = VEC: parseBindingList(`)`) with TypeScript's binding elements,
# after `(`; consumes `)`. flags: 2 type annotations, 4 a constructor (parameter properties).
FUNC jts_binding_list
    ENTER5 8
    mov r12d, edi
    call ss_mark
    mov r13, rax
    xor r14d, r14d                      # items
1:  TT_IS J_RPAREN
    je 8f
    test r14d, r14d
    jz 2f
    EXPECT J_COMMA
    TT_IS J_RPAREN
    je 8f
2:  inc r14d
    TT_IS J_ELLIPSIS
    jne 4f
    call jpp_rest_element
    mov rbx, rax
    test r12d, 2
    jz 3f
    mov rdi, rbx
    call jts_param_type
3:  mov rdi, rbx
    call ss_push
    # checkCommaAfterRest: `...a,)` is allowed (RestTrailingComma), another element is not
    TT_IS J_COMMA
    jne 8f
    call ts_lookahead_char
    cmp eax, ')'
    jne 90f
    NEXT
    jmp 8f
4:  xor ebx, ebx                        # decorators
    test r12d, 2
    jz 5f
    TT_IS J_AT
    jne 5f
    call jpd_decorators
    mov rbx, rax
5:  mov edi, r12d
    mov rsi, rbx
    call jts_binding_element
    mov rdi, rax
    call ss_push
    jmp 1b
8:  EXPECT J_RPAREN
    mov rdi, r13
    call ss_to_vec
    LEAVE5 8
90: REFUSE "syntax error: element after a rest element"
ENDF jts_binding_list

# jts_binding_element(flags, decorators VEC or 0) -> rax: TypeScript's parseBindingElement:
# modifiers (a TSParameterProperty), a binding atom with a default, `?` and a type, a default
FUNC jts_binding_element
    ENTER5 8
    mov r12d, edi
    mov r13, rsi
    mov r14, [rip + g_jt_start]         # start
    test r13, r13
    jz 1f
    mov rax, [r13 + 8]
    mov r14d, [rax + N_START]
1:  NODE T_TSParameterProperty, r14
    mov r15, rax
    mov rdi, r15
    mov esi, M_ACCESS | M_OVERRIDE | M_READONLY
    xor edx, edx
    xor ecx, ecx
    call jts_modifiers
    mov [rsp], rax
    test eax, eax
    jz 2f
    test r12d, 4
    jz 90f
2:  call jpp_binding_element             # left = parseMaybeDefault()
    mov rbx, rax
    mov r14, rax                        # elt
    test r12d, 2
    jz 3f
    mov rdi, rbx
    call jts_param_type
    cmp word ptr [rbx + N_TYPE], T_AssignmentPattern
    jne 3f
    cmp qword ptr [rbx + N_F5], 0
    jne 91f
3:  TT_IS J_EQ                          # elt = parseMaybeDefault(left.start, left)
    jne 4f
    mov esi, [rbx + N_START]
    NODE T_AssignmentPattern, rsi
    mov [rax + N_F0], rbx
    mov r14, rax
    NEXT
    call jpe_maybe_assign_allow_in
    mov [r14 + N_F1], rax
    FINISH r14
4:  cmp qword ptr [rsp], 0
    je 5f
    mov [r15 + N_F0], r14
    mov [r15 + N_F6], r13
    FINISH r15
    mov rax, r15
    jmp 9f
5:  test r13, r13
    jz 6f
    mov [rbx + N_F6], r13
6:  mov rax, r14
9:  LEAVE5 8
90: REFUSE "syntax error: parameter property outside a constructor"
91: REFUSE "syntax error: type annotation after a default"
ENDF jts_binding_element

# jts_param_type(param): parseFunctionParamType: `?` and a type annotation; the end moves to the
# last token read
FUNC jts_param_type
    push rbx
    sub rsp, 8
    mov rbx, rdi
    TT_IS J_QUESTION
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_OPTIONAL
1:  call jts_try_type_annotation
    test rax, rax
    jz 2f
    mov [rbx + N_F5], rax
2:  mov rdi, rbx
    mov rsi, [rip + g_jt_last_end]
    call js_extend_end
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_param_type

# ---------------------------------------------------------------- decorators
    .section .rodata
    .balign 2
# the node types whose F1 holds parameters
jts_function_types:
    .word T_FunctionDeclaration, T_FunctionExpression, T_ArrowFunctionExpression, T_ObjectMethod
    .word T_ClassMethod, T_ClassPrivateMethod, T_TSDeclareMethod, T_TSDeclareFunction
    .word T_TSMethodSignature, T_TSCallSignatureDeclaration, T_TSConstructSignatureDeclaration
    .word T_TSFunctionType, T_TSConstructorType, 0
    .text

# jts_check_param_decorators(node, class type): typescript-estree's nodeCanBeDecorated for
# parameters, which babel-ts does not check. A decorated parameter must belong to a method,
# constructor or setter with a body (ClassMethod or ClassPrivateMethod) in a ClassDeclaration,
# and must not be `this`; otherwise Prettier's typescript parser throws "Decorators are not
# valid here", so this refuses. The class type is that of the class whose body holds node, or 0.
FUNC jts_check_param_decorators
    ENTER5 8
    mov rbx, rdi
    mov r12d, esi
    test rbx, rbx
    jz 9f
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + jts_function_types]
1:  movzx edx, word ptr [rcx]
    test edx, edx
    jz 5f
    add rcx, 2
    cmp eax, edx
    jne 1b
    mov r13, [rbx + N_F1]
    test r13, r13
    jz 5f
    xor r14d, r14d
2:  cmp r14, [r13]
    jae 5f
    mov r15, [r13 + 8 + r14*8]
    inc r14
    mov rdi, r15
    cmp word ptr [rdi + N_TYPE], T_AssignmentPattern
    jne 3f
    mov rdi, [rdi + N_F0]               # Babel puts the decorators on the left side
3:  mov rax, [rdi + N_F6]
    test rax, rax
    jz 2b
    cmp qword ptr [rax], 0
    je 2b
    cmp r12d, T_ClassDeclaration
    jne 90f
    cmp word ptr [rbx + N_TYPE], T_ClassMethod
    je 4f
    cmp word ptr [rbx + N_TYPE], T_ClassPrivateMethod
    jne 90f
4:  mov rdi, r15
    call ts_is_this_param
    test eax, eax
    jnz 90f
    jmp 2b
    # the children; a class passes its type to its body, the body to its members
5:  xor r15d, r15d
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_ClassBody
    jne 51f
    mov r15d, r12d
    jmp 6f
51: cmp eax, T_ClassDeclaration
    je 52f
    cmp eax, T_ClassExpression
    jne 6f
52: mov r15d, eax
6:  lea rcx, [rip + ast_visitor_keys]
    mov r12, [rcx + rax*8]
7:  movzx r13d, byte ptr [r12]
    test r13d, r13d
    jz 9f
    inc r12
    mov r14d, r13d
    and r14d, 0x7f
    mov r14, [rbx + r14]
    test r13d, 0x80
    jnz 8f
    mov rdi, r14
    mov esi, r15d
    call jts_check_param_decorators
    jmp 7b
8:  test r14, r14
    jz 7b
    mov qword ptr [rsp], 0
81: mov rax, [rsp]
    cmp rax, [r14]
    jae 7b
    mov rdi, [r14 + 8 + rax*8]
    inc rax
    mov [rsp], rax
    mov esi, r15d
    call jts_check_param_decorators
    jmp 81b
9:  LEAVE5 8
90: REFUSE "rejected by Prettier's typescript parser: a decorator on a parameter outside a class declaration's method, constructor or setter, or on `this`"
ENDF jts_check_param_decorators

# jpd_decorators() -> rax = VEC: decorators while `@` follows
FUNC jpd_decorators
    push rbx
    sub rsp, 8
    call ss_mark
    mov rbx, rax
1:  TT_IS J_AT
    jne 2f
    call jpd_decorator
    mov rdi, rax
    call ss_push
    jmp 1b
2:  mov rdi, rbx
    call ss_to_vec
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jpd_decorators

# jpd_decorator() -> rax: Decorator at `@` (Babel's parseDecorator with the decorators plugin):
# `@(expr)`, or `@a.b.#c` with optional type arguments and arguments
FUNC jpd_decorator
    ENTER5 8
    NODE T_Decorator, [rip + g_jt_start]
    mov rbx, rax
    NEXT
    mov r12, [rip + g_jt_start]         # startLoc
    TT_IS J_LPAREN
    jne 1f
    NODE T_ParenthesizedExpression, r12
    mov r13, rax
    NEXT
    call jpe_expression_allow_in
    mov [r13 + N_F0], rax
    EXPECT J_RPAREN
    FINISH r13
    jmp 5f
1:  xor edi, edi
    call js_ident
    mov r13, rax
2:  TT_IS J_DOT
    jne 5f
    NEXT
    NODE T_MemberExpression, r12
    mov [rax + N_F0], r13
    mov r13, rax
    TT_IS J_PRIVATE
    jne 3f
    call jpe_private_name
    jmp 4f
3:  call js_ident_name
4:  mov [r13 + N_F1], rax
    FINISH r13
    jmp 2b
    # parseMaybeDecoratorArguments
5:  xor r14d, r14d                      # type arguments
    IF_NOT_TS 6f
    TT_IS J_LT
    je 51f
    TT_IS J_SHL
    jne 6f
51: call jts_type_arguments_in_expression
    mov r14, rax
    TT_IS J_LPAREN
    jne 90f
6:  TT_IS J_LPAREN
    jne 8f
    NEXT
    NODE T_CallExpression, r12
    mov [rax + N_F0], r13
    mov [rax + N_F4], r14
    mov r13, rax
    xor edi, edi
    call jpe_call_args
    mov [r13 + N_F1], rax
    FINISH r13
8:  mov [rbx + N_F0], r13
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: ( expected after decorator type arguments"
ENDF jpd_decorator

# ---------------------------------------------------------------- expressions
# jts_check_jsx(): at a `<` that starts an expression. Prettier's babel-ts tries the jsx and
# typescript plugins together first, where this `<` starts a JSX element. That parse can succeed
# only if a closing tag for the element follows: `</name` for `<name`, `</>` for `<>`. When one
# does, the file is refused rather than guessed at; otherwise the JSX parse fails and Babel's
# typescript-only result is the one this parser gives.
FUNC jts_check_jsx
    ENTER5 8
    call jl_peek
    mov r12, r8                         # name start
    mov r13, r9
    sub r13, r8                         # name length, 0 for a fragment
    cmp eax, J_NAME
    je 1f
    cmp eax, J_GT
    jne 9f
    xor r13d, r13d
1:  mov r14, [rip + g_text]
    mov r15, [rip + g_text_len]
    mov rbx, [rip + g_jt_end]
2:  cmp rbx, r15
    jae 9f
    movzx eax, byte ptr [r14 + rbx]
    inc rbx
    cmp al, '<'
    jne 2b
    mov rdi, rbx
    call jts_skip_ws
    cmp rax, r15
    jae 9f
    cmp byte ptr [r14 + rax], '/'
    jne 2b
    lea rdi, [rax + 1]
    call jts_skip_ws
    test r13, r13
    jnz 3f
    cmp rax, r15
    jae 9f
    cmp byte ptr [r14 + rax], '>'
    je 90f
    jmp 2b
3:  lea rcx, [rax + r13]
    cmp rcx, r15
    ja 2b
    push rcx
    sub rsp, 8
    lea rdi, [r14 + rax]
    lea rsi, [r14 + r12]
    mov rdx, r13
    call mem_eq
    add rsp, 8
    pop rcx
    test eax, eax
    jz 2b
    cmp rcx, r15
    jae 90f
    movzx eax, byte ptr [r14 + rcx]
    cmp eax, 0x80
    jae 2b
    lea rdx, [rip + js_char_class]
    movzx edx, byte ptr [rdx + rax]
    cmp edx, 3
    je 2b
    cmp edx, 4
    je 2b
90: REFUSE "`<` that the jsx+typescript parse Prettier tries first could read as JSX"
9:  LEAVE5 8
ENDF jts_check_jsx

# jts_skip_ws(pos) -> rax: the first position from pos that is not a space, tab or line break
FUNC jts_skip_ws
    mov rax, rdi
    mov rsi, [rip + g_text]
1:  cmp rax, [rip + g_text_len]
    jae 9f
    movzx ecx, byte ptr [rsi + rax]
    cmp cl, ' '
    je 2f
    cmp cl, 9
    jb 9f
    cmp cl, 13
    ja 9f
2:  inc rax
    jmp 1b
9:  leave
    ret
ENDF jts_skip_ws

# jts_maybe_assign_lt(flags) -> rax: TypeScript's parseMaybeAssign at `<`: a generic arrow
# function if that parses, else a type assertion
FUNC jts_maybe_assign_lt
    ENTER5 8
    mov r12, rdi
    call jts_check_jsx
    lea rdi, [rip + jts_generic_arrow]
    mov rsi, r12
    call js_try
    cmp edx, TRY_OK
    je 9f
    lea rdi, [rip + jpe_maybe_assign]
    mov rsi, r12
    or rsi, MA_NO_LT
    call js_try
    cmp edx, TRY_OK
    jne 90f
9:  LEAVE5 8
90: REFUSE "syntax error: after <"
ENDF jts_maybe_assign_lt

# jts_generic_arrow(flags) -> rax: `<T>(...) => ...`; aborts unless an unparenthesized arrow
# function follows the type parameters
FUNC jts_generic_arrow
    ENTER5 8
    mov r12, rdi
    mov edi, TP_CONST
    call jts_type_parameters
    mov rbx, rax
    mov rdi, r12
    or rdi, MA_NO_LT
    call jpe_maybe_assign
    cmp word ptr [rax + N_TYPE], T_ArrowFunctionExpression
    jne 8f
    mov rcx, [rbx + N_F0]
    cmp qword ptr [rcx], 0
    je 1f
    mov ecx, [rbx + N_START]
    mov [rax + N_START], ecx
1:  mov [rax + N_F4], rbx
    LEAVE5 8
8:  call js_abort
ENDF jts_generic_arrow

# jts_paren_item(node, start) -> rax: parseParenItem: `?` marks the node optional, `: T` wraps it
# in a TSTypeCastExpression
FUNC jts_paren_item
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    TT_IS J_QUESTION
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_OPTIONAL
    mov rdi, rbx
    mov rsi, [rip + g_jt_last_end]
    call js_extend_end
1:  TT_IS J_COLON
    jne 9f
    NODE T_TSTypeCastExpression, r12
    mov [rax + N_F0], rbx
    mov rbx, rax
    call jts_try_type_annotation
    mov [rbx + N_F5], rax
    FINISH rbx
9:  mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF jts_paren_item

# jts_as_type(node) -> rax: the type after `as` or `satisfies` (the current token); `as const`
# is a reference to `const`
FUNC jts_as_type
    ENTER5 8
    mov rbx, rdi
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    NEXT
    KW_IS KW_CONST
    jne 1f
    cmp word ptr [rbx + N_TYPE], T_TSSatisfiesExpression
    je 90f
    call jts_type_reference
    jmp 2f
1:  call jts_type
2:  mov rbx, rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: satisfies const"
ENDF jts_as_type

# jts_type_assertion() -> rax: TSTypeAssertion `<T>expr` (tsParseTypeAssertion)
FUNC jts_type_assertion
    ENTER5 8
    call jts_check_jsx
    NODE T_TSTypeAssertion, [rip + g_jt_start]
    mov rbx, rax
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    NEXT
    KW_IS KW_CONST
    jne 1f
    call jts_type_reference
    jmp 2f
1:  call jts_type
2:  mov [rbx + N_F5], rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    EXPECT J_GT
    xor edi, edi
    xor esi, esi
    call jpe_maybe_unary
    mov [rbx + N_F0], rax
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_assertion

# jts_check_type_casts(vec): tsCheckForInvalidTypeCasts: a TSTypeCastExpression left in an
# expression list is an error
FUNC jts_check_type_casts
    test rdi, rdi
    jz 9f
    xor ecx, ecx
1:  cmp rcx, [rdi]
    jae 9f
    mov rax, [rdi + 8 + rcx*8]
    inc rcx
    test rax, rax
    jz 1b
    cmp word ptr [rax + N_TYPE], T_TSTypeCastExpression
    jne 1b
    REFUSE "syntax error: type annotation in an expression"
9:  leave
    ret
ENDF jts_check_type_casts

# jts_arrow_return_type() -> rax: TypeScript's parseArrow: a return type at `:` that `=>` follows
# on the same line; aborts otherwise
FUNC jts_arrow_return_type
    push rbx
    sub rsp, 8
    mov edi, J_COLON
    call jts_type_or_predicate_annotation
    mov rbx, rax
    call js_can_insert_semicolon
    test eax, eax
    jnz 8f
    TT_IS J_ARROW
    jne 8f
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
8:  call js_abort
ENDF jts_arrow_return_type

# js_is_assignable(node, binding) -> eax: Babel's isAssignable with TypeScript's cases
FUNC js_is_assignable
    ENTER5 8
    mov rbx, rdi
    mov r12d, esi
    movzx eax, word ptr [rbx + N_TYPE]
    cmp eax, T_TSTypeCastExpression
    je 10f
    cmp eax, T_TSParameterProperty
    je 8f
    cmp eax, T_Identifier
    je 8f
    cmp eax, T_ObjectPattern
    je 8f
    cmp eax, T_ArrayPattern
    je 8f
    cmp eax, T_AssignmentPattern
    je 8f
    cmp eax, T_RestElement
    je 8f
    cmp eax, T_ObjectProperty
    je 11f
    cmp eax, T_SpreadElement
    je 12f
    cmp eax, T_ParenthesizedExpression
    je 10f
    cmp eax, T_AssignmentExpression
    je 13f
    cmp eax, T_MemberExpression
    je 14f
    cmp eax, T_OptionalMemberExpression
    je 14f
    cmp eax, T_ObjectExpression
    je 20f
    cmp eax, T_ArrayExpression
    je 30f
    jmp 7f
10: mov rdi, [rbx + N_F0]               # expression
    jmp 15f
11: mov rdi, [rbx + N_F1]               # value
    jmp 15f
12: mov rdi, [rbx + N_F0]               # argument
15: mov esi, r12d
    call js_is_assignable
    jmp 9f
13: xor eax, eax
    cmp qword ptr [rbx + N_F2], J_EQ
    sete al
    jmp 9f
14: xor eax, eax
    test r12d, r12d
    sete al
    jmp 9f
20: mov r13, [rbx + N_F0]               # every property; a spread only last
    xor r14d, r14d
21: cmp r14, [r13]
    jae 8f
    mov rdi, [r13 + 8 + r14*8]
    cmp word ptr [rdi + N_TYPE], T_ObjectMethod
    je 7f
    lea rax, [r14 + 1]
    cmp rax, [r13]
    je 22f
    cmp word ptr [rdi + N_TYPE], T_SpreadElement
    je 7f
22: mov esi, r12d
    call js_is_assignable
    test eax, eax
    jz 9f
    inc r14
    jmp 21b
30: mov r13, [rbx + N_F0]
    xor r14d, r14d
31: cmp r14, [r13]
    jae 8f
    mov rdi, [r13 + 8 + r14*8]
    inc r14
    test rdi, rdi
    jz 31b
    mov esi, r12d
    call js_is_assignable
    test eax, eax
    jz 9f
    jmp 31b
7:  xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  LEAVE5 8
ENDF js_is_assignable

# ts_token_starts_expr() -> eax: Babel's tokenCanStartExpression for the current token
FUNC ts_token_starts_expr
    mov eax, 1
    mov rcx, [rip + g_jt_type]
    cmp rcx, J_NAME
    je 1f
    cmp rcx, J_STRING
    je 9f
    cmp rcx, J_NUM
    je 9f
    cmp rcx, J_BIGINT
    je 9f
    cmp rcx, J_TEMPLATE
    je 9f
    cmp rcx, J_PRIVATE
    je 9f
    cmp rcx, J_LBRACK
    je 9f
    cmp rcx, J_LBRACE
    je 9f
    cmp rcx, J_LPAREN
    je 9f
    cmp rcx, J_INC
    je 9f
    cmp rcx, J_DEC
    je 9f
    cmp rcx, J_BANG
    je 9f
    cmp rcx, J_TILDE
    je 9f
    cmp rcx, J_PLUS
    je 9f
    cmp rcx, J_MINUS
    je 9f
    cmp rcx, J_PERCENT
    je 9f
    cmp rcx, J_HASH
    je 9f
    xor eax, eax
    jmp 9f
1:  mov rcx, [rip + g_jt_kw]
    lea rdx, [rip + ts_non_expr_words]
2:  movzx r8d, byte ptr [rdx]
    test r8d, r8d
    jz 9f
    cmp r8, rcx
    je 8f
    inc rdx
    jmp 2b
8:  xor eax, eax
9:  leave
    ret
ENDF ts_token_starts_expr

    .section .rodata
ts_non_expr_words:
    .byte KW_BREAK, KW_CASE, KW_CATCH, KW_CONST, KW_CONTINUE, KW_DEBUGGER, KW_DEFAULT, KW_DO
    .byte KW_ELSE, KW_EXPORT, KW_EXTENDS, KW_FINALLY, KW_FOR, KW_IF, KW_IN, KW_INSTANCEOF
    .byte KW_RETURN, KW_SWITCH, KW_TRY, KW_VAR, KW_WHILE, KW_WITH, 0
    .text

    .bss
    .balign 8
g_missing_paren: .quad 0
    .text

# jts_subscript_lt(base, start, flags) -> rax, edx: TypeScript's parseSubscript at `<` or `<<`:
# a call, tagged template or instantiation expression with type arguments, or a generic async
# arrow; 0 when the type arguments do not parse (Babel's tsTryParseAndCatch). edx 1: no more
# subscripts after this one. flags: 1 no calls, 2 in an optional chain, 4 after `?.`.
FUNC jts_subscript_lt
    ENTER5 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov qword ptr [rip + g_missing_paren], 0
    lea rdi, [rip + jts_subscript_lt_try]
    mov rsi, rbx
    mov rdx, r12
    mov ecx, r13d
    call js_try
    cmp qword ptr [rip + g_missing_paren], 0
    jne 90f
    xor edx, edx
    test rax, rax
    jz 9f
    cmp word ptr [rax + N_TYPE], T_TSInstantiationExpression
    jne 9f
    TT_IS J_DOT
    je 91f
    TT_IS J_QDOT
    jne 1f
    mov r14, rax
    call ts_lookahead_char
    cmp eax, '('
    jne 91f
    mov rax, r14
    xor edx, edx
    jmp 9f
1:  mov edx, 1
9:  LEAVE5 8
90: REFUSE "syntax error: ( expected"
91: REFUSE "syntax error: property access after an instantiation expression"
ENDF jts_subscript_lt

FUNC jts_subscript_lt_try
    ENTER5 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    test r13d, 1
    jnz 1f
    mov rdi, rbx
    call js_at_possible_async_arrow
    test eax, eax
    jz 1f
    mov rdi, r12
    call jts_generic_async_arrow
    test rax, rax
    jnz 9f
1:  call jts_type_arguments_in_expression
    test rax, rax
    jz 80f
    mov r14, rax
    test r13d, 4
    jz 2f
    TT_IS J_LPAREN
    je 2f
    mov qword ptr [rip + g_missing_paren], 1
    jmp 80f
2:  TT_IS J_TEMPLATE
    jne 3f
    test r13d, 2
    jnz 90f
    NODE T_TaggedTemplateExpression, r12
    mov r15, rax
    mov [r15 + N_F0], rbx
    mov [r15 + N_F4], r14
    mov edi, 1
    call jpe_template
    mov [r15 + N_F1], rax
    FINISH r15
    mov rax, r15
    jmp 9f
3:  test r13d, 1
    jnz 4f
    TT_IS J_LPAREN
    jne 4f
    NEXT
    mov edi, T_CallExpression
    test r13d, 2
    jz 31f
    mov edi, T_OptionalCallExpression
31: mov rsi, r12
    call js_node
    mov r15, rax
    mov [r15 + N_F0], rbx
    mov [r15 + N_F4], r14
    test r13d, 4
    jz 32f
    or dword ptr [r15 + N_ATTR], NA_OPTIONAL
32: xor edi, edi
    call jpe_call_args
    mov [r15 + N_F1], rax
    FINISH r15
    mov rax, r15
    jmp 9f
4:  mov rax, [rip + g_jt_type]
    cmp rax, J_GT
    je 80f
    cmp rax, J_SHR
    je 80f
    cmp rax, J_USHR
    je 80f
    cmp rax, J_LPAREN
    je 5f
    call ts_token_starts_expr
    test eax, eax
    jz 5f
    cmp qword ptr [rip + g_jt_nl], 0
    je 80f
5:  NODE T_TSInstantiationExpression, r12
    mov [rax + N_F0], rbx
    mov [rax + N_F4], r14
    FINISH rax
9:  LEAVE5 8
80: call js_abort
90: REFUSE "syntax error: tagged template in an optional chain"
ENDF jts_subscript_lt_try

# jts_generic_async_arrow(start) -> rax: `async <T>(...) => ...` (tsTryParseGenericAsyncArrowFunction)
# with `async` read, or 0
FUNC jts_generic_async_arrow
    ENTER5 8
    mov r12, rdi
    xor eax, eax
    TT_IS J_LT
    jne 9f
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_ARROW_PARAMS
    lea rdi, [rip + jts_generic_async_head]
    mov rsi, r12
    call js_try
    mov rbx, rax
    TS_RESTORE TS_ARROW_PARAMS, [rsp]
    xor eax, eax
    cmp edx, TRY_OK
    jne 9f
    mov rdi, r12
    mov rsi, [rbx + N_F1]
    mov edx, 1
    call jpf_arrow
    mov rcx, [rbx + N_F4]
    mov [rax + N_F4], rcx
    mov rcx, [rbx + N_F5]
    mov [rax + N_F5], rcx
9:  LEAVE5 8
ENDF jts_generic_async_arrow

FUNC jts_generic_async_head
    push rbx
    sub rsp, 8
    NODE T_ArrowFunctionExpression, rdi
    mov rbx, rax
    mov edi, TP_CONST
    call jts_type_parameters
    mov [rbx + N_F4], rax
    EXPECT J_LPAREN
    mov edi, 2
    call jts_binding_list
    mov [rbx + N_F1], rax
    TT_IS J_COLON
    jne 1f
    mov edi, J_COLON
    call jts_type_or_predicate_annotation
    mov [rbx + N_F5], rax
1:  EXPECT J_ARROW
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_generic_async_head
