#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_ios_toolchain_utils import find_ios_sysroot, find_ios_toolchain_binary


def main():
    args = sys.argv[1:]
    cwd = os.getcwd()

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

    is_simulator = any("simulator" in arg.lower() for arg in effective_args)
    sysroot = None
    for i, arg in enumerate(effective_args):
        if arg.startswith("--sysroot="):
            sysroot = arg.split("=")[1]
            break
        elif arg == "--sysroot" and i + 1 < len(effective_args):
            sysroot = effective_args[i + 1]
            break
        elif arg.startswith("-isysroot="):
            sysroot = arg.split("=")[1]
            break
        elif arg == "-isysroot" and i + 1 < len(effective_args):
            sysroot = effective_args[i + 1]
            break

    if not sysroot:
        sysroot = find_ios_sysroot(is_simulator=is_simulator)

    if not sysroot:
        print("Error: iOS SDK sysroot not found. Ensure Xcode is installed.", file=sys.stderr)
        sys.exit(1)

    is_c_file = any(not arg.startswith("-") and arg.endswith(".c") for arg in effective_args)
    is_assembly_file = any(not arg.startswith("-") and (arg.endswith(".s") or arg.endswith(".S")) for arg in effective_args)
    is_linking = not any(arg in ("-c", "-S", "-E") for arg in effective_args)
    has_std = any(arg.startswith("-std=") for arg in effective_args)

    if is_linking or is_c_file:
        binary_to_run = find_ios_toolchain_binary("clang++" if is_linking else "clang")
    else:
        binary_to_run = find_ios_toolchain_binary("clang++")

    target_triple = None
    for i, arg in enumerate(effective_args):
        if arg.startswith("--target="):
            target_triple = arg.split("=")[1]
        elif arg.startswith("-target="):
            target_triple = arg.split("=")[1]
        elif arg in ("--target", "-target") and i + 1 < len(effective_args):
            target_triple = effective_args[i + 1]

    if not target_triple:
        if is_simulator:
            target_triple = "arm64-apple-ios15.0-simulator"
        else:
            target_triple = "arm64-apple-ios15.0"

    new_args = []
    for arg in args:
        if arg.startswith("@"):
            params_file = arg[1:]
            if os.path.exists(params_file):
                with open(params_file, "r", encoding="utf-8") as pf:
                    lines = pf.readlines()
                new_lines = []
                for line in lines:
                    stripped = line.strip()
                    if stripped.startswith("--sysroot=") or stripped.startswith("-isysroot="):
                        new_lines.append(f"-isysroot\n{sysroot}\n")
                    else:
                        new_lines.append(line.replace("__BAZEL_EXECROOT__", cwd))

                rewritten_params = params_file + ".ios"
                with open(rewritten_params, "w", encoding="utf-8") as pf:
                    pf.writelines(new_lines)
                new_args.append(f"@{rewritten_params}")
            else:
                new_args.append(arg)
        elif arg.startswith("--sysroot=") or arg.startswith("-isysroot="):
            new_args.extend(["-isysroot", sysroot])
        else:
            new_args.append(arg.replace("__BAZEL_EXECROOT__", cwd))

    if not is_linking:
        if not has_std and not is_assembly_file:
            if is_c_file:
                new_args.insert(0, "-std=c17")
            else:
                new_args.insert(0, "-std=c++20")
    else:
        new_args.append("-target")
        new_args.append(target_triple)
        new_args.append("-isysroot")
        new_args.append(sysroot)

    cmd = [binary_to_run] + new_args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
