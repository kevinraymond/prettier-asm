# TypeScript declarations, after Babel's typescript plugin: interfaces, type aliases, enums,
# namespaces and modules, `declare`, `abstract class`, `import x = ...`, and the checks Babel
# makes in ambient contexts.
.include "defs.inc"
.include "parse_js.inc"

.equ TP_INOUT, 2
.equ TP_INOUTCONST, 3

    .section .rodata
s_enum: .ascii "enum"
    .text

# jts_statement_start(start) -> rax: Babel's parseStatementContent for TypeScript: `const enum`,
# `enum` and `interface` declarations at the current token, or 0
FUNC jts_statement_start
    ENTER5 8
    mov r12, rdi
    KW_IS KW_CONST
    jne 1f
    lea rdi, [rip + s_enum]
    mov esi, 4
    call ts_lookahead_word
    test eax, eax
    jz 8f
    NODE T_TSEnumDeclaration, r12
    mov rbx, rax
    NEXT
    mov rdi, rbx
    mov esi, NA_CONST
    call jts_enum
    jmp 9f
1:  KW_IS KW_ENUM
    jne 2f
    NODE T_TSEnumDeclaration, r12
    mov rdi, rax
    xor esi, esi
    call jts_enum
    jmp 9f
2:  KW_IS KW_INTERFACE
    jne 8f
    NODE T_TSInterfaceDeclaration, r12
    mov rdi, rax
    xor esi, esi
    call jts_interface
    jmp 9f
8:  xor eax, eax
9:  LEAVE5 8
ENDF jts_statement_start

# jts_enum(node, attrs) -> rax: tsParseEnumDeclaration at `enum`; attrs: NA_CONST, NA_DECLARE.
# The members go in a TSEnumBody from `{`, as Prettier's postprocess makes it.
FUNC jts_enum
    ENTER5 8
    mov rbx, rdi
    or [rbx + N_ATTR], esi
    KW_IS KW_ENUM
    jne 90f
    NEXT
    mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
    NODE T_TSEnumBody, [rip + g_jt_start]
    mov r12, rax
    EXPECT J_LBRACE
    mov edi, J_RBRACE
    lea rsi, [rip + jts_enum_member]
    call jts_delimited_list
    mov [r12 + N_F0], rax
    EXPECT J_RBRACE
    FINISH r12
    mov [rbx + N_F1], r12
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: enum expected"
ENDF jts_enum

# jts_enum_member() -> rax: TSEnumMember
FUNC jts_enum_member
    push rbx
    sub rsp, 8
    NODE T_TSEnumMember, [rip + g_jt_start]
    mov rbx, rax
    TT_IS J_STRING
    jne 1f
    call jpm_string
    jmp 2f
1:  call js_ident_name
2:  mov [rbx + N_F0], rax
    TT_IS J_EQ
    jne 3f
    NEXT
    call jpe_maybe_assign_allow_in
    mov [rbx + N_F1], rax
3:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_enum_member

# jts_interface(node, attrs) -> rax: tsParseInterfaceDeclaration at `interface`, or 0 when a line
# break follows the word
FUNC jts_interface
    ENTER5 8
    mov rbx, rdi
    mov r12d, esi
    call ts_lookahead_char
    test ecx, ecx
    jnz 8f
    mov word ptr [rbx + N_TYPE], T_TSInterfaceDeclaration
    or [rbx + N_ATTR], r12d
    NEXT
    call ts_tok_is_ident
    test eax, eax
    jz 90f
    mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
    mov edi, TP_INOUTCONST
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
    KW_IS KW_EXTENDS
    jne 1f
    NEXT
    call jts_heritage_clause
    mov [rbx + N_F1], rax
1:  NODE T_TSInterfaceBody, [rip + g_jt_start]
    mov r12, rax
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    call jts_object_type_members
    mov [r12 + N_F0], rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    FINISH r12
    mov [rbx + N_F2], r12
    FINISH rbx
    mov rax, rbx
    jmp 9f
8:  xor eax, eax
9:  LEAVE5 8
90: REFUSE "syntax error: interface name expected"
ENDF jts_interface

