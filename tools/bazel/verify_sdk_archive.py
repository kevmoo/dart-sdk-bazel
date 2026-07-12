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
    if not os.path.isfile(archive_path):
        print(f"Error: File not found or is not a file at {archive_path}", file=sys.stderr)
        return False

    try:
        archive_path_lower = archive_path.lower()
        if archive_path_lower.endswith(".zip"):
            file_list = list_zip_files(archive_path)
        elif (
            archive_path_lower.endswith(".tar.xz")
            or archive_path_lower.endswith(".tar.gz")
            or archive_path_lower.endswith(".tar")
        ):
            file_list = list_tar_files(archive_path)
        else:
            print(
                f"Error: Unknown archive format for {archive_path}",
                file=sys.stderr,
            )
            return False
    except (zipfile.BadZipFile, tarfile.TarError, OSError) as e:
        print(f"Error: Failed to read archive {archive_path}: {e}", file=sys.stderr)
        return False

    # Normalize all paths once to forward slashes and strip leading './'
    # to avoid redundant normalization and handle tar archives robustly.
    normalized_paths = []
    for path in file_list:
        clean = path.replace("\\", "/")
        if clean.startswith("./"):
            clean = clean[2:]
        if ".." in clean.split("/"):
            print(f"Error: Path traversal sequence detected in path: {path}", file=sys.stderr)
            return False
        normalized_paths.append((clean, path))

    # 1. Verify all paths have the 'dart-sdk/' prefix
    invalid_prefixes = []
    for clean_path, original_path in normalized_paths:
        # Ignore empty directory entries or root-level directory entries if any
        if not clean_path or clean_path == "." or clean_path == "/":
            continue
        if clean_path == "dart-sdk" or clean_path == "dart-sdk/":
            continue
        if not clean_path.startswith("dart-sdk/"):
            invalid_prefixes.append(original_path)

    if invalid_prefixes:
        print("Error: Found files outside the 'dart-sdk/' root directory:")
        for path in invalid_prefixes[:10]:
            print(f"  {path}")
        if len(invalid_prefixes) > 10:
            print(f"  ... and {len(invalid_prefixes) - 10} more.")
        return False

    # 2. Check for required paths
    missing_paths = []
    normalized_set = {clean_path for clean_path, _ in normalized_paths}
    for required in REQUIRED_PATHS:
        if required not in normalized_set:
            # On some platforms (like Windows), executable might have .exe
            if required == "dart-sdk/bin/dart" and "dart-sdk/bin/dart.exe" in normalized_set:
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
