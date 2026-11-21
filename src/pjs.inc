# Macros for the JS printer (src/pjs_*.s). See "JS printer" in README.md.
.include "defs.inc"

# PROLOGUE n / EPILOGUE: after FUNC, save rbx and r12-r15 and reserve n quadword
# locals at [rsp], [rsp + 8], ...; the stack stays 16-byte aligned. EPILOGUE
# restores them from any point of the function and returns.
.macro PROLOGUE n=0
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8 + ((\n + 1) / 2) * 16
.endm

.macro EPILOGUE
    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
.endm

# Doc arrays on the scratch stack. ss_push clobbers only rax.
.macro DMARK reg
    call ss_mark
    mov \reg, rax
.endm
.macro DPUSH src
    mov rdi, \src
    call ss_push
.endm
.macro DPUSHL sym
    lea rdi, [rip + \sym]
    call ss_push
.endm
# DARRAY reg: rax = the array of the docs pushed since mark reg ("" dropped)
.macro DARRAY reg
    mov rdi, \reg
    call ss_to_array
.endm
.macro DARRAYK reg
    mov rdi, \reg
    call ss_to_array_keep
.endm

# rax = group(rax) / indent(rax) / group(rax, {shouldBreak: true})
.macro GROUP_RAX
    mov rdi, rax
    xor esi, esi
    call doc_group
.endm
.macro GROUP_BREAK_RAX
    mov rdi, rax
    mov esi, 1
    call doc_group
.endm
.macro INDENT_RAX
    mov rdi, rax
    call doc_indent
.endm

# PRINT off, key: rax = print("key") of the current node (field at offset off)
.macro PRINT off, key
    mov edi, \off
    mov esi, \key
    xor edx, edx
    call print_field
.endm
# PRINT_ARGS off, key, args: print("key", args); args is a register or memory
.macro PRINT_ARGS off, key, args
    mov rdx, \args
    mov edi, \off
    mov esi, \key
    call print_field
.endm

# Type tests: flags from comparing node.type
.macro TYPE reg, t
    cmp word ptr [\reg + N_TYPE], \t
.endm
# ATTR reg, bit: ZF clear when the NA_* bit is set
.macro ATTR reg, bit
    test dword ptr [\reg + N_ATTR], \bit
.endm

# VLEN dst, vec: dst = element count of a VEC field value (0 or js_empty_vec when empty)
.macro VLEN dst, vec
    test \vec, \vec
    jz .Lvlenz\@
    mov \dst, [\vec]
    jmp .Lvlen\@
.Lvlenz\@:
    xor \dst, \dst
.Lvlen\@:
.endm

# Global static string doc.
.macro GSDOC label, text
    .globl \label
    SDOC \label, "\text"
.endm