# jts_heritage_clause() -> rax = VEC: tsParseHeritageClause: TSExpressionWithTypeArguments items
# up to `{`
FUNC jts_heritage_clause
    push rbx
    sub rsp, 8
    mov edi, J_LBRACE
    lea rsi, [rip + jts_heritage_item]
    call jts_delimited_list
    cmp qword ptr [rax], 0
    je 90f
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: empty extends or implements list"
ENDF jts_heritage_clause

FUNC jts_heritage_item
    push rbx
    sub rsp, 8
    NODE T_TSExpressionWithTypeArguments, [rip + g_jt_start]
    mov rbx, rax
    mov edi, 3
    call jts_entity_name
    mov [rbx + N_F0], rax
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
ENDF jts_heritage_item

# jts_type_alias(node) -> rax: tsParseTypeAliasDeclaration; the current token is the name
FUNC jts_type_alias
    ENTER5 8
    mov rbx, rdi
    mov word ptr [rbx + N_TYPE], T_TSTypeAliasDeclaration
    mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_IN_TYPE
    mov edi, TP_INOUT
    call jts_try_type_parameters
    mov [rbx + N_F4], rax
    EXPECT J_EQ
    KW_IS KW_INTRINSIC
    jne 1f
    call ts_lookahead_char
    cmp eax, '.'
    je 1f
    NODE T_TSIntrinsicKeyword, [rip + g_jt_start]
    mov r12, rax
    NEXT
    FINISH r12
    mov rax, r12
    jmp 2f
1:  call jts_type
2:  mov [rbx + N_F5], rax
    TS_RESTORE TS_IN_TYPE, [rsp]
    call js_semicolon
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_type_alias

# jts_module_block() -> rax: TSModuleBlock at `{`: statements as at the top level, outside any
# function (await and yield are identifiers)
FUNC jts_module_block
    ENTER5 8
    NODE T_TSModuleBlock, [rip + g_jt_start]
    mov rbx, rax
    EXPECT J_LBRACE
    mov r12, [rip + g_px]
    mov qword ptr [rip + g_px], 0
    mov edi, J_RBRACE
    xor esi, esi
    call jps_block_body
    mov [rbx + N_F0], rax
    mov [rip + g_px], r12
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
ENDF jts_module_block

# jts_module_or_namespace(node) -> rax: tsParseModuleOrNamespaceDeclaration; `A.B.C` nests
# declarations without kind
FUNC jts_module_or_namespace
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov word ptr [rbx + N_TYPE], T_TSModuleDeclaration
    mov edi, 1
    call js_ident
    mov [rbx + N_F0], rax
    TT_IS J_DOT
    jne 1f
    NEXT
    NODE T_TSModuleDeclaration, [rip + g_jt_start]
    mov rdi, rax
    call jts_module_or_namespace
    jmp 2f
1:  call jts_module_block
2:  mov [rbx + N_F1], rax
    FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
ENDF jts_module_or_namespace

# jts_ambient_module(node) -> rax: tsParseAmbientExternalModuleDeclaration: `global` or a string
# name, then a body or `;`
FUNC jts_ambient_module
    push rbx
    sub rsp, 8
    mov rbx, rdi
    mov word ptr [rbx + N_TYPE], T_TSModuleDeclaration
    KW_IS KW_GLOBAL
    jne 1f
    mov qword ptr [rbx + N_F3], KD_GLOBAL
    or dword ptr [rbx + N_ATTR], NA_GLOBAL
    xor edi, edi
    call js_ident
    jmp 2f
1:  TT_IS J_STRING
    jne 90f
    mov qword ptr [rbx + N_F3], KD_MODULE
    call jpm_string
2:  mov [rbx + N_F0], rax
    TT_IS J_LBRACE
    jne 3f
    call jts_module_block
    mov [rbx + N_F1], rax
    jmp 4f
3:  call js_semicolon
4:  FINISH rbx
    mov rax, rbx
    add rsp, 8
    pop rbx
    leave
    ret
90: REFUSE "syntax error: module name expected"
ENDF jts_ambient_module

# jts_check_line_terminator(next) -> eax: tsCheckLineTerminator. With next, the word is consumed
# unless a line break follows it.
FUNC jts_check_line_terminator
    test edi, edi
    jz 1f
    call ts_lookahead_char
    xor eax, eax
    test ecx, ecx
    jnz 9f
    NEXT
    mov eax, 1
    jmp 9f
