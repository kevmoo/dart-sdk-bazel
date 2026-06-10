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

def _dart_lint_test_impl(ctx, cmd_args, use_package_dir = True):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    runner = ctx.actions.declare_file(ctx.label.name)

    package_dir = ctx.attr.package_dir
    dart_path = _runfiles_path(ctx, toolchain.dart_executable)
    package_config_path = _runfiles_path(ctx, ctx.file._package_config)

    workspace_name = ctx.workspace_name or "_main"

    # Run the command. If use_package_dir is True, we append the package_dir
    # to the command (used for 'dart analyze'). If False, the command already
    # contains the explicit files (used for 'dart format').
    if use_package_dir:
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

    script_content = """#!/bin/bash
if [ -n "$RUNFILES_DIR" ]; then
  rdir="$RUNFILES_DIR"
else
  rdir="$0.runfiles"
fi

ws_root="${{rdir}}/{workspace_name}"

# Stage and adjust package_config.json if it exists
if [ -f "${{rdir}}/{package_config_path}" ]; then
  mkdir -p "${{ws_root}}/.dart_tool"
  sed 's|"rootUri": "\\.\\./\\.\\./\\.\\./|"rootUri": "../|g' "${{rdir}}/{package_config_path}" > "${{ws_root}}/.dart_tool/package_config.json"
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

    runfiles = ctx.runfiles(
        files = [
            toolchain.dart_executable,
            ctx.file._package_config,
        ],
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
    package_dir = ctx.attr.package_dir
    direct_srcs = []

    # Filter the transitive sources to find only the direct Dart sources of this package.
    # Any file in transitive_srcs that starts with the package_dir and ends with .dart is a direct source.
    for f in ctx.attr.package[DartLibraryInfo].transitive_srcs.to_list():
        if f.short_path.startswith(package_dir + "/") and f.path.endswith(".dart"):
            direct_srcs.append(f)

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

    file_paths = [_runfiles_path(ctx, f) for f in direct_srcs]

    # Construct the command arguments by pointing directly to the runfiles paths
    # of the direct sources. This forces 'dart format' to follow the symlinks.
    cmd_args = "format --output=none --set-exit-if-changed " + " ".join(["\"${rdir}/" + p + "\"" for p in file_paths])

    return _dart_lint_test_impl(ctx, cmd_args, use_package_dir = False)

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
        "package_dir": attr.string(mandatory = True),
        "_package_config": attr.label(
            default = "//tools/bazel/dart:runfiles_package_config",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)
