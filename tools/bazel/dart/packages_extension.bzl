# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Dynamic package dependency mapping extension."""

def _parse_dependencies(ctx, pubspec_path, sections = ["dependencies"]):
    """Parse dependencies from a pubspec.yaml file in specified sections, returning a list of package names."""
    if not pubspec_path.exists:
        return []
    content = ctx.read(pubspec_path)
    deps = []
    in_deps = False
    for line in content.split("\n"):
        line = line.rstrip("\r")

        # Strip comments to handle inline comments and commented-out packages correctly
        line = line.split("#", 1)[0]
        if not line.strip():
            continue
        first_char = line[0] if len(line) > 0 else ""
        if first_char.isalpha():
            key = line.split(":", 1)[0].strip()
            if key in sections:
                in_deps = True
            else:
                in_deps = False
            continue
        if in_deps:
            if line.startswith("  ") and not line.startswith("   "):
                parts = line.strip().split(":")
                if len(parts) > 0:
                    dep_name = parts[0].strip()
                    if dep_name:
                        deps.append(dep_name)
    return deps

def _copy_path(ctx, src, dst):
    if "windows" not in ctx.os.name.lower():
        parent = "/".join(dst.split("/")[:-1])
        if parent:
            ctx.execute(["mkdir", "-p", parent])
        ctx.execute(["rm", "-rf", dst])
        res = ctx.execute(["cp", "-r", str(src), dst])
        if res.return_code != 0:
            fail("Failed to copy %s to %s: %s" % (src, dst, res.stderr))
        return

    python_code = """
import os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
parent = os.path.dirname(dst)
if parent:
    os.makedirs(parent, exist_ok=True)
if os.path.exists(dst):
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    else:
        os.remove(dst)
if os.path.isdir(src):
    shutil.copytree(src, dst, symlinks=True)
else:
    shutil.copy2(src, dst)
"""
    res = ctx.execute(["python3", "-c", python_code, str(src), str(dst)])
    if res.return_code != 0:
        res = ctx.execute(["python", "-c", python_code, str(src), str(dst)])
    if res.return_code != 0:
        fail("Failed to copy %s to %s: %s" % (src, dst, res.stderr))

def _list_files(ctx, physical_dir, workspace_root_str, extensions = [".dart", ".yaml"]):
    """Recursively list all files in physical_dir on the host, returning their paths relative to workspace or virtual root."""

    if not physical_dir.exists:
        return []
    res = ctx.execute(["find", str(physical_dir), "-type", "f"])
    if res.return_code != 0:
        fail("Failed to list files in " + str(physical_dir) + ": " + res.stderr)

    files = []
    virtual_root_str = str(ctx.path(""))
    for line in res.stdout.split("\n"):
        line = line.strip()
        if not line:
            continue

        # Filter by extension
        matched = False
        for ext in extensions:
            if line.endswith(ext):
                matched = True
                break
        if not matched:
            continue

        # Make path relative to the appropriate root
        if line.startswith(virtual_root_str):
            rel_path = line[len(virtual_root_str) + 1:]
            files.append(rel_path)
        elif line.startswith(workspace_root_str):
            rel_path = line[len(workspace_root_str) + 1:]
            files.append(rel_path)
        else:
            fail("File path " + line + " does not start with workspace root " + workspace_root_str + " or virtual root " + virtual_root_str)
    return files

