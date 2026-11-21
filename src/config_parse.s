# Readers for config files: JSON as JSON.parse accepts it, and the small part
# of YAML that a hand-written .prettierrc uses. Both build CV records.
.include "defs.inc"

    .bss
    .balign 8
jp_pos:   .quad 0
jp_end:   .quad 0
jp_rsp:   .quad 0
jp_rbp:   .quad 0
jp_mark:  .quad 0
jp_depth: .quad 0

    .text

# cv_new(type) -> rax: zeroed CV
FUNC cv_new
    push rdi
    sub rsp, 8
    mov edi, CV_SIZE
    call alloc
    add rsp, 8
    pop rdi
    mov [rax + CV_TYPE], dil
    leave
    ret
ENDF cv_new

# cfg_json_parse(ptr, len) -> rax = CV, or 0 when JSON.parse would throw.
FUNC cfg_json_parse
    push rbx
    push r12
    push r13
    push r14
    mov [rip + jp_pos], rdi
    add rsi, rdi
    mov [rip + jp_end], rsi
    mov qword ptr [rip + jp_depth], 0
    call ss_mark
    mov [rip + jp_mark], rax
    mov [rip + jp_rsp], rsp
    mov [rip + jp_rbp], rbp
    call jp_value
    mov rbx, rax
    call jp_ws
    mov rax, [rip + jp_pos]
    cmp rax, [rip + jp_end]
    jne jp_fail
    mov rax, rbx
    jmp 9f
jp_fail:
    mov rsp, [rip + jp_rsp]
    mov rbp, [rip + jp_rbp]
    mov rax, [rip + jp_mark]
    mov [rip + g_ss_ptr], rax
    xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF cfg_json_parse

# jp_ws(): skips JSON whitespace
FUNC jp_ws
    mov rax, [rip + jp_pos]
    mov rdx, [rip + jp_end]
1:  cmp rax, rdx
    jae 2f
    movzx ecx, byte ptr [rax]
    cmp cl, ' '
    je 3f
    cmp cl, 9
    je 3f
    cmp cl, 10
    je 3f
    cmp cl, 13
    jne 2f
3:  inc rax
    jmp 1b
2:  mov [rip + jp_pos], rax
    leave
    ret
ENDF jp_ws

# jp_peek() -> eax = byte at the cursor, 0 at the end
FUNC jp_peek
    mov rdx, [rip + jp_pos]
    xor eax, eax
    cmp rdx, [rip + jp_end]
    jae 1f
    movzx eax, byte ptr [rdx]
1:  leave
    ret
ENDF jp_peek

# jp_value() -> rax = CV
FUNC jp_value
    push rbx
    push r12
    push r13
    push r14
    call jp_ws
    call jp_peek
    cmp al, '{'
    je 10f
    cmp al, '['
    je 20f
    cmp al, '"'
    je 30f
    cmp al, 't'
    je 40f
    cmp al, 'f'
    je 41f
    cmp al, 'n'
    je 42f
    cmp al, '-'
    je 50f
    sub al, '0'
    cmp al, 9
    jbe 50f
    jmp jp_fail
    # object
10: call jp_enter
    call ss_mark
    mov r12, rax
    call jp_ws
    call jp_peek
    cmp al, '}'
    je 15f
11: call jp_ws
    call jp_peek
    cmp al, '"'
    jne jp_fail
    call jp_string
    mov rdi, rax
    call ss_push
    call jp_ws
    call jp_peek
    cmp al, ':'
    jne jp_fail
    inc qword ptr [rip + jp_pos]
    call jp_value
    mov rdi, rax
    call ss_push
    call jp_ws
    call jp_peek
    inc qword ptr [rip + jp_pos]
    cmp al, ','
    je 11b
    cmp al, '}'
    jne jp_fail
    jmp 16f
15: inc qword ptr [rip + jp_pos]
16: mov rdi, r12
    call ss_to_vec
    mov rbx, rax
    mov edi, CV_OBJ
    jmp 25f
    # array
20: call jp_enter
    call ss_mark
    mov r12, rax
    call jp_ws
    call jp_peek
    cmp al, ']'
    je 23f
