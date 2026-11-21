#!/bin/sh
# Stand-in: Prettier's output plus one byte. Expect 100% DIFFERENT.
node "$(dirname "$0")/../../node_modules/prettier/bin/prettier.cjs" "$@"
s=$?
printf x
exit $s
