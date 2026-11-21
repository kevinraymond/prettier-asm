# Config search as Prettier's CLI does it for one file: .gitignore and
# .prettierignore in the working directory, then .editorconfig files up to the
# project root (a directory holding .git or .hg) and the first Prettier config
# file from the file's directory up to /.
#
# Each directory from / down to the file's is opened once and listed with
# getdents64; the names Prettier would stat are looked up in the listing, and
# only names that are there cost another syscall. A directory that cannot be
# listed, or holds names that a case-folding file system could match, is
# probed name by name instead.
.include "defs.inc"

.equ MAX_LEVELS, 128
.equ DENTS_SIZE, 32768

# Names Prettier looks for, in its order. Bits in the level masks.
.equ N_PACKAGE_JSON, 0
.equ N_PACKAGE_YAML, 1
.equ N_PRETTIERRC, 2
.equ N_PRETTIERRC_JSON, 3
.equ N_PRETTIERRC_YAML, 4
.equ N_PRETTIERRC_YML, 5
.equ N_PRETTIERRC_JSON5, 6
.equ N_CONFIG_COUNT, 20
.equ N_EDITORCONFIG, 20
.equ N_GIT, 21
.equ N_HG, 22
.equ N_GITIGNORE, 23
.equ N_PRETTIERIGNORE, 24
.equ N_COUNT, 25
.equ CONFIG_MASK, (1 << N_CONFIG_COUNT) - 1

.equ LV_ABSENT, 0
.equ LV_LISTED, 1
.equ LV_PROBE, 2

.equ DT_UNKNOWN, 0
.equ DT_DIR, 4
.equ DT_REG, 8
.equ DT_LNK, 10

    .bss
    .balign 8
    .globl g_no_config, g_no_editorconfig
g_no_config:       .quad 0
g_no_editorconfig: .quad 0
cf_cwd:      .space 4096
cf_cwd_len:  .quad 0
cf_abs:      .space 4096
cf_abs_len:  .quad 0
cf_nlv:      .quad 0                # levels: / is 0, the file's directory is cf_nlv - 1
cf_cwd_lv:   .quad 0                # level of the working directory, or -1
cf_end:      .space 8 * MAX_LEVELS  # cf_end[k]: end of path component k in cf_abs
lv_fd:       .space 8 * MAX_LEVELS
lv_state:    .space 8 * MAX_LEVELS
lv_mask:     .space 8 * MAX_LEVELS
lv_probe:    .space 8 * MAX_LEVELS
lv_type:     .space 32 * MAX_LEVELS
cf_name:     .space 256
cf_stat:     .space STAT_SIZE
cf_dents:    .space DENTS_SIZE
cf_rel:      .space 4096
cf_rel_len:  .quad 0
pend_val:    .space 8 * OPT_COUNT
pend_set:    .quad 0

    .section .rodata
    .balign 8
name_table:
    .quad n0, n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14, n15
    .quad n16, n17, n18, n19, n20, n21, n22, n23, n24
n0:  .asciz "package.json"
n1:  .asciz "package.yaml"
n2:  .asciz ".prettierrc"
n3:  .asciz ".prettierrc.json"
n4:  .asciz ".prettierrc.yaml"
n5:  .asciz ".prettierrc.yml"
n6:  .asciz ".prettierrc.json5"
n7:  .asciz ".prettierrc.js"
n8:  .asciz ".prettierrc.ts"
n9:  .asciz ".prettierrc.mjs"
n10: .asciz ".prettierrc.mts"
n11: .asciz ".prettierrc.cjs"
n12: .asciz ".prettierrc.cts"
n13: .asciz "prettier.config.js"
n14: .asciz "prettier.config.ts"
n15: .asciz "prettier.config.mjs"
n16: .asciz "prettier.config.mts"
n17: .asciz "prettier.config.cjs"
n18: .asciz "prettier.config.cts"
n19: .asciz ".prettierrc.toml"
n20: .asciz ".editorconfig"
n21: .asciz ".git"
n22: .asciz ".hg"
n23: .asciz ".gitignore"
n24: .asciz ".prettierignore"
s_root_dir: .asciz "/"
s_node_modules_rule: .ascii "node_modules"
s_prettier_key: .asciz "prettier"

    .text

# ---------------------------------------------------------------- paths

# cfg_setup(): the absolute path of the file (path.resolve), the working
# directory, then one listing per directory level.
FUNC cfg_setup
    push rbx
    push r12
    push r13
    push r14
    mov eax, SYS_getcwd
    lea rdi, [rip + cf_cwd]
    mov esi, 4096
    syscall
    test rax, rax
    jle 90f
    cmp byte ptr [rip + cf_cwd], '/'
    jne 90f
    dec rax
    mov [rip + cf_cwd_len], rax
    mov rbx, [rip + g_filepath]
    cmp byte ptr [rbx], 0
    je 91f
    # cf_abs gets "/" then components; cf_end records where each ends
    mov qword ptr [rip + cf_abs_len], 0
    mov qword ptr [rip + cf_nlv], 0
    cmp byte ptr [rbx], '/'
    je 1f
    lea rdi, [rip + cf_cwd]
    call cfg_push_path
1:  mov rdi, rbx
    call cfg_push_path
    mov r12, [rip + cf_abs_len]
    mov r13, [rip + cf_nlv]
    test r13, r13
    jz 91f
    lea rax, [rip + cf_abs]
    mov byte ptr [rax + r12], 0
    # the working directory's level
    mov qword ptr [rip + cf_cwd_lv], -1
    mov rcx, [rip + cf_cwd_len]
    cmp rcx, 1
    jne 2f
    mov qword ptr [rip + cf_cwd_lv], 0
    jmp 5f
2:  cmp rcx, r12
    jae 5f
    lea rdi, [rip + cf_cwd]
    lea rsi, [rip + cf_abs]
    mov rdx, rcx
    push rcx
    sub rsp, 8
    call mem_eq
    add rsp, 8
    pop rcx
    test eax, eax
    jz 5f
    lea rsi, [rip + cf_abs]
    cmp byte ptr [rsi + rcx], '/'
    jne 5f
    # level k has k components: find k with cf_end[k-1] == cwd length
    xor edx, edx
3:  cmp rdx, r13
    jae 5f
    lea rsi, [rip + cf_end]
    cmp [rsi + rdx*8], rcx
    je 4f
    inc rdx
    jmp 3b
4:  inc rdx
    cmp rdx, r13
    jae 5f
    mov [rip + cf_cwd_lv], rdx
