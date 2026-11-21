# JS comment handlers: src/language-js/comments/handle-comments.js, plus
# --debug-comments, which dumps where attachComments put each comment.
#
# A handler is handler(comment, is_last) -> eax 1 when it attached the
# comment; the comment's CM_ENCL, CM_PREC and CM_FOLL are Prettier's
# enclosingNode, precedingNode and followingNode. Lines marked GAP stand for
# handlers or branches whose node types the parser does not produce yet.
.include "pjs.inc"

    .section .rodata
    .balign 8
    .globl pjs_handlers_own_line, pjs_handlers_end_of_line, pjs_handlers_remaining
# handleOwnLineComment
pjs_handlers_own_line:
    .quad pjc_handle_ignore_comments
    .quad pjc_handle_conditional_expression_comments
    .quad pjc_handle_last_function_arg_comments
    # GAP(flow): handleLastComponentArgComments needs the component types
    .quad pjc_handle_member_expression_comments
    .quad pjc_handle_if_statement_comments
    .quad pjc_handle_while_comments
    .quad pjc_handle_try_statement_comments
    .quad pjc_handle_class_comments
    .quad pjc_handle_for_comments
    .quad pjc_handle_union_type_comments
    .quad pjc_handle_only_comments
    .quad pjc_handle_module_specifiers_comments
    .quad pjc_handle_assignment_pattern_comments
    .quad pjc_handle_method_name_comments
    .quad pjc_handle_labeled_statement_comments
    .quad pjc_handle_break_and_continue_statement_comments
    .quad pjc_handle_nested_conditional_expression_comments
    .quad pjc_handle_comments_in_destructuring_pattern
    .quad pjc_handle_ts_mapped_type_comments
    .quad 0
# handleEndOfLineComment
pjs_handlers_end_of_line:
    .quad pjc_handle_closure_type_cast_comments
    .quad pjc_handle_last_function_arg_comments
    .quad pjc_handle_conditional_expression_comments
    .quad pjc_handle_module_specifiers_comments
    .quad pjc_handle_if_statement_comments
    .quad pjc_handle_while_comments
    .quad pjc_handle_try_statement_comments
    .quad pjc_handle_class_comments
    .quad pjc_handle_labeled_statement_comments
    .quad pjc_handle_call_expression_comments
    .quad pjc_handle_property_comments
    .quad pjc_handle_only_comments
    .quad pjc_handle_variable_declarator_comments
    .quad pjc_handle_break_and_continue_statement_comments
    .quad pjc_handle_switch_default_case_comments
    .quad pjc_handle_last_union_element_in_expression
    .quad pjc_handle_last_binary_operator_operand
    .quad pjc_handle_ts_mapped_type_comments
    .quad 0
# handleRemainingComment
pjs_handlers_remaining:
    .quad pjc_handle_ignore_comments
    .quad pjc_handle_if_statement_comments
    .quad pjc_handle_while_comments
    .quad pjc_handle_object_property_assignment
    .quad pjc_handle_comment_in_empty_parens
    .quad pjc_handle_method_name_comments
    .quad pjc_handle_only_comments
    .quad pjc_handle_comment_after_arrow_params
    .quad pjc_handle_function_name_comments
    .quad pjc_handle_break_and_continue_statement_comments
    .quad pjc_handle_ts_function_trailing_comments
    .quad 0

# Markers of dangling comments (addDanglingComment's third argument). The
# printer asks for them by these addresses.
    .globl pjs_marker_implements, pjs_marker_extends
pjs_marker_implements: .asciz "implements"
pjs_marker_extends:    .asciz "extends"

# Context: rbx comment, r12 enclosingNode, r13 precedingNode, r14 followingNode,
# r15 isLastComment. Labels 7 (return true) and 8 (return false) come from HEND.
.macro HCTX
    mov rbx, rdi
    mov r15, rsi
    mov r12, [rdi + CM_ENCL]
    mov r13, [rdi + CM_PREC]
    mov r14, [rdi + CM_FOLL]
.endm
.macro HEND
7:  mov eax, 1
    EPILOGUE
8:  xor eax, eax
    EPILOGUE
.endm
# dst = node?.type as a T_* number, 0 for a null node
.macro LTYPE dst, node
    xor \dst, \dst
    test \node, \node
    jz .Llt\@
    movzx \dst, word ptr [\node + N_TYPE]
.Llt\@:
.endm
# Attach the comment and return true
.macro LEAD node
    mov rdi, \node
    mov rsi, rbx
    call add_leading
    jmp 7f
.endm
.macro TRAIL node
    mov rdi, \node
    mov rsi, rbx
    call add_trailing
    jmp 7f
.endm
.macro DANGLE node
    mov rdi, \node
    mov rsi, rbx
    xor edx, edx
    call add_dangling
    jmp 7f
.endm
# eax = getNextNonSpaceNonCommentCharacter(text, locEnd(comment)), -1 for ""
.macro NEXTCH
    mov edi, [rbx + CM_END]
    call next_nonspace_noncomment_char
.endm

    .text

# pjs_handle_own_line_comment(comment, is_last) -> eax, and the end-of-line
# and remaining forms: the handler lists run in order (handleOwnLineComment...)
FUNC pjs_handle_own_line_comment
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + pjs_handlers_own_line]
    call run_handlers
    leave
    ret
ENDF pjs_handle_own_line_comment

FUNC pjs_handle_end_of_line_comment
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + pjs_handlers_end_of_line]
    call run_handlers
    leave
    ret
ENDF pjs_handle_end_of_line_comment

FUNC pjs_handle_remaining_comment
    mov rdx, rsi
    mov rsi, rdi
    lea rdi, [rip + pjs_handlers_remaining]
    call run_handlers
    leave
    ret
ENDF pjs_handle_remaining_comment

# ================================================================ helpers
# pjc_add_block_statement_first_comment(node, comment): addBlockStatementFirstComment:
# leading comment of the first statement of node.body that is not an
# EmptyStatement, else a dangling comment of node
FUNC pjc_add_block_statement_first_comment
    mov r8, [rdi + N_F0]                # body (BlockStatement, ClassBody)
    test r8, r8
    jz 5f
    xor ecx, ecx
