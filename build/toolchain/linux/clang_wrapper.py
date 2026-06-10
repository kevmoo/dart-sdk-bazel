#!/usr/bin/env python3
import sys
import subprocess
import glob
import os


def main():
    args = sys.argv[1:]

    # Detect and dynamically heal the Bazel standalone execroot external symlink bug.
    # If 'external' is missing, create a temporary symlink pointing to '../../external'.
    # We never delete this symlink during the build to avoid concurrency race conditions
    # where one parallel compile finishes and deletes it while others are still running.
    # Bazel will clean up the execroot at the end of the build anyway.
    if not os.path.exists("external"):
        try:
            if os.path.lexists("external"):
                os.unlink("external")
            os.symlink("../../external", "external")
        except Exception:
            # If another parallel instance created it just now, or we lack permissions,
            # ignore the error and let the build proceed.
            pass

    # Dynamically find clang++ in the execroot.
    # Since we guaranteed that the 'external' symlink exists above, this glob
    # will always succeed both for sandboxed and standalone builds!
    matches = glob.glob("external/*/bin/clang++")
    if matches:
        real_clang = matches[0]
    else:
        # Fallback to relative path from script location if not in sandbox, supporting arm64 hosts
        import platform
        machine = platform.machine()
        arch = "x64"
        if machine in ("aarch64", "arm64"):
            arch = "arm64"
        script_dir = os.path.dirname(os.path.realpath(__file__))
        real_clang = os.path.normpath(
            os.path.join(script_dir, "../../..",
                         f"buildtools/linux-{arch}/clang/bin/clang++"))
        if not os.path.exists(real_clang):
            print("Error: clang++ not found by wrapper at: " + real_clang,
                  file=sys.stderr)
            sys.exit(1)

    # Strip -fPIE if -fPIC is present
    if "-fPIC" in args:
        args = [arg for arg in args if arg != "-fPIE"]

    # Replace __BAZEL_EXECROOT__ placeholder with actual CWD
    cwd = os.getcwd()
    args = [arg.replace("__BAZEL_EXECROOT__", cwd) for arg in args]

    # Launch the real compiler relatively!
    cmd = [real_clang] + args
    res = subprocess.run(cmd)
    sys.exit(res.returncode)


if __name__ == "__main__":
    main()
