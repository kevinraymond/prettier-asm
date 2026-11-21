# AstPath (src/common/ast-path.js).
#
# Prettier's stack is [root, name1, value1, name2, value2, ...] where a value
# is a node or an array. Here each name/value pair is one entry: the value, its
# key (K_*), its index when it is an element of an array (else -1), that array
# (the siblings), and PEF_ARRAY when the value is itself an array. An element
# pushed with its siblings but without an entry for the array behaves as if
# the array entry were there.
#
# Callbacks get (ctx, node, index): rdi ctx, rsi the node now at the top of
# the path, rdx its index (-1 outside arrays). Predicates for path_match get
# (node, key, index) as Prettier's (node, name, number); key 0 is null.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_path_base, g_path_top
g_path_base: .quad 0
g_path_top:  .quad 0        # next free entry

    .text

# path_init(root): the path is [root]
FUNC path_init
    push rdi
    sub rsp, 8
    mov rdi, R_PATH
    call region_base
    add rsp, 8
    pop rdi
    mov [rip + g_path_base], rax
    mov [rip + g_path_top], rax
    xor esi, esi
    mov edx, -1
    xor ecx, ecx
    call path_push
    leave
    ret
ENDF path_init

# path_push(value, key, index, siblings)
FUNC path_push
    mov rax, [rip + g_path_top]
    mov [rax + PE_NODE], rdi
    mov [rax + PE_KEY], esi
    mov [rax + PE_INDEX], edx
    mov [rax + PE_SIBS], rcx
    mov dword ptr [rax + PE_FLAGS], 0
    add rax, PE_SIZE
    mov [rip + g_path_top], rax
    leave
    ret
ENDF path_push

# path_push_array(vec, key): an array value (path.call(fn, "body") on an array)
FUNC path_push_array
    mov rax, [rip + g_path_top]
    mov [rax + PE_NODE], rdi
    mov [rax + PE_KEY], esi
    mov dword ptr [rax + PE_INDEX], -1
    mov qword ptr [rax + PE_SIBS], 0
    mov dword ptr [rax + PE_FLAGS], PEF_ARRAY
    add rax, PE_SIZE
    mov [rip + g_path_top], rax
    leave
    ret
ENDF path_push_array

# path_pop()
FUNC path_pop
    sub qword ptr [rip + g_path_top], PE_SIZE
    leave
    ret
ENDF path_pop

# path_entry_of_node(count) -> rax: the entry of getNode(count), or 0
FUNC path_entry_of_node
    mov rax, [rip + g_path_top]
    mov rcx, [rip + g_path_base]
1:  sub rax, PE_SIZE
    cmp rax, rcx
    jb 8f
    test dword ptr [rax + PE_FLAGS], PEF_ARRAY
    jnz 1b
    dec rdi
    jns 1b
    leave
    ret
8:  xor eax, eax
    leave
    ret
ENDF path_entry_of_node

# path_node(count) -> rax: path.getNode(count): 0 the current node, 1 the
# parent, ... skipping arrays; 0 past the root.
FUNC path_node
    call path_entry_of_node
    test rax, rax
    jz 1f
    mov rax, [rax + PE_NODE]
1:  leave
    ret
ENDF path_node

# path_parent() / path_grandparent() -> rax
FUNC path_parent
    mov edi, 1
    call path_node
    leave
    ret
ENDF path_parent

FUNC path_grandparent
    mov edi, 2
    call path_node
    leave
    ret
ENDF path_grandparent

# path_parent_node(count) -> rax: path.getParentNode(count)
FUNC path_parent_node
    inc rdi
    call path_node
    leave
    ret
ENDF path_parent_node

# path_value() -> rax: path.node (the top value, node or array)
FUNC path_value
    mov rax, [rip + g_path_top]
    mov rax, [rax - PE_SIZE + PE_NODE]
    leave
    ret
ENDF path_value

# path_key() -> eax: path.key (0 for null)
FUNC path_key
    mov rax, [rip + g_path_top]
    mov eax, [rax - PE_SIZE + PE_KEY]
    leave
    ret
ENDF path_key

# path_index() -> rax: path.index, -1 for null
FUNC path_index
    mov rax, [rip + g_path_top]
    movsxd rax, dword ptr [rax - PE_SIZE + PE_INDEX]
    leave
    ret
ENDF path_index

# path_siblings() -> rax: the array the current node is in (VEC or LIST), or 0
FUNC path_siblings
    mov rax, [rip + g_path_top]
    cmp dword ptr [rax - PE_SIZE + PE_INDEX], 0
    jl 1f
    mov rax, [rax - PE_SIZE + PE_SIBS]
    leave
    ret