1:  cmp rcx, [r8]
    jae 5f
    mov rax, [r8 + 8 + rcx*8]
    inc rcx
    test rax, rax
    jz 1b
    cmp word ptr [rax + N_TYPE], T_EmptyStatement
    je 1b
    mov rdi, rax
    call add_leading
    leave
    ret
5:  xor edx, edx
    call add_dangling
    leave
    ret
ENDF pjc_add_block_statement_first_comment

# pjc_add_block_or_not_comment(node, comment) (addBlockOrNotComment)
FUNC pjc_add_block_or_not_comment
    test rdi, rdi
    jz 90f
    cmp word ptr [rdi + N_TYPE], T_BlockStatement
    jne 1f
    call pjc_add_block_statement_first_comment
    leave
    ret
1:  call add_leading
    leave
    ret
90: REFUSE "a comment handler reads a missing node (Prettier throws)"
ENDF pjc_add_block_or_not_comment

# pjs_is_line_comment(comment) -> eax (isLineComment: a hashbang counts)
FUNC pjs_is_line_comment
    xor eax, eax
    cmp byte ptr [rdi + CM_TYPE], CT_LINE
    je 1f
    cmp byte ptr [rdi + CM_TYPE], CT_INTERPRETER
    jne 9f
1:  mov eax, 1
9:  leave
    ret
ENDF pjs_is_line_comment

# pjc_is_single_line_comment(comment) -> eax (isSingleLineComment)
FUNC pjc_is_single_line_comment
    push rdi
    sub rsp, 8
    call pjs_is_line_comment
    add rsp, 8
    pop rdi
    test eax, eax
    jnz 9f
    mov esi, [rdi + CM_END]
    mov edi, [rdi + CM_START]
    call has_newline_in_range
    xor eax, 1
9:  leave
    ret
ENDF pjc_is_single_line_comment

# pjc_vec_len(vec) -> rax: length of a VEC field, 0 for 0
FUNC pjc_vec_len
    xor eax, eax
    test rdi, rdi
    jz 9f
    mov rax, [rdi]
9:  leave
    ret
ENDF pjc_vec_len

# pjc_is_real_function_like(node) -> eax (isRealFunctionLikeNode)
FUNC pjc_is_real_function_like
    LTYPE eax, rdi
    cmp eax, T_ArrowFunctionExpression
    je 1f
    cmp eax, T_FunctionExpression
    je 1f
    cmp eax, T_FunctionDeclaration
    je 1f
    cmp eax, T_ObjectMethod
    je 1f
    cmp eax, T_ClassMethod
    je 1f
    cmp eax, T_TSDeclareFunction
    je 1f
    cmp eax, T_TSCallSignatureDeclaration
    je 1f
    cmp eax, T_TSConstructSignatureDeclaration
    je 1f
    cmp eax, T_TSMethodSignature
    je 1f
    cmp eax, T_TSConstructorType
    je 1f
    cmp eax, T_TSFunctionType
    je 1f
    cmp eax, T_TSDeclareMethod
    je 1f
    xor eax, eax
    leave
    ret
1:  mov eax, 1
    leave
    ret
ENDF pjc_is_real_function_like

# pjc_is_union_type(node) -> eax (isUnionType)
FUNC pjc_is_union_type
    LTYPE ecx, rdi
    xor eax, eax
    # GAP(flow): UnionTypeAnnotation
    cmp ecx, T_TSUnionType
    sete al
    leave
    ret
ENDF pjc_is_union_type

# pjc_is_intersection_type(node) -> eax (isIntersectionType)
FUNC pjc_is_intersection_type
    LTYPE ecx, rdi
    xor eax, eax
    # GAP(flow): IntersectionTypeAnnotation
    cmp ecx, T_TSIntersectionType
    sete al
    leave
    ret
ENDF pjc_is_intersection_type

# pjc_is_conditional_type(node) -> eax (isConditionalType)
FUNC pjc_is_conditional_type
    LTYPE ecx, rdi
    xor eax, eax
    # GAP(flow): ConditionalTypeAnnotation
    cmp ecx, T_TSConditionalType
    sete al
    leave
    ret
ENDF pjc_is_conditional_type

# pjc_is_conditional(node) -> eax: ConditionalExpression or isConditionalType
FUNC pjc_is_conditional
    LTYPE ecx, rdi
    mov eax, 1
    cmp ecx, T_ConditionalExpression
    je 9f
    call pjc_is_conditional_type
9:  leave
    ret
ENDF pjc_is_conditional

# ================================================================ handlers
# handleClosureTypeCastComments
FUNC pjc_handle_closure_type_cast_comments
    PROLOGUE
    HCTX
    test r14, r14
    jz 8f
    mov rdi, rbx
    call is_type_cast_comment
    test eax, eax
    jz 8f
    LEAD r14
    HEND
ENDF pjc_handle_closure_type_cast_comments

# handleIfStatementComments
FUNC pjc_handle_if_statement_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_IfStatement
    jne 8f
    test r14, r14
    jz 8f
    NEXTCH
    cmp eax, ')'
    jne 1f
    test r13, r13
    jz 90f
    TRAIL r13
    # comments before `else`
1:  cmp r13, [r12 + N_F1]
    jne 5f
    cmp r14, [r12 + N_F2]
    jne 5f
    mov rax, [r12 + N_F1]
    mov edi, [rax + N_END]
    call next_nonspace_noncomment_index
    mov ecx, [rbx + CM_START]
    cmp rcx, rax                        # locStart(comment) < maybeElseTokenIndex
    jl 2f
    mov rax, [r12 + N_F2]
    TYPE rax, T_BlockStatement
    jne 5f
2:  TYPE r13, T_BlockStatement
    jne 3f
    TRAIL r13
