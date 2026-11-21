# Macros and context bits shared by parse_js*.s.

# Parser context (g_px), after Babel's prodParam and scope flags.
.equ CX_AWAIT, 1            # `await` starts an AwaitExpression
.equ CX_YIELD, 2            # `yield` starts a YieldExpression
.equ CX_FUNC, 4             # inside a function (scope.inFunction)
.equ CX_CLASS_INIT, 8       # class field initializer or static block, not inside a function
.equ CX_NO_IN, 16           # `in` is not a binary operator (for-init)
.equ CX_STATIC_BLOCK, 32
.equ CX_GEN_PARAMS, 64      # parameters of a generator or async function
.equ CX_NO_RETURN, 128      # directly in a class static block

# Label stack entry
.equ LB_START, 0            # name start, or -1 for a loop or switch entry
.equ LB_LEN, 4
.equ LB_KIND, 8             # 1 loop, 2 switch, 0 other
.equ LB_STMT, 12            # start of the labeled statement
.equ LB_SIZE, 16
.equ LB_MAX, 1024

# ZF set when the current token has type t.
.macro TT_IS t
    cmp qword ptr [rip + g_jt_type], \t
.endm

# ZF set when the current token is the word with keyword id k.
.macro KW_IS k
    cmp qword ptr [rip + g_jt_kw], \k
.endm

.macro NEXT
    call jl_next
.endm

# Refuses unless the current token has type t, then advances.
.macro EXPECT t
    mov edi, \t
    call js_expect
.endm

# rax = new node of type t starting at src (register or memory).
.macro NODE t, src
    mov rsi, \src
    mov edi, \t
    call js_node
.endm

# Sets node.end to the end of the previous token.
.macro FINISH reg
    mov r11d, [rip + g_jt_last_end]
    mov [\reg + N_END], r11d
.endm

.macro SYNTAX_ERROR
    call js_syntax_error
.endm

# In the parser, a refusal whose reason starts with "syntax error" unwinds to the innermost
# js_try (Babel's tryParse) when one is active; other reasons refuse the file.
.purgem REFUSE
.macro REFUSE text
    .pushsection .rodata.refuse, "a"
.Lrefuse\@: .asciz "\text"
    .popsection
    lea rdi, [rip + .Lrefuse\@]
    call js_refuse
.endm

# TypeScript state (g_ts), after Babel's state flags. Saved and restored with the rest of the
# parser state by js_try.
.equ TS_ON, 1               # the file is TypeScript
.equ TS_IN_TYPE, 2          # state.inType: `<` and `>` are one-character tokens
.equ TS_NO_COND, 4          # state.inDisallowConditionalTypesContext
.equ TS_AMBIENT, 8          # state.isAmbientContext
.equ TS_ABSTRACT_CLASS, 16  # state.inAbstractClass
.equ TS_ARROW_PARAMS, 32    # state.maybeInArrowParameters

.macro IF_TS label
    test qword ptr [rip + g_ts], TS_ON
    jnz \label
.endm

.macro IF_NOT_TS label
    test qword ptr [rip + g_ts], TS_ON
    jz \label
.endm

# ENTER5 n / LEAVE5 n: saves rbx and r12 to r15 and reserves n bytes (n = 8 mod 16, so calls
# are aligned), then undoes that and returns. The reserved bytes start at [rsp].
.macro ENTER5 n
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, \n
.endm

.macro LEAVE5 n
    add rsp, \n
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
.endm

# TS_SAVE slot / TS_RESTORE bits, slot: Babel's `const old = state.flag; ... state.flag = old` for
# the g_ts bits in `bits`.
.macro TS_SAVE slot
    mov rax, [rip + g_ts]
    mov \slot, rax
.endm

.macro TS_RESTORE bits, slot
    mov rax, \slot
    and rax, \bits
    and qword ptr [rip + g_ts], ~(\bits)
    or [rip + g_ts], rax
.endm

# TypeScript modifier bits (jts_modifiers, Babel's tsParseModifiers)
.equ M_PUBLIC, 1
.equ M_PRIVATE, 2
.equ M_PROTECTED, 4
.equ M_DECLARE, 8
.equ M_ABSTRACT, 16
.equ M_OVERRIDE, 32
.equ M_READONLY, 64
.equ M_STATIC, 128
.equ M_IN, 256
.equ M_OUT, 512
.equ M_CONST, 1024
.equ M_ACCESS, M_PUBLIC | M_PRIVATE | M_PROTECTED

# jpe_maybe_assign flags
.equ MA_REF, 1              # the caller keeps an expression error record
.equ MA_PAREN_ITEM, 2       # TypeScript's parseParenItem applies to the left side
.equ MA_NO_LT, 4            # Babel's super.parseMaybeAssign: no TypeScript `<` handling here

# js_try status (edx)
.equ TRY_THROWN, 0
.equ TRY_OK, 1
.equ TRY_ABORTED, 2

# js_source_is_script result bits
.equ JS_SRC_SCRIPT, 1
.equ JS_SRC_TS, 2
