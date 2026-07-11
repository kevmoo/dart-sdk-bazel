#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
"""Presubmit check helpers for Bazel files and configurations."""

import os
import subprocess


def CheckBuildifier(input_api, output_api):
    """Ensure that all modified Bazel files are formatted and linted with buildifier."""
    bazel_files = []
    for git_file in input_api.AffectedTextFiles():
        local_path = git_file.LocalPath()
        filename = os.path.basename(local_path)
        if (filename in ("BUILD", "BUILD.bazel", "WORKSPACE", "WORKSPACE.bazel", "MODULE.bazel") or
                local_path.endswith(".bzl")):
            abs_path = git_file.AbsoluteLocalPath()
            if os.path.exists(abs_path):
                bazel_files.append(abs_path)

    if not bazel_files:
        return []

    cmd = ["buildifier", "--lint=warn", "--warnings=all", "--mode=check"] + bazel_files
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as e:
        return [
            output_api.PresubmitError(
                "Buildifier found formatting or lint issues in Bazel files:\n" + e.stdout + e.stderr
            )
        ]
    except OSError as e:
        return [
            output_api.PresubmitPromptWarning(
                f"buildifier could not be run ({e}). Skipping Bazel lint checks. "
                "Please install buildifier to ensure Bazel files are formatted correctly."
            )
        ]

    return []
