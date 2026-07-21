#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bazel_ios_toolchain_utils import find_ios_toolchain_binary


def main():
    real_strip = find_ios_toolchain_binary("strip")
    cmd = [real_strip] + sys.argv[1:]
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