5:  call cfg_scan
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "cannot get the working directory"
91: REFUSE "file path not ported"
ENDF cfg_setup

# cfg_push_path(cstr): appends the components of a path to cf_abs
# (cf_abs_len bytes, cf_nlv components). Empty and "." components are
# skipped and ".." drops one, as path.resolve does.
FUNC cfg_push_path
    push r12
    push r13
    mov r12, [rip + cf_abs_len]
    mov r13, [rip + cf_nlv]
    mov rsi, rdi
1:  cmp byte ptr [rsi], 0
    je 9f
    cmp byte ptr [rsi], '/'
    jne 2f
    inc rsi
    jmp 1b
2:  mov rdx, rsi
3:  movzx eax, byte ptr [rdx]
    test al, al
    jz 4f
    cmp al, '/'
    je 4f
    inc rdx
    jmp 3b
4:  mov rcx, rdx
    sub rcx, rsi                    # component length
    cmp rcx, 1
    jne 5f
    cmp byte ptr [rsi], '.'
    jne 5f
    mov rsi, rdx
    jmp 1b
5:  cmp rcx, 2
    jne 6f
    cmp word ptr [rsi], 0x2e2e
    jne 6f
    mov rsi, rdx
    test r13, r13
    jz 1b
    dec r13
    xor r12d, r12d
    test r13, r13
    jz 1b
    lea rax, [rip + cf_end]
    mov r12, [rax + r13*8 - 8]
    jmp 1b
6:  cmp rcx, 255
    ja 90f
    lea rax, [r12 + rcx + 1]
    cmp rax, 4000
    ja 90f
    cmp r13, MAX_LEVELS
    jae 90f
    lea rdi, [rip + cf_abs]
    mov byte ptr [rdi + r12], '/'
    inc r12
    add rdi, r12
    push rsi
    push rdx
    mov rdx, rcx
    add r12, rcx
    call memcpy
    pop rdx
    pop rsi
    lea rax, [rip + cf_end]
    mov [rax + r13*8], r12
    inc r13
    mov rsi, rdx
    jmp 1b
9:  mov [rip + cf_abs_len], r12
    mov [rip + cf_nlv], r13
    pop r13
    pop r12
    leave
    ret
90: REFUSE "file path too long"
ENDF cfg_push_path

# cfg_comp(k) -> rax = start of component k in cf_abs, rdx = its length
FUNC cfg_comp
    lea rcx, [rip + cf_end]
    mov rdx, [rcx + rdi*8]
    xor eax, eax
    test rdi, rdi
    jz 1f
    mov rax, [rcx + rdi*8 - 8]
1:  inc rax                         # past the '/'
    sub rdx, rax
    lea rcx, [rip + cf_abs]
    add rax, rcx
    leave
    ret
ENDF cfg_comp

# ---------------------------------------------------------------- listing

# cfg_scan(): opens and lists every level from / down.
FUNC cfg_scan
    push rbx
    push r12
    push r13
    push r14
    xor ebx, ebx                    # level
1:  cmp rbx, [rip + cf_nlv]
    jae 9f
    test rbx, rbx
    jnz 2f
    mov edi, AT_FDCWD
    lea r12, [rip + s_root_dir]
    jmp 3f
2:  lea rdi, [rbx - 1]
    call cfg_comp
    lea rdi, [rip + cf_name]
    mov rsi, rax
    push rdx
    sub rsp, 8
    call memcpy
    add rsp, 8
    pop rdx
    lea r12, [rip + cf_name]
    mov byte ptr [r12 + rdx], 0
    lea rax, [rip + lv_fd]
    mov rdi, [rax + rbx*8 - 8]
3:  mov r13, rdi                    # parent fd
    mov eax, SYS_openat
    mov rsi, r12
    mov edx, O_DIRECTORY | O_CLOEXEC
    syscall
    test rax, rax
    js 5f
    lea rcx, [rip + lv_fd]
    mov [rcx + rbx*8], rax
    lea rcx, [rip + lv_state]
    mov qword ptr [rcx + rbx*8], LV_LISTED
    mov rdi, rbx
    call cfg_list
    inc rbx
    jmp 1b
5:  cmp rax, -ENOENT
    je 9f
    cmp rax, -ENOTDIR
    je 9f
    cmp rax, -EACCES
    jne 90f
    # not readable: probe by name through an O_PATH descriptor
    mov eax, SYS_openat
    mov rdi, r13
    mov rsi, r12
    mov edx, O_PATH | O_DIRECTORY | O_CLOEXEC
    syscall
    test rax, rax
    js 6f
    lea rcx, [rip + lv_fd]
    mov [rcx + rbx*8], rax
    lea rcx, [rip + lv_state]
    mov qword ptr [rcx + rbx*8], LV_PROBE
    inc rbx
    jmp 1b
6:  cmp rax, -EACCES
    je 9f
    cmp rax, -ENOENT
    je 9f
    cmp rax, -ENOTDIR
    je 9f
    jmp 90f
    # levels from rbx down stay LV_ABSENT: nothing below can be found
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "cannot open a directory on the file's path"
ENDF cfg_scan

# cfg_list(level): reads the directory and notes the names Prettier probes.
FUNC cfg_list
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov qword ptr [rsp], 0          # buffers read
1:  mov eax, SYS_getdents64
    lea rcx, [rip + lv_fd]
    mov rdi, [rcx + rbx*8]
    lea rsi, [rip + cf_dents]
    mov edx, DENTS_SIZE
    syscall
    test rax, rax
    js 90f
    jz 9f
    inc qword ptr [rsp]
    cmp qword ptr [rsp], 2
    ja 8f                           # a large directory: probe by name
    lea r12, [rip + cf_dents]
    lea r13, [r12 + rax]
2:  cmp r12, r13
    jae 1b
    movzx r14d, word ptr [r12 + 16] # reclen
    lea rdi, [r12 + 19]
    movzx esi, byte ptr [r12 + 18]
    mov rdx, rbx
    call cfg_note
    add r12, r14
    jmp 2b
8:  lea rcx, [rip + lv_state]
    mov qword ptr [rcx + rbx*8], LV_PROBE
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "cannot list a directory on the file's path"
ENDF cfg_list

# cfg_note(name, d_type, level): one directory entry.
FUNC cfg_note
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov [rsp], rsi
    mov r15, rdx
    movzx eax, byte ptr [rbx]
    cmp al, '.'
    je 1f
    or al, 0x20
    cmp al, 'p'
    je 1f
    # a name with non-ASCII bytes could fold to one of ours
    test al, 0x80
    jnz 7f
    jmp 9f
