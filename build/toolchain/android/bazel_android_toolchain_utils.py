#!/usr/bin/env python3
import glob
import os
import platform
import sys


def _get_host_os():
    return "darwin-x86_64" if platform.system().lower() == "darwin" else "linux-x86_64"


def find_android_toolchain_binary(binary_name, sysroot=None):
    host_os = _get_host_os()

    if sysroot:
        binary_path = os.path.abspath(os.path.join(sysroot, "..", "bin", binary_name))
        if os.path.exists(binary_path):
            return binary_path

    # Check exact sandbox paths first to avoid expensive glob/directory traversals
    exact_sandbox_paths = [
        f"external/dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"external/_main~dart_android_ndk~dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"external/+dart_android_ndk+dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../external/dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../external/_main~dart_android_ndk~dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../external/+dart_android_ndk+dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
    ]
    for path in exact_sandbox_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    # Fallback to globbing sandbox repository patterns
    patterns = [
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    # Host fallback for non-sandboxed executions
    host_paths = [
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
        f"../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/bin/{binary_name}",
    ]
    for path in host_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    print(f"Error: Android Clang binary '{binary_name}' not found for host {host_os}.", file=sys.stderr)
    sys.exit(1)


def find_android_sysroot():
    host_os = _get_host_os()

    # Check exact sandbox paths first
    exact_sandbox_paths = [
        f"external/dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"external/_main~dart_android_ndk~dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"external/+dart_android_ndk+dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../external/dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../external/_main~dart_android_ndk~dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../external/+dart_android_ndk+dart_android_ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
    ]
    for path in exact_sandbox_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    # Fallback to globbing sandbox repository patterns
    patterns = [
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/{host_os}/sysroot",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    # Host fallback for non-sandboxed executions
    host_paths = [
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
        f"../../third_party/android_tools/ndk/toolchains/llvm/prebuilt/{host_os}/sysroot",
    ]
    for path in host_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    return None
