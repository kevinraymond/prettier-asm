# Glob matching for config files: the minimatch fork inside the editorconfig
# package (section names), and the part of picomatch that `overrides` globs use.
# Strings are (ptr, len) pairs; lists of them are arena blocks of
# count, then ptr and len per string.
.include "defs.inc"

.equ MAX_EXPANSIONS, 4096
.equ MAX_SEGS, 256

    .bss
    .balign 8
gl_pseg: .space 16 * MAX_SEGS      # pattern segments
gl_fseg: .space 16 * MAX_SEGS      # path segments
gl_fcount: .quad 0

    .text

# gl_strlist_one(ptr, len) -> rax: a list holding one string
FUNC gl_strlist_one
    push rdi
    push rsi
    mov edi, 24
    call alloc
    pop rsi
    pop rdi
    mov qword ptr [rax], 1
    mov [rax + 8], rdi
    mov [rax + 16], rsi
    leave
    ret
ENDF gl_strlist_one

# gl_concat3(p1, l1, p2, l2, p3, l3) -> rax = ptr (len l1+l2+l3)
FUNC gl_concat3
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov rbx, rdx
    mov r12, rcx
    mov r13, r8
    mov r14, r9
    lea rdi, [rsi + rcx]
    add rdi, r9
    inc rdi
    call alloc
    mov r15, rax
    mov rdi, rax
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call memcpy
    mov rdi, r15
    add rdi, [rsp + 8]
    mov rsi, rbx
    mov rdx, r12
    call memcpy
    mov rdi, r15
    add rdi, [rsp + 8]
    add rdi, r12
    mov rsi, r13
    mov rdx, r14
    call memcpy
    mov rax, r15
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF gl_concat3

# gl_brace_expand(ptr, len, mode) -> rax = string list. Every brace group must
# be closed and hold a comma at its own depth; numeric ranges and single
# members (which minimatch leaves as text) are refused. Mode 1 is the
# picomatch subset: no nesting, members are plain names.
FUNC gl_brace_expand
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rdi                    # ptr
    mov r12, rsi                    # len
    mov [rsp + 48], rdx             # mode
    xor ecx, ecx
1:  cmp rcx, r12
    jae 80f
    cmp byte ptr [rbx + rcx], '{'
    je 2f
    cmp byte ptr [rbx + rcx], '}'
    je 90f
    inc rcx
    jmp 1b
2:  mov [rsp + 56], rcx             # prefix length = index of '{'
    lea rcx, [rcx + 1]
    mov edx, 1                      # depth
    xor r8d, r8d                    # commas at depth 1
3:  cmp rcx, r12
    jae 90f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, '{'
    jne 31f
    cmp qword ptr [rsp + 48], 1
    je 90f
    inc edx
    jmp 34f
31: cmp al, '}'
    jne 32f
    dec edx
    jz 35f
    jmp 34f
32: cmp al, ','
    jne 34f
    cmp edx, 1
    jne 34f
    inc r8
34: inc rcx
    jmp 3b
35: test r8, r8
    jz 90f
    mov r14, rcx                    # index of the closing '}'
    lea rdi, [rbx + r14 + 1]
    mov rsi, r12
    sub rsi, r14
    dec rsi
    mov rdx, [rsp + 48]
    call gl_brace_expand
    mov [rsp], rax                  # suffix list
    call ss_mark
    mov [rsp + 8], rax
    mov r15, [rsp + 56]
    inc r15                         # member start
    mov rcx, r15
    xor edx, edx                    # depth inside the group
4:  movzx eax, byte ptr [rbx + rcx]
    cmp rcx, r14
    je 45f
    cmp al, '{'
    jne 41f
    inc edx
    jmp 44f
41: cmp al, '}'
    jne 42f
    dec edx
    jmp 44f
42: cmp al, ','
    jne 44f
    test edx, edx
    jnz 44f
45: mov [rsp + 16], rcx
    mov [rsp + 24], rdx
    lea rdi, [rbx + r15]
    mov rsi, rcx
    sub rsi, r15
    cmp qword ptr [rsp + 48], 1
    jne 46f
    mov [rsp + 32], rdi
    mov [rsp + 40], rsi
    call gl_pico_name_ok
    mov rdi, [rsp + 32]
    mov rsi, [rsp + 40]
