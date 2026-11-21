# Entry point, argument handling, parser inference and the refuse/fallback path.
.include "defs.inc"

    .bss
    .balign 8
    .globl g_parser, g_filepath, g_from_stdin
g_argc:         .quad 0
g_argv:         .quad 0
g_envp:         .quad 0
g_filepath:     .quad 0     # cstr given by --stdin-filepath or as a bare path
g_from_stdin:   .quad 0     # 1 when the source comes from stdin
g_stdin_read:   .quad 0     # 1 once stdin bytes are in g_input
g_parser:       .quad 0
g_basename:     .space 256

    .text
    .globl _start
_start:
    mov rdi, [rsp]
    lea rsi, [rsp + 8]
    lea rdx, [rsi + rdi*8 + 8]
    and rsp, -16
    call main
    mov edi, eax
    call sys_exit

# main(argc, argv, envp) -> exit code
FUNC main
    push rbx
    push r12
    push r13
    push r14
    mov [rip + g_argc], rdi
    mov [rip + g_argv], rsi
    mov [rip + g_envp], rdx
    call mem_init
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call debug_main
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call js_debug_scan
    mov rdi, [rip + g_argc]
    mov rsi, [rip + g_argv]
    call pjc_debug_scan
    call parse_args
    cmp qword ptr [rip + g_from_stdin], 0
    je 1f
    xor edi, edi
    call read_fd_all
    mov qword ptr [rip + g_stdin_read], 1
    test rax, rax
    jz 2f
    REFUSE "cannot read stdin"
1:  call cfg_before_read
    mov rdi, [rip + g_filepath]
    call read_file
    test rax, rax
    jz 2f
    REFUSE "cannot read file"
2:  call cfg_after_read
    call options_for_parser
    call out_init
    call format_input
    # rax = 1 if a BOM must be written first
    test rax, rax
    jz 3f
    mov edi, 1
    lea rsi, [rip + bom_bytes]
    mov edx, 3
    call write_all
3:  mov rdx, [rip + g_out_ptr]
    mov rsi, [rip + g_out_base]
    sub rdx, rsi
    mov edi, 1
    call write_all
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
ENDF main

    .section .rodata
bom_bytes: .byte 0xEF, 0xBB, 0xBF
s_stdin_filepath:    .asciz "--stdin-filepath"
s_stdin_filepath_eq: .asciz "--stdin-filepath="

# parse_args(): accepts `--stdin-filepath <path>`, `--stdin-filepath=<path>`
# or one bare file path, plus the options in options.s. Anything else is
# refused.
FUNC parse_args
    push rbx
    push r12
    push r13
    push r14
    mov r12, [rip + g_argv]
    mov r13, [rip + g_argc]
    mov ebx, 1
1:  cmp rbx, r13
    jae 8f
    mov r14, [r12 + rbx*8]
    mov rdi, r14
    lea rsi, [rip + s_stdin_filepath]
    call cstr_eq
    test rax, rax
    jz 2f
    inc rbx
    cmp rbx, r13
    jae 90f
    cmp qword ptr [rip + g_filepath], 0
    jne 91f
    mov rax, [r12 + rbx*8]
    mov [rip + g_filepath], rax
    mov qword ptr [rip + g_from_stdin], 1
    inc rbx
    jmp 1b
2:  mov rdi, r14
    lea rsi, [rip + s_stdin_filepath_eq]
    call cstr_prefix
    test rax, rax
    jz 3f
    cmp qword ptr [rip + g_filepath], 0
    jne 91f
    lea rax, [r14 + 17]
    mov [rip + g_filepath], rax
    mov qword ptr [rip + g_from_stdin], 1
    inc rbx
    jmp 1b
3:  mov rdi, r14
    call debug_flag
    test rax, rax
    jz 30f
    inc rbx
    jmp 1b
30: mov rdi, r14
    call cfg_flag
    test rax, rax
    jz 33f
    inc rbx
    jmp 1b
33: mov rdi, r14
    lea rcx, [rbx + 1]
    xor esi, esi
    cmp rcx, r13
    jae 31f
    mov rsi, [r12 + rcx*8]
31: call parse_option
    test rax, rax
    jz 32f
    add rbx, rax
    jmp 1b
