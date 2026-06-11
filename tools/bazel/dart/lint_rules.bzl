# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Rules for running Dart static analysis and formatting checks as tests."""

load(":defs.bzl", "DartLibraryInfo")

def _runfiles_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    workspace = ctx.workspace_name
    if not workspace:
        workspace = "_main"
    return workspace + "/" + file.short_path

def _dart_lint_test_impl(ctx, cmd_args, use_package_dir = True, params_file = None):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    runner = ctx.actions.declare_file(ctx.label.name)

    # Use getattr to safely default to the target's package if package_dir is not defined or empty
    package_dir = getattr(ctx.attr, "package_dir", "")
    if not package_dir:
        package_dir = ctx.label.package
    if not package_dir:
        package_dir = "."

    runfiles_repo = ctx.label.workspace_name or ctx.workspace_name or "_main"
    runfiles_package_dir = runfiles_repo + "/" + package_dir

    dart_path = _runfiles_path(ctx, toolchain.dart_executable)
    package_config_path = _runfiles_path(ctx, ctx.file._package_config)

    # Run the command.
    # If params_file is provided, we use xargs with stdin redirection (portable across Linux and macOS).
    # If use_package_dir is True, we append the package_dir to the command (used for 'dart analyze').
    # Otherwise, we just run the command as is (args are already embedded).
    if params_file:
        params_path = _runfiles_path(ctx, params_file)
        exec_cmd = 'exec xargs "${{rdir}}/{dart_path}" {cmd_args} < "${{rdir}}/{params_path}" "$@"'.format(
            params_path = params_path,
            dart_path = dart_path,
            cmd_args = cmd_args,
        )
    elif use_package_dir:
        # Run on "." because we will cd into the package directory
        exec_cmd = 'exec "${{rdir}}/{dart_path}" {cmd_args} . "$@"'.format(
            dart_path = dart_path,
            cmd_args = cmd_args,
        )
    else:
        exec_cmd = 'exec "${{rdir}}/{dart_path}" {cmd_args} "$@"'.format(
            dart_path = dart_path,
            cmd_args = cmd_args,
        )

    # Clean runner script.
    # We export DART_PACKAGE_CONFIG pointing to the staged config in the runfiles.
    # Since it is generated at .dart_tool/package_config.json in the virtual repo,
    # the path will end with .dart_tool/package_config.json, which the Dart VM
    # requires to recognize it as a valid package config.
    script_content = """#!/bin/bash
set -e
if [ -n "$RUNFILES_DIR" ]; then
  rdir="$RUNFILES_DIR"
else
  rdir="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").runfiles"
fi

if [ -f "${{rdir}}/{package_config_path}" ]; then
  export DART_PACKAGE_CONFIG="${{rdir}}/{package_config_path}"
fi

cd "${{rdir}}"

# If we need to run in package dir, cd into it
if [ "{use_package_dir}" = "True" ] && [ -n "{runfiles_package_dir}" ]; then
  cd "{runfiles_package_dir}"
fi

# Run the command
{exec_cmd}
""".format(
        package_config_path = package_config_path,
        exec_cmd = exec_cmd,
        use_package_dir = use_package_dir,
        runfiles_package_dir = runfiles_package_dir,
    )

    ctx.actions.write(
        output = runner,
        content = script_content,
        is_executable = True,
    )

    extra_files = []
    if params_file:
        extra_files.append(params_file)

    runfiles = ctx.runfiles(
        files = [
            toolchain.dart_executable,
            ctx.file._package_config,
        ] + extra_files + getattr(ctx.files, "srcs", []),
        transitive_files = depset(
            transitive = [
                toolchain.sdk_files[DefaultInfo].files,
                ctx.attr.package[DartLibraryInfo].transitive_srcs,
            ] + [dep[DartLibraryInfo].transitive_srcs for dep in getattr(ctx.attr, "deps", [])],
        ),
    )

    return [
        DefaultInfo(
            executable = runner,
            runfiles = runfiles,
        ),
    ]

def _dart_analyze_test_impl(ctx):
    return _dart_lint_test_impl(ctx, "analyze --verbose")