1:  mov rdi, rbx
    call strlen
    mov r12, rax                    # length
    xor ecx, ecx
11: cmp rcx, r12
    jae 12f
    test byte ptr [rbx + rcx], 0x80
    jnz 7f
    inc rcx
    jmp 11b
12: cmp r12, 19
    ja 9f
    xor r13d, r13d                  # name index
2:  cmp r13, N_COUNT
    jae 9f
    lea rax, [rip + name_table]
    mov r14, [rax + r13*8]
    mov rdi, r14
    call strlen
    cmp rax, r12
    jne 6f
    # compare ignoring ASCII case, note whether exact
    xor ecx, ecx
    mov r8d, 1                      # exact
3:  cmp rcx, r12
    jae 4f
    movzx eax, byte ptr [rbx + rcx]
    movzx edx, byte ptr [r14 + rcx]
    cmp eax, edx
    je 31f
    xor r8d, r8d
    or eax, 0x20
    cmp eax, edx
    jne 6f
    sub eax, 'a'
    cmp eax, 25
    ja 6f
31: inc rcx
    jmp 3b
4:  mov eax, 1
    mov ecx, r13d
    shl eax, cl
    test r8d, r8d
    jz 5f
    lea rcx, [rip + lv_mask]
    or [rcx + r15*8], rax
    mov rax, r15
    shl rax, 5
    lea rcx, [rip + lv_type]
    add rcx, rax
    mov rdx, [rsp]
    mov [rcx + r13], dl
    jmp 9f
5:  lea rcx, [rip + lv_probe]
    or [rcx + r15*8], rax
    jmp 9f
6:  inc r13
    jmp 2b
7:  lea rcx, [rip + lv_state]
    mov qword ptr [rcx + r15*8], LV_PROBE
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF cfg_note

# cfg_present(level, name) -> eax: 0 when the name is surely not there,
# 1 when it is listed, 2 when only a probe can tell.
FUNC cfg_present
    lea rcx, [rip + lv_state]
    mov rax, [rcx + rdi*8]
    cmp rax, LV_ABSENT
    je 8f
    cmp rax, LV_PROBE
    je 7f
    mov ecx, esi
    mov edx, 1
    shl edx, cl
    lea rcx, [rip + lv_probe]
    test [rcx + rdi*8], rdx
    jnz 7f
    lea rcx, [rip + lv_mask]
    test [rcx + rdi*8], rdx
    jz 8f
    mov eax, 1
    jmp 9f
7:  mov eax, 2
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF cfg_present

# cfg_dtype(level, name) -> eax
FUNC cfg_dtype
    shl rdi, 5
    lea rcx, [rip + lv_type]
    add rcx, rdi
    movzx eax, byte ptr [rcx + rsi]
    leave
    ret
ENDF cfg_dtype

# cfg_stat(level, name, flags) -> eax = st_mode, or 0 when stat fails
FUNC cfg_stat
    lea rcx, [rip + lv_fd]
    mov rdi, [rcx + rdi*8]
    lea rcx, [rip + name_table]
    mov rsi, [rcx + rsi*8]
    mov r10, rdx
    lea rdx, [rip + cf_stat]
    mov eax, SYS_newfstatat
    syscall
    test rax, rax
    jnz 8f
    mov eax, [rip + cf_stat + ST_MODE]
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF cfg_stat

# cfg_is_file(level, name) -> eax: stat (following links) says a file
FUNC cfg_is_file
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call cfg_present
    test eax, eax
    jz 9f
    cmp eax, 2
    je 5f
    mov rdi, rbx
    mov rsi, r12
    call cfg_dtype
    cmp eax, DT_REG
    je 8f
    cmp eax, DT_LNK
    je 5f
    cmp eax, DT_UNKNOWN
    je 5f
    xor eax, eax
    jmp 9f
5:  mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call cfg_stat
    and eax, S_IFMT
    cmp eax, S_IFREG
    sete al
    movzx eax, al
    jmp 9f
8:  mov eax, 1
9:  pop r12
    pop rbx
    leave
    ret
ENDF cfg_is_file

# cfg_is_dir_nofollow(level, name) -> eax: lstat says a directory
FUNC cfg_is_dir_nofollow
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call cfg_present
    test eax, eax
    jz 9f
    cmp eax, 2
    je 5f
    mov rdi, rbx
    mov rsi, r12
    call cfg_dtype
    cmp eax, DT_DIR
    je 5f
    cmp eax, DT_UNKNOWN
    je 5f
    xor eax, eax
    jmp 9f
    # a listed directory is confirmed: lstat also needs search permission
5:  mov rdi, rbx
    mov rsi, r12
    mov edx, AT_SYMLINK_NOFOLLOW
    call cfg_stat
    and eax, S_IFMT
    cmp eax, S_IFDIR
    sete al
    movzx eax, al
9:  pop r12
    pop rbx
    leave
    ret
ENDF cfg_is_dir_nofollow

# ---------------------------------------------------------------- reading

# cfg_read_fd(fd) -> rax = ptr, rdx = len; rax = -errno when a read fails.
# The bytes land in the arena; the fd is closed.
FUNC cfg_read_fd
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, [rip + g_arena_ptr]
    xor r13d, r13d
1:  lea rax, [r12 + r13 + 0x10000 + 8]
    cmp rax, [rip + g_arena_end]
    ja 90f
    mov eax, SYS_read
    mov rdi, rbx
    lea rsi, [r12 + r13]
    mov edx, 0x10000
    syscall
    cmp rax, -4
    je 1b
    test rax, rax
    js 5f
    jz 2f
    add r13, rax
    jmp 1b
2:  lea rdi, [r13 + 1]
    call alloc
    mov r14, rax
    mov rdx, r13
    jmp 6f
5:  mov r14, rax
6:  push rdx
    sub rsp, 8
    mov eax, SYS_close
    mov rdi, rbx
    syscall
    add rsp, 8
    pop rdx
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "config file too large"
ENDF cfg_read_fd

# cfg_read(level, name) -> rax = ptr, rdx = len, or rax = -errno.
# Level -1 reads the name from the working directory.
FUNC cfg_read
    mov rax, rdi
    lea rcx, [rip + name_table]
    mov rsi, [rcx + rsi*8]
    mov rdi, AT_FDCWD
    cmp rax, -1
    je 1f
    lea rcx, [rip + lv_fd]
    mov rdi, [rcx + rax*8]
1:  mov eax, SYS_openat
    mov edx, O_CLOEXEC
    syscall
    test rax, rax
    js 9f
    mov rdi, rax
    call cfg_read_fd