21: call jp_value
    mov rdi, rax
    call ss_push
    call jp_ws
    call jp_peek
    inc qword ptr [rip + jp_pos]
    cmp al, ','
    je 21b
    cmp al, ']'
    jne jp_fail
    jmp 24f
23: inc qword ptr [rip + jp_pos]
24: mov rdi, r12
    call ss_to_vec
    mov rbx, rax
    mov edi, CV_ARR
25: call cv_new
    mov [rax + CV_A], rbx
    dec qword ptr [rip + jp_depth]
    jmp 99f
30: call jp_string
    jmp 99f
40: lea rdi, [rip + s_true]
    mov ebx, CV_TRUE
    jmp 45f
41: lea rdi, [rip + s_false]
    mov ebx, CV_FALSE
    jmp 45f
42: lea rdi, [rip + s_null]
    mov ebx, CV_NULL
45: call jp_word
    mov edi, ebx
    call cv_new
    jmp 99f
50: call jp_number
99: pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF jp_value

    .section .rodata
s_true:  .asciz "true"
s_false: .asciz "false"
s_null:  .asciz "null"
    .text

# jp_enter(): one level deeper; V8 parses far deeper than any config needs.
FUNC jp_enter
    inc qword ptr [rip + jp_pos]
    mov rax, [rip + jp_depth]
    inc rax
    mov [rip + jp_depth], rax
    cmp rax, 1000
    ja 9f
    leave
    ret
9:  REFUSE "config nested too deep"
ENDF jp_enter

# jp_word(cstr): the cursor must be at this literal; skips it.
FUNC jp_word
    mov rsi, [rip + jp_pos]
    mov rdx, [rip + jp_end]
1:  movzx eax, byte ptr [rdi]
    test al, al
    jz 2f
    cmp rsi, rdx
    jae jp_fail
    cmp al, [rsi]
    jne jp_fail
    inc rdi
    inc rsi
    jmp 1b
2:  mov [rip + jp_pos], rsi
    leave
    ret
ENDF jp_word

# jp_string() -> rax = CV_STR; the cursor is at the opening quote.
FUNC jp_string
    push rbx
    push r12
    mov rsi, [rip + jp_pos]
    mov rdx, [rip + jp_end]
    inc rsi
    mov rbx, rsi                    # start
    xor r12d, r12d                  # flags
1:  cmp rsi, rdx
    jae jp_fail
    movzx eax, byte ptr [rsi]
    cmp al, '"'
    je 5f
    cmp al, '\\'
    je 2f
    cmp al, 0x20
    jb jp_fail
    inc rsi
    jmp 1b
2:  or r12d, CVF_ESC
    inc rsi
    cmp rsi, rdx
    jae jp_fail
    movzx eax, byte ptr [rsi]
    inc rsi
    lea rdi, [rip + s_escapes]
3:  movzx ecx, byte ptr [rdi]
    test ecx, ecx
    jz 4f
    cmp eax, ecx
    je 1b
    inc rdi
    jmp 3b
4:  cmp al, 'u'
    jne jp_fail
    mov ecx, 4
41: cmp rsi, rdx
    jae jp_fail
    movzx eax, byte ptr [rsi]
    inc rsi
    or al, 0x20
    sub al, '0'
    cmp al, 9
    jbe 42f
    sub al, 'a' - '0'
    cmp al, 5
    ja jp_fail
42: dec ecx
    jnz 41b
    jmp 1b
5:  lea rax, [rsi + 1]
    mov [rip + jp_pos], rax
    mov rcx, rsi
    sub rcx, rbx
    push rcx
    sub rsp, 8
    mov edi, CV_STR
    call cv_new
    add rsp, 8
    pop rcx
    mov [rax + CV_A], rbx
    mov [rax + CV_B], rcx
    mov [rax + CV_FLAGS], r12b
    pop r12
    pop rbx
    leave
    ret
ENDF jp_string

    .section .rodata
s_escapes: .asciz "\"\\/bfnrt"
    .text

