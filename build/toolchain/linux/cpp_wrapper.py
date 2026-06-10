#!/usr/bin/env python3
import sys, subprocess, glob, os


def main():
    matches = glob.glob("external/*/bin/clang-cpp")
    if matches:
        real_bin = matches[0]
    else:
        import platform
        machine = platform.machine()
        arch = "x64"
        if machine in ("aarch64", "arm64"):
            arch = "arm64"
        script_dir = os.path.dirname(os.path.realpath(__file__))
        real_bin = os.path.normpath(
            os.path.join(script_dir, "../../..",
                         f"buildtools/linux-{arch}/clang/bin/clang-cpp"))
        if not os.path.exists(real_bin):
            print("Error: clang-cpp not found by wrapper at: " + real_bin,
                  file=sys.stderr)
            sys.exit(1)

    args = sys.argv[1:]
    # Replace __BAZEL_EXECROOT__ placeholder with actual CWD
    cwd = os.getcwd()
    args = [arg.replace("__BAZEL_EXECROOT__", cwd) for arg in args]

    cmd = [real_bin] + args
    sys.exit(subprocess.run(cmd).returncode)


if __name__ == "__main__":
    main()
