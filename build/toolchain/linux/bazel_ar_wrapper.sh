#!/bin/sh
set -e
AR=""
for p in external/*dart_linux_*_clang/bin/llvm-ar ../../external/*dart_linux_*_clang/bin/llvm-ar; do
  if [ -f "$p" ]; then
    AR="$p"
    break
  fi
done
if [ -z "$AR" ]; then
  if [ -f "buildtools/linux-x64/clang/bin/llvm-ar" ]; then
    AR="buildtools/linux-x64/clang/bin/llvm-ar"
  else
    echo "Error: llvm-ar not found in execroot" >&2
    exit 1
  fi
fi
exec "$AR" "$@"
