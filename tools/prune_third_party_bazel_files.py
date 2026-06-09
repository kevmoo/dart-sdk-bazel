#!/usr/bin/env python3
"""Script to prune unused upstream Bazel files from vendored third_party deps.

These files conflict with our own Bazel definitions and cause package boundary
issues. Run automatically as a gclient hook after sync.
"""

import os
import sys

# Target directories to prune (relative to SDK root)
TARGET_DIRS = [
    "third_party/perfetto/src",
    "third_party/boringssl/src",
]

# Filenames to prune
PRUNE_NAMES = {
    "BUILD",
    "BUILD.bazel",
    "WORKSPACE",
    "MODULE.bazel",
}


def prune_dir(target_dir):
    sdk_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    full_path = os.path.join(sdk_root, target_dir)
    
    if not os.path.exists(full_path):
        print(f"Directory {target_dir} does not exist, skipping.")
        return True

    print(f"Pruning upstream Bazel files in {target_dir}...")
    pruned_count = 0
    success = True
    
    for root, dirs, files in os.walk(full_path):
        for f in files:
            # Prune standard bazel files
            if f in PRUNE_NAMES:
                file_path = os.path.join(root, f)
                try:
                    os.remove(file_path)
                    print(f"  Removed: {os.path.relpath(file_path, sdk_root)}")
                    pruned_count += 1
                except Exception as e:
                    print(f"  Error removing {file_path}: {e}", file=sys.stderr)
                    success = False
            
            # Prune legacy disabled files
            elif f.endswith(".disabled-for-dart-bazel-migration"):
                file_path = os.path.join(root, f)
                try:
                    os.remove(file_path)
                    print(f"  Removed legacy: {os.path.relpath(file_path, sdk_root)}")
                    pruned_count += 1
                except Exception as e:
                    print(f"  Error removing legacy {file_path}: {e}", file=sys.stderr)
                    success = False
                    
    print(f"Completed pruning {target_dir}. Removed {pruned_count} files.")
    return success


def main():
    sdk_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    stamp_file = os.path.join(sdk_root, "third_party", ".bazel_pruned")
    deps_file = os.path.join(sdk_root, "DEPS")

    # If the stamp file is newer than DEPS, no sync has happened, so we can skip!
    if os.path.exists(stamp_file) and os.path.exists(deps_file):
        if os.path.getmtime(stamp_file) > os.path.getmtime(deps_file):
            return

    success = True
    for d in TARGET_DIRS:
        if not prune_dir(d):
            success = False

    if not success:
        sys.exit(1)

    try:
        with open(stamp_file, "w") as f:
            f.write("pruned")
    except Exception as e:
        print(f"Warning: could not create stamp file {stamp_file}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