1:  call js_is_line_terminator
    xor eax, 1
9:  leave
    ret
ENDF jts_check_line_terminator

# jts_declaration(node, kw, next, decorators) -> rax: tsParseDeclaration for the words abstract,
# module, namespace and type, or 0. With next the word is the current token.
FUNC jts_declaration
    ENTER5 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    cmp r12, KW_ABSTRACT
    je 10f
    cmp r12, KW_MODULE
    je 20f
    cmp r12, KW_NAMESPACE
    je 30f
    cmp r12, KW_TYPE
    je 40f
    jmp 8f
10: mov edi, r13d
    call jts_check_line_terminator
    test eax, eax
    jz 8f
    KW_IS KW_CLASS
    je 11f
    call ts_tok_is_ident
    test eax, eax
    jz 8f
    KW_IS KW_INTERFACE
    jne 90f
    call ts_lookahead_char
    test ecx, ecx
    jz 91f                              # abstract interface: NonClassMethodPropertyHasAbstractModifier
    jmp 8f
11: or dword ptr [rbx + N_ATTR], NA_ABSTRACT
    mov word ptr [rbx + N_TYPE], T_ClassDeclaration
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    call jpf_class
    mov rbx, rax
    test r14, r14
    jz 12f
    mov [rbx + N_F6], r14                # maybeTakeDecorators
    mov rax, [r14 + 8]
    mov eax, [rax + N_START]
    mov [rbx + N_START], eax
12: mov rax, rbx
    jmp 9f
20: mov edi, r13d
    call jts_check_line_terminator
    test eax, eax
    jz 8f
    TT_IS J_STRING
    jne 21f
    mov rdi, rbx
    call jts_ambient_module
    jmp 9f
21: call ts_tok_is_ident
    test eax, eax
    jz 8f
    mov qword ptr [rbx + N_F3], KD_MODULE
    mov rdi, rbx
    call jts_module_or_namespace
    jmp 9f
30: mov edi, r13d
    call jts_check_line_terminator
    test eax, eax
    jz 8f
    call ts_tok_is_ident
    test eax, eax
    jz 8f
    mov qword ptr [rbx + N_F3], KD_NAMESPACE
    mov rdi, rbx
    call jts_module_or_namespace
    jmp 9f
40: mov edi, r13d
    call jts_check_line_terminator
    test eax, eax
    jz 8f
    call ts_tok_is_ident
    test eax, eax
    jz 8f
    mov rdi, rbx
    call jts_type_alias
    jmp 9f
8:  xor eax, eax
9:  LEAVE5 8
90: REFUSE "syntax error: class expected after abstract"
91: REFUSE "syntax error: abstract interface"
ENDF jts_declaration

# jts_expression_statement(start, kw, decorators) -> rax: tsParseExpressionStatement for a
# statement that so far is the single word with keyword id kw: a declaration, or 0
FUNC jts_expression_statement
    ENTER5 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r13, KW_DECLARE
    je 10f
    cmp r13, KW_GLOBAL
    je 20f
    NODE T_TSModuleDeclaration, r12
    mov rdi, rax
    mov rsi, r13
    xor edx, edx
    mov rcx, r14
    call jts_declaration
    jmp 9f
10: NODE T_TSModuleDeclaration, r12
    mov rdi, rax
    call jts_try_declare
    test rax, rax
    jz 9f
    or dword ptr [rax + N_ATTR], NA_DECLARE
    jmp 9f
20: xor eax, eax
    TT_IS J_LBRACE
    jne 9f
    NODE T_TSModuleDeclaration, r12
    mov rbx, rax
    mov qword ptr [rbx + N_F3], KD_GLOBAL
    or dword ptr [rbx + N_ATTR], NA_GLOBAL
    NODE T_Identifier, r12
    mov ecx, [rip + g_jt_last_end]
    mov [rax + N_END], ecx
    mov [rbx + N_F0], rax
    call jts_module_block
    mov [rbx + N_F1], rax
    FINISH rbx
    mov rax, rbx
9:  LEAVE5 8
ENDF jts_expression_statement

