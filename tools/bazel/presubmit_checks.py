# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
"""Presubmit check helpers for Bazel files and configurations."""

import os
import subprocess


def CheckUpstreamChanges(input_api, output_api):
    """Ensure that we minimize changes outside tools/bazel/."""
    repo_root = input_api.change.RepositoryRoot()
    allowed_file_path = os.path.join(repo_root, "tools", "bazel", "allowed_upstream_files.txt")
    allowed_external_files = set()
    if os.path.exists(allowed_file_path):
        with open(allowed_file_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                allowed_external_files.add(line)

    violations = []
    for git_file in input_api.AffectedTextFiles():
        local_path = git_file.LocalPath().replace('\\', '/')
        if not local_path.startswith("tools/bazel/") and not local_path.startswith("docs/bazel-migration/"):
            if local_path not in allowed_external_files:
                violations.append(local_path)

    if violations:
        return [
            output_api.PresubmitPromptWarning(
                "The following files were modified outside tools/bazel/.\n"
                "Please verify if these changes are absolutely necessary and maintain the spirit of the migration:\n"
                + "\n".join(f"  - {f}" for f in violations)
            )
        ]
    return []


def CheckStarlarkCp(input_api, output_api):
    """Ensure we don't use 'cp' command in Starlark files."""
    violations = []
    for git_file in input_api.AffectedTextFiles():
        local_path = git_file.LocalPath().replace('\\', '/')
        if local_path.endswith(".bzl"):
            for line_num, line_content in git_file.ChangedContents():
                if "ctx.execute" in line_content and "cp " in line_content:
                    violations.append(f"{local_path}:{line_num}: {line_content.strip()}")

    if violations:
        return [
            output_api.PresubmitError(
                "Avoid using 'cp' command in Starlark files. Use ctx.symlink or ctx.file instead:\n"
                + "\n".join(violations)
            )
        ]
    return []


def CheckBuildifier(input_api, output_api):
    """Ensure that all modified Bazel files are formatted and linted with buildifier."""
    results = []
    results.extend(CheckUpstreamChanges(input_api, output_api))
    results.extend(CheckStarlarkCp(input_api, output_api))

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
        return results

    cmd = ["buildifier", "--lint=warn", "--warnings=all", "--mode=check"] + bazel_files
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as e:
        results.append(
            output_api.PresubmitError(
                "Buildifier found formatting or linter issues in Bazel files:\n" + e.stdout + e.stderr
            )
        )
    except OSError as e:
        results.append(
            output_api.PresubmitPromptWarning(
                f"buildifier could not be run ({e}). Skipping Bazel lint checks. "
                "Please install buildifier to ensure Bazel files are formatted correctly."
            )
        )

    return results