# jp_number() -> rax = CV_NUM. Grammar: -?(0|[1-9][0-9]*)(.[0-9]+)?([eE][+-]?[0-9]+)?
FUNC jp_number
    push rbx
    push r12
    mov rsi, [rip + jp_pos]
    mov rdx, [rip + jp_end]
    mov r12d, CVF_INT
    xor ebx, ebx                    # value
    cmp byte ptr [rsi], '-'
    jne 1f
    xor r12d, r12d
    inc rsi
1:  cmp rsi, rdx
    jae jp_fail
    movzx eax, byte ptr [rsi]
    cmp al, '0'
    jne 2f
    inc rsi
    jmp 4f
2:  sub al, '0'
    cmp al, 9
    ja jp_fail
3:  cmp rsi, rdx
    jae 4f
    movzx eax, byte ptr [rsi]
    sub al, '0'
    cmp al, 9
    ja 4f
    imul rbx, rbx, 10
    add rbx, rax
    cmp rbx, 0x7fffffff
    jbe 31f
    xor r12d, r12d
    mov ebx, 0x7fffffff
31: inc rsi
    jmp 3b
4:  cmp rsi, rdx
    jae 8f
    cmp byte ptr [rsi], '.'
    jne 6f
    xor r12d, r12d
    inc rsi
    call jp_digits
6:  cmp rsi, rdx
    jae 8f
    movzx eax, byte ptr [rsi]
    or al, 0x20
    cmp al, 'e'
    jne 8f
    xor r12d, r12d
    inc rsi
    cmp rsi, rdx
    jae jp_fail
    movzx eax, byte ptr [rsi]
    cmp al, '+'
    je 7f
    cmp al, '-'
    jne 71f
7:  inc rsi
71: call jp_digits
8:  mov [rip + jp_pos], rsi
    mov edi, CV_NUM
    call cv_new
    mov [rax + CV_A], rbx
    mov [rax + CV_FLAGS], r12b
    pop r12
    pop rbx
    leave
    ret
ENDF jp_number

# jp_digits(): rsi = cursor, rdx = end; needs one digit or more. Leaves rsi after them.
FUNC jp_digits
    mov rcx, rsi
1:  cmp rsi, rdx
    jae 2f
    movzx eax, byte ptr [rsi]
    sub al, '0'
    cmp al, 9
    ja 2f
    inc rsi
    jmp 1b
2:  cmp rsi, rcx
    je jp_fail
    leave
    ret
ENDF jp_digits

# ---------------------------------------------------------------- CV helpers

# cv_str_is(cv, cstr) -> rax = 1 when cv is a string without escapes equal to cstr
FUNC cv_str_is
    push rbx
    push r12
    xor eax, eax
    test rdi, rdi
    jz 9f
    cmp byte ptr [rdi + CV_TYPE], CV_STR
    jne 9f
    test byte ptr [rdi + CV_FLAGS], CVF_ESC
    jnz 9f
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rsi
    call strlen
    cmp rax, [rbx + CV_B]
    jne 8f
    mov rdi, [rbx + CV_A]
    mov rsi, r12
    mov rdx, rax
    call mem_eq
    jmp 9f
8:  xor eax, eax
9:  pop r12
    pop rbx
    leave
    ret
ENDF cv_str_is

# cv_obj_check(obj): refuses when a key has escapes or appears twice. YAML
# rejects repeated keys; JSON.parse keeps the last one.
FUNC cv_obj_check
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [rdi + CV_A]           # VEC
    mov r12, [rbx]                  # 2 * pairs
    xor r13d, r13d
1:  cmp r13, r12
    jae 9f
    mov rax, [rbx + 8 + r13*8]
    test byte ptr [rax + CV_FLAGS], CVF_ESC
    jnz 90f
    lea r14, [r13 + 2]
2:  cmp r14, r12
    jae 3f
    mov rdi, [rbx + 8 + r13*8]
    mov rsi, [rbx + 8 + r14*8]
    mov rdx, [rdi + CV_B]
    cmp rdx, [rsi + CV_B]
    jne 21f
    mov rdi, [rdi + CV_A]
    mov rsi, [rsi + CV_A]
    call mem_eq
    test eax, eax
    jnz 91f
21: add r14, 2
    jmp 2b
3:  add r13, 2
    jmp 1b
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "config key with escapes"
91: REFUSE "config key repeated"
ENDF cv_obj_check

