#!/usr/bin/env python3
import glob
import os
import sys


def find_toolchain_binary(binary_name):
    if not os.path.exists("external"):
        try:
            if os.path.lexists("external"):
                os.unlink("external")
            os.symlink("../../external", "external")
        except Exception:
            pass

    matches = sorted(glob.glob(f"external/*/bin/{binary_name}"))
    dart_matches = [m for m in matches if "dart_" in m]
    if dart_matches:
        return dart_matches[0]
    if matches:
        return matches[0]

    print(
        f"Error: {binary_name} not found in execroot under external/*/bin/{binary_name}",
        file=sys.stderr,
    )
    sys.exit(1)