46: mov rdx, [rsp + 48]
    call gl_brace_expand
    mov rdi, rax
    call ss_push
    mov rcx, [rsp + 16]
    mov rdx, [rsp + 24]
    lea r15, [rcx + 1]
    cmp rcx, r14
    je 5f
44: inc rcx
    jmp 4b
5:  mov rdi, [rsp + 8]
    call ss_to_vec
    mov [rsp + 8], rax              # VEC of member lists
    mov rcx, [rax]
    xor r8d, r8d
51: test rcx, rcx
    jz 52f
    mov rdx, [rax + rcx*8]
    add r8, [rdx]
    dec rcx
    jmp 51b
52: mov rdx, [rsp]
    imul r8, [rdx]
    cmp r8, MAX_EXPANSIONS
    ja 91f
    mov [rsp + 24], r8
    mov rdi, r8
    shl rdi, 4
    add rdi, 8
    call alloc
    mov [rsp + 32], rax             # result list
    mov rcx, [rsp + 24]
    mov [rax], rcx
    lea r15, [rax + 8]              # write cursor
    mov qword ptr [rsp + 40], 0     # member index
6:  mov rax, [rsp + 8]
    mov rcx, [rsp + 40]
    cmp rcx, [rax]
    jae 70f
    mov r13, [rax + 8 + rcx*8]      # member list
    xor r12d, r12d
61: cmp r12, [r13]
    jae 69f
    xor r14d, r14d
62: mov rax, [rsp]
    cmp r14, [rax]
    jae 68f
    mov r8, r14
    shl r8, 4
    mov r9, [rax + 16 + r8]         # suffix len
    mov r8, [rax + 8 + r8]          # suffix ptr
    mov rax, r12
    shl rax, 4
    mov rdx, [r13 + 8 + rax]        # member ptr
    mov rcx, [r13 + 16 + rax]       # member len
    mov rsi, [rsp + 56]
    lea rax, [rsi + rcx]
    add rax, r9
    mov [rsp + 16], rax
    mov rdi, rbx
    call gl_concat3
    mov [r15], rax
    mov rax, [rsp + 16]
    mov [r15 + 8], rax
    add r15, 16
    inc r14
    jmp 62b
68: inc r12
    jmp 61b
69: inc qword ptr [rsp + 40]
    jmp 6b
70: mov rax, [rsp + 32]
    jmp 99f
80: mov rdi, rbx
    mov rsi, r12
    call gl_strlist_one
99: add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "glob braces not ported"
91: REFUSE "glob expands too far"
ENDF gl_brace_expand

# ---------------------------------------------------------------- segments

    .bss
    .balign 8
gl_pcount: .quad 0
gl_pico:   .quad 0                  # 1: picomatch rules, 0: minimatch rules
    .text

# gl_seg_split(ptr, len, out) -> rax = count. Runs of '/' separate segments;
# empty segments are dropped, as minimatch's split(/\/+/) and a path without
# empty parts give.
FUNC gl_seg_split
    xor eax, eax
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 9f
    cmp byte ptr [rdi + rcx], '/'
    jne 2f
    inc rcx
    jmp 1b
2:  mov r8, rcx                     # segment start
3:  inc rcx
    cmp rcx, rsi
    jae 4f
    cmp byte ptr [rdi + rcx], '/'
    jne 3b
4:  cmp rax, MAX_SEGS
    jae 90f
    mov r9, rax
    shl r9, 4
    lea r10, [rdi + r8]
    mov [rdx + r9], r10
    mov r10, rcx
    sub r10, r8
    mov [rdx + r9 + 8], r10
    inc rax
    jmp 1b
9:  leave
    ret
90: REFUSE "path too deep for globs"
ENDF gl_seg_split

# gl_wild_match(p, plen, s, slen) -> rax: '*' matches any run, '?' one byte,
# anything else itself.
FUNC gl_wild_match
    push rbx
    push r12
    xor r8, r8                      # pattern index
    xor r9, r9                      # string index
    mov r10, -1                     # pattern index after the last star
    xor r11, r11                    # string index for that star
1:  cmp r9, rcx
    jae 5f
    cmp r8, rsi
    jae 3f
    movzx eax, byte ptr [rdi + r8]
    cmp al, '*'
    jne 2f
    inc r8
    mov r10, r8
    mov r11, r9
    jmp 1b