3:  mov rdi, rbx
    call pjc_is_single_line_comment
    test eax, eax
    jz 4f
    mov edi, [r13 + N_START]
    mov esi, [rbx + CM_START]
    call has_newline_in_range
    test eax, eax
    jnz 4f
    TRAIL r13
4:  DANGLE r12
5:  TYPE r14, T_BlockStatement
    jne 6f
    mov rdi, r14
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
6:  TYPE r14, T_IfStatement
    jne 61f
    mov rdi, [r14 + N_F1]
    mov rsi, rbx
    call pjc_add_block_or_not_comment
    jmp 7f
61: cmp r14, [r12 + N_F1]
    jne 8f
    LEAD r14
    HEND
90: REFUSE "a comment handler reads a missing node (Prettier throws)"
ENDF pjc_handle_if_statement_comments

# handleWhileComments
FUNC pjc_handle_while_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_WhileStatement
    jne 8f
    test r14, r14
    jz 8f
    NEXTCH
    cmp eax, ')'
    jne 1f
    test r13, r13
    jz 90f
    TRAIL r13
1:  TYPE r14, T_BlockStatement
    jne 2f
    mov rdi, r14
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
2:  cmp r14, [r12 + N_F1]
    jne 8f
    LEAD r14
    HEND
90: REFUSE "a comment handler reads a missing node (Prettier throws)"
ENDF pjc_handle_while_comments

# handleTryStatementComments
FUNC pjc_handle_try_statement_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_TryStatement
    je 1f
    cmp eax, T_CatchClause
    jne 8f
1:  test r14, r14
    jz 8f
    cmp eax, T_CatchClause
    jne 2f
    test r13, r13
    jz 2f
    TRAIL r13
2:  TYPE r14, T_BlockStatement
    jne 3f
    mov rdi, r14
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
3:  TYPE r14, T_TryStatement
    jne 4f
    mov rdi, [r14 + N_F2]               # finalizer
    mov rsi, rbx
    call pjc_add_block_or_not_comment
    jmp 7f
4:  TYPE r14, T_CatchClause
    jne 8f
    mov rdi, [r14 + N_F1]               # body
    mov rsi, rbx
    call pjc_add_block_or_not_comment
    jmp 7f
    HEND
ENDF pjc_handle_try_statement_comments

# handleMemberExpressionComments
FUNC pjc_handle_member_expression_comments
    PROLOGUE
    HCTX
    mov rdi, r12
    call pjs_is_member_expression
    test eax, eax
    jz 8f
    LTYPE eax, r14
    cmp eax, T_Identifier
    jne 8f
    LEAD r12
    HEND
ENDF pjc_handle_member_expression_comments

# handleNestedConditionalExpressionComments
FUNC pjc_handle_nested_conditional_expression_comments
    PROLOGUE
    HCTX
    cmp qword ptr [rip + g_experimental_ternaries], 0
    je 8f
    mov rdi, r12
    call pjc_is_conditional
    test eax, eax
    jz 8f
    mov rdi, r14
    call pjc_is_conditional
    test eax, eax
    jz 8f
    DANGLE r12
    HEND
ENDF pjc_handle_nested_conditional_expression_comments

# handleConditionalExpressionComments
FUNC pjc_handle_conditional_expression_comments
    PROLOGUE
    HCTX
    test r14, r14
    jz 8f
    mov rdi, r12
    call pjc_is_conditional
    test eax, eax
    jz 8f
    test r13, r13
    jz 1f
    mov edi, [r13 + N_END]
    mov esi, [rbx + CM_START]
    call has_newline_in_range
    test eax, eax
    jz 8f                               # on the preceding node's line
1:  cmp qword ptr [rip + g_experimental_ternaries], 0
    je 3f
    TYPE r12, T_ConditionalExpression   # a conditional type has no alternate
    jne 3f
    cmp r14, [r12 + N_F2]
    jne 3f
    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK
    jne 2f
    mov edi, [rbx + CM_START]
    mov esi, [rbx + CM_END]
    call has_newline_in_range
    test eax, eax
    jz 3f
2:  DANGLE r12
3:  LEAD r14
    HEND
ENDF pjc_handle_conditional_expression_comments

# handleObjectPropertyAssignment
FUNC pjc_handle_object_property_assignment
    PROLOGUE
    HCTX
    mov rdi, r12
    call pjs_is_object_property
    test eax, eax
    jz 8f
    ATTR r12, NA_SHORTHAND
    jz 8f
    cmp r13, [r12 + N_F0]
    jne 8f
    mov rax, [r12 + N_F1]
    TYPE rax, T_AssignmentPattern
    jne 8f
    TRAIL [rax + N_F0]
    HEND
ENDF pjc_handle_object_property_assignment

# handleClassComments. Class slots: id F0, superClass F1, body F2,
# typeParameters F4, implements F5, decorators F6; TSInterfaceDeclaration has
# extends in F1.
FUNC pjc_handle_class_comments
    PROLOGUE
    HCTX
    # GAP(flow): DeclareClass, DeclareInterface, InterfaceDeclaration (and mixins)
    LTYPE eax, r12
    cmp eax, T_ClassDeclaration
    je 1f
    cmp eax, T_ClassExpression
    je 1f
    cmp eax, T_TSInterfaceDeclaration
    jne 8f
    jmp 2f
    # decorators: trailing comment of the last one unless a decorator follows
1:  mov rax, [r12 + N_F6]
    test rax, rax
    jz 2f
    mov rcx, [rax]
    test rcx, rcx
    jz 2f
    LTYPE edx, r14
    cmp edx, T_Decorator
    je 2f
    TRAIL [rax + rcx*8]
2:  mov rax, [r12 + N_F2]
    test rax, rax
    jz 3f
    cmp r14, rax
    jne 3f
    mov rdi, rax
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
3:  test r14, r14
    jz 8f
    TYPE r12, T_TSInterfaceDeclaration
    je 4f
    mov rax, [r12 + N_F1]               # superClass
    test rax, rax
    jz 5f
    cmp r14, rax
    jne 5f
    test r13, r13
    jz 5f
    cmp r13, [r12 + N_F0]
    je 31f
    cmp r13, [r12 + N_F4]
    jne 5f
