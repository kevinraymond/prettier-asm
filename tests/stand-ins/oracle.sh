#!/bin/sh
# Stand-in: Prettier itself. Expect 100% identical.
exec node "$(dirname "$0")/../../node_modules/prettier/bin/prettier.cjs" "$@"