2:  cmp al, '?'
    je 21f
    cmp al, [rdx + r9]
    jne 3f
21: inc r8
    inc r9
    jmp 1b
3:  cmp r10, -1
    je 8f
    inc r11
    mov r9, r11
    mov r8, r10
    jmp 1b
5:  cmp r8, rsi
    jae 7f
    cmp byte ptr [rdi + r8], '*'
    jne 8f
    inc r8
    jmp 5b
7:  mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF gl_wild_match

# gl_seg_match(p, plen, s, slen) -> rax. A segment with no wildcard compares
# exactly; one with a wildcard matches as a regex anchored at both ends.
FUNC gl_seg_match
    xor eax, eax
    xor r8d, r8d
1:  cmp r8, rsi
    jae 2f
    movzx r9d, byte ptr [rdi + r8]
    cmp r9b, '*'
    je 5f
    cmp r9b, '?'
    je 5f
    inc r8
    jmp 1b
2:  cmp rsi, rcx
    jne 9f
    mov rsi, rdx
    mov rdx, rcx
    call mem_eq
    jmp 9f
5:  call gl_wild_match
9:  leave
    ret
ENDF gl_seg_match

# gl_match_one(pi, fi) -> rax: pattern segments gl_pseg[pi..] against path
# segments gl_fseg[fi..], minimatch's matchOne with dot set.
FUNC gl_match_one
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
1:  cmp rbx, [rip + gl_pcount]
    jae 7f
    cmp r12, [rip + gl_fcount]
    jae 6f
    mov rax, rbx
    shl rax, 4
    lea rcx, [rip + gl_pseg]
    mov rdi, [rcx + rax]
    mov rsi, [rcx + rax + 8]
    cmp rsi, 2
    jne 3f
    cmp word ptr [rdi], 0x2a2a      # "**"
    jne 3f
    # globstar
    lea r13, [rbx + 1]
    cmp r13, [rip + gl_pcount]
    jae 80f
    mov r14, r12
2:  cmp r14, [rip + gl_fcount]
    jae 81f
    mov rdi, r13
    mov rsi, r14
    call gl_match_one
    test eax, eax
    jnz 80f
    inc r14
    jmp 2b
3:  mov rax, r12
    shl rax, 4
    lea rcx, [rip + gl_fseg]
    mov rdx, [rcx + rax]
    mov rcx, [rcx + rax + 8]
    call gl_seg_match
    test eax, eax
    jz 81f
    inc rbx
    inc r12
    jmp 1b
    # the path ran out first: picomatch lets trailing globstars match nothing,
    # unless the segment before them ends in a star ("*/**" needs a segment)
6:  cmp qword ptr [rip + gl_pico], 0
    je 81f
    test rbx, rbx
    jz 61f
    mov rax, rbx
    shl rax, 4
    lea rcx, [rip + gl_pseg]
    mov rdi, [rcx + rax - 16]
    mov rsi, [rcx + rax - 8]
    cmp byte ptr [rdi + rsi - 1], '*'
    jne 61f
    cmp rsi, 2
    jne 81f
    cmp byte ptr [rdi], '*'
    jne 81f
61: cmp rbx, [rip + gl_pcount]
    jae 80f
    mov rax, rbx
    shl rax, 4
    lea rcx, [rip + gl_pseg]
    cmp qword ptr [rcx + rax + 8], 2
    jne 81f
    mov rdi, [rcx + rax]
    cmp word ptr [rdi], 0x2a2a
    jne 81f
    inc rbx
    jmp 61b
7:  cmp r12, [rip + gl_fcount]
    jne 81f
80: mov eax, 1
    jmp 9f
81: xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF gl_match_one

# gl_match_list(list) -> rax: 1 when any string in the list matches the path
# already split into gl_fseg. A pattern ending in '/' never matches a file.
FUNC gl_match_list
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    xor r12d, r12d
1:  cmp r12, [rbx]
    jae 8f
    mov rax, r12
    shl rax, 4
    mov rdi, [rbx + 8 + rax]
    mov rsi, [rbx + 16 + rax]
    inc r12
    test rsi, rsi
    jz 1b
    cmp byte ptr [rdi + rsi - 1], '/'
    je 1b
    lea rdx, [rip + gl_pseg]
    call gl_seg_split
    mov [rip + gl_pcount], rax
    xor edi, edi
    xor esi, esi
    call gl_match_one
    test eax, eax
    jz 1b
    mov eax, 1
    jmp 9f
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF gl_match_list