9:  leave
    ret
ENDF cfg_read

# ---------------------------------------------------------------- ignore files

# cfg_ignored() -> eax: Prettier would print the file unchanged.
FUNC cfg_ignored
    push rbx
    push r12
    push r13
    push r14
    call cfg_relative
    xor r14d, r14d                  # result
    mov ebx, N_GITIGNORE
1:  call ig_reset
    # the ignore file's text, "" when it does not exist
    mov rdi, [rip + cf_cwd_lv]
    cmp rdi, -1
    je 2f
    lea rax, [rip + lv_state]
    cmp qword ptr [rax + rdi*8], LV_ABSENT
    jne 11f
    mov rdi, -1
    jmp 2f
11: mov esi, ebx
    call cfg_present
    test eax, eax
    jz 5f
    mov rdi, [rip + cf_cwd_lv]
2:  mov esi, ebx
    call cfg_read
    cmp rax, -ENOENT
    je 5f
    test rax, rax
    js 90f
    mov r12, rax
    mov r13, rdx
    mov rdi, r12
    mov rsi, r13
    call ig_add_text
    cmp qword ptr [rip + ig_count], 0
    je 5f
    call cfg_rel_plain
5:  lea rdi, [rip + s_node_modules_rule]
    mov esi, 12
    call ig_add_text
    lea rdi, [rip + cf_rel]
    mov rsi, [rip + cf_rel_len]
    call ig_test
    or r14d, eax
    inc ebx
    cmp ebx, N_PRETTIERIGNORE
    jbe 1b
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "cannot read an ignore file"
ENDF cfg_ignored

# cfg_rel_plain(): user patterns are ported for printable ASCII paths only
FUNC cfg_rel_plain
    lea rdi, [rip + cf_rel]
    mov rcx, [rip + cf_rel_len]
1:  test rcx, rcx
    jz 9f
    movzx eax, byte ptr [rdi]
    cmp al, 0x20
    jb 90f
    cmp al, 0x7e
    ja 90f
    inc rdi
    dec rcx
    jmp 1b
9:  leave
    ret
90: REFUSE "ignore patterns with a path that is not printable ASCII"
ENDF cfg_rel_plain

# cfg_relative(): cf_rel = path.relative(cwd, file)
FUNC cfg_relative
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    # common leading components
    lea rbx, [rip + cf_cwd]
    mov r12, [rip + cf_cwd_len]
    lea r13, [rip + cf_abs]
    xor r14d, r14d                  # cwd index
    xor r15d, r15d                  # matched prefix end (in both)
    cmp r12, 1
    jne 1f
    xor r12d, r12d                  # cwd "/": no components
1:  cmp r15, r12
    jae 3f
    # next cwd component [r15+1, e)
    lea rcx, [r15 + 1]
2:  cmp rcx, r12
    jae 21f
    cmp byte ptr [rbx + rcx], '/'
    je 21f
    inc rcx
    jmp 2b
21: cmp rcx, [rip + cf_abs_len]
    ja 3f
    je 22f
    cmp byte ptr [r13 + rcx], '/'
    jne 3f
22: lea rdi, [rbx + r15]
    lea rsi, [r13 + r15]
    mov rdx, rcx
    sub rdx, r15
    mov [rsp], rcx
    call mem_eq
    mov rcx, [rsp]
    test eax, eax
    jz 3f
    mov r15, rcx
    jmp 1b
    # ".." for each cwd component left, then the rest of the file path
3:  lea rdi, [rip + cf_rel]
    xor edx, edx
    mov rcx, r15
4:  cmp rcx, r12
    jae 5f
    cmp byte ptr [rbx + rcx], '/'
    jne 41f
    mov word ptr [rdi + rdx], 0x2e2e
    mov byte ptr [rdi + rdx + 2], '/'
    add rdx, 3
    cmp rdx, 4000
    ja 90f
41: inc rcx
    jmp 4b
5:  mov rcx, r15
    inc rcx                         # past the '/'
    mov r8, [rip + cf_abs_len]
    cmp rcx, r8
    ja 6f
51: cmp rcx, r8
    jae 6f
    mov al, [r13 + rcx]
    mov [rdi + rdx], al
    inc rdx
    inc rcx
    cmp rdx, 4090
    ja 90f
    jmp 51b
6:  # drop a trailing '/' left when the file path was a prefix of cwd
    test rdx, rdx
    jz 91f
    cmp byte ptr [rdi + rdx - 1], '/'
    jne 7f
    dec rdx
7:  mov [rip + cf_rel_len], rdx
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "file path too long"
91: REFUSE "file path is the working directory"
ENDF cfg_relative

# ---------------------------------------------------------------- options

# cfg_pend(slot, value): a config value for option slot (opt_table order).
# Later calls win, as later config sources do.
FUNC cfg_pend
    lea rax, [rip + pend_val]
    mov [rax + rdi*8], rsi
    mov ecx, edi
    mov eax, 1
    shl eax, cl
    or [rip + pend_set], rax
    leave
    ret
ENDF cfg_pend

# cfg_config(): editorconfig, then the Prettier config file, then the
# options they set wherever the command line did not.
FUNC cfg_config
    push rbx
    push r12
    cmp qword ptr [rip + g_no_editorconfig], 0
    jne 1f
    call cfg_editorconfig
1:  call cfg_prettierrc
    xor ebx, ebx
2:  cmp ebx, OPT_COUNT
    jae 9f
    mov rax, [rip + pend_set]
    bt rax, rbx
    jnc 3f
    mov edi, ebx
    lea rax, [rip + pend_val]
    mov rsi, [rax + rbx*8]
    call option_from_config
3:  inc ebx
    jmp 2b
9:  pop r12
    pop rbx
    leave
    ret
ENDF cfg_config

# cfg_editorconfig(): reads .editorconfig files from the file's directory up
# to the project root, stopping at root = true, and applies them outermost
# first.
FUNC cfg_editorconfig
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    # project root: the nearest level with a .git or .hg directory
    mov rbx, [rip + cf_nlv]
1:  dec rbx
    js 2f
    mov rdi, rbx
    mov esi, N_GIT
    call cfg_is_dir_nofollow
    test eax, eax
    jnz 3f
    mov rdi, rbx
    mov esi, N_HG
    call cfg_is_dir_nofollow
    test eax, eax
    jnz 3f
    jmp 1b
2:  xor ebx, ebx
3:  mov [rsp], rbx                  # root level
    call ss_mark
    mov r15, rax
    mov r12, [rip + cf_nlv]
