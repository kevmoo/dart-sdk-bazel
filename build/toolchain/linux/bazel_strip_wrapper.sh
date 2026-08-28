#!/bin/sh
set -e
STRIP=""
for p in external/*dart_linux_*_clang/bin/llvm-strip ../../external/*dart_linux_*_clang/bin/llvm-strip; do
  if [ -f "$p" ]; then
    STRIP="$p"
    break
  fi
done
if [ -z "$STRIP" ]; then
  if [ -f "buildtools/linux-x64/clang/bin/llvm-strip" ]; then
    STRIP="buildtools/linux-x64/clang/bin/llvm-strip"
  else
    echo "Error: llvm-strip not found in execroot" >&2
    exit 1
  fi
fi
exec "$STRIP" "$@"
