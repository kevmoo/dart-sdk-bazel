#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import argparse
import os
import sys
import tarfile
import zipfile

# Manifest of critical files that MUST exist in the Dart SDK archive
REQUIRED_PATHS = [
    "dart-sdk/bin/dart",
    "dart-sdk/bin/snapshots/analysis_server.dart.snapshot",
    "dart-sdk/lib/core/core.dart",
    "dart-sdk/include/dart_api.h",
    "dart-sdk/version",
    "dart-sdk/revision",
    "dart-sdk/LICENSE",
    "dart-sdk/README",
]


def list_zip_files(archive_path):
    with zipfile.ZipFile(archive_path, "r") as z:
        return z.namelist()


def list_tar_files(archive_path):
    with tarfile.open(archive_path, "r:*") as t:
        return t.getnames()


def verify_archive(archive_path):
    print(f"Auditing archive: {archive_path}")
    if not os.path.exists(archive_path):
        print(f"Error: File not found at {archive_path}", file=sys.stderr)
        return False

    if archive_path.endswith(".zip"):
        file_list = list_zip_files(archive_path)
    elif (
        archive_path.endswith(".tar.xz")
        or archive_path.endswith(".tar.gz")
        or archive_path.endswith(".tar")
    ):
        file_list = list_tar_files(archive_path)
    else:
        print(
            f"Error: Unknown archive format for {archive_path}",
            file=sys.stderr,
        )
        return False

    # 1. Verify all paths have the 'dart-sdk/' prefix
    invalid_prefixes = []
    for path in file_list:
        # Ignore empty directory entries or root-level directory entries if any
        if not path or path == "." or path == "./":
            continue
        # Normalize path
        normalized = os.path.normpath(path)
        if normalized == "dart-sdk":
            continue
        if not normalized.startswith("dart-sdk" + os.sep) and not normalized.startswith("dart-sdk/"):
            invalid_prefixes.append(path)

    if invalid_prefixes:
        print("Error: Found files outside the 'dart-sdk/' root directory:")
        for path in invalid_prefixes[:10]:
            print(f"  {path}")
        if len(invalid_prefixes) > 10:
            print(f"  ... and {len(invalid_prefixes) - 10} more.")
        return False

    # 2. Check for required paths
    missing_paths = []
    # Normalize our required paths for comparison
    normalized_file_list = {os.path.normpath(p) for p in file_list}
    for required in REQUIRED_PATHS:
        req_norm = os.path.normpath(required)
        if req_norm not in normalized_file_list:
            # On some platforms (like Windows), executable might have .exe
            if required == "dart-sdk/bin/dart":
                if os.path.normpath("dart-sdk/bin/dart.exe") in normalized_file_list:
                    continue
            missing_paths.append(required)

    if missing_paths:
        print("Error: Missing critical files in the archive:")
        for path in missing_paths:
            print(f"  {path}")
        return False

    print(
        f"Validation Successful! Archive contains {len(file_list)} files and matches the layout manifest."
    )
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Verify Dart SDK release archive layout."
    )
    parser.add_argument("archive", help="Path to the SDK zip or tar archive.")
    args = parser.parse_args()

    if verify_archive(args.archive):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