31: TRAIL r13
    # implements (classes) and extends (interfaces): the first one follows
5:  mov rax, [r12 + N_F5]
    lea rdx, [rip + pjs_marker_implements]
    jmp 6f
4:  mov rax, [r12 + N_F1]
    lea rdx, [rip + pjs_marker_extends]
6:  test rax, rax
    jz 8f
    cmp qword ptr [rax], 0
    je 8f
    cmp r14, [rax + 8]
    jne 8f
    test r13, r13
    jz 61f
    cmp r13, [r12 + N_F0]
    je 62f
    cmp r13, [r12 + N_F4]
    je 62f
    TYPE r12, T_TSInterfaceDeclaration
    je 61f
    cmp r13, [r12 + N_F1]
    je 62f
61: mov rdi, r12
    mov rsi, rbx
    call add_dangling
    jmp 7f
62: TRAIL r13
    HEND
ENDF pjc_handle_class_comments

# handleFunctionNameComments
FUNC pjc_handle_function_name_comments
    PROLOGUE
    HCTX
    NEXTCH
    cmp eax, '('
    jne 8f
    test r13, r13
    jz 8f
    # GAP(estree): MethodDefinition
    LTYPE eax, r12
    cmp eax, T_FunctionDeclaration
    je 1f
    cmp eax, T_FunctionExpression
    je 1f
    cmp eax, T_ClassMethod
    je 1f
    cmp eax, T_ObjectMethod
    jne 8f
1:  TRAIL r13
    HEND
ENDF pjc_handle_function_name_comments

# handleCommentAfterArrowParams
FUNC pjc_handle_comment_after_arrow_params
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_ArrowFunctionExpression
    jne 8f
    mov edi, [rbx + CM_END]
    call next_nonspace_noncomment_index
    mov rcx, IDX_FALSE
    cmp rax, rcx
    je 8f
    lea rcx, [rax + 2]
    cmp rcx, [rip + g_text_len]
    ja 8f
    mov rcx, [rip + g_text]
    cmp word ptr [rcx + rax], 0x3e3d    # "=>"
    jne 8f
    DANGLE r12
    HEND
ENDF pjc_handle_comment_after_arrow_params

# handleCommentInEmptyParens
FUNC pjc_handle_comment_in_empty_parens
    PROLOGUE
    HCTX
    NEXTCH
    cmp eax, ')'
    jne 8f
    test r12, r12
    jz 8f
    mov rdi, r12
    call pjc_is_real_function_like
    test eax, eax
    jz 1f
    mov rdi, r12
    call pjs_get_function_parameters
    cmp qword ptr [rax], 0
    je 3f
1:  mov rdi, r12
    call pjs_is_call_like_expression
    test eax, eax
    jz 2f
    mov rdi, r12
    call pjs_get_call_arguments
    cmp qword ptr [rax], 0
    je 3f
    # GAP(estree): MethodDefinition, TSAbstractMethodDefinition (dangling on node.value)
2:  jmp 8f
3:  DANGLE r12
    HEND
ENDF pjc_handle_comment_in_empty_parens

# handleLastFunctionArgComments
FUNC pjc_handle_last_function_arg_comments
    PROLOGUE
    HCTX
    # GAP(flow): FunctionTypeParam in FunctionTypeAnnotation
    LTYPE eax, r13
    cmp eax, T_Identifier
    je 1f
    cmp eax, T_AssignmentPattern
    je 1f
    cmp eax, T_ObjectPattern
    je 1f
    cmp eax, T_ArrayPattern
    je 1f
    cmp eax, T_RestElement
    je 1f
    cmp eax, T_TSParameterProperty
    je 1f
    jmp 2f
1:  mov rdi, r12
    call pjc_is_real_function_like
    test eax, eax
    jz 2f
    NEXTCH
    cmp eax, ')'
    jne 2f
    TRAIL r13
    # a comment between the parameters' `)` and the body
2:  cmp byte ptr [rbx + CM_TYPE], CT_BLOCK
    je 8f
    LTYPE eax, r12
    cmp eax, T_FunctionDeclaration
    je 3f
    cmp eax, T_FunctionExpression
    je 3f
    cmp eax, T_ObjectMethod
    jne 8f
3:  LTYPE eax, r14
    cmp eax, T_BlockStatement
    jne 8f
    cmp r14, [r12 + N_F2]
    jne 8f
    mov edi, [rbx + CM_END]
    call next_nonspace_noncomment_index
    mov ecx, [r14 + N_START]
    cmp rax, rcx
    jne 8f
    mov rdi, r14
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
    HEND
ENDF pjc_handle_last_function_arg_comments

# handleLabeledStatementComments
FUNC pjc_handle_labeled_statement_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_LabeledStatement
    jne 8f
    LEAD r12
    HEND
ENDF pjc_handle_labeled_statement_comments

# handleBreakAndContinueStatementComments
FUNC pjc_handle_break_and_continue_statement_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_ContinueStatement
    je 1f
    cmp eax, T_BreakStatement
    jne 8f
1:  cmp qword ptr [r12 + N_F0], 0       # label
    jne 8f
    TRAIL r12
    HEND
ENDF pjc_handle_break_and_continue_statement_comments

# handleCallExpressionComments
FUNC pjc_handle_call_expression_comments
    PROLOGUE
    HCTX
    mov rdi, r12
    call pjs_is_call_expression
    test eax, eax
    jz 8f
    test r13, r13
    jz 8f
    cmp r13, [r12 + N_F0]
    jne 8f
    mov rax, [r12 + N_F1]
    test rax, rax
    jz 8f
    cmp qword ptr [rax], 0
    je 8f
    LEAD [rax + 8]
    HEND
ENDF pjc_handle_call_expression_comments

