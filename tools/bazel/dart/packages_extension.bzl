# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Dynamic package dependency mapping extension."""

def _parse_dependencies(ctx, pubspec_path):
    """Parse dependencies from a pubspec.yaml file, returning a list of package names."""
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
            if key == "dependencies":
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
    clone_script = ctx.path(Label("@//tools/bazel:clone_dependencies.py"))
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

    # Generate the macro in defs.bzl
    macro_lines = [
        "load(\"@//tools/bazel/dart:defs.bzl\", \"dart_library\")",
        "load(\"@//tools/bazel/dart:lint_rules.bzl\", \"dart_analyze_test\", \"dart_format_test\")",
        "",
        "def declare_package_targets():",
    ]

    packages_json = []

    for name in sorted(pkgs.keys()):
        pkg = pkgs[name]

        # Parse dependencies from pubspec in the workspace
        pubspec_path = workspace_dir.get_child(pkg.reldir).get_child("pubspec.yaml")
        deps = []
        for d in _parse_dependencies(ctx, pubspec_path):
            if d in known and d != name:
                deps.append(d)

        # Emit target declaration in the macro
        glob_path = "%s/%s/**/*.dart" % (pkg.reldir, pkg.lib)
        dep_labels = ", ".join(['":dart_pkg_%s"' % d for d in sorted(deps)])

        macro_lines.append("    dart_library(")
        macro_lines.append("        name = \"dart_pkg_%s\"," % name)
        macro_lines.append("        srcs = native.glob([\"%s\"], allow_empty = True)," % glob_path)
        macro_lines.append("        deps = [%s]," % dep_labels)
        macro_lines.append("    )")
        macro_lines.append("")
        macro_lines.append("    dart_analyze_test(")
        macro_lines.append("        name = \"dart_pkg_%s_analyze\"," % name)
        macro_lines.append("        package = \":dart_pkg_%s\"," % name)
        macro_lines.append("        package_dir = \"%s\"," % pkg.reldir)
        macro_lines.append("    )")
        macro_lines.append("")
        macro_lines.append("    dart_format_test(")
        macro_lines.append("        name = \"dart_pkg_%s_format\"," % name)
        macro_lines.append("        package = \":dart_pkg_%s\"," % name)
        macro_lines.append("        package_dir = \"%s\"," % pkg.reldir)
        macro_lines.append("    )")
        macro_lines.append("")

        # Reconstruct package_config entry pointing to the sandbox location
        root_uri = "../../../%s/%s" % (pkg.reldir, pkg.lib)
        pkg_entry = {
            "name": name,
            "packageUri": "",
            "rootUri": root_uri,
        }
        if pkg.language_version:
            pkg_entry["languageVersion"] = pkg.language_version
        packages_json.append(pkg_entry)

    if not pkgs:
        macro_lines.append("    pass")

    # Generate package_config.json file
    package_config_content = {
        "configVersion": 2,
        "packages": packages_json,
    }
    ctx.file("package_config.json", json.encode(package_config_content) + "\n")

    # Write BUILD.bazel (only holds the filegroup for package_config.json)
    ctx.file("BUILD.bazel", "\n".join([
        "package(default_visibility = [\"//visibility:public\"])",
        "",
        "filegroup(",
        "    name = \"package_config_json\",",
        "    srcs = [\"package_config.json\"],",
        ")",
    ]) + "\n")

    # Write defs.bzl
    ctx.file("defs.bzl", "\n".join(macro_lines) + "\n")

dart_packages_repo = repository_rule(
    implementation = _packages_repo_impl,
)

def _packages_ext_impl(ctx):
    dart_packages_repo(name = "dart_packages")
    return ctx.extension_metadata(reproducible = True)

dart_packages_extension = module_extension(implementation = _packages_ext_impl)