32: cmp byte ptr [r14], '-'
    je 92f
    cmp qword ptr [rip + g_filepath], 0
    jne 91f
    mov [rip + g_filepath], r14
    inc rbx
    jmp 1b
8:  cmp qword ptr [rip + g_filepath], 0
    je 93f
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "--stdin-filepath without a value"
91: REFUSE "more than one file"
92: REFUSE "CLI option not ported"
93: REFUSE "no file path given"
ENDF parse_args

# ---------------------------------------------------------------- parser inference
# Mirrors getLanguageByFileName: file names of every language first, then the
# extensions, matched against the lowercased basename. Only the JSON languages
# are ported; a name that belongs to another language is refused.

    .section .rodata
# Each entry: parser byte, then a NUL-terminated lowercase name. Ends with 0xff.
# Parser 0 means "another language".
lang_filenames:
    .byte 0
    .asciz "jakefile"
    .byte 0
    .asciz "start.frag"
    .byte 0
    .asciz "end.frag"
    .byte 0
    .asciz "contents.lr"
    .byte 0
    .asciz "readme"
    .byte 0
    .asciz ".clang-format"
    .byte 0
    .asciz ".clang-tidy"
    .byte 0
    .asciz ".clangd"
    .byte 0
    .asciz ".gemrc"
    .byte 0
    .asciz "citation.cff"
    .byte 0
    .asciz "glide.lock"
    .byte 0
    .asciz "pixi.lock"
    .byte 0
    .asciz ".prettierrc"
    .byte 0
    .asciz ".stylelintrc"
    .byte 0
    .asciz ".lintstagedrc"
    .byte P_JSON_STRINGIFY
    .asciz "package.json"
    .byte P_JSON_STRINGIFY
    .asciz "package-lock.json"
    .byte P_JSON_STRINGIFY
    .asciz "composer.json"
    .byte P_JSON
    .asciz ".all-contributorsrc"
    .byte P_JSON
    .asciz ".arcconfig"
    .byte P_JSON
    .asciz ".auto-changelog"
    .byte P_JSON
    .asciz ".c8rc"
    .byte P_JSON
    .asciz ".htmlhintrc"
    .byte P_JSON
    .asciz ".imgbotconfig"
    .byte P_JSON
    .asciz ".nycrc"
    .byte P_JSON
    .asciz ".tern-config"
    .byte P_JSON
    .asciz ".tern-project"
    .byte P_JSON
    .asciz ".watchmanconfig"
    .byte P_JSON
    .asciz ".babelrc"
    .byte P_JSON
    .asciz ".jscsrc"
    .byte P_JSON
    .asciz ".jshintrc"
    .byte P_JSON
    .asciz ".jslintrc"
    .byte P_JSON
    .asciz ".swcrc"
    .byte 0xff

# Extensions of the JSON languages, in language order. No extension of any
# other language is a suffix of these or the other way round, so order across
# languages does not matter. Extensions with capitals never match (Prettier
# lowercases the basename but not the extension) and are left out.
lang_extensions:
    .byte P_BABEL
    .asciz ".js"
    .byte P_BABEL
    .asciz ".mjs"
    .byte P_BABEL
    .asciz ".cjs"
    .byte P_TYPESCRIPT
    .asciz ".ts"
    .byte P_TYPESCRIPT
    .asciz ".cts"
    .byte P_TYPESCRIPT
    .asciz ".mts"
    .byte P_JSON_STRINGIFY
    .asciz ".importmap"
    .byte P_JSON
    .asciz ".json"
    .byte P_JSON
    .asciz ".avsc"
    .byte P_JSON
    .asciz ".geojson"
    .byte P_JSON
    .asciz ".gltf"
    .byte P_JSON
    .asciz ".har"
    .byte P_JSON
    .asciz ".ice"
    .byte P_JSON
    .asciz ".json.example"
    .byte P_JSON
    .asciz ".mcmeta"
    .byte P_JSON
    .asciz ".sarif"
    .byte P_JSON
    .asciz ".tact"
    .byte P_JSON
    .asciz ".tfstate"
    .byte P_JSON
    .asciz ".tfstate.backup"
    .byte P_JSON
    .asciz ".topojson"
    .byte P_JSON
    .asciz ".webapp"
    .byte P_JSON
    .asciz ".webmanifest"
    .byte P_JSON
    .asciz ".yy"
    .byte P_JSON
    .asciz ".yyp"
    .byte P_JSONC
    .asciz ".jsonc"
    .byte P_JSONC
    .asciz ".code-snippets"
    .byte P_JSONC
    .asciz ".code-workspace"
    .byte P_JSONC
    .asciz ".sublime-build"
    .byte P_JSONC
    .asciz ".sublime-color-scheme"
    .byte P_JSONC
    .asciz ".sublime-commands"
    .byte P_JSONC
    .asciz ".sublime-completions"
    .byte P_JSONC
    .asciz ".sublime-keymap"
    .byte P_JSONC
    .asciz ".sublime-macro"
    .byte P_JSONC
    .asciz ".sublime-menu"
    .byte P_JSONC
    .asciz ".sublime-mousemap"
    .byte P_JSONC
    .asciz ".sublime-project"
    .byte P_JSONC
    .asciz ".sublime-settings"
    .byte P_JSONC
    .asciz ".sublime-theme"
    .byte P_JSONC
    .asciz ".sublime-workspace"
    .byte P_JSONC
    .asciz ".sublime_metrics"
    .byte P_JSONC
    .asciz ".sublime_session"
    .byte P_JSON5
    .asciz ".json5"
    .byte 0xff
