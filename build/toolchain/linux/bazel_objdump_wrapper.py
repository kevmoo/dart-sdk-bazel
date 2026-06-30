#!/usr/bin/env python3
import subprocess
import sys
from bazel_toolchain_utils import find_toolchain_binary

if __name__ == "__main__":
    real_bin = find_toolchain_binary("llvm-objdump")
    sys.exit(subprocess.run([real_bin] + sys.argv[1:]).returncode)
