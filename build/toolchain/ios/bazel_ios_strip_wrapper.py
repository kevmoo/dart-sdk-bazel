#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_ios_toolchain_utils import find_ios_toolchain_binary


def main():
    args = sys.argv[1:]
    real_binary = find_ios_toolchain_binary("strip")
    cmd = [real_binary] + args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
