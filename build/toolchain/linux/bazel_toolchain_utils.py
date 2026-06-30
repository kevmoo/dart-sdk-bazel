#!/usr/bin/env python3
import glob
import os
import platform
import sys


def find_toolchain_binary(binary_name):
    if not os.path.exists("external"):
        try:
            if os.path.lexists("external"):
                os.unlink("external")
            os.symlink("../../external", "external")
        except Exception:
            pass

    matches = sorted(glob.glob(f"external/*dart_linux_*_clang/bin/{binary_name}"))
    machine = platform.machine()
    host_arch = "x64" if machine in ("x86_64", "AMD64") else "arm64"
    arch_matches = [m for m in matches if f"_{host_arch}_" in m]
    if arch_matches:
        return arch_matches[0]
    if matches:
        return matches[0]

    print(
        f"Error: {binary_name} not found in execroot under external/*dart_linux_*_clang/bin/{binary_name}",
        file=sys.stderr,
    )
    sys.exit(1)
