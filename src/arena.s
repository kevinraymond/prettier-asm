# Memory: one MAP_NORESERVE reservation carved into fixed regions.
# The arena is a bump allocator that is never freed; fresh memory is zero.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_mem_base, g_arena_ptr, g_arena_end, g_ss_ptr, g_ss_base
g_mem_base:  .quad 0
g_arena_ptr: .quad 0
g_arena_end: .quad 0
g_ss_base:   .quad 0
g_ss_ptr:    .quad 0
g_ss_end:    .quad 0

# mem_init(): reserve all regions. Refuses if the kernel says no.
FUNC mem_init
    mov eax, SYS_mmap
    xor edi, edi
    mov rsi, REGION_SIZE * R_COUNT
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON_NORESERVE
    mov r8, -1
    xor r9d, r9d
    syscall
    cmp rax, -4096
    ja 9f
    mov [rip + g_mem_base], rax
    mov [rip + g_arena_ptr], rax
    # With transparent huge pages on, the first touch of each region would
    # zero a 2 MiB page; small inputs touch a few 4 KiB pages instead.
    push rax
    sub rsp, 8
    mov rdi, rax
    mov eax, SYS_madvise
    mov rsi, REGION_SIZE * R_COUNT
    mov edx, MADV_NOHUGEPAGE
    syscall
    add rsp, 8
    pop rax
    mov rcx, rax
    mov rdx, REGION_SIZE * 8
    add rcx, rdx
    mov [rip + g_arena_end], rcx
    mov rdi, R_SCRATCH
    call region_base
    mov [rip + g_ss_base], rax
    mov [rip + g_ss_ptr], rax
    add rax, REGION_SIZE
    mov [rip + g_ss_end], rax
    leave
    ret
9:  REFUSE "cannot reserve memory"
ENDF mem_init

# region_base(index) -> rax
FUNC region_base
    mov rax, rdi
    imul rax, rax, REGION_SIZE
    add rax, [rip + g_mem_base]
    leave
    ret
ENDF region_base

# alloc(size) -> rax: zeroed, 8-byte aligned.
FUNC alloc
    mov rax, [rip + g_arena_ptr]
    add rdi, 7
    and rdi, -8
    lea rdx, [rax + rdi]
    cmp rdx, [rip + g_arena_end]
    ja 9f
    mov [rip + g_arena_ptr], rdx
    leave
    ret
9:  REFUSE "arena exhausted"
ENDF alloc

# alloc_copy(src, len) -> rax: copy of len bytes.
FUNC alloc_copy
    push rdi
    push rsi
    mov rdi, rsi
    call alloc
    pop rdx
    pop rsi
    mov rdi, rax
    call memcpy
    leave
    ret
ENDF alloc_copy

# ---------------------------------------------------------------- scratch stack
# List builders push 8-byte values here, then copy them out with ss_to_vec or
# ss_to_array. A builder remembers ss_mark() and must finish before an outer
# builder pushes again.

# ss_mark() -> rax
FUNC ss_mark
    mov rax, [rip + g_ss_ptr]
    leave
    ret
ENDF ss_mark

# ss_push(value)
FUNC ss_push
    mov rax, [rip + g_ss_ptr]
    cmp rax, [rip + g_ss_end]
    jae 9f
    mov [rax], rdi
    add rax, 8
    mov [rip + g_ss_ptr], rax
    leave
    ret
9:  REFUSE "scratch stack exhausted"
ENDF ss_push

# ss_to_vec(mark) -> rax: VEC of the values pushed since mark; pops them.
FUNC ss_to_vec
    push rbx
    push r12
    mov rbx, rdi
    mov r12, [rip + g_ss_ptr]
    sub r12, rbx                    # bytes
    lea rdi, [r12 + 8]
    call alloc
    mov rcx, r12
    shr rcx, 3
    mov [rax], rcx
    lea rdi, [rax + 8]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    mov [rip + g_ss_ptr], rbx
    pop r12
    pop rbx
    leave
    ret
ENDF ss_to_vec

# ss_to_array(mark) -> rax: DK_ARRAY doc of the docs pushed since mark.
# Zero (empty) docs are dropped, as they print nothing.
FUNC ss_to_array
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rip + g_ss_ptr]
    # count non-zero items
    xor r13d, r13d
    mov rcx, rbx
1:  cmp rcx, r12
    jae 2f
    cmp qword ptr [rcx], 0
    je 3f
    inc r13
3:  add rcx, 8
    jmp 1b
2:  lea rdi, [r13*8 + DA_ITEMS]
    call alloc
    mov byte ptr [rax], DK_ARRAY
    mov [rax + DA_COUNT], r13d
    lea rdi, [rax + DA_ITEMS]
    mov rcx, rbx
4:  cmp rcx, r12
    jae 5f
    mov rdx, [rcx]
    test rdx, rdx
    jz 6f
    mov [rdi], rdx
    add rdi, 8
6:  add rcx, 8
    jmp 4b
5:  mov [rip + g_ss_ptr], rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF ss_to_array

# ss_to_array_keep(mark) -> rax: like ss_to_array but keeps empty docs.
# fill() needs its parts at fixed positions.
FUNC ss_to_array_keep
    push rbx
    push r12
    mov rbx, rdi
    mov r12, [rip + g_ss_ptr]
    sub r12, rbx
    lea rdi, [r12 + DA_ITEMS]
    call alloc
    mov byte ptr [rax], DK_ARRAY
    mov rcx, r12
    shr rcx, 3
    mov [rax + DA_COUNT], ecx
    lea rdi, [rax + DA_ITEMS]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
    mov [rip + g_ss_ptr], rbx
    pop r12
    pop rbx
    leave
    ret
ENDF ss_to_array_keep

# ---------------------------------------------------------------- growable lists
# list_push(list_or_0, value) -> rax = list (possibly moved)
FUNC list_push
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jnz 1f
    mov edi, 8 + 4*8
    call alloc
    mov dword ptr [rax + 4], 4
    mov rbx, rax
1:  mov ecx, [rbx]
    cmp ecx, [rbx + 4]
    jb 2f
    # grow: double the capacity
    mov edi, [rbx + 4]
    shl edi, 4                      # 2*cap*8
    add edi, 8
    call alloc
    mov ecx, [rbx + 4]
    shl ecx, 1
    mov [rax + 4], ecx
    mov ecx, [rbx]
    mov [rax], ecx
    lea rdi, [rax + 8]
    lea rsi, [rbx + 8]
    shl ecx, 3
    rep movsb
    mov rbx, rax
2:  mov ecx, [rbx]
    mov [rbx + 8 + rcx*8], r12
    inc ecx
    mov [rbx], ecx
    mov rax, rbx
    pop r12
    pop rbx
    leave
    ret
ENDF list_push
