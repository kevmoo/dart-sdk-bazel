#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_ios_toolchain_utils import find_ios_toolchain_binary


def main():
    args = sys.argv[1:]
    real_ar = find_ios_toolchain_binary("ar")

    new_args = []
    for arg in args:
        if arg.startswith("@"):
            params_file = arg[1:]
            if os.path.exists(params_file):
                try:
                    with open(params_file, "r", encoding="utf-8") as pf:
                        lines = pf.readlines()
                    new_lines = []
                    for line in lines:
                        stripped = line.strip()
                        if stripped == "rcsD":
                            new_lines.append("rcs\n")
                        elif stripped == "rcD":
                            new_lines.append("rc\n")
                        elif stripped == "sD":
                            new_lines.append("s\n")
                        elif stripped == "-rcsD":
                            new_lines.append("-rcs\n")
                        elif stripped == "-rcD":
                            new_lines.append("-rc\n")
                        elif stripped == "-sD":
                            new_lines.append("-s\n")
                        else:
                            new_lines.append(line)
                    rewritten_params = params_file + ".ios_ar"
                    with open(rewritten_params, "w", encoding="utf-8") as pf:
                        pf.writelines(new_lines)
                    new_args.append(f"@{rewritten_params}")
                except IOError:
                    new_args.append(arg)
            else:
                new_args.append(arg)
        elif arg in ("rcsD", "-rcsD"):
            new_args.append("rcs" if arg == "rcsD" else "-rcs")
        elif arg in ("rcD", "-rcD"):
            new_args.append("rc" if arg == "rcD" else "-rc")
        elif arg in ("sD", "-sD"):
            new_args.append("s" if arg == "sD" else "-s")
        else:
            new_args.append(arg)

    cmd = [real_ar] + new_args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
