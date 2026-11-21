#!/bin/sh
# Links build/js-parse: the JS parser and the core files it needs, with a minimal entry.
set -e
cd "$(dirname "$0")/../../.."
mkdir -p build/js-parse.d
for f in sys arena io text width unicode_tables lex ast_types parse_js parse_js_lex parse_js_expr parse_js_pat \
         parse_js_class parse_js_module parse_js_post parse_js_dump parse_ts parse_ts_decl; do
  as --64 -g -I src -o build/js-parse.d/$f.o src/$f.s
done
as --64 -g -I src -o build/js-parse.d/js_main.o tests/stage3/parser/js_main.s
ld -static -o build/js-parse build/js-parse.d/*.o
