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
                with open(params_file, "r", encoding="utf-8") as pf:
                    lines = pf.readlines()
                new_lines = []
                for line in lines:
                    stripped = line.strip()
                    if "rcsD" in stripped:
                        new_lines.append(line.replace("rcsD", "rcs"))
                    elif "rcD" in stripped:
                        new_lines.append(line.replace("rcD", "rc"))
                    elif "sD" in stripped:
                        new_lines.append(line.replace("sD", "s"))
                    else:
                        new_lines.append(line)
                rewritten_params = params_file + ".ios_ar"
                with open(rewritten_params, "w", encoding="utf-8") as pf:
                    pf.writelines(new_lines)
                new_args.append(f"@{rewritten_params}")
            else:
                new_args.append(arg)
        elif arg == "rcsD":
            new_args.append("rcs")
        elif arg == "rcD":
            new_args.append("rc")
        elif arg == "sD":
            new_args.append("s")
        else:
            new_args.append(arg)

    cmd = [real_ar] + new_args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