s_node_modules: .asciz "node_modules"

# infer_parser(): sets g_parser or refuses.
FUNC infer_parser
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [rip + g_filepath]
    # Files under node_modules are ignored by the CLI; not ported.
    mov r12, rbx
1:  mov rdi, r12
    lea rsi, [rip + s_node_modules]
    call cstr_prefix
    test rax, rax
    jz 2f
    cmp r12, rbx
    je 90f
    mov al, [r12 - 1]
    cmp al, '/'
    je 90f
    cmp al, '\\'
    je 90f
2:  cmp byte ptr [r12], 0
    je 3f
    inc r12
    jmp 1b
    # basename: after the last / or backslash
3:  mov r12, rbx
    mov r13, rbx
4:  mov al, [r12]
    test al, al
    jz 5f
    inc r12
    cmp al, '/'
    je 6f
    cmp al, '\\'
    jne 4b
6:  mov r13, r12
    jmp 4b
    # copy lowercased into g_basename
5:  lea rdi, [rip + g_basename]
    xor ecx, ecx
7:  mov al, [r13 + rcx]
    test al, 0x80
    jnz 91f
    cmp al, 'A'
    jb 8f
    cmp al, 'Z'
    ja 8f
    add al, 32
8:  mov [rdi + rcx], al
    test al, al
    jz 10f
    inc rcx
    cmp rcx, 255
    jae 91f
    jmp 7b
10: mov r14, rcx                    # basename length
    # file names: exact match
    lea rbx, [rip + lang_filenames]
11: movzx eax, byte ptr [rbx]
    cmp al, 0xff
    je 20f
    mov r12d, eax
    lea rdi, [rbx + 1]
    lea rsi, [rip + g_basename]
    call cstr_eq
    test rax, rax
    jnz 30f
    inc rbx
12: cmp byte ptr [rbx], 0
    je 13f
    inc rbx
    jmp 12b
13: inc rbx
    jmp 11b
    # extensions: basename ends with the extension
20: lea rbx, [rip + lang_extensions]
21: movzx eax, byte ptr [rbx]
    cmp al, 0xff
    je 92f
    mov r12d, eax
    lea rdi, [rbx + 1]
    call strlen
    cmp rax, r14
    ja 22f
    lea rdi, [rip + g_basename]
    add rdi, r14
    sub rdi, rax
    lea rsi, [rbx + 1]
    call cstr_eq
    test rax, rax
    jnz 30f
22: inc rbx
23: cmp byte ptr [rbx], 0
    je 24f
    inc rbx
    jmp 23b
24: inc rbx
    jmp 21b
30: test r12d, r12d
    jz 92f
    mov [rip + g_parser], r12
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
90: REFUSE "file under node_modules"
91: REFUSE "file name not ported"
92: REFUSE "no ported parser for this file name"
ENDF infer_parser

