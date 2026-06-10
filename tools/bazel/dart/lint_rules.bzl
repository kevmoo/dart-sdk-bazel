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

    # Use getattr to safely default to "." if package_dir is not defined on the rule (e.g. for format tests)
    package_dir = getattr(ctx.attr, "package_dir", ".") or "."
    dart_path = _runfiles_path(ctx, toolchain.dart_executable)
    package_config_path = _runfiles_path(ctx, ctx.file._package_config)

    workspace_name = ctx.workspace_name or "_main"

    # Run the command.
    # If params_file is provided, we use xargs with stdin redirection (portable across Linux and macOS).
    # If use_package_dir is True, we append the package_dir to the command (used for 'dart analyze').
    # Otherwise, we just run the command as is (args are already embedded).
    if params_file:
        params_path = _runfiles_path(ctx, params_file)
        exec_cmd = 'exec xargs "${{rdir}}/{dart_path}" {cmd_args} < "${{rdir}}/{params_path}"'.format(
            params_path = params_path,
            dart_path = dart_path,
            cmd_args = cmd_args,
        )
    elif use_package_dir:
        exec_cmd = 'exec "${{rdir}}/{dart_path}" {cmd_args} "{package_dir}"'.format(
            dart_path = dart_path,
            cmd_args = cmd_args,
            package_dir = package_dir,
        )
    else:
        exec_cmd = 'exec "${{rdir}}/{dart_path}" {cmd_args}'.format(
            dart_path = dart_path,
            cmd_args = cmd_args,
        )

    # Added set -e for fail-fast safety
    script_content = """#!/bin/bash
set -e
if [ -n "$RUNFILES_DIR" ]; then
  rdir="$RUNFILES_DIR"
else
  rdir="$(cd "$(dirname "$0")" && pwd)/$(basename "$0").runfiles"
fi

ws_root="${{rdir}}/{workspace_name}"

# Set the package config environment variable pointing to the runfiles version
if [ -f "${{rdir}}/{package_config_path}" ]; then
  export DART_PACKAGE_CONFIG="${{rdir}}/{package_config_path}"
fi

# CD into the workspace root (needed for relative paths in package_config to resolve)
cd "${{ws_root}}"

# Run the command
{exec_cmd}
""".format(
        workspace_name = workspace_name,
        package_config_path = package_config_path,
        exec_cmd = exec_cmd,
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
        ] + extra_files,
        transitive_files = depset(
            transitive = [
                toolchain.sdk_files[DefaultInfo].files,
                ctx.attr.package[DartLibraryInfo].transitive_srcs,
            ],
        ),
    )

    return [
        DefaultInfo(
            executable = runner,
            runfiles = runfiles,
        ),
    ]

def _dart_analyze_test_impl(ctx):
    return _dart_lint_test_impl(ctx, "analyze")

def _dart_format_test_impl(ctx):
    # Expose direct sources directly from the provider, avoiding expensive depset.to_list()
    direct_srcs = ctx.attr.package[DartLibraryInfo].srcs

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

dart_analyze_test = rule(
    implementation = _dart_analyze_test_impl,
    test = True,
    attrs = {
        "package": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "package_dir": attr.string(mandatory = True),
        "_package_config": attr.label(
            default = "//tools/bazel/dart:runfiles_package_config",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

dart_format_test = rule(
    implementation = _dart_format_test_impl,
    test = True,
    attrs = {
        "package": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "_package_config": attr.label(
            default = "//tools/bazel/dart:runfiles_package_config",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)