# handlePropertyComments
FUNC pjc_handle_property_comments
    PROLOGUE
    HCTX
    mov rdi, r12
    call pjs_is_object_property
    test eax, eax
    jz 8f
    LEAD r12
    HEND
ENDF pjc_handle_property_comments

# handleOnlyComments
FUNC pjc_handle_only_comments
    PROLOGUE
    HCTX
    # ast.body.length === 0: only a Program root has a body (babel's root is File)
    mov rax, [rip + g_root]
    LTYPE ecx, rax
    cmp ecx, T_Program
    jne 1f
    mov rdi, [rax + N_F0]
    call pjc_vec_len
    test rax, rax
    jnz 1f
    mov r12, [rip + g_root]
    jmp 3f
1:  LTYPE eax, r12
    cmp eax, T_Program
    jne 8f
    mov rdi, [r12 + N_F0]
    call pjc_vec_len
    test rax, rax
    jnz 8f
    mov rdi, [r12 + N_F1]
    call pjc_vec_len
    test rax, rax
    jnz 8f
3:  test r15, r15
    jz 4f
    DANGLE r12
4:  LEAD r12
    HEND
ENDF pjc_handle_only_comments

# handleForComments
FUNC pjc_handle_for_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_ForInStatement
    je 1f
    cmp eax, T_ForOfStatement
    jne 8f
1:  LEAD r12
    HEND
ENDF pjc_handle_for_comments

# handleModuleSpecifiersComments
FUNC pjc_handle_module_specifiers_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_ImportSpecifier
    je 1f
    cmp eax, T_ExportSpecifier
    jne 2f
1:  LEAD r12
2:  LTYPE ecx, r13
    cmp ecx, T_ImportSpecifier
    jne 3f
    cmp eax, T_ImportDeclaration
    je 4f
    jmp 8f
3:  cmp ecx, T_ExportSpecifier
    jne 8f
    cmp eax, T_ExportNamedDeclaration
    jne 8f
4:  mov edi, [rbx + CM_END]
    xor esi, esi
    call has_newline
    test eax, eax
    jz 8f
    TRAIL r13
    HEND
ENDF pjc_handle_module_specifiers_comments

# handleAssignmentPatternComments
FUNC pjc_handle_assignment_pattern_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_AssignmentPattern
    jne 8f
    LEAD r12
    HEND
ENDF pjc_handle_assignment_pattern_comments

# handleVariableDeclaratorComments
FUNC pjc_handle_variable_declarator_comments
    PROLOGUE
    HCTX
    # GAP(flow): TypeAlias
    LTYPE eax, r12
    cmp eax, T_VariableDeclarator
    je 1f
    cmp eax, T_AssignmentExpression
    je 1f
    cmp eax, T_TSTypeAliasDeclaration
    jne 8f
1:  test r14, r14
    jz 8f
    # GAP(flow): ObjectTypeAnnotation
    movzx eax, word ptr [r14 + N_TYPE]
    cmp eax, T_TSTypeLiteral
    je 2f
    cmp eax, T_ObjectExpression
    je 2f
    cmp eax, T_ArrayExpression
    je 2f
    cmp eax, T_TemplateLiteral
    je 2f
    cmp eax, T_TaggedTemplateExpression
    je 2f
    cmp byte ptr [rbx + CM_TYPE], CT_BLOCK
    jne 8f
2:  LEAD r14
    HEND
ENDF pjc_handle_variable_declarator_comments

# handleSwitchDefaultCaseComments
FUNC pjc_handle_switch_default_case_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_SwitchCase
    jne 8f
    cmp qword ptr [r12 + N_F0], 0       # test
    jne 8f
    test r14, r14
    jz 8f
    mov rax, [r12 + N_F1]               # consequent
    test rax, rax
    jz 8f
    cmp qword ptr [rax], 0
    je 8f
    cmp r14, [rax + 8]
    jne 8f
    TYPE r14, T_BlockStatement
    jne 1f
    mov rdi, rbx
    call pjs_is_line_comment
    test eax, eax
    jz 1f
    mov rdi, r14
    mov rsi, rbx
    call pjc_add_block_statement_first_comment
    jmp 7f
1:  DANGLE r12
    HEND
ENDF pjc_handle_switch_default_case_comments

# handleLastBinaryOperatorOperand
FUNC pjc_handle_last_binary_operator_operand
    PROLOGUE
    HCTX
    test r14, r14
    jnz 8f
    LTYPE eax, r12
    cmp eax, T_UnaryExpression
    jne 8f
    LTYPE eax, r13
    cmp eax, T_LogicalExpression
    je 1f
    cmp eax, T_BinaryExpression
    jne 8f
1:  mov rax, [r12 + N_F0]               # argument
    mov edi, [rax + N_START]
    mov rax, [r13 + N_F1]               # right
    mov esi, [rax + N_START]
    call has_newline_in_range
    test eax, eax
    jz 8f
    mov rdi, rbx
    call pjc_is_single_line_comment
    test eax, eax
    jz 8f
    mov rax, [r13 + N_F1]
    mov edi, [rax + N_START]
    mov esi, [rbx + CM_START]
    call has_newline_in_range
    test eax, eax
    jnz 8f
    TRAIL [r13 + N_F1]
    HEND
ENDF pjc_handle_last_binary_operator_operand

# handleIgnoreComments
FUNC pjc_handle_ignore_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_TSMappedType
    jne 8f
    cmp r14, [r12 + N_F0]               # key
    jne 8f
    mov rdi, rbx
    call is_prettier_ignore_comment
    test eax, eax
    jz 8f
    or word ptr [r12 + N_FLAGS], NF_PRETTIER_IGNORE
    or byte ptr [rbx + CM_FLAGS], CF_UNIGNORE
    jmp 7f
    HEND
ENDF pjc_handle_ignore_comments

# handleUnionTypeComments
FUNC pjc_handle_union_type_comments
    PROLOGUE
    HCTX
    mov rdi, r12
    call pjc_is_union_type
    test eax, eax
    jz 5f
    mov rdi, rbx
    call is_prettier_ignore_comment
    test eax, eax
    jz 1f
    test r14, r14
    jz 90f
    or word ptr [r14 + N_FLAGS], NF_PRETTIER_IGNORE
    or byte ptr [rbx + CM_FLAGS], CF_UNIGNORE