4:  dec r12
    cmp r12, [rsp]
    jl 6f
    mov rdi, r12
    mov esi, N_EDITORCONFIG
    call cfg_present
    test eax, eax
    jz 4b
    mov rdi, r12
    mov esi, N_EDITORCONFIG
    call cfg_read
    test rax, rax
    js 4b                           # unreadable: the package reads ""
    mov rdi, rax
    mov rsi, rdx
    call ec_parse
    mov r13, rax
    mov rdi, r12
    call ss_push
    mov rdi, r13
    call ss_push
    mov rdi, r13
    call ec_file_root
    test eax, eax
    jz 4b
6:  mov rdi, r15
    call ss_to_vec
    mov r13, rax                    # level, file, level, file, ...
    mov r14, [r13]
    test r14, r14
    jz 9f
    call ec_reset
    # outermost first
7:  sub r14, 2
    js 8f
    mov r12, [r13 + 8 + r14*8]      # level
    mov rbx, [r13 + 16 + r14*8]     # file
    cmp qword ptr [rbx + 8], 1
    jbe 7b                          # no sections
    mov rdi, r12
    call cfg_glob_dir_ok
    # the file's path below that level
    mov rdi, r12
    call cfg_below
    mov rcx, rax
    mov r8, rdx
    mov rdi, rbx
    call ec_apply
    jmp 7b
8:  call ec_finish
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF cfg_editorconfig

# cfg_below(level) -> rax = ptr, rdx = len: the file path below that level
FUNC cfg_below
    xor eax, eax
    test rdi, rdi
    jz 1f
    lea rcx, [rip + cf_end]
    mov rax, [rcx + rdi*8 - 8]
1:  inc rax
    mov rdx, [rip + cf_abs_len]
    sub rdx, rax
    lea rcx, [rip + cf_abs]
    add rax, rcx
    leave
    ret
ENDF cfg_below

# cfg_glob_dir_ok(level): the editorconfig package puts the directory into
# the glob unescaped, and the path is matched byte by byte here; both must be
# plain.
FUNC cfg_glob_dir_ok
    lea rsi, [rip + cf_abs]
    mov rcx, [rip + cf_abs_len]
    xor edx, edx
1:  cmp rdx, rcx
    jae 9f
    movzx eax, byte ptr [rsi + rdx]
    inc rdx
    cmp al, 0x20
    jb 90f
    cmp al, 0x7e
    ja 90f
    cmp al, '*'
    je 2f
    cmp al, '?'
    je 2f
    cmp al, '['
    je 2f
    cmp al, ']'
    je 2f
    cmp al, '{'
    je 2f
    cmp al, '}'
    je 2f
    cmp al, '\\'
    je 2f
    jmp 1b
    # a glob character: only allowed below the .editorconfig's directory
2:  test rdi, rdi
    jz 1b
    lea r8, [rip + cf_end]
    cmp rdx, [r8 + rdi*8 - 8]
    jbe 90f
    jmp 1b
9:  leave
    ret
90: REFUSE "editorconfig with a path that is not plain ASCII"
ENDF cfg_glob_dir_ok

# cfg_prettierrc(): the first config file from the file's directory up.
FUNC cfg_prettierrc
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    cmp qword ptr [rip + g_no_config], 0
    jne 99f
    mov rbx, [rip + cf_nlv]
1:  dec rbx
    js 99f
    lea rax, [rip + lv_state]
    mov rax, [rax + rbx*8]
    cmp rax, LV_ABSENT
    je 1b
    cmp rax, LV_PROBE
    je 2f
    lea rax, [rip + lv_mask]
    mov rcx, [rax + rbx*8]
    lea rax, [rip + lv_probe]
    or rcx, [rax + rbx*8]
    test rcx, CONFIG_MASK
    jz 1b
2:  xor r12d, r12d                  # name
3:  cmp r12, N_CONFIG_COUNT
    jae 1b
    mov rdi, rbx
    mov rsi, r12
    call cfg_is_file
    test eax, eax
    jz 8f
    cmp r12, N_PACKAGE_JSON
    jne 4f
    # package.json counts only with a truthy `prettier` key
    mov rdi, rbx
    mov rsi, r12
    call cfg_read
    test rax, rax
    js 8f
    mov rdi, rax
    mov rsi, rdx
    call cfg_json_parse
    test rax, rax
    jz 8f
    cmp byte ptr [rax + CV_TYPE], CV_OBJ
    jne 8f
    mov rdi, rax
    lea rsi, [rip + s_prettier_key]
    call cv_obj_get
    test rax, rax
    jz 8f
    movzx ecx, byte ptr [rax + CV_TYPE]
    cmp ecx, CV_NULL
    je 8f
    cmp ecx, CV_FALSE
    je 8f
    cmp ecx, CV_STR
    jne 31f
    cmp qword ptr [rax + CV_B], 0
    je 8f
    jmp 91f
31: cmp ecx, CV_OBJ
    jne 91f
    jmp 70f
4:  cmp r12, N_PACKAGE_YAML
    je 92f
    cmp r12, N_PRETTIERRC
    je 50f
    cmp r12, N_PRETTIERRC_YAML
    je 50f
    cmp r12, N_PRETTIERRC_YML
    je 50f
    cmp r12, N_PRETTIERRC_JSON5
    je 41f
    cmp r12, N_PRETTIERRC_JSON
    jne 92f
    # .prettierrc.json: JSON.parse; null means no options. JSON5 reads JSON
    # text the same way.
41:
    mov rdi, rbx
    mov rsi, r12
    call cfg_read
    test rax, rax
    js 93f
    mov rdi, rax
    mov rsi, rdx
    call cfg_json_parse
    test rax, rax
    jz 94f
    cmp byte ptr [rax + CV_TYPE], CV_NULL
    je 99f
    cmp byte ptr [rax + CV_TYPE], CV_OBJ
    jne 94f
    jmp 70f
    # .prettierrc, .prettierrc.yaml, .prettierrc.yml: YAML. JSON text means
    # the same in both when it has no escapes and no repeated keys; else the
    # YAML subset.
50: mov rdi, rbx
    mov rsi, r12
    call cfg_read
    test rax, rax
    js 93f
    mov r13, rax
    mov r14, rdx
    xor ecx, ecx
51: cmp rcx, r14
    jae 52f
    movzx eax, byte ptr [r13 + rcx]
    cmp al, 0x7f
    jae 95f
    inc rcx
    jmp 51b