# ---------------------------------------------------------------- editorconfig

# gl_ec_match(glob, glen, rel, rlen) -> rax: does the section name match
# the file at `rel` below the .editorconfig's directory. The editorconfig
# package joins the directory and the glob ("**/" first when the glob has no
# slash), turns every "**" into "{*,**/**/**}", and runs its minimatch fork
# with matchBase, dot and noext.
FUNC gl_ec_match
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    # characters: printable ASCII without classes or escapes
    xor ecx, ecx
    xor r8d, r8d                    # has '/'
1:  cmp rcx, r12
    jae 2f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, 0x20
    jb 90f
    cmp al, 0x7e
    ja 90f
    cmp al, '['
    je 90f
    cmp al, ']'
    je 90f
    cmp al, '\\'
    je 90f
    cmp al, '/'
    jne 11f
    mov r8d, 1
11: inc rcx
    jmp 1b
2:  # glob relative to the directory
    test r8d, r8d
    jnz 21f
    lea rdi, [rip + s_any_dir]
    mov esi, 3
    mov rdx, rbx
    mov rcx, r12
    xor r8d, r8d
    xor r9d, r9d
    call gl_concat3
    mov rbx, rax
    add r12, 3
    jmp 23f
21: cmp byte ptr [rbx], '/'
    jne 23f
    inc rbx
    dec r12
    # path.join would rewrite empty, "." and ".." segments
23: xor ecx, ecx
    mov r8, rcx                     # segment start
24: cmp rcx, r12
    je 25f
    cmp byte ptr [rbx + rcx], '/'
    je 25f
    inc rcx
    jmp 24b
25: mov rax, rcx
    sub rax, r8
    jz 90f
    cmp rax, 1
    jne 26f
    cmp byte ptr [rbx + r8], '.'
    je 90f
26: cmp rax, 2
    jne 27f
    cmp word ptr [rbx + r8], 0x2e2e
    je 90f
27: cmp rcx, r12
    jae 3f
    inc rcx
    mov r8, rcx
    jmp 24b
    # "**" -> "{*,**/**/**}"
3:  lea rdi, [r12 + r12*8]
    add rdi, 8
    call alloc
    mov r15, rax
    xor ecx, ecx
    xor edx, edx
31: cmp rcx, r12
    jae 34f
    movzx eax, byte ptr [rbx + rcx]
    cmp al, '*'
    jne 33f
    lea r8, [rcx + 1]
    cmp r8, r12
    jae 33f
    cmp byte ptr [rbx + r8], '*'
    jne 33f
    lea rsi, [rip + s_globstar_braces]
    xor r9d, r9d
32: movzx eax, byte ptr [rsi + r9]
    test al, al
    jz 321f
    mov [r15 + rdx], al
    inc rdx
    inc r9
    jmp 32b
321: add rcx, 2
    jmp 31b
33: mov [r15 + rdx], al
    inc rdx
    inc rcx
    jmp 31b
34: mov rdi, r15
    mov rsi, rdx
    xor edx, edx
    call gl_brace_expand
    mov [rsp], rax
    mov rdi, r13
    mov rsi, r14
    lea rdx, [rip + gl_fseg]
    call gl_seg_split
    mov [rip + gl_fcount], rax
    mov qword ptr [rip + gl_pico], 0
    mov rdi, [rsp]
    call gl_match_list
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "editorconfig section glob not ported"
ENDF gl_ec_match

    .section .rodata
s_any_dir: .ascii "**/"
s_globstar_braces: .asciz "{*,**/**/**}"
    .text

# ---------------------------------------------------------------- picomatch

# gl_pico_name_ok(ptr, len): a brace member must be a plain name.
FUNC gl_pico_name_ok
    test rsi, rsi
    jz 90f
    xor ecx, ecx
1:  cmp rcx, rsi
    jae 2f
    movzx eax, byte ptr [rdi + rcx]
    inc rcx
    cmp al, '.'
    je 1b
    cmp al, '_'
    je 1b
    cmp al, '-'
    je 1b
    mov dl, al
    sub dl, '0'
    cmp dl, 9
    jbe 1b
    or al, 0x20
    sub al, 'a'
    cmp al, 25
    jbe 1b
    jmp 90f
