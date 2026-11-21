# Input reading and the output buffer.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_input, g_input_len, g_out_base, g_out_ptr
g_input:     .quad 0
g_input_len: .quad 0
g_out_base:  .quad 0
g_out_ptr:   .quad 0

# read_fd_all(fd) -> rax = 0 on success. Fills g_input/g_input_len.
FUNC read_fd_all
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    mov rdi, R_INPUT
    call region_base
    mov [rip + g_input], rax
    mov r12, rax                    # write cursor
    lea r13, [rax + REGION_SIZE]    # end
1:  mov rdx, r13
    sub rdx, r12
    jz 8f
    cmp rdx, 0x100000
    jbe 2f
    mov edx, 0x100000
2:  mov eax, SYS_read
    mov edi, ebx
    mov rsi, r12
    syscall
    cmp rax, -4
    je 1b
    test rax, rax
    js 9f
    jz 3f
    add r12, rax
    jmp 1b
3:  mov rax, r12
    sub rax, [rip + g_input]
    mov [rip + g_input_len], rax
    xor eax, eax
    jmp 7f
8:  REFUSE "input too large"
9:  mov eax, 1
7:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF read_fd_all

# read_file(cstr_path) -> rax = 0 on success.
FUNC read_file
    push rbx
    push r12
    # Prettier refuses a file argument that is a symbolic link
    mov eax, SYS_open
    mov esi, O_NOFOLLOW | O_CLOEXEC
    xor edx, edx
    syscall
    test rax, rax
    js 9f
    mov rbx, rax
    mov rdi, rax
    call read_fd_all
    mov r12, rax
    mov eax, SYS_close
    mov rdi, rbx
    syscall
    mov rax, r12
    jmp 8f
9:  mov eax, 1
8:  pop r12
    pop rbx
    leave
    ret
ENDF read_file

# out_init()
FUNC out_init
    mov rdi, R_OUT
    call region_base
    mov [rip + g_out_base], rax
    mov [rip + g_out_ptr], rax
    leave
    ret
ENDF out_init

# out_bytes(ptr, len)
FUNC out_bytes
    mov rax, [rip + g_out_ptr]
    lea rcx, [rax + rsi]
    mov r8, [rip + g_out_base]
    add r8, REGION_SIZE
    cmp rcx, r8
    ja 9f
    mov [rip + g_out_ptr], rcx
    mov rcx, rsi
    mov rsi, rdi
    mov rdi, rax
    rep movsb
    leave
    ret
9:  REFUSE "output too large"
ENDF out_bytes

# out_byte(c)
FUNC out_byte
    mov rax, [rip + g_out_ptr]
    mov [rax], dil
    inc rax
    mov [rip + g_out_ptr], rax
    leave
    ret
ENDF out_byte

# out_spaces(n)
FUNC out_spaces
    mov rcx, rdi
    mov rdi, [rip + g_out_ptr]
    mov al, ' '
    rep stosb
    mov [rip + g_out_ptr], rdi
    leave
    ret
ENDF out_spaces

# out_trim() -> rax = number of trailing spaces/tabs removed from the output.
FUNC out_trim
    mov rcx, [rip + g_out_ptr]
    mov rdx, [rip + g_out_base]
    mov rax, rcx
1:  cmp rcx, rdx
    jbe 2f
    mov r8b, [rcx - 1]
    cmp r8b, ' '
    je 3f
    cmp r8b, 9
    jne 2f
3:  dec rcx
    jmp 1b
2:  mov [rip + g_out_ptr], rcx
    sub rax, rcx
    leave
    ret
ENDF out_trim
