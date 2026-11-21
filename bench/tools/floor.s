# A do-nothing static binary: exit(0) at once. bench/record.mjs times it the way it times the
# contenders, so the report can show how much of a run is starting a process.
.intel_syntax noprefix
.globl _start
.text
_start:
    mov eax, 60                 # exit
    xor edi, edi
    syscall