1:  test r13, r13
    jz 8f
    TRAIL r13
5:  mov rdi, r14
    call pjc_is_union_type
    test eax, eax
    jz 8f
    mov rdi, rbx
    call is_prettier_ignore_comment
    test eax, eax
    jz 8f
    mov rax, [r14 + N_F0]               # types
    test rax, rax
    jz 90f
    cmp qword ptr [rax], 0
    je 90f
    mov rax, [rax + 8]
    or word ptr [rax + N_FLAGS], NF_PRETTIER_IGNORE
    or byte ptr [rbx + CM_FLAGS], CF_UNIGNORE
    jmp 8f
    HEND
90: REFUSE "a comment handler reads a missing node (Prettier throws)"
ENDF pjc_handle_union_type_comments

# handleMethodNameComments
FUNC pjc_handle_method_name_comments
    PROLOGUE
    HCTX
    # obj = { fn /*comment*/() {} }: only the estree parsers need it
    test r12, r12
    jz 5f
    test r13, r13
    jz 5f
    # GAP(estree): Property, TSAbstractMethodDefinition
    TYPE r12, T_TSDeclareMethod
    jne 5f
    TYPE r13, T_Identifier
    jne 5f
    cmp r13, [r12 + N_F0]
    jne 5f
    NEXTCH
    cmp eax, '('
    jne 5f
    mov edi, [r13 + N_END]
    call next_nonspace_noncomment_char
    cmp eax, ':'
    je 5f
    TRAIL r13
    # a comment between a decorator and a class member
5:  LTYPE eax, r13
    cmp eax, T_Decorator
    jne 8f
    # GAP(estree): PropertyDefinition, TSAbstractPropertyDefinition, TSAbstractMethodDefinition,
    # MethodDefinition, AccessorProperty, TSAbstractAccessorProperty
    LTYPE eax, r12
    cmp eax, T_ClassMethod
    je 6f
    cmp eax, T_ClassProperty
    je 6f
    cmp eax, T_TSDeclareMethod
    je 6f
    cmp eax, T_ClassAccessorProperty
    je 6f
    cmp eax, T_TSParameterProperty
    jne 8f
6:  mov rdi, rbx
    call pjs_is_line_comment
    test eax, eax
    jnz 61f
    cmp byte ptr [rbx + CM_PLACEMENT], PL_OWNLINE
    jne 8f
61: TRAIL r13
    HEND
ENDF pjc_handle_method_name_comments

# handleCommentsInDestructuringPattern (returns undefined when it does not apply)
FUNC pjc_handle_comments_in_destructuring_pattern
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_ObjectPattern
    je 1f
    cmp eax, T_ArrayPattern
    jne 8f
1:  LTYPE eax, r14
    cmp eax, T_TSTypeAnnotation
    jne 8f
    test r13, r13
    jz 2f
    TRAIL r13
2:  DANGLE r12
    HEND
ENDF pjc_handle_comments_in_destructuring_pattern

# handleTSMappedTypeComments
FUNC pjc_handle_ts_mapped_type_comments
    PROLOGUE
    HCTX
    LTYPE eax, r12
    cmp eax, T_TSMappedType
    jne 8f
    test r13, r13
    jnz 8f
    DANGLE r12
    HEND
ENDF pjc_handle_ts_mapped_type_comments

# handleLastUnionElementInExpression
FUNC pjc_handle_last_union_element_in_expression
    PROLOGUE
    HCTX
    mov rdi, r13
    call pjc_is_union_type
    test eax, eax
    jz 8f
    # GAP(flow): ArrayTypeAnnotation
    TYPE r12, T_TSArrayType
    jne 1f
    test r14, r14
    jz 2f
1:  mov rdi, r12
    call pjc_is_intersection_type
    test eax, eax
    jz 8f
2:  mov rax, [r13 + N_F0]               # types
    mov rcx, [rax]
    TRAIL [rax + rcx*8]
    HEND
ENDF pjc_handle_last_union_element_in_expression

# handleTSFunctionTrailingComments
FUNC pjc_handle_ts_function_trailing_comments
    PROLOGUE
    HCTX
    test r14, r14
    jnz 8f
    # GAP(estree): TSAbstractMethodDefinition
    LTYPE eax, r12
    cmp eax, T_TSMethodSignature
    je 1f
    cmp eax, T_TSDeclareFunction
    jne 8f
1:  NEXTCH
    cmp eax, ';'
    jne 8f
    TRAIL r12
    HEND
ENDF pjc_handle_ts_function_trailing_comments

# ================================================================ --debug-comments
# Parses a JS file, attaches its comments with the JS hooks and writes, per
# comment in source order:
#   <start> <end> <Block|Line|Interp> <ownLine|endOfLine|remaining>
#     <leading|trailing|dangling> <NodeType> <nodeStart> <nodeEnd>[ marker=<m>][ unignore]
# then `prettierIgnore <NodeType> <start> <end>` for each node a handler
# flagged. Positions are UTF-16 offsets. tests/stage3/comments/oracle.mjs
# writes the same from Prettier.

    .section .rodata
    .balign 8
pjc_debug_printer:
    .quad 0                             # PR_PRINT
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
s_flag_comments:   .asciz "--debug-comments"
s_flag_docs:       .asciz "--debug-comment-docs"
s_flag_ternaries:  .asciz "--experimental-ternaries"
s_flag_stdin2:     .asciz "--stdin-filepath"
s_flag_stdin2_eq:  .asciz "--stdin-filepath="
s_ct_names:        .asciz "?"
                   .asciz "Block"
                   .asciz "Line"
                   .asciz "Interp"
s_pl_names:        .asciz "?"
                   .asciz "ownLine"
                   .asciz "endOfLine"
                   .asciz "remaining"
