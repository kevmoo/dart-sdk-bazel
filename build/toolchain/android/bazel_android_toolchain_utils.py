#!/usr/bin/env python3
import glob
import os
import platform
import sys


def _get_host_os():
    return "darwin-x86_64" if platform.system().lower() == "darwin" else "linux-x86_64"


def find_android_toolchain_binary(binary_name):
    # Always use the NDK's own toolchain binaries for Android compilation to ensure
    # ABI compatibility and cross-platform support (e.g. on macOS hosts).
    host_os = _get_host_os()
    patterns = [
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    print(f"Error: Android Clang binary '{binary_name}' not found for host {host_os}.", file=sys.stderr)
    sys.exit(1)


def find_android_sysroot():
    host_os = _get_host_os()
    patterns = [
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    return None