# jts_try_declare(node) -> rax: tsTryParseDeclare: the declaration after `declare`, parsed in an
# ambient context, or 0
FUNC jts_try_declare
    ENTER5 8
    mov rbx, rdi
    call js_is_line_terminator
    test eax, eax
    jnz 8f
    TS_SAVE [rsp]
    or qword ptr [rip + g_ts], TS_AMBIENT
    TT_IS J_NAME
    jne 80f
    mov rax, [rip + g_jt_kw]
    cmp rax, KW_FUNCTION
    je 10f
    cmp rax, KW_CLASS
    je 11f
    cmp rax, KW_ENUM
    je 12f
    cmp rax, KW_GLOBAL
    je 13f
    cmp rax, KW_LET
    je 14f
    cmp rax, KW_CONST
    je 14f
    cmp rax, KW_VAR
    je 14f
    cmp rax, KW_USING
    je 92f
    cmp rax, KW_INTERFACE
    jne 16f
    mov rdi, rbx
    mov esi, NA_DECLARE
    call jts_interface
    test rax, rax
    jnz 89f
16: call ts_tok_is_ident
    test eax, eax
    jz 80f
    mov rdi, rbx
    mov rsi, [rip + g_jt_kw]
    mov edx, 1
    xor ecx, ecx
    call jts_declaration
    jmp 89f
10: mov word ptr [rbx + N_TYPE], T_FunctionDeclaration
    or dword ptr [rbx + N_ATTR], NA_DECLARE
    NEXT
    mov rdi, rbx
    mov esi, 1
    call jpf_function
    jmp 89f
11: mov word ptr [rbx + N_TYPE], T_ClassDeclaration
    or dword ptr [rbx + N_ATTR], NA_DECLARE
    mov rdi, rbx
    mov esi, 1
    xor edx, edx
    call jpf_class
    jmp 89f
12: mov word ptr [rbx + N_TYPE], T_TSEnumDeclaration
    mov rdi, rbx
    mov esi, NA_DECLARE
    call jts_enum
    jmp 89f
13: mov rdi, rbx
    call jts_ambient_module
    jmp 89f
14: KW_IS KW_CONST
    jne 15f
    lea rdi, [rip + s_enum]
    mov esi, 4
    call ts_lookahead_word
    test eax, eax
    jz 15f
    NEXT
    mov word ptr [rbx + N_TYPE], T_TSEnumDeclaration
    mov rdi, rbx
    mov esi, NA_CONST | NA_DECLARE
    call jts_enum
    jmp 89f
15: mov edi, KD_VAR
    KW_IS KW_LET
    jne 151f
    mov edi, KD_LET
151: KW_IS KW_CONST
    jne 152f
    mov edi, KD_CONST
152: call jps_var_statement
    mov ecx, [rbx + N_START]
    mov [rax + N_START], ecx
    or dword ptr [rax + N_ATTR], NA_DECLARE
    jmp 89f
80: xor eax, eax
89: mov rbx, rax
    TS_RESTORE TS_AMBIENT, [rsp]
    mov rax, rbx
    jmp 9f
8:  xor eax, eax
9:  LEAVE5 8
92: REFUSE "using declaration (explicit resource management)"
ENDF jts_try_declare

# jts_check_ambient_var(declaration): Babel's checks of a variable declaration in an ambient
# context: initializers only on a const without a type, and only literal-like ones
FUNC jts_check_ambient_var
    ENTER5 8
    test qword ptr [rip + g_ts], TS_AMBIENT
    jz 9f
    mov rbx, rdi
    mov r12, [rbx + N_F0]
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 9f
    mov r14, [r12 + 8 + r13*8]
    inc r13
    mov rdi, [r14 + N_F1]
    test rdi, rdi
    jz 1b
    cmp qword ptr [rbx + N_F1], KD_CONST
    jne 90f
    mov rax, [r14 + N_F0]
    cmp qword ptr [rax + N_F5], 0
    jne 90f
    call jts_valid_ambient_const_init
    test eax, eax
    jz 90f
    jmp 1b
9:  LEAVE5 8
90: REFUSE "syntax error: initializer in an ambient context"
ENDF jts_check_ambient_var