def _dart_format_test_impl(ctx):
    # Expose direct sources directly from the provider, avoiding expensive depset.to_list()
    direct_srcs = [f for f in ctx.attr.package[DartLibraryInfo].srcs if f.extension == "dart"]

    if not direct_srcs:
        # If there are no Dart files to format, return a dummy test runner that exits 0.
        runner = ctx.actions.declare_file(ctx.label.name)
        ctx.actions.write(
            output = runner,
            content = "#!/bin/bash\necho 'No Dart sources found to format.'\nexit 0\n",
            is_executable = True,
        )
        return [
            DefaultInfo(
                executable = runner,
                runfiles = ctx.runfiles(),
            ),
        ]

    # Declare a params file to store the list of files to format.
    # This completely avoids the ARG_MAX command-line length limit.
    params_file = ctx.actions.declare_file(ctx.label.name + ".files.txt")

    # Write the workspace-relative paths of the direct sources to the params file.
    # When xargs runs in CWD (ws_root), these paths resolve perfectly.
    ctx.actions.write(
        output = params_file,
        content = "\n".join([f.short_path for f in direct_srcs]),
    )

    cmd_args = "format --output=none --set-exit-if-changed"

    return _dart_lint_test_impl(ctx, cmd_args, use_package_dir = False, params_file = params_file)

def _dart_package_test_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    runner = ctx.actions.declare_file(ctx.label.name)

    runfiles_repo = ctx.label.workspace_name or ctx.workspace_name or "_main"
    package_dir = ctx.attr.package_dir or ctx.label.package
    runfiles_package_dir = runfiles_repo + "/" + package_dir

    # Path resolved above

    package_config_path = _runfiles_path(ctx, ctx.file._package_config)
    dart_path = _runfiles_path(ctx, toolchain.dart_executable)

    script_content = """#!/bin/bash
set -e
if [ -n "$RUNFILES_DIR" ]; then
  rdir="$RUNFILES_DIR"
else
  rdir="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").runfiles"
fi

if [ -f "${{rdir}}/{package_config_path}" ]; then
  export DART_PACKAGE_CONFIG="${{rdir}}/{package_config_path}"
fi

cd "${{rdir}}"

if [ -n "{runfiles_package_dir}" ]; then
  cd "{runfiles_package_dir}"
fi

# Find and run all tests
failed=0
tests_found=0
while IFS= read -r test_file; do
  if [ -z "$test_file" ]; then
    continue
  fi
  tests_found=$((tests_found + 1))
  echo "----------------------------------------"
  echo "Running test: $test_file"
  echo "----------------------------------------"
  if ! "${{rdir}}/{dart_path}" "$test_file" "$@"; then
    echo "FAIL: $test_file"
    failed=1
  fi
done < <(find test -name "*_test.dart" 2>/dev/null)

if [ $tests_found -eq 0 ]; then
  echo "Error: No test files matching '*_test.dart' were found in the 'test' directory!"
  exit 1
fi

if [ $failed -ne 0 ]; then
  echo "Some tests failed!"
  exit 1
fi
echo "All $tests_found tests passed!"
""".format(
        package_config_path = package_config_path,
        runfiles_package_dir = runfiles_package_dir,
        dart_path = dart_path,
    )

    ctx.actions.write(
        output = runner,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            toolchain.dart_executable,
            ctx.file._package_config,
        ] + ctx.files.srcs,
        transitive_files = depset(
            transitive = [
                toolchain.sdk_files[DefaultInfo].files,
                ctx.attr.package[DartLibraryInfo].transitive_srcs,
            ] + [dep[DartLibraryInfo].transitive_srcs for dep in getattr(ctx.attr, "deps", [])],
        ),
    )

    return [
        DefaultInfo(
            executable = runner,
            runfiles = runfiles,
        ),
    ]

dart_analyze_test = rule(
    implementation = _dart_analyze_test_impl,
    test = True,
    attrs = {
        "deps": attr.label_list(default = [], providers = [DartLibraryInfo]),
        "package": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "package_dir": attr.string(default = ""),
        "_package_config": attr.label(
            default = "@dart_packages//:package_config_json",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

dart_format_test = rule(
    implementation = _dart_format_test_impl,
    test = True,
    attrs = {
        "deps": attr.label_list(default = [], providers = [DartLibraryInfo]),
        "package": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "_package_config": attr.label(
            default = "@dart_packages//:package_config_json",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

dart_package_test = rule(
    implementation = _dart_package_test_impl,
    test = True,
    attrs = {
        "deps": attr.label_list(default = [], providers = [DartLibraryInfo]),
        "package": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "package_dir": attr.string(default = ""),
        "srcs": attr.label_list(allow_files = True, default = []),
        "_package_config": attr.label(
            default = "@dart_packages//:package_config_json",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)
