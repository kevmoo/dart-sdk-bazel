#!/usr/bin/env python3
import os
import subprocess
import sys


def find_sdk_repo_path():
    cwd = os.getcwd()
    script_dir = os.path.dirname(os.path.realpath(__file__))
    for start_dir in [cwd, script_dir]:
        cur = start_dir
        for _ in range(4):
            ext = os.path.join(cur, "external")
            if os.path.isdir(ext):
                for entry in os.listdir(ext):
                    if "dart_ios_sdk" in entry:
                        path = os.path.join(ext, entry)
                        if os.path.isdir(path):
                            return os.path.abspath(path)
            parent = os.path.dirname(cur)
            if parent == cur:
                break
            cur = parent
    return None


def find_ios_sysroot(is_simulator=False):
    sdk_name = "iphonesimulator_sdk" if is_simulator else "iphoneos_sdk"
    repo_path = find_sdk_repo_path()
    if repo_path:
        sdk_path = os.path.join(repo_path, sdk_name)
        if os.path.exists(sdk_path):
            return sdk_path

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
    repo_path = find_sdk_repo_path()
    if repo_path:
        binary_path = os.path.join(repo_path, "xcode_toolchain", "usr", "bin", binary_name)
        if os.path.exists(binary_path):
            return binary_path

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