2:  cmp rsi, 2
    ja 9f
    cmp byte ptr [rdi], '.'
    jne 9f
    cmp rsi, 1
    je 90f
    cmp byte ptr [rdi + 1], '.'
    je 90f
9:  leave
    ret
90: REFUSE "override glob not ported"
ENDF gl_pico_name_ok

# gl_pico_match(glob, glen, path, plen, basename) -> rax: micromatch.isMatch with
# dot set, for globs made of names, '*', '?', "**" segments and flat
# {a,b} groups. With basename set, the glob is tested against the last
# path segment, as picomatch's matchBase does.
FUNC gl_pico_match
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    test r12, r12
    jz 90f
    # picomatch tests input === glob before the regex
    cmp r12, r14
    jne 10f
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    call mem_eq
    test eax, eax
    jz 10f
    mov eax, 1
    jmp 99f
10:
    # characters, commas only inside braces
    xor ecx, ecx
    xor edx, edx                    # inside braces
1:  cmp rcx, r12
    jae 2f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '{'
    jne 11f
    mov edx, 1
    jmp 1b
11: cmp al, '}'
    jne 12f
    xor edx, edx
    jmp 1b
12: cmp al, ','
    jne 13f
    test edx, edx
    jz 90f
    jmp 1b
13: cmp al, '*'
    je 1b
    cmp al, '?'
    je 1b
    cmp al, '/'
    je 1b
    cmp al, '.'
    je 1b
    cmp al, '_'
    je 1b
    cmp al, '-'
    je 1b
    mov r8b, al
    sub r8b, '0'
    cmp r8b, 9
    jbe 1b
    or al, 0x20
    sub al, 'a'
    cmp al, 25
    jbe 1b
    jmp 90f
2:  mov rdi, rbx
    mov rsi, r12
    mov edx, 1
    call gl_brace_expand
    mov r15, rax
    # check every segment of every expansion
    xor ecx, ecx
3:  cmp rcx, [r15]
    jae 4f
    mov rax, rcx
    shl rax, 4
    mov rdi, [r15 + 8 + rax]
    mov rsi, [r15 + 16 + rax]
    mov [rsp + 8], rcx
    call gl_pico_segments_ok
    mov rcx, [rsp + 8]
    inc rcx
    jmp 3b
    # the string to test
4:  mov rdi, r13
    mov rsi, r14
    cmp qword ptr [rsp], 0
    je 5f
    lea rax, [r13 + r14]
41: cmp rax, r13
    je 42f
    cmp byte ptr [rax - 1], '/'
    je 42f
    dec rax
    jmp 41b
42: mov rdi, rax
    lea rsi, [r13 + r14]
    sub rsi, rax
5:  lea rdx, [rip + gl_fseg]
    call gl_seg_split
    mov [rip + gl_fcount], rax
    mov qword ptr [rip + gl_pico], 1
    mov rdi, r15
    call gl_match_list
99: add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "override glob not ported"
ENDF gl_pico_match

# gl_pico_segments_ok(ptr, len): no empty, "." or ".." segments; "**" only alone.
FUNC gl_pico_segments_ok
    xor ecx, ecx
    xor r8d, r8d                    # segment start
1:  cmp rcx, rsi
    je 2f
    cmp byte ptr [rdi + rcx], '/'
    je 2f
    inc rcx
    jmp 1b
2:  mov rax, rcx
    sub rax, r8
    jz 90f
    # stars: either the whole segment is "**", or no two in a row
    xor r9d, r9d
    lea r10, [rdi + r8]
3:  cmp r9, rax
    jae 4f
    cmp byte ptr [r10 + r9], '*'
    jne 31f
    lea r11, [r9 + 1]
    cmp r11, rax
    jae 31f
    cmp byte ptr [r10 + r11], '*'
    jne 31f
    cmp rax, 2
    jne 90f
31: inc r9
    jmp 3b
4:  cmp rax, 1
    jne 41f
    cmp byte ptr [r10], '.'
    je 90f
41: cmp rax, 2
    jne 42f
    cmp word ptr [r10], 0x2e2e
    je 90f
42: cmp rcx, rsi
    jae 9f
    inc rcx
    mov r8, rcx
    jmp 1b
9:  leave
    ret
90: REFUSE "override glob not ported"
ENDF gl_pico_segments_ok
