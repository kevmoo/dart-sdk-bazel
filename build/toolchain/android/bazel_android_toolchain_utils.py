#!/usr/bin/env python3
import glob
import os
import platform
import sys


def find_android_toolchain_binary(binary_name):
    if os.path.lexists("external") and not os.path.exists("external"):
        try:
            os.unlink("external")
        except Exception:
            pass
    if not os.path.exists("external"):
        try:
            os.symlink("../../external", "external")
        except Exception:
            pass

    # Prefer in-tree Clang (LLVM 23) which has modern C++20/C++23 libc++ support
    patterns = [
        f"external/*dart_linux_*_clang/bin/{binary_name}",
        f"../../external/*dart_linux_*_clang/bin/{binary_name}",
        f"buildtools/linux-x64/clang/bin/{binary_name}",
        f"../../buildtools/linux-x64/clang/bin/{binary_name}",
        f"external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/bin/{binary_name}",
        f"../../external/*dart_android_ndk*/toolchains/llvm/prebuilt/*/bin/{binary_name}",
        f"third_party/android_tools/ndk/toolchains/llvm/prebuilt/*/bin/{binary_name}",
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

    for env_var in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        if env_var in os.environ:
            host_tag = "darwin-x86_64" if platform.system() == "Darwin" else "linux-x86_64"
            candidate = os.path.join(os.environ[env_var], "toolchains", "llvm", "prebuilt", host_tag, "sysroot")
            if os.path.exists(candidate):
                return os.path.abspath(candidate)

    return None
