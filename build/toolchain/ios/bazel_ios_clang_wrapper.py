#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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
                    with open(params_file, "r", encoding="utf-8", errors="replace") as pf:
                        effective_args.extend([line.rstrip("\r\n").replace("__BAZEL_EXECROOT__", cwd) for line in pf.readlines()])
                except Exception:
                    effective_args.append(arg)
            else:
                effective_args.append(arg)
        else:
            effective_args.append(arg)

    # Extract target triple first
    target_triple = None
    for i, arg in enumerate(effective_args):
        if arg.startswith("--target="):
            target_triple = arg.split("=")[1]
            break
        elif arg.startswith("-target="):
            target_triple = arg.split("=")[1]
            break
        elif arg in ("--target", "-target") and i + 1 < len(effective_args):
            target_triple = effective_args[i + 1]
            break

    # Determine if we are targeting simulator
    if target_triple:
        is_simulator = "simulator" in target_triple.lower()
    else:
        is_simulator = any("simulator" in arg.lower() for arg in effective_args if arg.startswith("-"))

    if not target_triple:
        target_triple = "arm64-apple-ios15.0-simulator" if is_simulator else "arm64-apple-ios15.0"

    # Extract sysroot
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

    if not sysroot or "dart_ios_sdk" in sysroot or not os.path.exists(sysroot):
        sysroot = find_ios_sysroot(is_simulator=is_simulator)

    if not sysroot:
        print("Error: iOS SDK sysroot not found. Ensure Xcode is installed.", file=sys.stderr)
        sys.exit(1)

    is_c_file = any(not arg.startswith("-") and arg.endswith(".c") for arg in effective_args)
    is_objc_file = any(not arg.startswith("-") and arg.endswith(".m") for arg in effective_args)
    is_assembly_file = any(not arg.startswith("-") and (arg.endswith(".s") or arg.endswith(".S")) for arg in effective_args)
    is_linking = not any(arg in ("-c", "-S", "-E") for arg in effective_args)
    has_std = any(arg.startswith("-std=") for arg in effective_args)

    if is_linking or is_c_file or is_objc_file:
        binary_to_run = find_ios_toolchain_binary("clang++" if is_linking else "clang")
    else:
        binary_to_run = find_ios_toolchain_binary("clang++")

    new_args = []
    skip_next = False
    for i, arg in enumerate(args):
        if skip_next:
            skip_next = False
            continue
        if arg.startswith("@"):
            params_file = arg[1:]
            if os.path.exists(params_file):
                try:
                    with open(params_file, "r", encoding="utf-8", errors="replace") as pf:
                        lines = pf.readlines()
                    new_lines = []
                    skip_param_next = False
                    for line in lines:
                        if skip_param_next:
                            skip_param_next = False
                            continue
                        stripped = line.rstrip("\r\n")
                        if stripped.startswith("--sysroot=") or stripped.startswith("-isysroot="):
                            new_lines.append(f"-isysroot\n{sysroot}\n")
                        elif stripped in ("--sysroot", "-isysroot"):
                            new_lines.append(f"-isysroot\n{sysroot}\n")
                            skip_param_next = True
                        else:
                            new_lines.append(line.replace("__BAZEL_EXECROOT__", cwd))

                    rewritten_params = params_file + ".ios"
                    with open(rewritten_params, "w", encoding="utf-8", errors="replace") as pf:
                        pf.writelines(new_lines)
                    new_args.append(f"@{rewritten_params}")
                except Exception:
                    new_args.append(arg)
            else:
                new_args.append(arg)
        elif arg.startswith("--sysroot=") or arg.startswith("-isysroot="):
            new_args.extend(["-isysroot", sysroot])
        elif arg in ("--sysroot", "-isysroot") and i + 1 < len(args):
            new_args.extend(["-isysroot", sysroot])
            skip_next = True
        else:
            new_args.append(arg.replace("__BAZEL_EXECROOT__", cwd))

    if not is_linking:
        if not has_std and not is_assembly_file:
            if is_c_file or is_objc_file:
                new_args.insert(0, "-std=c17")
            else:
                new_args.insert(0, "-std=c++20")
    else:
        has_target = any(arg in ("-target", "--target") or arg.startswith("-target=") or arg.startswith("--target=") for arg in effective_args)
        if not has_target:
            new_args.extend(["-target", target_triple])
        has_sysroot = any(arg in ("-isysroot", "--sysroot") or arg.startswith("-isysroot=") or arg.startswith("--sysroot=") for arg in effective_args)
        if not has_sysroot:
            new_args.extend(["-isysroot", sysroot])

    cmd = [binary_to_run] + new_args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
