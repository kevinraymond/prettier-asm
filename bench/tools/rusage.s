# rusage <outfile> <command> [args...]: runs the command (fork, execve with the same environment,
# stdin, stdout and stderr), waits with wait4 and writes one line to <outfile>:
#   maxrss_kb=N utime_us=N stime_us=N status=N
# then the child's /proc/<pid>/smaps_rollup as it was when the child called exit (ptrace with
# PTRACE_O_TRACEEXIT stops it there, before its memory is released). ru_maxrss comes from
# counters Linux keeps in per-CPU batches, so it reads low by up to a few hundred KiB; the Rss
# line of smaps_rollup is counted from the page tables. status is the raw wait status.
# Static and libc-free, so its own memory (a few pages) is all the child inherits through fork;
# Linux carries the pre-exec peak into ru_maxrss.
.intel_syntax noprefix
.globl _start
.text
_start:
    mov rax, [rsp]                  # argc
    cmp rax, 3
    jb fail
    lea r13, [rsp + 8]              # argv
    lea r14, [r13 + rax*8 + 8]      # envp
    mov eax, 57                     # fork
    syscall
    test rax, rax
    js fail
    jz child
    mov r15, rax
    xor ebx, ebx                    # rbx: smaps_rollup bytes read
    call wait_child                 # the stop after execve
    mov edi, 0x4200                 # PTRACE_SETOPTIONS
    mov rsi, r15
    xor edx, edx
    mov r10d, 0x40                  # PTRACE_O_TRACEEXIT
    mov eax, 101                    # ptrace
    syscall
    xor r10d, r10d                  # signal to pass on
1:  mov edi, 7                      # PTRACE_CONT
    mov rsi, r15
    xor edx, edx
    mov eax, 101
    syscall
    call wait_child
    mov eax, [rip + wstatus]
    cmp al, 0x7f                    # stopped?
    jne 3f
    shr eax, 8
    cmp eax, 0x605                  # SIGTRAP | PTRACE_EVENT_EXIT << 8
    jne 2f
    call read_rollup
    xor r10d, r10d
    jmp 1b
2:  movzx r10d, al                  # another signal: deliver it
    cmp r10d, 5                     # a plain SIGTRAP is ptrace's, not the program's
    jne 1b
    xor r10d, r10d
    jmp 1b
3:
    lea rdi, [rip + out]            # build the line in out
    lea rsi, [rip + s_maxrss]
    call puts
    mov rax, [rip + ru + 32]        # ru_maxrss, KiB
    call putu
    lea rsi, [rip + s_utime]
    call puts
    mov rax, [rip + ru + 0]         # ru_utime.tv_sec
    imul rax, rax, 1000000
    add rax, [rip + ru + 8]         # tv_usec
    call putu
    lea rsi, [rip + s_stime]
    call puts
    mov rax, [rip + ru + 16]
    imul rax, rax, 1000000
    add rax, [rip + ru + 24]
    call putu
    lea rsi, [rip + s_status]
    call puts
    mov eax, [rip + wstatus]
    call putu
    mov byte ptr [rdi], 10
    inc rdi
    lea rax, [rip + out]
    sub rdi, rax
    mov r12, rdi                    # length
    mov rdi, [r13 + 8]              # outfile
    mov esi, 0x241                  # O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644
    mov eax, 2                      # open
    syscall
    test rax, rax
    js fail
    mov edi, eax
    mov r14d, eax
    lea rsi, [rip + out]
    mov rdx, r12
    mov eax, 1                      # write (the line is short: one call)
    syscall
    cmp rax, r12
    jne fail
    mov edi, r14d
    lea rsi, [rip + rollup]
    mov rdx, rbx
    mov eax, 1
    syscall
    cmp rax, rbx
    jne fail
    mov eax, 60
    xor edi, edi
    syscall

child:
    xor edi, edi                    # PTRACE_TRACEME
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 101
    syscall
    mov rdi, [r13 + 16]             # argv[2]
    lea rsi, [r13 + 16]
    mov rdx, r14
    mov eax, 59                     # execve
    syscall
    mov eax, 60
    mov edi, 127
    syscall

fail:
    mov eax, 60
    mov edi, 125
    syscall

# wait_child: wait4(r15, &wstatus, __WALL, &ru), retried on EINTR.
wait_child:
    mov rdi, r15
    lea rsi, [rip + wstatus]
    mov edx, 0x40000000             # __WALL
    lea r10, [rip + ru]
    mov eax, 61                     # wait4
    syscall
    cmp rax, -4                     # EINTR
    je wait_child
    test rax, rax
    js fail
    ret

# read_rollup: reads /proc/<r15>/smaps_rollup into rollup, length in rbx.
read_rollup:
    push r12
    lea rdi, [rip + procpath]
    lea rsi, [rip + s_proc]
    call puts
    mov rax, r15
    call putu
    lea rsi, [rip + s_rollup]
    call puts
    mov byte ptr [rdi], 0
    mov edi, -100                   # AT_FDCWD
    lea rsi, [rip + procpath]
    xor edx, edx                    # O_RDONLY
    mov eax, 257                    # openat
    syscall
    test rax, rax
    js 9f
    mov r12, rax
    xor ebx, ebx
1:  mov rdi, r12
    lea rsi, [rip + rollup]
    add rsi, rbx
    mov edx, 4096
    sub rdx, rbx
    jbe 2f
    xor eax, eax                    # read
    syscall
    test rax, rax
    jle 2f
    add rbx, rax
    jmp 1b
2:  mov rdi, r12
    mov eax, 3                      # close
    syscall
9:  pop r12
    ret

# puts: copies the NUL-terminated string at rsi to rdi, advances rdi.
puts:
    mov al, [rsi]
    test al, al
    jz 2f
    mov [rdi], al
    inc rsi
    inc rdi
    jmp puts
2:  ret

# putu: writes rax in decimal at rdi, advances rdi.
putu:
    lea r8, [rip + digits + 24]
    mov r9, r8
    mov ecx, 10
1:  xor edx, edx
    div rcx
    add dl, '0'
    dec r8
    mov [r8], dl
    test rax, rax
    jnz 1b
2:  cmp r8, r9
    je 3f
    mov al, [r8]
    mov [rdi], al
    inc r8
    inc rdi
    jmp 2b
3:  ret

.section .rodata
s_maxrss: .asciz "maxrss_kb="
s_utime:  .asciz " utime_us="
s_stime:  .asciz " stime_us="
s_status: .asciz " status="
s_proc:   .asciz "/proc/"
s_rollup: .asciz "/smaps_rollup"

.bss
.align 16
ru:      .skip 144
wstatus: .skip 8
digits:  .skip 24
out:     .skip 128
procpath: .skip 64
rollup:  .skip 4096