52: xor ecx, ecx
53: cmp rcx, r14
    jae 55f
    movzx eax, byte ptr [r13 + rcx]
    inc rcx
    cmp al, ' '
    je 53b
    cmp al, 9
    je 53b
    cmp al, 10
    je 53b
    cmp al, 13
    je 53b
    cmp al, '{'
    jne 55f
    mov rdi, r13
    mov rsi, r14
    call cfg_json_parse
    test rax, rax
    jz 95f
    jmp 70f
55: mov rdi, r13
    mov rsi, r14
    call cfg_yaml_parse
    test rax, rax
    jz 99f
    # found: the config object at level rbx
70: mov rdi, rax
    mov rsi, rbx
    call cfg_apply_config
    jmp 99f
8:  inc r12
    jmp 3b
99: add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
91: REFUSE "package.json prettier key not ported"
92: REFUSE "config file format not ported"
93: REFUSE "cannot read the config file"
94: REFUSE "config file is not a JSON object"
95: REFUSE ".prettierrc not ported"
ENDF cfg_prettierrc


# ---------------------------------------------------------------- config objects

.equ K_INT, 1           # slot, max
.equ K_BOOL, 2          # slot
.equ K_ENUM, 3          # slot, enum list
.equ K_BOOL_NOP, 4      # valid booleans, no effect on JSON
.equ K_ENUM_NOP, 5      # enum list
.equ K_SCHEMA, 6
.equ K_OVERRIDES, 7

    .section .rodata
    .balign 8
# entry: name, kind, slot, argument
key_table:
    .quad k_print_width, K_INT, 0, 1000
    .quad k_tab_width, K_INT, 1, 64
    .quad k_use_tabs, K_BOOL, 2, 0
    .quad k_single_quote, K_BOOL, 3, 0
    .quad k_bracket_spacing, K_BOOL, 4, 0
    .quad k_quote_props, K_ENUM, 5, e_quote_props
    .quad k_trailing_comma, K_ENUM, 6, e_trailing_comma
    .quad k_object_wrap, K_ENUM, 7, e_object_wrap
    .quad k_end_of_line, K_ENUM_NOP, 0, e_end_of_line
    .quad k_semi, K_BOOL, 8, 0
    .quad k_bracket_same_line, K_BOOL, 9, 0
    .quad k_jsx_single_quote, K_BOOL_NOP, 0, 0
    .quad k_vue_indent, K_BOOL_NOP, 0, 0
    .quad k_single_attr, K_BOOL_NOP, 0, 0
    .quad k_experimental_ternaries, K_BOOL, 10, 0
    .quad k_arrow_parens, K_ENUM, 11, e_arrow_parens
    .quad k_prose_wrap, K_ENUM_NOP, 0, e_prose_wrap
    .quad k_html_ws, K_ENUM_NOP, 0, e_html_ws
    .quad k_operator_position, K_ENUM, 12, e_operator_position
    .quad k_embedded, K_ENUM, 13, e_embedded
    .quad k_schema, K_SCHEMA, 0, 0
    .quad k_overrides, K_OVERRIDES, 0, 0
    .quad 0
k_print_width:     .asciz "printWidth"
k_tab_width:       .asciz "tabWidth"
k_use_tabs:        .asciz "useTabs"
k_single_quote:    .asciz "singleQuote"
k_bracket_spacing: .asciz "bracketSpacing"
k_quote_props:     .asciz "quoteProps"
k_trailing_comma:  .asciz "trailingComma"
k_object_wrap:     .asciz "objectWrap"
k_end_of_line:     .asciz "endOfLine"
k_semi:            .asciz "semi"
k_bracket_same_line: .asciz "bracketSameLine"
k_jsx_single_quote: .asciz "jsxSingleQuote"
k_vue_indent:      .asciz "vueIndentScriptAndStyle"
k_single_attr:     .asciz "singleAttributePerLine"
k_experimental_ternaries: .asciz "experimentalTernaries"
k_arrow_parens:    .asciz "arrowParens"
k_prose_wrap:      .asciz "proseWrap"
k_html_ws:         .asciz "htmlWhitespaceSensitivity"
k_operator_position: .asciz "experimentalOperatorPosition"
k_embedded:        .asciz "embeddedLanguageFormatting"
k_schema:          .asciz "$schema"
k_overrides:       .asciz "overrides"
k_files:           .asciz "files"
k_exclude_files:   .asciz "excludeFiles"
k_options:         .asciz "options"
    .balign 8
e_quote_props:
    .quad v_as_needed, QP_AS_NEEDED, v_consistent, QP_CONSISTENT, v_preserve, QP_PRESERVE, 0
e_trailing_comma:
    .quad v_all, TC_ALL, v_es5, TC_ES5, v_none, TC_NONE, 0
e_object_wrap:
    .quad v_preserve, OW_PRESERVE, v_collapse, OW_COLLAPSE, 0
e_end_of_line:
    .quad v_lf, 0, 0
e_arrow_parens:
    .quad v_always, AP_ALWAYS, v_avoid, AP_AVOID, 0
e_prose_wrap:
    .quad v_always, 0, v_never, 0, v_preserve, 0, 0
e_html_ws:
    .quad v_css, 0, v_strict, 0, v_ignore, 0, 0
e_operator_position:
    .quad v_start, OP_START, v_end, OP_END, 0
e_embedded:
    .quad v_auto, 0, v_off, 1, 0
v_as_needed:  .asciz "as-needed"
v_consistent: .asciz "consistent"
v_preserve:   .asciz "preserve"
v_all:        .asciz "all"
v_es5:        .asciz "es5"
v_none:       .asciz "none"
v_collapse:   .asciz "collapse"
v_lf:         .asciz "lf"
v_always:     .asciz "always"
v_avoid:      .asciz "avoid"
v_never:      .asciz "never"
v_css:        .asciz "css"
v_strict:     .asciz "strict"
v_ignore:     .asciz "ignore"
v_start:      .asciz "start"
v_end:        .asciz "end"
v_auto:       .asciz "auto"
v_off:        .asciz "off"
    .text

# cfg_apply_config(obj, level): base options, then each matching override,
# as mergeOverrides does; `$schema` is dropped.
FUNC cfg_apply_config
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov [rsp], rsi
    mov rdi, rbx
    call cv_obj_check
    mov rdi, rbx
    mov esi, 1
    call cfg_apply_options
    mov rdi, rbx
    lea rsi, [rip + k_overrides]
    call cv_obj_get
    test rax, rax
    jz 9f
    cmp byte ptr [rax + CV_TYPE], CV_NULL
    je 9f
    cmp byte ptr [rax + CV_TYPE], CV_ARR
    jne 90f
    mov r12, [rax + CV_A]           # VEC of overrides
    xor r13d, r13d