s_leading:         .asciz " leading "
s_trailing:        .asciz " trailing "
s_dangling:        .asciz " dangling "
s_unattached:      .asciz " unattached"
s_marker:          .asciz " marker="
s_unignore:        .asciz " unignore"
s_prettier_ignore_line: .asciz "prettierIgnore "

    .bss
    .balign 8
pjc_owners:  .quad 0                    # node per comment index
pjc_ignored: .quad 0                    # LIST of nodes flagged prettierIgnore

    .text

# pjc_debug_scan(argc, argv): with --debug-comments or --debug-comment-docs
# among the arguments, runs that dump on the file named by --stdin-filepath
# (read from stdin) or by the first other argument and exits 0. Otherwise
# returns.
FUNC pjc_debug_scan
    PROLOGUE
    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d                      # path
    xor r15d, r15d                      # 1: from stdin
    xor eax, eax
    mov [rsp], rax                      # --debug-comments seen
    mov ebx, 1
1:  cmp rbx, r12
    jae 5f
    mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_comments]
    call cstr_eq
    test eax, eax
    jz 2f
    mov qword ptr [rsp], 1
    jmp 4f
2:  mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_docs]
    call cstr_eq
    test eax, eax
    jz 20f
    mov qword ptr [rsp], 2
    jmp 4f
20: mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_ternaries]
    call cstr_eq
    test eax, eax
    jz 21f
    mov qword ptr [rip + g_experimental_ternaries], 1
    jmp 4f
21: mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_stdin2]
    call cstr_eq
    test eax, eax
    jz 22f
    inc rbx
    cmp rbx, r12
    jae 5f
    mov r14, [r13 + rbx*8]
    mov r15d, 1
    jmp 4f
22: mov rdi, [r13 + rbx*8]
    lea rsi, [rip + s_flag_stdin2_eq]
    call cstr_prefix
    test eax, eax
    jz 23f
    mov r14, [r13 + rbx*8]
    add r14, 17
    mov r15d, 1
    jmp 4f
23: test r14, r14
    jnz 4f
    mov rax, [r13 + rbx*8]
    cmp byte ptr [rax], '-'
    je 4f
    mov r14, rax
4:  inc rbx
    jmp 1b
5:  cmp qword ptr [rsp], 0
    je 9f
    test r14, r14
    jz 90f
    mov [rip + g_filepath], r14
    mov [rip + g_from_stdin], r15
    test r15d, r15d
    jz 6f
    xor edi, edi
    call read_fd_all
    jmp 7f
6:  mov rdi, r14
    call read_file
7:  test rax, rax
    jnz 91f
    call out_init
    cmp qword ptr [rsp], 2
    je 8f
    call pjc_debug_main
    jmp 81f
8:  call pjc_debug_docs
81:    mov rdx, [rip + g_out_ptr]
    mov rsi, [rip + g_out_base]
    sub rdx, rsi
    mov edi, 1
    call write_all
    xor edi, edi
    call sys_exit
9:  EPILOGUE
90: REFUSE "--debug-comments without a file"
91: REFUSE "cannot read the input"
ENDF pjc_debug_scan

# pjc_debug_main(): parse, attach, dump into the output buffer
FUNC pjc_debug_main
    PROLOGUE
    call text_prepare
    call js_source_is_script
    mov edi, eax
    call js_parse
    mov rbx, rax
    lea rax, [rip + pjc_debug_printer]
    mov [rip + g_printer], rax
    mov rdi, rbx
    call attach_comments
    call jd_build_offsets
    mov r12, [rip + g_comments]
    xor r13d, r13d                      # comment count
    test r12, r12
    jz 1f
    mov r13d, [r12]
1:  lea rdi, [r13*8 + 8]
    call alloc
    mov [rip + pjc_owners], rax
    mov qword ptr [rip + pjc_ignored], 0
    mov rdi, rbx
    call pjc_collect
    xor r14d, r14d
2:  cmp r14, r13
    jae 5f
    mov rdi, [r12 + 8 + r14*8]
    mov rax, [rip + pjc_owners]
    mov rsi, [rax + r14*8]
    call pjc_dump_comment
    inc r14
    jmp 2b
5:  mov r12, [rip + pjc_ignored]
    test r12, r12
    jz 9f
    xor r14d, r14d
6:  cmp r14d, [r12]
    jae 9f
    lea rdi, [rip + s_prettier_ignore_line]
    call jd_cstr
    mov rdi, [r12 + 8 + r14*8]
    call pjc_dump_node
    mov edi, 10
    call out_byte
    inc r14
    jmp 6b
9:  EPILOGUE
ENDF pjc_debug_main

# pjc_debug_docs(): --debug-comment-docs: parses the file and writes, for each
# comment, "<start> <end>\n" and then printComment's doc printed with
# printDocToString (width 80, tab width 2, spaces, lf) twice, alone and as
# indent([hardline, doc]), each as "<byte length>\n<text>\n".
# tests/stage3/comments/print-run.mjs writes the same from Prettier.
FUNC pjc_debug_docs
    PROLOGUE 4
    call text_prepare
    call js_source_is_script
    mov edi, eax
    call js_parse
    lea rax, [rip + pjc_debug_printer]
    mov [rip + g_printer], rax
    call jd_build_offsets
    mov qword ptr [rsp + PO_WIDTH], 80
    mov qword ptr [rsp + PO_TAB_WIDTH], 2
    mov qword ptr [rsp + PO_USE_TABS], 0
    mov qword ptr [rsp + PO_EOL], EOL_LF
    mov r12, [rip + g_comments]
    test r12, r12
    jz 9f
    xor r13d, r13d
1:  cmp r13d, [r12]
    jae 9f
    mov rbx, [r12 + 8 + r13*8]
    mov edi, [rbx + CM_START]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov edi, [rbx + CM_END]
    call jd_pos
    mov edi, 10
    call out_byte
    mov rdi, rbx
    call pjs_print_comment
    mov r14, rax
    mov rdi, r14
    mov rsi, rsp
    call pjc_debug_docs_one
    lea rdi, [rip + d_hardline]
    mov rsi, r14
    call doc_array2
    mov rdi, rax
    call doc_indent
    mov rdi, rax
    mov rsi, rsp
    call pjc_debug_docs_one
    inc r13
    jmp 1b
