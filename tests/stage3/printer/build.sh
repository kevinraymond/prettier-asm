#!/bin/sh
# tests/stage3/printer/build.sh NAME: assembles src/*.s into build/NAME/ and links
# build/NAME/prettier-asm, so work in progress does not touch build/. A source
# that does not assemble keeps its previous object (with a warning), so another
# file's half-done edit does not stop the build.
set -u
cd "$(dirname "$0")/../../.."
name=${1:?usage: build.sh NAME}
out=build/$name
mkdir -p "$out"
for s in src/*.s; do
  o=$out/$(basename "$s" .s).o
  if [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ src/defs.inc -nt "$o" ] || [ src/pjs.inc -nt "$o" ]; then
    as --64 -g -I src -o "$o.tmp" "$s" 2>"$out/as.err" && mv "$o.tmp" "$o" || {
      echo "build.sh: $s does not assemble; keeping the old object" >&2
      head -5 "$out/as.err" >&2
      rm -f "$o.tmp"
    }
  fi
done
objs=""
for s in src/*.s; do
  o=$out/$(basename "$s" .s).o
  [ -f "$o" ] && objs="$objs $o"
done
ld -static -o "$out/prettier-asm" $objs
