# A hash map from nonzero 64-bit keys (usually pointers) to 64-bit values, in
# the arena. Open addressing with linear probing; it doubles when half full.
# Map record: +0 table, +8 capacity (a power of two), +16 count.
# Table slot: key, value.
.include "defs.inc"

.equ PM_TABLE, 0
.equ PM_CAP, 8
.equ PM_COUNT, 16
.equ PM_SIZE, 24

# ptrmap_new(capacity) -> rax. capacity is rounded up to a power of two >= 16.
FUNC ptrmap_new
    push rbx
    push r12
    mov ebx, 16
1:  cmp rbx, rdi
    jae 2f
    shl rbx, 1
    jmp 1b
2:  mov edi, PM_SIZE
    call alloc
    mov r12, rax
    mov [r12 + PM_CAP], rbx
    mov rdi, rbx
    shl rdi, 4
    call alloc
    mov [r12 + PM_TABLE], rax
    mov rax, r12
    pop r12
    pop rbx
    leave
    ret
ENDF ptrmap_new

# pm_hash: rdi key, rsi capacity -> rax slot index. Leaf, no frame.
pm_hash:
    mov rax, rdi
    shr rax, 3
    xor rax, rdi
    mov rcx, 0x9E3779B97F4A7C15
    imul rax, rcx
    shr rax, 20
    lea rcx, [rsi - 1]
    and rax, rcx
    ret

# ptrmap_get(map, key) -> rax = value, edx = 1 when present
FUNC ptrmap_get
    mov r8, rdi
    mov rdi, rsi
    mov rsi, [r8 + PM_CAP]
    call pm_hash
    mov r9, [r8 + PM_TABLE]
    lea r10, [rsi - 1]
1:  mov rcx, rax
    shl rcx, 4
    mov r11, [r9 + rcx]
    test r11, r11
    jz 8f
    cmp r11, rdi
    je 9f
    inc rax
    and rax, r10
    jmp 1b
8:  xor eax, eax
    xor edx, edx
    leave
    ret
9:  mov rax, [r9 + rcx + 8]
    mov edx, 1
    leave
    ret
ENDF ptrmap_get

# ptrmap_slot(map, key) -> rax: address of the value slot, inserting the key
# with value 0 when absent; edx = 1 when the key was present.
FUNC ptrmap_slot
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    # grow at half full
    mov rax, [rbx + PM_COUNT]
    shl rax, 1
    cmp rax, [rbx + PM_CAP]
    jb 1f
    mov rdi, rbx
    call pm_grow
1:  mov rdi, r12
    mov rsi, [rbx + PM_CAP]
    call pm_hash
    mov r9, [rbx + PM_TABLE]
    lea r10, [rsi - 1]
2:  mov rcx, rax
    shl rcx, 4
    mov r11, [r9 + rcx]
    test r11, r11
    jz 3f
    cmp r11, r12
    je 4f
    inc rax
    and rax, r10
    jmp 2b
3:  mov [r9 + rcx], r12
    inc qword ptr [rbx + PM_COUNT]
    lea rax, [r9 + rcx + 8]
    xor edx, edx
    jmp 9f
4:  lea rax, [r9 + rcx + 8]
    mov edx, 1
9:  pop r12
    pop rbx
    leave
    ret
ENDF ptrmap_slot

# ptrmap_put(map, key, value)
FUNC ptrmap_put
    push rdx
    sub rsp, 8
    call ptrmap_slot
    add rsp, 8
    pop rdx
    mov [rax], rdx
    leave
    ret
ENDF ptrmap_put

# pm_grow(map): double the table
FUNC pm_grow
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rbx + PM_TABLE]
    mov r13, [rbx + PM_CAP]
    lea rdi, [r13 * 2]
    mov [rbx + PM_CAP], rdi
    shl rdi, 4
    call alloc
    mov [rbx + PM_TABLE], rax
    xor r14d, r14d
1:  cmp r14, r13
    jae 9f
    mov rdi, r14
    shl rdi, 4
    mov rdx, [r12 + rdi + 8]
    mov rdi, [r12 + rdi]
    inc r14
    test rdi, rdi
    jz 1b
    # reinsert
    push rdx
    push rdi
    mov rsi, [rbx + PM_CAP]
    call pm_hash
    pop rdi
    pop rdx
    mov r9, [rbx + PM_TABLE]
    mov r10, [rbx + PM_CAP]
    dec r10
2:  mov rcx, rax
    shl rcx, 4
    cmp qword ptr [r9 + rcx], 0
    je 3f
    inc rax
    and rax, r10
    jmp 2b
3:  mov [r9 + rcx], rdi
    mov [r9 + rcx + 8], rdx
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF pm_grow