9:  EPILOGUE
ENDF pjc_debug_docs

# pjc_debug_docs_one(doc, options): "<length>\n<text>\n" of the doc printed
# with the PO_* options
FUNC pjc_debug_docs_one
    PROLOGUE
    call print_doc_to_string
    mov rbx, rax
    mov r12, rdx
    mov edi, r12d
    call jd_u32
    mov edi, 10
    call out_byte
    mov rdi, rbx
    mov rsi, r12
    call out_bytes
    mov edi, 10
    call out_byte
    EPILOGUE
ENDF pjc_debug_docs_one

# pjc_dump_node(node): "<Type> <start> <end>"
FUNC pjc_dump_node
    PROLOGUE
    mov rbx, rdi
    movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_type_names]
    mov rdi, [rcx + rax*8]
    call jd_cstr
    mov edi, ' '
    call out_byte
    mov edi, [rbx + N_START]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov edi, [rbx + N_END]
    call jd_pos
    EPILOGUE
ENDF pjc_dump_node

# pjc_nth_cstr(list, n) -> rax: the n-th string of consecutive asciz strings
FUNC pjc_nth_cstr
    mov rax, rdi
1:  test esi, esi
    jz 9f
2:  cmp byte ptr [rax], 0
    je 3f
    inc rax
    jmp 2b
3:  inc rax
    dec esi
    jmp 1b
9:  leave
    ret
ENDF pjc_nth_cstr

# pjc_dump_comment(comment, owner)
FUNC pjc_dump_comment
    PROLOGUE
    mov rbx, rdi
    mov r12, rsi
    mov edi, [rbx + CM_START]
    call jd_pos
    mov edi, ' '
    call out_byte
    mov edi, [rbx + CM_END]
    call jd_pos
    mov edi, ' '
    call out_byte
    lea rdi, [rip + s_ct_names]
    movzx esi, byte ptr [rbx + CM_TYPE]
    call pjc_nth_cstr
    mov rdi, rax
    call jd_cstr
    mov edi, ' '
    call out_byte
    lea rdi, [rip + s_pl_names]
    movzx esi, byte ptr [rbx + CM_PLACEMENT]
    call pjc_nth_cstr
    mov rdi, rax
    call jd_cstr
    test r12, r12
    jnz 1f
    lea rdi, [rip + s_unattached]
    call jd_cstr
    jmp 5f
1:  lea rdi, [rip + s_dangling]
    test byte ptr [rbx + CM_FLAGS], CF_LEADING
    jz 2f
    lea rdi, [rip + s_leading]
2:  test byte ptr [rbx + CM_FLAGS], CF_TRAILING
    jz 3f
    lea rdi, [rip + s_trailing]
3:  call jd_cstr
    mov rdi, r12
    call pjc_dump_node
5:  mov rax, [rbx + CM_MARKER]
    test rax, rax
    jz 6f
    lea rdi, [rip + s_marker]
    call jd_cstr
    mov rdi, [rbx + CM_MARKER]
    call jd_cstr
6:  test byte ptr [rbx + CM_FLAGS], CF_UNIGNORE
    jz 7f
    lea rdi, [rip + s_unignore]
    call jd_cstr
7:  mov edi, 10
    call out_byte
    EPILOGUE
ENDF pjc_dump_comment

# pjc_comment_index(comment) -> rax: its index in g_comments (sorted by start)
FUNC pjc_comment_index
    mov r8, [rip + g_comments]
    mov esi, [rdi + CM_START]
    xor ecx, ecx                        # lo
    mov edx, [r8]                       # hi
1:  cmp ecx, edx
    jae 8f
    lea eax, [rcx + rdx]
    shr eax, 1
    mov r9, [r8 + 8 + rax*8]
    cmp esi, [r9 + CM_START]
    je 9f
    jb 2f
    lea ecx, [rax + 1]
    jmp 1b
2:  mov edx, eax
    jmp 1b
8:  REFUSE "--debug-comments: a node holds a comment that is not in the list"
9:  leave
    ret
ENDF pjc_comment_index

# pjc_collect(node): records the node of each attached comment and the nodes
# flagged prettierIgnore, then visits the children by visitor keys
FUNC pjc_collect
    PROLOGUE
    mov rbx, rdi
    test word ptr [rbx + N_FLAGS], NF_PRETTIER_IGNORE
    jz 1f
    mov rdi, [rip + pjc_ignored]
    mov rsi, rbx
    call list_push
    mov [rip + pjc_ignored], rax
1:  mov r12, [rbx + N_COMMENTS]
    test r12, r12
    jz 3f
    xor r13d, r13d
2:  cmp r13d, [r12]
    jae 3f
    mov rdi, [r12 + 8 + r13*8]
    call pjc_comment_index
    mov rcx, [rip + pjc_owners]
    mov [rcx + rax*8], rbx
    inc r13
    jmp 2b
3:  movzx eax, word ptr [rbx + N_TYPE]
    lea rcx, [rip + ast_visitor_keys]
    mov r12, [rcx + rax*8]
4:  movzx eax, byte ptr [r12]
    test eax, eax
    jz 9f
    inc r12
    test eax, VK_VEC
    jnz 5f
    mov rdi, [rbx + rax]
    test rdi, rdi
    jz 4b
    call pjc_collect
    jmp 4b
5:  and eax, VK_VEC - 1
    mov r13, [rbx + rax]
    test r13, r13
    jz 4b
    xor r14d, r14d
6:  cmp r14, [r13]
    jae 4b
    mov rdi, [r13 + 8 + r14*8]
    inc r14
    test rdi, rdi
    jz 6b
    call pjc_collect
    jmp 6b
9:  EPILOGUE
ENDF pjc_collect
