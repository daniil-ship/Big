#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"

: "${NASM:=nasm}"
"$NASM" -f bin -w+all src/bigc.asm -o bigc.exe

size=$(wc -c < bigc.exe)
if [ "$size" -ne 6144 ]; then
    echo "error: expected 6144-byte compiler, got ${size}" >&2
    exit 1
fi
printf '[OK] bigc.exe: %s bytes, NASM flat PE64\n' "$size"