# cv_obj_get(obj, cstr) -> rax = value of the last key equal to cstr, or 0.
# Refuses when a key has escapes, since it could spell the name.
FUNC cv_obj_get
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, [rdi + CV_A]
    mov r12, [rbx]
    mov r13, rsi
    xor r14d, r14d
    xor r15d, r15d                  # result
1:  cmp r14, r12
    jae 9f
    mov rdi, [rbx + 8 + r14*8]
    test byte ptr [rdi + CV_FLAGS], CVF_ESC
    jnz 90f
    mov rsi, r13
    call cv_str_is
    test eax, eax
    jz 2f
    mov r15, [rbx + 16 + r14*8]
2:  add r14, 2
    jmp 1b
9:  mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "config key with escapes"
ENDF cv_obj_get

# ---------------------------------------------------------------- YAML subset
# cfg_yaml_parse(ptr, len) -> rax = CV_OBJ, or 0 for a document with no content.
# Accepts lines `key: value` at column 0, blank lines and comments. A value is
# a decimal integer, true, false, a lowercase word, or a quoted string with no
# escapes. Everything else is refused: the YAML parser Prettier uses would
# need porting to be sure of the meaning.
FUNC cfg_yaml_parse
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi                    # cursor
    lea r12, [rdi + rsi]            # end
    call ss_mark
    mov r13, rax
    xor r15d, r15d                  # number of keys
    # line loop
1:  cmp rbx, r12
    jae 80f
    mov rsi, rbx
    # skip leading spaces
2:  cmp rsi, r12
    jae 80f
    movzx eax, byte ptr [rsi]
    cmp al, ' '
    jne 3f
    inc rsi
    jmp 2b
3:  cmp al, 10
    je 70f
    cmp al, 13
    je 65f
    cmp al, '#'
    je 60f
    cmp rsi, rbx
    jne 90f                         # indented content
    # key
    mov r14, rsi
4:  cmp rsi, r12
    jae 90f
    movzx eax, byte ptr [rsi]
    cmp al, ':'
    je 5f
    mov ecx, eax
    or cl, 0x20
    sub cl, 'a'
    cmp cl, 25
    jbe 41f
    cmp rsi, r14
    je 90f
    sub al, '0'
    cmp al, 9
    ja 90f
41: inc rsi
    jmp 4b
5:  cmp rsi, r14
    je 90f
    mov rcx, rsi
    sub rcx, r14
    push rsi
    push rcx
    mov edi, CV_STR
    call cv_new
    pop rcx
    pop rsi
    mov [rax + CV_A], r14
    mov [rax + CV_B], rcx
    push rsi
    sub rsp, 8
    mov rdi, rax
    call ss_push
    add rsp, 8
    pop rsi
    inc rsi                         # past ':'
    cmp rsi, r12
    jae 90f
    cmp byte ptr [rsi], ' '
    jne 90f
51: cmp rsi, r12
    jae 90f
    cmp byte ptr [rsi], ' '
    jne 52f
    inc rsi
    jmp 51b
52: mov rdi, rsi
    mov rsi, r12
    call cfg_yaml_scalar                # rax = CV, rdx = cursor after it
    mov rbx, rdx
    mov rdi, rax
    call ss_push
    inc r15
    mov rsi, rbx
    # after the value: spaces, then a comment or the end of the line
53: cmp rsi, r12
    jae 80f
    movzx eax, byte ptr [rsi]
    cmp al, ' '
    jne 54f
    inc rsi
    jmp 53b
54: cmp al, 10
    je 70f
    cmp al, 13
    je 65f
    cmp al, '#'
    jne 90f
    cmp rsi, rbx
    je 90f                          # `#` must follow a space
    # comment: to the end of the line
60: cmp rsi, r12
    jae 80f
    movzx eax, byte ptr [rsi]
    cmp al, 10
    je 70f
    cmp al, 9
    je 61f
    cmp al, 0x20
    jb 90f
    cmp al, 0x7e
    ja 90f
61: inc rsi
    jmp 60b
65: inc rsi                         # CR must be followed by LF
    cmp rsi, r12
    jae 90f
    cmp byte ptr [rsi], 10
    jne 90f