1:  xor eax, eax
    leave
    ret
ENDF path_siblings

# path_is_in_array() -> eax
FUNC path_is_in_array
    call path_siblings
    test rax, rax
    setnz al
    movzx eax, al
    leave
    ret
ENDF path_is_in_array

# path_is_first() -> eax: index === 0
FUNC path_is_first
    mov rax, [rip + g_path_top]
    cmp dword ptr [rax - PE_SIZE + PE_INDEX], 0
    sete al
    movzx eax, al
    leave
    ret
ENDF path_is_first

# path_is_last() -> eax
FUNC path_is_last
    call path_siblings
    test rax, rax
    jz 1f
    mov ecx, [rax]                  # count (u32 for VEC and LIST)
    dec ecx
    mov rax, [rip + g_path_top]
    xor edx, edx
    cmp ecx, [rax - PE_SIZE + PE_INDEX]
    sete dl
    mov eax, edx
1:  leave
    ret
ENDF path_is_last

# path_previous() / path_next() -> rax: the sibling before/after, or 0
FUNC path_previous
    mov rdi, -1
    call path_sibling_at
    leave
    ret
ENDF path_previous

FUNC path_next
    mov edi, 1
    call path_sibling_at
    leave
    ret
ENDF path_next

# path_sibling_at(delta) -> rax: siblings[index + delta], or 0
FUNC path_sibling_at
    push rdi
    sub rsp, 8
    call path_siblings
    add rsp, 8
    pop rdi
    test rax, rax
    jz 9f
    mov rcx, [rip + g_path_top]
    movsxd rcx, dword ptr [rcx - PE_SIZE + PE_INDEX]
    add rcx, rdi
    js 8f
    cmp ecx, [rax]
    jae 8f
    mov rax, [rax + 8 + rcx*8]
    jmp 9f
8:  xor eax, eax
9:  leave
    ret
ENDF path_sibling_at

# path_is_root() -> eax / path_root() -> rax
FUNC path_is_root
    mov rax, [rip + g_path_top]
    sub rax, [rip + g_path_base]
    cmp rax, PE_SIZE
    sete al
    movzx eax, al
    leave
    ret
ENDF path_is_root

FUNC path_root
    mov rax, [rip + g_path_base]
    mov rax, [rax + PE_NODE]
    leave
    ret
ENDF path_root

# path_call(fn, ctx, key, field_offset) -> rax:
# path.call(fn, key) for a node field of the current node. A 0 field is
# pushed as is (Prettier pushes undefined).
FUNC path_call
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    call path_value
    mov rdi, [rax + rcx]
    push rdi
    sub rsp, 8
    mov esi, edx
    mov edx, -1
    xor ecx, ecx
    call path_push
    add rsp, 8
    pop rsi
    mov rdi, r12
    mov rdx, -1
    call rbx
    sub qword ptr [rip + g_path_top], PE_SIZE
    pop r12
    pop rbx
    leave
    ret
ENDF path_call

# path_call_node(fn, ctx, node, key) -> rax: path.call with a value found by
# the caller (for name chains and computed selectors).
FUNC path_call_node
    push rbx
    push r12
    push r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    mov esi, ecx
    mov edx, -1
    xor ecx, ecx
    call path_push
    mov rdi, r12
    mov rsi, r13
    mov rdx, -1
    call rbx
    sub qword ptr [rip + g_path_top], PE_SIZE
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF path_call_node

# path_each_vec(fn, ctx, key, vec): path.each over the array `vec`, the value
# of `key` in the current node: fn(ctx, element, index) with the array and
# then the element pushed. vec may be a VEC or a LIST; 0 is empty.
FUNC path_each_vec
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    test r14, r14
    jz 9f
    mov rdi, r14
    mov esi, r13d
    call path_push_array
    xor r15d, r15d
1:  cmp r15d, [r14]
    jae 8f
    mov rdi, [r14 + 8 + r15*8]
    mov esi, r13d
    mov edx, r15d
    mov rcx, r14
    call path_push
    mov rdi, r12
    mov rsi, [r14 + 8 + r15*8]
    mov rdx, r15
    call rbx
    sub qword ptr [rip + g_path_top], PE_SIZE
    inc r15d
    jmp 1b
8:  sub qword ptr [rip + g_path_top], PE_SIZE
9:  add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF path_each_vec

# path_each(fn, ctx, key, field_offset): path.each(fn, key)
FUNC path_each
    push rdi
    push rsi
    push rdx
    push rcx
    call path_value
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    mov rcx, [rax + rcx]
    call path_each_vec
    leave
    ret
ENDF path_each

