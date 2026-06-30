#!/usr/bin/env python3
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from bazel_toolchain_utils import find_toolchain_binary

if __name__ == "__main__":
    real_bin = find_toolchain_binary("llvm-dwp")
    sys.exit(subprocess.run([real_bin] + sys.argv[1:]).returncode)
