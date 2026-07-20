#!/usr/bin/env python3
import glob
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_android_toolchain_utils import find_android_sysroot, find_android_toolchain_binary


def find_ndk_binary(binary_name):
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
    return find_android_toolchain_binary(binary_name)


def main():
    args = sys.argv[1:]
    sysroot = find_android_sysroot()
    if not sysroot:
        print("Error: Android NDK sysroot not found. Ensure the NDK is properly configured.", file=sys.stderr)
        sys.exit(1)

    cwd = os.getcwd()
    wrapper_dir = os.path.dirname(os.path.realpath(__file__))
    shim_inc_dir = os.path.join(wrapper_dir, "include")

    # Expand params files to get the full list of effective arguments for analysis
    effective_args = []
    for arg in args:
        if arg.startswith("@"):
            params_file = arg[1:]
            if os.path.exists(params_file):
                try:
                    with open(params_file, "r", encoding="utf-8") as pf:
                        effective_args.extend([line.strip() for line in pf.readlines()])
                except IOError:
                    effective_args.append(arg)
            else:
                effective_args.append(arg)
        else:
            effective_args.append(arg)

    is_c_file = any(not arg.startswith("-") and arg.endswith(".c") for arg in effective_args)
    is_linking = not any(arg in ("-c", "-S", "-E") for arg in effective_args)

    if is_linking or is_c_file:
        binary_to_run = find_ndk_binary("clang++" if is_linking else "clang")
    else:
        binary_to_run = find_ndk_binary("clang++")

    # Extract target triple from effective arguments, or fallback to heuristics
    target_triple = None
    for i, arg in enumerate(effective_args):
        if arg.startswith("--target="):
            target_triple = arg.split("=")[1]
        elif arg == "--target" and i + 1 < len(effective_args):
            target_triple = effective_args[i + 1]

    if not target_triple:
        if any("aarch64" in arg for arg in effective_args):
            target_triple = "aarch64-linux-android26"
        elif any("arm" in arg for arg in effective_args):
            target_triple = "armv7a-linux-androideabi26"
        elif any("riscv64" in arg for arg in effective_args):
            target_triple = "riscv64-linux-android35"
        else:
            target_triple = "x86_64-linux-android26"

    # Find NDK cpufeatures include directory
    cpufeatures_inc = None
    ndk_root = os.path.abspath(os.path.join(sysroot, "..", "..", "..", "..", ".."))
    cand = os.path.join(ndk_root, "sources", "android", "cpufeatures")
    if os.path.exists(cand):
        cpufeatures_inc = cand

    new_args = []
    has_std = False

    for arg in args:
        if arg.startswith("@"):
            params_file = arg[1:]
            if os.path.exists(params_file):
                with open(params_file, "r") as pf:
                    lines = pf.readlines()
                new_lines = []
                for line in lines:
                    stripped = line.strip()
                    if stripped == "-lpthread":
                        continue
                    if stripped.startswith("--sysroot="):
                        new_lines.append(f"--sysroot={sysroot}\n")
                    else:
                        new_lines.append(line.replace("__BAZEL_EXECROOT__", cwd))

                rewritten_params = params_file + ".android"
                with open(rewritten_params, "w") as pf:
                    pf.writelines(new_lines)
                new_args.append(f"@{rewritten_params}")
            else:
                new_args.append(arg)
        elif arg == "-lpthread":
            continue
        elif arg.startswith("-std="):
            has_std = True
            new_args.append(arg)
        elif arg.startswith("--sysroot="):
            new_args.append(f"--sysroot={sysroot}")
        else:
            new_args.append(arg.replace("__BAZEL_EXECROOT__", cwd))

    if not is_linking:
        if not has_std:
            if is_c_file:
                new_args.insert(0, "-std=c17")
            else:
                new_args.insert(0, "-std=c++20")

        if os.path.exists(shim_inc_dir):
            new_args.insert(0, f"-isystem{shim_inc_dir}")

        if cpufeatures_inc:
            new_args.insert(0, f"-isystem{cpufeatures_inc}")
    else:
        new_args.append(f"--target={target_triple}")
        new_args.append(f"--sysroot={sysroot}")
        new_args.append("-static-libstdc++")

    cmd = [binary_to_run] + new_args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