70: lea rbx, [rsi + 1]
    jmp 1b
80: mov rdi, r13
    call ss_to_vec
    xor ecx, ecx
    test r15, r15
    jz 81f
    mov rbx, rax
    mov edi, CV_OBJ
    call cv_new
    mov [rax + CV_A], rbx
    mov rbx, rax
    mov rdi, rax
    call cv_obj_check
    mov rcx, rbx
81: mov rax, rcx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "YAML config not ported"
ENDF cfg_yaml_parse

# cfg_yaml_scalar(ptr, end) -> rax = CV, rdx = cursor after the scalar
FUNC cfg_yaml_scalar
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    movzx eax, byte ptr [rbx]
    cmp al, '"'
    je 30f
    cmp al, 0x27
    je 30f
    # plain: up to a space, CR or LF
    mov r13, rbx
1:  cmp r13, r12
    jae 2f
    movzx eax, byte ptr [r13]
    cmp al, ' '
    je 2f
    cmp al, 10
    je 2f
    cmp al, 13
    je 2f
    inc r13
    jmp 1b
2:  mov r14, r13
    sub r14, rbx                    # length
    jz 90f
    # true / false
    cmp r14, 4
    jne 3f
    cmp dword ptr [rbx], 0x65757274 # "true"
    jne 3f
    mov edi, CV_TRUE
    call cv_new
    jmp 80f
3:  cmp r14, 5
    jne 4f
    cmp dword ptr [rbx], 0x736c6166 # "fals"
    jne 4f
    cmp byte ptr [rbx + 4], 'e'
    jne 4f
    mov edi, CV_FALSE
    call cv_new
    jmp 80f
4:  movzx eax, byte ptr [rbx]
    sub al, '1'
    cmp al, 8
    jbe 20f
    # lowercase word: [a-z][a-z0-9-]*, not null
    movzx eax, byte ptr [rbx]
    sub al, 'a'
    cmp al, 25
    ja 90f
    xor ecx, ecx
5:  cmp rcx, r14
    jae 6f
    movzx eax, byte ptr [rbx + rcx]
    inc rcx
    cmp al, '-'
    je 5b
    mov dl, al
    sub dl, '0'
    cmp dl, 9
    jbe 5b
    sub al, 'a'
    cmp al, 25
    jbe 5b
    jmp 90f
6:  cmp r14, 4
    jne 7f
    cmp dword ptr [rbx], 0x6c6c756e # "null"
    je 90f
7:  mov edi, CV_STR
    call cv_new
    mov [rax + CV_A], rbx
    mov [rax + CV_B], r14
    jmp 80f
    # integer [1-9][0-9]*
20: xor edx, edx
    xor ecx, ecx
21: cmp rcx, r14
    jae 22f
    movzx eax, byte ptr [rbx + rcx]
    sub al, '0'
    cmp al, 9
    ja 90f
    imul rdx, rdx, 10
    add rdx, rax
    cmp rdx, 0x7fffffff
    ja 90f
    inc rcx
    jmp 21b
22: push rdx
    sub rsp, 8
    mov edi, CV_NUM
    call cv_new
    add rsp, 8
    pop rdx
    mov [rax + CV_A], rdx
    mov byte ptr [rax + CV_FLAGS], CVF_INT
    jmp 80f
    # quoted, no escapes
30: mov r14d, eax                   # quote
    lea r13, [rbx + 1]
31: cmp r13, r12
    jae 90f
    movzx eax, byte ptr [r13]
    cmp eax, r14d
    je 32f
    cmp al, '\\'
    je 90f
    cmp al, 0x20
    jb 90f
    cmp al, 0x7e
    ja 90f
    inc r13
    jmp 31b
32: mov edi, CV_STR
    call cv_new
    lea rcx, [rbx + 1]
    mov [rax + CV_A], rcx
    mov rdx, r13
    sub rdx, rcx
    mov [rax + CV_B], rdx
    inc r13
    # the closing quote must not be doubled (YAML's '' escape)
    cmp r13, r12
    jae 80f
    movzx ecx, byte ptr [r13]
    cmp ecx, r14d
    je 90f
80: mov rdx, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "YAML config value not ported"
ENDF cfg_yaml_scalar
