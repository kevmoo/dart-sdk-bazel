#!/usr/bin/env python3
import glob
import os
import sys


def find_android_toolchain_binary(binary_name):
    # Always use the NDK's own toolchain binaries for Android compilation to ensure
    # ABI compatibility and cross-platform support (e.g. on macOS hosts).
    patterns = [
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/bin/{binary_name}",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/bin/{binary_name}",
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/*/bin/{binary_name}",
        f"../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/*/bin/{binary_name}",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    print(f"Error: Android Clang binary '{binary_name}' not found.", file=sys.stderr)
    sys.exit(1)


def find_android_sysroot():
    patterns = [
        "external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/sysroot",
        "../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/sysroot",
        "third_party/android_tools/ndk/toolchains/llvm/prebuilt/*/sysroot",
        "../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/*/sysroot",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    return None