# ---------------------------------------------------------------- refuse / fallback
    .section .rodata
s_unsupported: .asciz "unsupported: "
s_newline:     .asciz "\n"
s_fallback_failed: .asciz "unsupported: fallback could not start node\n"
s_env_fallback: .asciz "PRETTIER_ASM_FALLBACK="
s_env_path:     .asciz "PATH="
s_node:         .asciz "node"
s_memfd_name:   .asciz "stdin"

    .bss
    .balign 8
g_exec_path: .space 4096
g_exec_argv: .space 8 * 1024

# getenv(prefix "NAME=") -> rax = value or 0
FUNC getenv
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [rip + g_envp]
1:  mov rdi, [rbx]
    test rdi, rdi
    jz 3f
    mov rsi, r12
    call cstr_prefix
    test rax, rax
    jnz 2f
    add rbx, 8
    jmp 1b
2:  mov rdi, r12
    call strlen
    add rax, [rbx]
    jmp 4f
3:  xor eax, eax
4:  pop r12
    pop rbx
    leave
    ret
ENDF getenv

# refuse(reason): hands the file to Prettier when PRETTIER_ASM_FALLBACK names
# prettier.cjs, otherwise reports and exits 3. Never returns.
FUNC refuse
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    lea rdi, [rip + s_env_fallback]
    call getenv
    test rax, rax
    jz 50f
    cmp byte ptr [rax], 0
    je 50f
    mov r12, rax                    # prettier.cjs path
    # stdin already consumed: replay it from a memfd
    cmp qword ptr [rip + g_stdin_read], 0
    je 10f
    mov eax, SYS_memfd_create
    lea rdi, [rip + s_memfd_name]
    xor esi, esi
    syscall
    test rax, rax
    js 60f
    mov r13, rax
    mov rdi, r13
    mov rsi, [rip + g_input]
    mov rdx, [rip + g_input_len]
    call write_all
    mov eax, SYS_lseek
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    syscall
    mov eax, SYS_dup2
    mov rdi, r13
    xor esi, esi
    syscall
    test rax, rax
    js 60f
    # argv: node, script, original arguments
10: lea r14, [rip + g_exec_argv]
    lea rax, [rip + s_node]
    mov [r14], rax
    mov [r14 + 8], r12
    mov rcx, [rip + g_argc]
    cmp rcx, 1000
    ja 60f
    mov rsi, [rip + g_argv]
    mov edx, 1
11: cmp rdx, rcx
    jae 12f
    mov rax, [rsi + rdx*8]
    mov [r14 + rdx*8 + 8], rax
    inc rdx
    jmp 11b
12: mov qword ptr [r14 + rdx*8 + 8], 0
    # try each PATH entry
    lea rdi, [rip + s_env_path]
    call getenv
    test rax, rax
    jz 60f
    mov r15, rax
20: mov r13, r15                    # entry start
21: mov al, [r15]
    test al, al
    jz 22f
    cmp al, ':'
    je 22f
    inc r15
    jmp 21b
22: # build "<entry>/node" (empty entry means the current directory)
    lea rdi, [rip + g_exec_path]
    mov rcx, r15
    sub rcx, r13
    cmp rcx, 4000
    ja 24f
    test rcx, rcx
    jnz 23f
    mov byte ptr [rdi], '.'
    inc rdi
23: mov rsi, r13
    rep movsb
    mov dword ptr [rdi], 0x006f6e2f     # "/no"
    mov dword ptr [rdi + 3], 0x00006564 # "de\0": "/node"
    mov eax, SYS_execve
    lea rdi, [rip + g_exec_path]
    mov rsi, r14
    mov rdx, [rip + g_envp]
    syscall
24: cmp byte ptr [r15], 0
    je 60f
    inc r15
    jmp 20b
50: mov edi, 2
    lea rsi, [rip + s_unsupported]
    call write_cstr
    mov edi, 2
    mov rsi, rbx
    call write_cstr
    mov edi, 2
    lea rsi, [rip + s_newline]
    call write_cstr
    mov edi, 3
    call sys_exit
60: mov edi, 2
    lea rsi, [rip + s_fallback_failed]
    call write_cstr
    mov edi, 3
    call sys_exit
ENDF refuse
