# print/expression-statement.js (the Vue and Markdown cases do not apply to
# .js files)
.include "pjs.inc"

# pjs_print_expression_statement(node, args) -> rax doc: [print("expression"), semi]
FUNC pjs_print_expression_statement
    PROLOGUE
    PRINT N_F0, K_expression
    mov rbx, rax
    call pjs_semi_doc
    mov rdi, rbx
    mov rsi, rax
    call doc_array2
    EPILOGUE
ENDF pjs_print_expression_statement
