#!/bin/sh
set -e

CLANG=""
for p in external/*dart_linux_*_clang/bin/clang++ ../../external/*dart_linux_*_clang/bin/clang++; do
  if [ -f "$p" ]; then
    CLANG="$p"
    break
  fi
done

if [ -z "$CLANG" ]; then
  if [ -f "buildtools/linux-x64/clang/bin/clang++" ]; then
    CLANG="buildtools/linux-x64/clang/bin/clang++"
  else
    echo "Error: clang++ not found in execroot" >&2
    exit 1
  fi
fi

# Filter -fPIE if -fPIC is present
HAS_PIC=0
for arg in "$@"; do
  if [ "$arg" = "-fPIC" ]; then
    HAS_PIC=1
    break
  fi
done

CWD="$(pwd)"

if [ "$HAS_PIC" -eq 1 ]; then
  for arg in "$@"; do
    if [ "$arg" != "-fPIE" ]; then
      case "$arg" in
        *__BAZEL_EXECROOT__*)
          arg=$(printf '%s\n' "$arg" | sed "s|__BAZEL_EXECROOT__|$CWD|g")
          ;;
      esac
      set -- "$@" "$arg"
    fi
    shift
  done
else
  for arg in "$@"; do
    case "$arg" in
      *__BAZEL_EXECROOT__*)
        arg=$(printf '%s\n' "$arg" | sed "s|__BAZEL_EXECROOT__|$CWD|g")
        ;;
    esac
    set -- "$@" "$arg"
    shift
  done
fi

exec "$CLANG" "$@"