# path_map_vec(fn, ctx, key, vec) -> rax: VEC of fn's results (path.map)
FUNC path_map_vec
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    # the result VEC first, so the callbacks may use the scratch stack
    xor edi, edi
    test r14, r14
    jz 1f
    mov edi, [r14]
1:  mov r15, rdi
    lea rdi, [rdi*8 + 8]
    call alloc
    mov [rax], r15
    mov [rsp], rax
    test r14, r14
    jz 9f
    mov rdi, r14
    mov esi, r13d
    call path_push_array
    xor r15d, r15d
2:  cmp r15d, [r14]
    jae 8f
    mov rdi, [r14 + 8 + r15*8]
    mov esi, r13d
    mov edx, r15d
    mov rcx, r14
    call path_push
    mov rdi, r12
    mov rsi, [r14 + 8 + r15*8]
    mov rdx, r15
    call rbx
    mov rcx, [rsp]
    mov [rcx + 8 + r15*8], rax
    sub qword ptr [rip + g_path_top], PE_SIZE
    inc r15d
    jmp 2b
8:  sub qword ptr [rip + g_path_top], PE_SIZE
9:  mov rax, [rsp]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF path_map_vec

# path_map(fn, ctx, key, field_offset) -> rax: VEC
FUNC path_map
    push rdi
    push rsi
    push rdx
    push rcx
    call path_value
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    mov rcx, [rax + rcx]
    call path_map_vec
    leave
    ret
ENDF path_map

# path_match(predicates, count) -> eax: path.match(...predicates). A 0
# predicate matches anything.
FUNC path_match
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi                    # predicates
    mov r12, rsi                    # count
    mov r13, [rip + g_path_top]
    sub r13, PE_SIZE                # entry of `node`
    xor r14d, r14d                  # name
    mov r15, -1                     # number
1:  test r12, r12
    jz 80f
    cmp r13, [rip + g_path_base]
    jb 81f
    mov rax, [rbx]
    test rax, rax
    jz 2f
    mov rdi, [r13 + PE_NODE]
    mov esi, r14d
    mov rdx, r15
    call rax
    test eax, eax
    jz 81f
    # the next node up: its name is this entry's key; an element's index
    # makes the array entry below it skipped
2:  mov r14d, [r13 + PE_KEY]
    movsxd r15, dword ptr [r13 + PE_INDEX]
    sub r13, PE_SIZE
    test r15, r15
    js 3f
    cmp r13, [rip + g_path_base]
    jb 3f
    test dword ptr [r13 + PE_FLAGS], PEF_ARRAY
    jz 3f
    sub r13, PE_SIZE
3:  add rbx, 8
    dec r12
    jmp 1b
80: mov eax, 1
    jmp 99f
81: xor eax, eax
99: add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF path_match

# path_find_ancestor(pred, ctx) -> rax: the first ancestor (not the current
# node, arrays skipped) for which pred(ctx, node) is true, or 0
FUNC path_find_ancestor
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rip + g_path_top]
    sub r13, 2 * PE_SIZE
1:  cmp r13, [rip + g_path_base]
    jb 8f
    test dword ptr [r13 + PE_FLAGS], PEF_ARRAY
    jnz 2f
    mov rdi, r12
    mov rsi, [r13 + PE_NODE]
    call rbx
    test eax, eax
    jz 2f
    mov rax, [r13 + PE_NODE]
    jmp 9f
2:  sub r13, PE_SIZE
    jmp 1b
8:  xor eax, eax
9:  pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF path_find_ancestor

# path_has_ancestor(pred, ctx) -> eax
FUNC path_has_ancestor
    call path_find_ancestor
    test rax, rax
    setnz al
    movzx eax, al
    leave
    ret
ENDF path_has_ancestor

# path_call_parent(fn, ctx, count) -> rax: path.callParent(fn, count): the
# entries above getNode(count + 1) are taken off for the call and put back.
FUNC path_call_parent
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [rdx + 1]
    call path_entry_of_node
    test rax, rax
    jz 90f
    lea r13, [rax + PE_SIZE]        # first entry taken off
    mov r14, [rip + g_path_top]
    sub r14, r13                    # bytes taken off
    mov rdi, r14
    call alloc
    mov r15, rax
    mov rdi, r15
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov [rip + g_path_top], r13
    sub r13, PE_SIZE
    mov rdi, r12
    mov rsi, [r13 + PE_NODE]
    movsxd rdx, dword ptr [r13 + PE_INDEX]
    call rbx
    mov [rsp], rax
    mov rdi, [rip + g_path_top]
    mov rsi, r15
    mov rcx, r14
    rep movsb
    mov [rip + g_path_top], rdi
    mov rax, [rsp]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "callParent past the root"
ENDF path_call_parent