# jts_valid_ambient_const_init(expr) -> eax: isValidAmbientConstInitializer
FUNC jts_valid_ambient_const_init
    xor eax, eax
    test dword ptr [rdi + N_ATTR], NA_PARENTHESIZED
    jnz 9f
    cmp word ptr [rdi + N_TYPE], T_ParenthesizedExpression
    je 9f
    movzx ecx, word ptr [rdi + N_TYPE]
    cmp ecx, T_StringLiteral
    je 8f
    cmp ecx, T_BooleanLiteral
    je 8f
    cmp ecx, T_NumericLiteral
    je 8f
    cmp ecx, T_BigIntLiteral
    je 8f
    cmp ecx, T_UnaryExpression
    jne 2f
    cmp qword ptr [rdi + N_F1], J_MINUS
    jne 9f
    mov rdx, [rdi + N_F0]
    movzx ecx, word ptr [rdx + N_TYPE]
    cmp ecx, T_NumericLiteral
    je 8f
    cmp ecx, T_BigIntLiteral
    je 8f
    jmp 9f
2:  cmp ecx, T_TemplateLiteral
    jne 3f
    mov rdx, [rdi + N_F1]
    cmp qword ptr [rdx], 0
    je 8f
    jmp 9f
3:  cmp ecx, T_MemberExpression        # isPossiblyLiteralEnum
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_COMPUTED
    jz 5f
    mov rdx, [rdi + N_F1]
    movzx ecx, word ptr [rdx + N_TYPE]
    cmp ecx, T_StringLiteral
    je 5f
    cmp ecx, T_TemplateLiteral
    jne 9f
    mov rdx, [rdx + N_F1]
    cmp qword ptr [rdx], 0
    jne 9f
5:  mov rdi, [rdi + N_F0]              # isUncomputedMemberExpressionChain
6:  cmp word ptr [rdi + N_TYPE], T_Identifier
    je 8f
    cmp word ptr [rdi + N_TYPE], T_MemberExpression
    jne 9f
    test dword ptr [rdi + N_ATTR], NA_COMPUTED
    jnz 9f
    mov rdi, [rdi + N_F0]
    jmp 6b
8:  mov eax, 1
9:  leave
    ret
ENDF jts_valid_ambient_const_init

# jts_import_equals(node, id or 0, is_export) -> rax: tsParseImportEqualsDeclaration: `id = ...;`
# after `import` (and `type`)
FUNC jts_import_equals
    ENTER5 8
    mov rbx, rdi
    mov word ptr [rbx + N_TYPE], T_TSImportEqualsDeclaration
    test edx, edx
    jz 1f
    or dword ptr [rbx + N_ATTR], NA_IS_EXPORT
1:  mov rax, rsi
    test rax, rax
    jnz 2f
    mov edi, 1
    call js_ident
2:  mov [rbx + N_F0], rax
    EXPECT J_EQ
    KW_IS KW_REQUIRE
    jne 3f
    call ts_lookahead_char
    cmp eax, '('
    jne 3f
    NODE T_TSExternalModuleReference, [rip + g_jt_start]
    mov r12, rax
    NEXT
    EXPECT J_LPAREN
    call jpm_string
    mov [r12 + N_F0], rax
    EXPECT J_RPAREN
    FINISH r12
    mov rax, r12
    jmp 4f
3:  xor edi, edi
    call jts_entity_name
    cmp qword ptr [rbx + N_F3], KD_TYPE
    je 90f
4:  mov [rbx + N_F1], rax
    call js_semicolon
    FINISH rbx
    mov rax, rbx
    LEAVE5 8
90: REFUSE "syntax error: import type alias"
ENDF jts_import_equals

# jts_var_id(declarator): parseVarId's TypeScript part: `!` (definite) after an identifier, then a
# type annotation on the id, whose range grows to take it in
FUNC jts_var_id
    push rbx
    push r12
    mov rbx, rdi
    mov r12, [rbx + N_F0]
    cmp word ptr [r12 + N_TYPE], T_Identifier
    jne 1f
    cmp qword ptr [rip + g_jt_nl], 0
    jne 1f
    TT_IS J_BANG
    jne 1f
    NEXT
    or dword ptr [rbx + N_ATTR], NA_DEFINITE
1:  call jts_try_type_annotation
    test rax, rax
    jz 9f
    mov [r12 + N_F5], rax
    mov rdi, r12
    mov rsi, [rip + g_jt_last_end]
    call js_extend_end
9:  pop r12
    pop rbx
    leave
    ret
ENDF jts_var_id