1:  cmp r13, [r12]
    jae 9f
    mov r14, [r12 + 8 + r13*8]
    inc r13
    cmp byte ptr [r14 + CV_TYPE], CV_OBJ
    jne 90f
    mov rdi, r14
    call cv_obj_check
    mov rdi, r14
    mov rsi, [rsp]
    call cfg_override_matches
    test eax, eax
    jz 1b
    mov rdi, r14
    lea rsi, [rip + k_options]
    call cv_obj_get
    test rax, rax
    jz 1b
    cmp byte ptr [rax + CV_TYPE], CV_OBJ
    jne 90f
    mov r15, rax
    mov rdi, r15
    call cv_obj_check
    mov rdi, r15
    xor esi, esi
    call cfg_apply_options
    jmp 1b
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "config overrides not ported"
ENDF cfg_apply_config

# cfg_apply_options(obj, top): every key must be an option this port knows.
FUNC cfg_apply_options
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, [rdi + CV_A]
    mov [rsp], rsi
    xor r12d, r12d
1:  cmp r12, [rbx]
    jae 99f
    mov r13, [rbx + 8 + r12*8]      # key
    mov r14, [rbx + 16 + r12*8]     # value
    add r12, 2
    lea r15, [rip + key_table]
2:  mov rsi, [r15]
    test rsi, rsi
    jz 90f
    mov rdi, r13
    call cv_str_is
    test eax, eax
    jnz 3f
    add r15, 32
    jmp 2b
3:  mov rax, [r15 + 8]
    cmp rax, K_SCHEMA
    je 30f
    cmp rax, K_OVERRIDES
    je 30f
    cmp rax, K_INT
    je 10f
    cmp rax, K_BOOL
    je 20f
    cmp rax, K_BOOL_NOP
    je 25f
    # enums
    cmp byte ptr [r14 + CV_TYPE], CV_STR
    jne 91f
    mov rcx, [r15 + 24]
    mov [rsp + 8], rcx
4:  mov rcx, [rsp + 8]
    mov rsi, [rcx]
    test rsi, rsi
    jz 91f
    mov rdi, r14
    call cv_str_is
    test eax, eax
    jnz 5f
    add qword ptr [rsp + 8], 16
    jmp 4b
5:  cmp qword ptr [r15 + 8], K_ENUM_NOP
    je 1b
    mov rcx, [rsp + 8]
    mov rsi, [rcx + 8]
    mov rdi, [r15 + 16]
    call cfg_pend
    jmp 1b
10: cmp byte ptr [r14 + CV_TYPE], CV_NUM
    jne 91f
    test byte ptr [r14 + CV_FLAGS], CVF_INT
    jz 91f
    mov rsi, [r14 + CV_A]
    test rsi, rsi
    jz 91f
    cmp rsi, [r15 + 24]
    ja 91f
    mov rdi, [r15 + 16]
    call cfg_pend
    jmp 1b
20: xor esi, esi
    cmp byte ptr [r14 + CV_TYPE], CV_FALSE
    je 21f
    mov esi, 1
    cmp byte ptr [r14 + CV_TYPE], CV_TRUE
    jne 91f
21: mov rdi, [r15 + 16]
    call cfg_pend
    jmp 1b
25: cmp byte ptr [r14 + CV_TYPE], CV_TRUE
    je 1b
    cmp byte ptr [r14 + CV_TYPE], CV_FALSE
    je 1b
    jmp 91f
30: cmp qword ptr [rsp], 0
    jne 1b
    jmp 90f
99: add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "config option not ported"
91: REFUSE "config option value not ported"
ENDF cfg_apply_options

# cfg_override_matches(override, level) -> eax: pathMatchesGlobs on the file
# path relative to the config file's directory. Globs without a slash match
# the basename, and in that pass excludeFiles are tried on the basename too.
FUNC cfg_override_matches
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov rdi, rsi
    call cfg_below
    mov [rip + cf_gpath], rax
    mov [rip + cf_glen], rdx
    mov rdi, rbx
    lea rsi, [rip + k_files]
    call cv_obj_get
    test rax, rax
    jz 90f
    mov r12, rax                    # files
    mov rdi, rbx
    lea rsi, [rip + k_exclude_files]
    call cv_obj_get
    mov r13, rax                    # excludeFiles or 0
    # pass 1: globs without '/', basename matching
    mov rdi, r12
    xor esi, esi
    mov edx, 1
    call cfg_any_glob
    test eax, eax
    jz 2f
    test r13, r13
    jz 8f
    mov rdi, r13
    mov esi, 2
    mov edx, 1
    call cfg_any_glob
    test eax, eax
    jz 8f
    # pass 2: globs with '/', whole path
2:  mov rdi, r12
    mov esi, 1
    xor edx, edx
    call cfg_any_glob
    test eax, eax
    jz 9f
    test r13, r13
    jz 8f
    mov rdi, r13
    mov esi, 2
    xor edx, edx
    call cfg_any_glob
    test eax, eax
    jz 8f
    xor eax, eax
    jmp 9f
8:  mov eax, 1
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "override without files"
ENDF cfg_override_matches

    .bss
cf_gpath: .quad 0
cf_glen:  .quad 0
    .text

# cfg_any_glob(globs, which, basename) -> eax: some glob of a string or array
# matches cf_gpath. which: 0 globs without '/', 1 globs with '/', 2 all.
FUNC cfg_any_glob
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r13, rsi
    mov r14, rdx
    cmp byte ptr [rdi + CV_TYPE], CV_STR
    jne 1f
    mov rsi, r13
    mov rdx, r14
    call cfg_one_glob
    jmp 9f
1:  cmp byte ptr [rdi + CV_TYPE], CV_ARR
    jne 90f
    mov r12, [rdi + CV_A]
    xor r15d, r15d
3:  cmp r15, [r12]
    jae 8f
    mov rdi, [r12 + 8 + r15*8]
    inc r15
    cmp byte ptr [rdi + CV_TYPE], CV_STR
    jne 90f
    mov rsi, r13
    mov rdx, r14
    call cfg_one_glob
    test eax, eax
    jz 3b
    jmp 9f
8:  xor eax, eax
9:  add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "override files not ported"
ENDF cfg_any_glob

