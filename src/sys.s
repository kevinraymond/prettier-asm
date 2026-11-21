# Raw syscalls and byte helpers. No libc.
.include "defs.inc"

# write_all(fd, buf, len): retries on short writes and EINTR, ignores errors.
FUNC write_all
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
1:  test r13, r13
    jz 3f
    mov eax, SYS_write
    mov edi, ebx
    mov rsi, r12
    mov rdx, r13
    syscall
    cmp rax, -4                 # EINTR
    je 1b
    test rax, rax
    jle 3f
    add r12, rax
    sub r13, rax
    jmp 1b
3:  add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF write_all

# write_cstr(fd, cstr)
FUNC write_cstr
    push rdi
    push rsi
    mov rdi, rsi
    call strlen
    mov rdx, rax
    pop rsi
    pop rdi
    call write_all
    leave
    ret
ENDF write_cstr

# exit(code): never returns.
FUNC sys_exit
    mov eax, SYS_exit_group
    syscall
    hlt
ENDF sys_exit

# strlen(cstr) -> rax
FUNC strlen
    mov rax, rdi
1:  cmp byte ptr [rax], 0
    je 2f
    inc rax
    jmp 1b
2:  sub rax, rdi
    leave
    ret
ENDF strlen

# memcpy(dst, src, n) -> rax = dst
FUNC memcpy
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    leave
    ret
ENDF memcpy

# mem_eq(a, b, n) -> rax = 1 if equal
FUNC mem_eq
    mov rcx, rdx
    xor eax, eax
    repe cmpsb
    sete al
    leave
    ret
ENDF mem_eq

# cstr_eq(a, b) -> rax = 1 if equal
FUNC cstr_eq
1:  mov al, [rdi]
    cmp al, [rsi]
    jne 2f
    test al, al
    jz 3f
    inc rdi
    inc rsi
    jmp 1b
2:  xor eax, eax
    leave
    ret
3:  mov eax, 1
    leave
    ret
ENDF cstr_eq

# cstr_prefix(str, prefix) -> rax = 1 if str starts with prefix
FUNC cstr_prefix
1:  mov al, [rsi]
    test al, al
    jz 3f
    cmp al, [rdi]
    jne 2f
    inc rdi
    inc rsi
    jmp 1b
2:  xor eax, eax
    leave
    ret
3:  mov eax, 1
    leave
    ret
ENDF cstr_prefix
