# The main print loop of src/main/ast-to-doc.js: mainPrint, its cache,
# callPluginPrintFunction (prettier-ignore, comments), printIgnored, and the
# print(selector, args) forms printers call. The printer's methods come from
# the record g_printer points at (PR_*).
#
# `args` is a pointer to an ARGS_* record, or 0 for undefined. Only a print
# with args 0 is cached, as in Prettier.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_printer
g_printer: .quad 0

    .data
    .balign 8
    .globl args_by_layout
# print(key, { assignmentLayout }) for each layout: an args record per AL_*
args_by_layout:
    .rept AL_COUNT
    .byte 0, 0, 0, 0, 0, 0, 0, 0
    .endr

    .text

# args_for_layout(layout) -> rax: the args record { assignmentLayout: layout }
FUNC args_for_layout
    lea rax, [rip + args_by_layout]
    lea rax, [rax + rdi*8]
    mov [rax + ARGS_ASSIGNMENT_LAYOUT], dil
    leave
    ret
ENDF args_for_layout

# print_ast_root(root) -> rax doc: printAstToDoc after attachComments:
# the path is [root], then callPluginPrintFunction without a cache.
FUNC print_ast_root
    push rbx
    sub rsp, 8
    mov rbx, rdi
    call path_init
    xor edi, edi
    call call_plugin_print
    add rsp, 8
    pop rbx
    leave
    ret
ENDF print_ast_root

# main_print_here(args) -> rax doc: mainPrintInternal for the node at the top
# of the path (print() with no selector).
FUNC main_print_here
    push rbx
    push r12
    mov r12, rdi
    call path_value
    mov rbx, rax
    test rbx, rbx
    jz 9f
    test r12, r12
    jnz 1f
    test word ptr [rbx + N_FLAGS], NF_DOC_CACHED
    jz 1f
    mov rax, [rbx + N_DOC]
    jmp 9f
1:  mov rdi, r12
    call call_plugin_print
    test r12, r12
    jnz 9f
    mov [rbx + N_DOC], rax
    or word ptr [rbx + N_FLAGS], NF_DOC_CACHED
9:  pop r12
    pop rbx
    leave
    ret
ENDF main_print_here

# main_print(node, key, index, args) -> rax doc: print a node that is not a
# field of the current one (or whose selector the caller resolved); index -1
# outside arrays.
FUNC main_print
    xor eax, eax
    test rdi, rdi
    jz 9f
    push rcx
    sub rsp, 8
    xor ecx, ecx
    call path_push
    add rsp, 8
    pop rdi
    call main_print_here
    sub qword ptr [rip + g_path_top], PE_SIZE
9:  leave
    ret
ENDF main_print

# print_field(field_offset, key, args) -> rax doc: print("key")
FUNC print_field
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    call path_value
    mov rdi, [rax + rbx]
    mov esi, r12d
    mov edx, -1
    mov rcx, r13
    call main_print
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_field

# print_elem(vec, index, key, args) -> rax doc: print([key, index])
FUNC print_elem
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    xor eax, eax
    mov rdi, [rbx + 8 + r12*8]
    test rdi, rdi
    jz 9f
    mov esi, r13d
    mov edx, r12d
    mov rcx, rbx
    call path_push
    mov rdi, r14
    call main_print_here
    sub qword ptr [rip + g_path_top], PE_SIZE
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF print_elem

# print_map(field_offset, key, args) -> rax: VEC of docs, path.map(print, key).
# A hole (0 element) prints as "".
FUNC print_map
    push rbx
    push r12
    mov r12, rdx
    mov ecx, edi
    mov edx, esi
    lea rdi, [rip + pm_print_one]
    mov rsi, r12
    call path_map
    pop r12
    pop rbx
    leave
    ret
ENDF print_map

# pm_print_one(args, node, index) -> rax
FUNC pm_print_one
    xor eax, eax
    test rsi, rsi
    jz 1f
    call main_print_here
1:  leave
    ret
ENDF pm_print_one

# call_plugin_print(args) -> rax doc (callPluginPrintFunction): the printer's
# print, or printIgnored when the printer has hasPrettierIgnore and it says so;
# then printComments unless the printer prints this node's comments itself.
# Cursors are not ported.
FUNC call_plugin_print
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, [rip + g_printer]
    call path_value
    mov rbx, rax
    mov rax, [r13 + PR_HAS_PRETTIER_IGNORE]
    test rax, rax
    jz 1f
    call rax
    test eax, eax
    jz 1f
    mov rdi, rbx
    call print_ignored
    jmp 2f
1:  mov rdi, rbx
    mov rsi, r12
    call [r13 + PR_PRINT]
2:  mov r14, rax
    cmp qword ptr [r13 + PR_PRINT_COMMENT], 0
    je 8f
    mov rax, [r13 + PR_WILL_PRINT_OWN_COMMENTS]
    test rax, rax
    jz 3f
    call rax
    test eax, eax
    jnz 8f
3:  mov rdi, rbx
    mov rsi, r14
    call print_comments
    mov r14, rax
8:  mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF call_plugin_print

# print_ignored(node) -> rax: printIgnored, the original text; the comments
# inside count as printed.
FUNC print_ignored
    push rbx
    push r12
    mov rbx, rdi
    mov rcx, [rip + g_comments]
    test rcx, rcx
    jz 3f
    xor edx, edx
1:  cmp edx, [rcx]
    jae 3f
    mov rax, [rcx + 8 + rdx*8]
    mov r8d, [rax + CM_START]
    cmp r8d, [rbx + N_START]
    jb 2f
    mov r8d, [rax + CM_END]
    cmp r8d, [rbx + N_END]
    ja 2f
    or byte ptr [rax + CM_FLAGS], CF_IGNORED
2:  inc edx
    jmp 1b
3:  mov edi, [rbx + N_START]
    mov esi, [rbx + N_END]
    call doc_text
    pop r12
    pop rbx
    leave
    ret
ENDF print_ignored