# cfg_one_glob(str, which, basename) -> eax
FUNC cfg_one_glob
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rdx
    test byte ptr [rbx + CV_FLAGS], CVF_ESC
    jnz 90f
    mov rdi, [rbx + CV_A]
    mov rax, [rbx + CV_B]
    test rax, rax
    jz 90f
    cmp rsi, 2
    je 3f
    xor ecx, ecx
    xor edx, edx
1:  cmp rcx, rax
    jae 2f
    cmp byte ptr [rdi + rcx], '/'
    jne 11f
    mov edx, 1
11: inc rcx
    jmp 1b
2:  cmp rdx, rsi
    jne 8f
3:  mov rsi, rax
    mov rdx, [rip + cf_gpath]
    mov rcx, [rip + cf_glen]
    mov r8, r12
    call gl_pico_match
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
90: REFUSE "override glob not ported"
ENDF cfg_one_glob

# ---------------------------------------------------------------- output

# cfg_utf8_ok(ptr, len) -> eax: valid UTF-8 (no surrogates, no overlongs)
FUNC cfg_utf8_ok
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 8f
    movzx eax, byte ptr [rdi + rcx]
    cmp al, 0x80
    jb 7f
    cmp al, 0xc2
    jb 9f
    cmp al, 0xe0
    jb 2f
    cmp al, 0xf0
    jb 3f
    cmp al, 0xf4
    ja 9f
    # 4 bytes
    lea rdx, [rcx + 3]
    cmp rdx, rsi
    jae 9f
    movzx edx, byte ptr [rdi + rcx + 1]
    cmp al, 0xf0
    jne 41f
    cmp dl, 0x90
    jb 9f
41: cmp al, 0xf4
    jne 42f
    cmp dl, 0x8f
    ja 9f
42: mov r8d, 3
    jmp 5f
2:  mov r8d, 1
    jmp 5f
3:  lea rdx, [rcx + 2]
    cmp rdx, rsi
    jae 9f
    movzx edx, byte ptr [rdi + rcx + 1]
    cmp al, 0xe0
    jne 31f
    cmp dl, 0xa0
    jb 9f
31: cmp al, 0xed
    jne 32f
    cmp dl, 0x9f
    ja 9f
32: mov r8d, 2
5:  inc rcx
51: cmp rcx, rsi
    jae 9f
    movzx eax, byte ptr [rdi + rcx]
    and al, 0xc0
    cmp al, 0x80
    jne 9f
    inc rcx
    dec r8d
    jnz 51b
    jmp 1b
7:  inc rcx
    jmp 1b
8:  mov eax, 1
    leave
    ret
9:  xor eax, eax
    leave
    ret
ENDF cfg_utf8_ok

# cfg_bare_path_ok(): a file given as an argument is skipped by Prettier when
# its path from the working directory runs through one of these directories.
FUNC cfg_bare_path_ok
    push rbx
    push r12
    push r13
    push r14
    call cfg_relative
    lea rbx, [rip + cf_rel]
    mov r12, [rip + cf_rel_len]
    xor r13d, r13d                  # segment start
    xor ecx, ecx
1:  cmp rcx, r12
    je 2f
    cmp byte ptr [rbx + rcx], '/'
    je 2f
    inc rcx
    jmp 1b
2:  mov [rip + cf_seg_end], rcx
    lea rdi, [rbx + r13]
    mov rsi, rcx
    sub rsi, r13
    lea r14, [rip + skip_dirs]
3:  mov rdx, [r14]
    test rdx, rdx
    jz 4f
    push rdi
    push rsi
    mov rdi, rdx
    call strlen
    pop rsi
    pop rdi
    cmp rax, rsi
    jne 31f
    push rdi
    push rsi
    mov rsi, [r14]
    mov rdx, rax
    call mem_eq
    pop rsi
    pop rdi
    test eax, eax
    jnz 90f
31: add r14, 8
    jmp 3b
4:  mov rcx, [rip + cf_seg_end]
    cmp rcx, r12
    jae 9f
    inc rcx
    mov r13, rcx
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "file under a directory Prettier skips"
ENDF cfg_bare_path_ok

    .bss
cf_seg_end: .quad 0
    .section .rodata
    .balign 8
skip_dirs: .quad d_git, d_sl, d_svn, d_hg, d_jj, d_nm, 0
d_git: .asciz ".git"
d_sl:  .asciz ".sl"
d_svn: .asciz ".svn"
d_hg:  .asciz ".hg"
d_jj:  .asciz ".jj"
d_nm:  .asciz "node_modules"
    .text

# ---------------------------------------------------------------- entry points

    .section .rodata
s_no_config:       .asciz "--no-config"
s_no_editorconfig: .asciz "--no-editorconfig"
    .text

# cfg_flag(arg) -> rax = 1 when arg is a config flag this port handles
FUNC cfg_flag
    push rbx
    sub rsp, 8
    mov rbx, rdi
    lea rsi, [rip + s_no_config]
    call cstr_eq
    test eax, eax
    jz 1f
    mov qword ptr [rip + g_no_config], 1
    jmp 8f
1:  mov rdi, rbx
    lea rsi, [rip + s_no_editorconfig]
    call cstr_eq
    test eax, eax
    jz 9f
    mov qword ptr [rip + g_no_editorconfig], 1
8:  mov eax, 1
9:  add rsp, 8
    pop rbx
    leave
    ret
ENDF cfg_flag

# cfg_before_read(): a file argument. Prettier resolves its config before
# reading it, so config problems count even for an ignored file.
FUNC cfg_before_read
    call cfg_setup
    call cfg_bare_path_ok
    cmp qword ptr [rip + g_no_config], 0
    jne 1f
    call cfg_config
1:  leave
    ret
ENDF cfg_before_read

# cfg_after_read(): an ignored file is printed as read and the process exits;
# otherwise the parser comes from the file name and, for stdin, the config is
# resolved now.
FUNC cfg_after_read
    cmp qword ptr [rip + g_from_stdin], 0
    je 1f
    call cfg_setup
1:  call cfg_ignored
    test eax, eax
    jz 3f
    mov rdi, [rip + g_input]
    mov rsi, [rip + g_input_len]
    call cfg_utf8_ok
    test eax, eax
    jz 90f
    mov edi, 1
    mov rsi, [rip + g_input]
    mov rdx, [rip + g_input_len]
    call write_all
    xor edi, edi
    call sys_exit
3:  call infer_parser
    cmp qword ptr [rip + g_from_stdin], 0
    je 4f
    cmp qword ptr [rip + g_no_config], 0
    jne 4f
    call cfg_config
4:  leave
    ret
90: REFUSE "ignored file that is not valid UTF-8"
ENDF cfg_after_read
