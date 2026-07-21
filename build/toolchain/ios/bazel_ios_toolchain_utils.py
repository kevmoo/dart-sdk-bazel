#!/usr/bin/env python3
import glob
import os
import subprocess
import sys


def find_ios_sysroot(is_simulator=False):
    sdk_name = "iphonesimulator_sdk" if is_simulator else "iphoneos_sdk"

    # Check exact sandbox paths first
    exact_sandbox_paths = [
        f"external/dart_ios_sdk/{sdk_name}",
        f"external/_main~dart_ios_sdk~dart_ios_sdk/{sdk_name}",
        f"external/+dart_ios_sdk+dart_ios_sdk/{sdk_name}",
        f"../../external/dart_ios_sdk/{sdk_name}",
        f"../../external/_main~dart_ios_sdk~dart_ios_sdk/{sdk_name}",
        f"../../external/+dart_ios_sdk+dart_ios_sdk/{sdk_name}",
    ]
    for path in exact_sandbox_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    patterns = [
        f"external/*dart_ios_sdk*/{sdk_name}",
        f"../../external/*dart_ios_sdk*/{sdk_name}",
    ]
    matches = []
    for p in patterns:
        matches.extend(sorted(glob.glob(p)))

    if matches:
        return os.path.abspath(matches[0])

    # Host fallback via xcrun
    sdk_flag = "iphonesimulator" if is_simulator else "iphoneos"
    try:
        res = subprocess.run(
            ["xcrun", "--sdk", sdk_flag, "--show-sdk-path"],
            capture_output=True,
            text=True,
            check=True,
        )
        out = res.stdout.strip()
        if os.path.exists(out):
            return out
    except Exception:
        pass

    return None


def find_ios_toolchain_binary(binary_name):
    exact_sandbox_paths = [
        f"external/dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
        f"external/_main~dart_ios_sdk~dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
        f"external/+dart_ios_sdk+dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
        f"../../external/dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
        f"../../external/_main~dart_ios_sdk~dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
        f"../../external/+dart_ios_sdk+dart_ios_sdk/xcode_toolchain/usr/bin/{binary_name}",
    ]
    for path in exact_sandbox_paths:
        if os.path.exists(path):
            return os.path.abspath(path)

    # Host fallback via xcrun
    try:
        res = subprocess.run(
            ["xcrun", "-f", binary_name],
            capture_output=True,
            text=True,
            check=True,
        )
        out = res.stdout.strip()
        if os.path.exists(out):
            return out
    except Exception:
        pass

    fallback = f"/usr/bin/{binary_name}"
    if os.path.exists(fallback):
        return fallback

    print(f"Error: iOS Toolchain binary '{binary_name}' not found.", file=sys.stderr)
    sys.exit(1)
