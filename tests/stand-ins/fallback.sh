#!/bin/sh
# Stand-in: supports nothing. Expect 100% fallback / oracle-error.
cat >/dev/null
echo "unsupported: stand-in supports nothing" >&2
exit 3
