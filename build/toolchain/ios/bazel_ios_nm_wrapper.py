#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bazel_ios_toolchain_utils import find_ios_toolchain_binary


def main():
    real_nm = find_ios_toolchain_binary("nm")
    cmd = [real_nm] + sys.argv[1:]
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
