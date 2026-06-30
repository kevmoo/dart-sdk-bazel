#!/usr/bin/env python3
import os
import subprocess
import sys
from bazel_toolchain_utils import find_toolchain_binary


def main():
    args = sys.argv[1:]
    real_clang = find_toolchain_binary("clang++")

    if "-fPIC" in args:
        args = [arg for arg in args if arg != "-fPIE"]

    cwd = os.getcwd()
    args = [arg.replace("__BAZEL_EXECROOT__", cwd) for arg in args]

    cmd = [real_clang] + args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
