#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_android_toolchain_utils import find_android_toolchain_binary


def main():
    args = sys.argv[1:]
    real_clang = find_android_toolchain_binary("clang++")
    cwd = os.getcwd()
    args = [arg.replace("__BAZEL_EXECROOT__", cwd) for arg in args]
    cmd = [real_clang] + args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