def _packages_repo_impl(ctx):
    workspace_dir = ctx.workspace_root
    devtools_root = ctx.path(ctx.attr.devtools_marker).dirname

    # Register dependency on the sentinel file to force Bzlmod invalidation if the workspace is cleaned.
    # This resolves the bug where Bazel restores the virtual repo from cache but the cloned files in the
    # workspace were deleted by a clean CI run, leaving dangling symlinks.
    sentinel = workspace_dir.get_child("third_party").get_child("pkg").get_child(".cloned_sentinel")
    if sentinel.exists:
        ctx.read(sentinel)

    # Check if we have a local third-party checkout in the workspace (developer mode).
    # We use 'third_party/pkg/core' as a representative check.
    # Detect if we are running in a CI environment.
    is_ci = ctx.os.environ.get("CI") == "true"

    # Check if we have a local third-party checkout in the workspace (developer mode).
    # We use 'third_party/pkg/core' as a representative check.
    # If we are in the CI, we force CI Mode (use_local_third_party = False) to ensure
    # we use relative symlinks and explicit srcs, even if the WORKSPACE downloader
    # has already cloned the files into the workspace.
    local_third_party_core = workspace_dir.get_child("third_party").get_child("pkg").get_child("core")
    use_local_third_party = local_third_party_core.exists and not is_ci

    # Dynamically clone third_party/pkg dependencies from DEPS if missing.
    clone_script = ctx.path(Label("@dart_sdk//tools/bazel:clone_dependencies.py"))

    if use_local_third_party:
        # Developer mode: reuse the clones in the main workspace.
        res = ctx.execute(["python3", str(clone_script)])
    else:
        # CI/Clean mode: clone the repositories directly INSIDE the virtual repository
        # so they are cached and restored together with the symlinks.
        res = ctx.execute(["python3", str(clone_script), "--dest", str(ctx.path(""))])

    if res.stdout:
        # buildifier: disable=print
        print("Clone stdout:\n" + res.stdout)
    if res.stderr:
        # buildifier: disable=print
        print("Clone stderr:\n" + res.stderr)
    if res.return_code != 0:
        fail("Failed to clone third-party Dart package dependencies: " + res.stderr)

    package_config_path = workspace_dir.get_child(".dart_tool").get_child("package_config.json")
    if not package_config_path.exists:
        fail("Could not find package_config.json at: " + str(package_config_path))

    config_str = ctx.read(package_config_path)
    config = json.decode(config_str)

    pkgs = {}
    known = []

    # First pass: identify all valid packages in the config
    packages_list = config.get("packages", [])
    for p in packages_list:
        name = p.get("name")
        root_uri = p.get("rootUri")
        if not name or not root_uri:
            continue

        # Resolve path relative to .dart_tool/
        package_root = ctx.path(str(package_config_path.dirname) + "/" + root_uri)

        # Verify it is inside the workspace checkout
        if not str(package_root).startswith(str(workspace_dir) + "/"):
            # Outside checkout (e.g. pub cache), skip.
            continue

        # Extract relative path from workspace root
        reldir = str(package_root)[len(str(workspace_dir)) + 1:]
        if reldir == ".":
            # Workspace root itself, skip
            continue

        lib = (p.get("packageUri") or "lib/").rstrip("/")
        language_version = p.get("languageVersion")
        pkgs[name] = struct(
            reldir = reldir,
            lib = lib,
            language_version = language_version,
        )
        known.append(name)

    # Copy root analysis options and pubspec.yaml so that they are available in the virtual repo root
    for file_name in ["analysis_options.yaml", "analysis_options_no_lints.yaml", "pubspec.yaml"]:
        root_file = workspace_dir.get_child(file_name)
        if root_file.exists:
            _copy_path(ctx, root_file, file_name)

    packages_json = []
    all_cloned_files = []

    for name in sorted(pkgs.keys()):
        pkg = pkgs[name]

        # Parse dependencies from pubspec
        if name == "devtools_shared" and not use_local_third_party:
            pubspec_path = devtools_root.get_child("devtools_shared").get_child("pubspec.yaml")
        else:
            pubspec_path = workspace_dir.get_child(pkg.reldir).get_child("pubspec.yaml")

        # Parse regular dependencies for dart_library
        deps = []
        for d in _parse_dependencies(ctx, pubspec_path, ["dependencies"]):
            if d in known and d != name:
                deps.append(d)

        # Parse dev_dependencies for dart_analyze_test
        dev_deps = []
        for d in _parse_dependencies(ctx, pubspec_path, ["dev_dependencies"]):
            if d in known and d != name:
                dev_deps.append(d)

        # Resolve physical path
        is_third_party_pkg = pkg.reldir.startswith("third_party/pkg/")

        if is_third_party_pkg and not use_local_third_party:
            # Check if it was actually cloned into the virtual repository
            cloned_path = ctx.path(pkg.reldir)
            if cloned_path.exists:
                physical_path = cloned_path
                is_cloned = True
            else:
                # It's a Git-tracked package in the main workspace (e.g. third_party/pkg/dap)
                physical_path = workspace_dir.get_child(pkg.reldir)
                is_cloned = False
        elif name == "devtools_shared" and not use_local_third_party:
            # CI Mode for devtools_shared: resolve to the external @devtools repository
            physical_path = devtools_root.get_child("devtools_shared")
            is_cloned = False
        else:
            # Developer mode / Local package: resolve to the main workspace
            physical_path = workspace_dir.get_child(pkg.reldir)
            is_cloned = False

        physical_lib = physical_path.get_child(pkg.lib)

        virtual_pkg_dir = "pkg/" + name

        # We only create symlinks in Developer Mode or for local SDK packages.
        # In CI Mode for third-party packages, we map them directly to their cloned paths
        # in package_config.json, eliminating the need for symlinks entirely!
        if not is_cloned:
            # 1. Copy 'lib' (mandatory for dart_library)
            if physical_lib.exists:
                _copy_path(ctx, physical_lib, virtual_pkg_dir + "/" + pkg.lib)

            # 2. Copy common files in package root (pubspec, analysis options, messages)
            for file_name in ["pubspec.yaml", "analysis_options.yaml", "analysis_options_no_lints.yaml", "messages.yaml", "api.txt"]:
                physical_file = physical_path.get_child(file_name)
                if physical_file.exists:
                    _copy_path(ctx, physical_file, virtual_pkg_dir + "/" + file_name)

            # 4. Copy other common directories if they exist (bin, test, tool, web)
            for dir_name in ["bin", "test", "tool", "web"]:
                physical_dir = physical_path.get_child(dir_name)
                if physical_dir.exists:
                    _copy_path(ctx, physical_dir, virtual_pkg_dir + "/" + dir_name)

        # Generate BUILD.bazel content for this package
        build_lines = [
            "# Generated by tools/bazel/dart/packages_extension.bzl. DO NOT EDIT.",
            "",
            'load("@dart_sdk//tools/bazel/dart:defs.bzl", "dart_library")',
            'load("@dart_sdk//tools/bazel/dart:lint_rules.bzl", "dart_analyze_test", "dart_format_test", "dart_package_test")',
            "",
            'package(default_visibility = ["//visibility:public"])',
            "",
        ]

        # Determine sources: Developer mode (glob) vs CI mode (explicit)
        workspace_root_str = str(workspace_dir)

        if not is_cloned:
            # Developer mode or Local package: use standard globbing
            glob_paths = ['"%s/**/*.dart"' % pkg.lib, '"%s/**/*.yaml"' % pkg.lib]
            for options_name in ["analysis_options.yaml", "analysis_options_no_lints.yaml", "messages.yaml"]:
                physical_options = physical_path.get_child(options_name)
                if physical_options.exists:
                    glob_paths.append('"%s"' % options_name)
            physical_pubspec = physical_path.get_child("pubspec.yaml")
            if physical_pubspec.exists:
                glob_paths.append('"pubspec.yaml"')
            srcs_val = "glob([%s], allow_empty = True)" % ", ".join(glob_paths)
        else:
            # CI/Clean mode for third-party: explicitly list all files recursively
            # to avoid host-globbing and force Bazel to stage them in the sandbox.
            lib_files = _list_files(ctx, physical_lib, workspace_root_str, [".dart", ".yaml"])

            # Add analysis options explicitly if they exist
            options_files = []
            for options_name in ["analysis_options.yaml", "analysis_options_no_lints.yaml", "messages.yaml"]:
                physical_options = physical_path.get_child(options_name)
                if physical_options.exists:
                    options_files.append(pkg.reldir + "/" + options_name)

            # Accumulate all cloned files for exports_files in the root BUILD.bazel
            for f in lib_files + options_files:
                all_cloned_files.append(f)

            # The paths in srcs must be root-relative labels in the same repository
            # starting with '//:' to comply with Bazel label constraints (no '..' allowed).
            srcs_labels = []
            for f in sorted(lib_files + options_files):
                srcs_labels.append('"//:%s"' % f)
            srcs_val = "[%s]" % ", ".join(srcs_labels)

        dep_labels = ", ".join(['"//pkg/%s"' % d for d in sorted(deps)])

        build_lines.append("dart_library(")
        build_lines.append('    name = "%s",' % name)
        build_lines.append("    srcs = %s," % srcs_val)
        if dep_labels:
            build_lines.append("    deps = [%s]," % dep_labels)
        build_lines.append(")")
        build_lines.append("")

        # Only generate lint/format tests for local packages (not in third_party/)
        if not pkg.reldir.startswith("third_party/"):
            # Merge regular deps and dev_deps for the tests.
            # Pragmatically always append 'lints' and 'dart_flutter_team_lints' if they are known
            # packages in the SDK, to ensure the analyzer and formatter can always resolve
            # these standard configuration packages in the sandbox.
            test_deps = list(deps + dev_deps)
            for default_dep in ["lints", "dart_flutter_team_lints"]:
                if default_dep in known and default_dep != name:
                    test_deps.append(default_dep)

            unique_test_deps = {}
            for d in test_deps:
                unique_test_deps[d] = True
            all_test_deps = sorted(unique_test_deps.keys())
            test_dep_labels = ", ".join(['"//pkg/%s"' % d for d in all_test_deps])

            build_lines.append("dart_analyze_test(")
            build_lines.append('    name = "analyze",')
            build_lines.append('    package = ":%s",' % name)
            if test_dep_labels:
                build_lines.append("    deps = [%s]," % test_dep_labels)
            build_lines.append(")")
            build_lines.append("")

            build_lines.append("dart_format_test(")
            build_lines.append('    name = "format",')
            build_lines.append('    package = ":%s",' % name)
            if test_dep_labels:
                build_lines.append("    deps = [%s]," % test_dep_labels)
            build_lines.append(")")
            build_lines.append("")

            # Generate package test target if test directory exists
            physical_test_dir = physical_path.get_child("test")
            if physical_test_dir.exists:
                build_lines.append("dart_package_test(")
                build_lines.append('    name = "pkg_test",')
                build_lines.append('    package = ":%s",' % name)
                build_lines.append('    srcs = glob(["test/**"], allow_empty = True),')
                if test_dep_labels:
                    build_lines.append("    deps = [%s]," % test_dep_labels)
                build_lines.append(")")
                build_lines.append("")

        # Add a filegroup that exposes all files in the package for runfiles
        build_lines.append("filegroup(")
        build_lines.append('    name = "sdk_package_sources",')
        build_lines.append('    srcs = glob(["**/*"], exclude = ["BUILD", "BUILD.bazel"], allow_empty = True),')
        build_lines.append(")")
        build_lines.append("")

        # Write the BUILD.bazel file
        ctx.file("%s/BUILD.bazel" % virtual_pkg_dir, "\n".join(build_lines) + "\n")

        # Reconstruct package_config entry pointing to the virtual location.
        # Since the config will be written to .dart_tool/package_config.json,
        # we must use '../pkg/name' for local/developer packages, or point
        # directly to the cloned 'third_party/' directory in CI Mode.
        if not is_cloned:
            root_uri = "../pkg/%s" % name
        else:
            root_uri = "../%s" % pkg.reldir
        package_uri = pkg.lib + "/"
        pkg_entry = {
            "name": name,
            "packageUri": package_uri,
            "rootUri": root_uri,
        }
        if pkg.language_version:
            pkg_entry["languageVersion"] = pkg.language_version
        packages_json.append(pkg_entry)

    # Generate .dart_tool/package_config.json file (standard Dart location)
    package_config_content = {
        "configVersion": 2,
        "packages": packages_json,
    }
    ctx.file(".dart_tool/package_config.json", json.encode(package_config_content) + "\n")

    # Write BUILD.bazel (holds the filegroup for package_config.json and exports_files for CI Mode)
    root_build_lines = [
        "# Generated by tools/bazel/dart/packages_extension.bzl. DO NOT EDIT.",
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "filegroup(",
        "    name = \"package_config_json\",",
        "    srcs = [\".dart_tool/package_config.json\"],",
        ")",
        "",
    ]
    if workspace_dir.get_child("pubspec.yaml").exists:
        root_build_lines.append("exports_files([\"pubspec.yaml\"])")
        root_build_lines.append("")
    if all_cloned_files:
        root_build_lines.append("exports_files([")
        for f in sorted(all_cloned_files):
            root_build_lines.append("    \"%s\"," % f)
        root_build_lines.append("])")
        root_build_lines.append("")

    ctx.file("BUILD.bazel", "\n".join(root_build_lines) + "\n")

    # buildifier: disable=print
    print("Generated Bazel targets for %d Dart packages (CI Mode: %s)." % (len(pkgs), str(not use_local_third_party)))

dart_packages_repo = repository_rule(
    implementation = _packages_repo_impl,
    environ = ["CI"],
    attrs = {
        "devtools_marker": attr.label(default = Label("@devtools//:web")),
    },
)

def _packages_ext_impl(ctx):
    dart_packages_repo(name = "dart_packages")
    return ctx.extension_metadata(reproducible = True)

dart_packages_extension = module_extension(
    implementation = _packages_ext_impl,
    environ = ["CI"],
)
# Force invalidation trigger: 8
