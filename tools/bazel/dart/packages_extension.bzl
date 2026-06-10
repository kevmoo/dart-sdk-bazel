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

def _packages_repo_impl(ctx):
    # Dynamically clone third_party/pkg dependencies from DEPS if missing
    clone_script = ctx.path(Label("@dart_sdk//tools/bazel:clone_dependencies.py"))
    res = ctx.execute(["python3", str(clone_script)])
    if res.stdout:
        # buildifier: disable=print
        print("Clone stdout:\n" + res.stdout)
    if res.stderr:
        # buildifier: disable=print
        print("Clone stderr:\n" + res.stderr)
    if res.return_code != 0:
        fail("Failed to clone third-party Dart package dependencies: " + res.stderr)

    workspace_dir = ctx.workspace_root
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

    packages_json = []

    for name in sorted(pkgs.keys()):
        pkg = pkgs[name]

        # Parse dependencies from pubspec in the workspace
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
        physical_path = workspace_dir.get_child(pkg.reldir)
        virtual_pkg_dir = "pkg/" + name

        # Safely symlink only the essential components of the Dart package.
        # This prevents polluting the virtual repository with main-repo Bazel infrastructure
        # (like tools/bazel) which contains BUILD files that would conflict.

        # 1. Symlink 'lib' (mandatory for dart_library)
        physical_lib = physical_path.get_child(pkg.lib)
        if physical_lib.exists:
            ctx.symlink(physical_lib, virtual_pkg_dir + "/" + pkg.lib)

        # 2. Symlink 'pubspec.yaml' (highly recommended for tooling)
        physical_pubspec = physical_path.get_child("pubspec.yaml")
        if physical_pubspec.exists:
            ctx.symlink(physical_pubspec, virtual_pkg_dir + "/pubspec.yaml")

        # 3. Symlink 'analysis_options.yaml' and its common sibling configurations
        for options_name in ["analysis_options.yaml", "analysis_options_no_lints.yaml"]:
            physical_options = physical_path.get_child(options_name)
            if physical_options.exists:
                ctx.symlink(physical_options, virtual_pkg_dir + "/" + options_name)

        # 4. Symlink 'bin' if it exists (for packages with executables)
        physical_bin = physical_path.get_child("bin")
        if physical_bin.exists:
            ctx.symlink(physical_bin, virtual_pkg_dir + "/bin")

        # Generate BUILD.bazel content for this package
        build_lines = [
            "# Generated by tools/bazel/dart/packages_extension.bzl. DO NOT EDIT.",
            "",
            'load("@dart_sdk//tools/bazel/dart:defs.bzl", "dart_library")',
            'load("@dart_sdk//tools/bazel/dart:lint_rules.bzl", "dart_analyze_test", "dart_format_test")',
            "",
            'package(default_visibility = ["//visibility:public"])',
            "",
        ]

        # Include both .dart and .yaml files in the library sources.
        # This ensures configuration files (like lints' recommended.yaml)
        # are carried in the transitive sources and staged in runfiles for analysis.
        glob_paths = ['"%s/**/*.dart"' % pkg.lib, '"%s/**/*.yaml"' % pkg.lib]

        # Also include the package's own analysis options if they exist
        for options_name in ["analysis_options.yaml", "analysis_options_no_lints.yaml"]:
            physical_options = physical_path.get_child(options_name)
            if physical_options.exists:
                glob_paths.append('"%s"' % options_name)

        glob_str = ", ".join(glob_paths)
        dep_labels = ", ".join(['"//pkg/%s"' % d for d in sorted(deps)])

        build_lines.append("dart_library(")
        build_lines.append('    name = "%s",' % name)
        build_lines.append("    srcs = glob([%s], allow_empty = True)," % glob_str)
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

        # Write the BUILD.bazel file
        ctx.file("%s/BUILD.bazel" % virtual_pkg_dir, "\n".join(build_lines) + "\n")

        # Reconstruct package_config entry pointing to the virtual location.
        # Since the config will be written to .dart_tool/package_config.json,
        # we must use '../pkg/name' to escape the .dart_tool directory and
        # point to the pkg directory at the root of the virtual repository.
        root_uri = "../pkg/%s" % name
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

    # Write BUILD.bazel (only holds the filegroup for package_config.json)
    ctx.file("BUILD.bazel", "\n".join([
        "# Generated by tools/bazel/dart/packages_extension.bzl. DO NOT EDIT.",
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "filegroup(",
        "    name = \"package_config_json\",",
        "    srcs = [\".dart_tool/package_config.json\"],",
        ")",
    ]) + "\n")

dart_packages_repo = repository_rule(
    implementation = _packages_repo_impl,
)

def _packages_ext_impl(ctx):
    dart_packages_repo(name = "dart_packages")
    return ctx.extension_metadata(reproducible = True)

dart_packages_extension = module_extension(implementation = _packages_ext_impl)
