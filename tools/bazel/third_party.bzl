# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Bzlmod module extensions for staging external third-party dependencies non-invasively."""

def _symlink_local(repository_ctx, src_dir, dest_dir, prefix):
    # Define a python script to recursively symlink the local directory,
    # supporting an optional subdirectory prefix, and skipping conflicting build files.
    py_script = repository_ctx.path("symlink_exclude.py")
    repository_ctx.file(py_script, content = """
import os
import sys

src = sys.argv[1]
dest = sys.argv[2]
prefix = sys.argv[3]

for root, dirs, files in os.walk(src, followlinks=True):
    rel = os.path.relpath(root, src)
    if rel == ".":
        td = os.path.join(dest, prefix) if prefix else dest
    else:
        td = os.path.join(dest, prefix, rel) if prefix else os.path.join(dest, rel)
    os.makedirs(td, exist_ok=True)
    for f in files:
        if f in ["BUILD", "BUILD.bazel", "WORKSPACE", "MODULE.bazel"]:
            continue
        src_file = os.path.join(root, f)
        dest_file = os.path.join(td, f)
        try:
            os.symlink(src_file, dest_file)
        except FileExistsError:
            pass
""")

    # Run the symlinking script hermetically passing the prefix
    res = repository_ctx.execute([
        "python3",
        str(py_script),
        str(src_dir),
        str(dest_dir),
        prefix,
    ])
    if res.return_code != 0:
        fail("Failed to recursively symlink third-party directory: " + res.stderr)

    # Clean up the temporary script
    repository_ctx.delete(py_script)

def _get_cipd_platform(repository_ctx):
    os_name = repository_ctx.os.name
    if os_name == "linux":
        os_str = "linux"
    elif os_name == "mac os x":
        os_str = "mac"
    elif os_name.startswith("windows"):
        os_str = "windows"
    else:
        fail("Unsupported OS for CIPD: " + os_name)

    # Detect architecture
    if os_str == "windows":
        arch = repository_ctx.os.environ.get("PROCESSOR_ARCHITECTURE", "AMD64").lower()
        if arch == "amd64":
            arch_str = "amd64"
        elif arch == "arm64":
            arch_str = "arm64"
        else:
            fail("Unsupported Windows arch for CIPD: " + arch)
    else:
        res = repository_ctx.execute(["uname", "-m"])
        if res.return_code != 0:
            fail("Failed to detect CPU architecture: " + res.stderr)
        arch = res.stdout.strip()
        if arch in ("x86_64", "amd64"):
            arch_str = "amd64"
        elif arch in ("aarch64", "arm64"):
            arch_str = "arm64"
        else:
            fail("Unsupported arch for CIPD: " + arch)

    return os_str + "-" + arch_str

def _fetch_remote(repository_ctx, repo_type, prefix):
    deps_file = repository_ctx.path(repository_ctx.attr.deps_file)
    parse_script = repository_ctx.path(repository_ctx.attr.parse_script)

    res = repository_ctx.execute([
        "python3",
        str(parse_script),
        str(deps_file),
        repo_type,
    ])
    if res.return_code != 0:
        fail("Failed to parse DEPS for {}: {}".format(repo_type, res.stderr))

    dep_info = json.decode(res.stdout.strip())
    dep_type = dep_info.get("dep_type")

    # Intercept public browser dependencies to bypass restricted Google CIPD credentials
    if repo_type in ["chrome", "chromedriver", "firefox"]:
        version = dep_info.get("version")
        if not version:
            fail("Could not resolve version for repository: " + repo_type)
        if version.startswith("version:"):
            version = version.split(":", 1)[1]

        os_name = repository_ctx.os.name
        arch = repository_ctx.os.arch

        if repo_type == "chrome":
            if os_name == "linux":
                platform = "linux64"
            elif os_name == "mac os x":
                platform = "mac-arm64" if arch in ["aarch64", "arm64"] else "mac-x64"
            elif os_name.startswith("windows"):
                platform = "win64"
            else:
                fail("Unsupported OS for chrome: " + os_name)
            url = "https://storage.googleapis.com/chrome-for-testing-public/{}/{}/chrome-{}.zip".format(version, platform, platform)
            dl_type = "zip"
            strip_prefix = "chrome-{}".format(platform)
        elif repo_type == "chromedriver":
            if os_name == "linux":
                platform = "linux64"
            elif os_name == "mac os x":
                platform = "mac-arm64" if arch in ["aarch64", "arm64"] else "mac-x64"
            elif os_name.startswith("windows"):
                platform = "win64"
            else:
                fail("Unsupported OS for chromedriver: " + os_name)
            url = "https://storage.googleapis.com/chrome-for-testing-public/{}/{}/chromedriver-{}.zip".format(version, platform, platform)
            dl_type = "zip"
            strip_prefix = "chromedriver-{}".format(platform)
        elif repo_type == "firefox":
            if os_name == "linux":
                url = "https://archive.mozilla.org/pub/firefox/releases/{}/linux-x86_64/en-US/firefox-{}.tar.xz".format(version, version)
                dl_type = "tar.xz"
                strip_prefix = "firefox"
            elif os_name == "mac os x":
                url = "https://archive.mozilla.org/pub/firefox/releases/{}/mac/en-US/Firefox%20{}.pkg".format(version, version)
                repository_ctx.delete("Firefox.app")
                repository_ctx.delete("firefox.pkg")
                repository_ctx.delete("tmp_pkg")
                repository_ctx.download(
                    url = url,
                    output = "firefox.pkg",
                )
                res = repository_ctx.execute(["pkgutil", "--expand-full", "firefox.pkg", "tmp_pkg"])
                print(res.stdout)  # buildifier: disable=print
                print(res.stderr)  # buildifier: disable=print
                if res.return_code != 0:
                    fail("Failed to expand Firefox pkg: " + res.stderr)
                res = repository_ctx.execute(["find", "tmp_pkg", "-name", "Firefox.app", "-type", "d", "-exec", "cp", "-R", "{}", ".", ";"])
                print(res.stdout)  # buildifier: disable=print
                print(res.stderr)  # buildifier: disable=print
                if res.return_code != 0:
                    fail("Failed to locate and copy Firefox.app from payload: " + res.stderr)
                if not repository_ctx.path("Firefox.app").exists:
                    fail("Firefox.app was not found in the expanded package payload")
                repository_ctx.file(
                    "firefox",
                    """#!/bin/bash
target="$0"
while [ -L "$target" ]; do
  dir="$(dirname "$target")"
  target="$(readlink "$target")"
  case "$target" in
    /*) ;;
    *) target="$dir/$target" ;;
  esac
done
script_dir="$(cd -P "$(dirname "$target")" && pwd)"
exec "$script_dir/Firefox.app/Contents/MacOS/firefox" "$@"
""",
                    executable = True,
                )
                repository_ctx.delete("firefox.pkg")
                repository_ctx.delete("tmp_pkg")
                return
            else:
                # Firefox download is only supported on Linux and macOS.
                # Return early on other platforms (e.g. Windows) to skip download and let the overlay BUILD file glob empty.
                return
        else:
            fail("Unreachable")

        output_dir = prefix if prefix else "."

        repository_ctx.download_and_extract(
            url = url,
            output = output_dir,
            type = dl_type,
            strip_prefix = strip_prefix,
        )
    elif dep_type == "git":
        url = dep_info.get("url")
        commit = dep_info.get("commit")

        if url.startswith("https://github.com") or url.startswith("http://github.com"):
            tarball_url = url + "/archive/" + commit + ".tar.gz"
        else:
            # Googlesource archive URL format
            tarball_url = url + "/+archive/" + commit + ".tar.gz"

        # Extract directly to the prefix directory if specified
        output_dir = prefix if prefix else "."

        repository_ctx.download_and_extract(
            url = tarball_url,
            output = output_dir,
            type = "tar.gz",
        )
    elif dep_type == "cipd":
        package = dep_info.get("package")
        version = dep_info.get("version")

        platform = _get_cipd_platform(repository_ctx)
        resolved_package = package.replace("${{platform}}", platform)

        url = "https://chrome-infra-packages.appspot.com/dl/" + resolved_package + "/+/" + version

        output_dir = prefix if prefix else "."

        repository_ctx.download_and_extract(
            url = url,
            output = output_dir,
            type = "zip",
        )
    else:
        fail("Unsupported dependency type: " + str(dep_type))

    # Clean up all extracted BUILD/WORKSPACE/MODULE.bazel files if requested to avoid package conflicts
    if repository_ctx.attr.clean_upstream_build_files:
        py_code = """
import os
for root, dirs, files in os.walk('.'):
    for f in files:
        if f in ('BUILD', 'BUILD.bazel', 'WORKSPACE', 'MODULE.bazel'):
            os.remove(os.path.join(root, f))
"""
        res = repository_ctx.execute(["python3", "-c", py_code])
        if res.return_code != 0:
            fail("Failed to clean up extracted build files: " + res.stderr)

def _overlay_repository_impl(repository_ctx):
    dest_dir = repository_ctx.path(".")

    # 1. Determine if we should use local path or fetch remote
    local_path = repository_ctx.path(str(repository_ctx.workspace_root) + "/" + repository_ctx.attr.path)
    use_local = local_path.exists and not repository_ctx.attr.force_remote

    if use_local:
        _symlink_local(repository_ctx, local_path, dest_dir, repository_ctx.attr.prefix)
    else:
        _fetch_remote(repository_ctx, repository_ctx.attr.repo_type, repository_ctx.attr.prefix)

    # Dynamic overlays and appends (Option 1 Custom Overlay System)
    if repository_ctx.attr.repo_type == "icu":
        # Resolve snapshot directory path from build_file label absolute path
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_snap_dir = root_snap.dirname

        # 1. Stage root BUILD.bazel by reading snap and dynamically replacing package paths
        root_content = repository_ctx.read(root_snap)

        # Redirect all main-workspace package references to local external repository targets
        root_content = root_content.replace("//third_party/icu/", "//")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")
        repository_ctx.file("BUILD.bazel", root_content)

        # 2. Apply custom sub-package exports_files append blocks dynamically
        for subpkg in ["common", "i18n", "stubdata"]:
            append_path = root_snap_dir.get_child("source").get_child(subpkg).get_child("BUILD.bazel.append")
            append_content = repository_ctx.read(append_path)

            if use_local:
                upstream_build = local_path.get_child("source").get_child(subpkg).get_child("BUILD.bazel")
            else:
                upstream_build = repository_ctx.path("source/{}/BUILD.bazel".format(subpkg))
            upstream_content = ""
            if upstream_build.exists:
                upstream_content = repository_ctx.read(upstream_build) + "\n"
            repository_ctx.file("source/{}/BUILD.bazel".format(subpkg), upstream_content + append_content)

        # 3. Stage flutter/BUILD.bazel overlay
        flutter_snap = root_snap_dir.get_child("flutter").get_child("BUILD.bazel.snap")
        repository_ctx.symlink(flutter_snap, "flutter/BUILD.bazel")

    elif repository_ctx.attr.repo_type == "zlib":
        # Stage root BUILD.bazel by reading snap and dynamically replacing package paths
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)
        root_content = root_content.replace("//third_party/zlib:", ":")
        root_content = root_content.replace("//third_party/zlib", ":zlib")
        root_content = root_content.replace("//build/", "@//build/")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")

        # Propagate include search paths to consumers and internal targets
        root_content = root_content.replace("name = \"zlib\",", "name = \"zlib\",\n    includes = [\".\", \"zlib\"],")
        root_content = root_content.replace("name = \"zlib_common_headers\",", "name = \"zlib_common_headers\",\n    includes = [\"zlib\"],")

        # Dynamically prefix all relative source/header paths inside the BUILD file with "zlib/"
        prefix_script = repository_ctx.path("prefix_build.py")
        temp_build = repository_ctx.path("temp_build.bazel")
        repository_ctx.file(temp_build, content = root_content)

        repository_ctx.file(prefix_script, content = """
import sys
import re

file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

# Surgical regex to identify relative source/header paths and prefix them with "zlib/"
modified = re.sub(r'"([^/@\\\\:-][^"]+\\.(c|h|S|cc))"', r'"zlib/\\1"', content)

with open(file_path, "w") as f:
    f.write(modified)
""")
        res = repository_ctx.execute(["python3", str(prefix_script), str(temp_build)])
        if res.return_code != 0:
            fail("Failed to prefix zlib BUILD file paths: " + res.stderr)

        root_content = repository_ctx.read(temp_build)
        repository_ctx.delete(prefix_script)
        repository_ctx.delete(temp_build)

        repository_ctx.file("BUILD.bazel", root_content)

    elif repository_ctx.attr.repo_type == "boringssl":
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)

        # Redirect package references internally
        root_content = root_content.replace("//third_party/boringssl:", ":")
        root_content = root_content.replace("//runtime/", "@//runtime/")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")

        # Replace hardcoded -I flags with Bazel includes
        root_content = root_content.replace('        "-Ithird_party/boringssl/src/include",', "")
        root_content = root_content.replace('    name = "boringssl",', '    name = "boringssl",\n    includes = ["src/include"],')
        root_content = root_content.replace('    name = "boringssl_asm",', '    name = "boringssl_asm",\n    includes = ["src/include"],')

        repository_ctx.file("BUILD.bazel", root_content)

    elif repository_ctx.attr.repo_type == "perfetto":
        # Symlink build flags from main workspace
        flags_file = repository_ctx.path(str(repository_ctx.workspace_root) + "/third_party/perfetto/perfetto_build_flags.h")
        repository_ctx.symlink(flags_file, "perfetto_build_flags.h")

        # Symlink checked-in protos directory from main workspace
        protos_dir = repository_ctx.path(str(repository_ctx.workspace_root) + "/third_party/perfetto/protos")
        repository_ctx.symlink(protos_dir, "protos")

        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")
        repository_ctx.file("BUILD.bazel", root_content)

    elif repository_ctx.attr.repo_type == "binaryen":
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        if hasattr(repository_ctx, "watch"):
            repository_ctx.watch(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)

        # Escape main workspace references to avoid them being hit by the local package redirection
        root_content = root_content.replace("@//third_party/binaryen:", "__MAIN_BINARYEN__")
        root_content = root_content.replace("//third_party/binaryen:", ":")
        root_content = root_content.replace("__MAIN_BINARYEN__", "@//third_party/binaryen:")
        root_content = root_content.replace("//runtime/", "@//runtime/")
        root_content = root_content.replace("//build/", "@//build/")
        root_content = root_content.replace("-Ithird_party/binaryen/src/", "-Iexternal/" + repository_ctx.name + "/src/")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")
        repository_ctx.file("BUILD.bazel", root_content)

    else:
        # General case (e.g. perfetto, prebuilt_dart_sdk)
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")
        repository_ctx.file("BUILD.bazel", root_content)

overlay_repository = repository_rule(
    implementation = _overlay_repository_impl,
    attrs = {
        "build_file": attr.label(mandatory = True, allow_single_file = True),
        "clean_upstream_build_files": attr.bool(default = False),
        "deps_file": attr.label(default = "@//:DEPS"),
        "force_remote": attr.bool(default = False),
        "parse_script": attr.label(default = "@//tools/bazel:parse_deps.py"),
        "path": attr.string(mandatory = True),
        "prefix": attr.string(default = ""),
        "repo_type": attr.string(mandatory = True),
    },
)

def _third_party_ext_impl(ctx):
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

    # 1. ICU Dynamic Overlay Repository
    overlay_repository(
        name = "icu",
        repo_type = "icu",
        path = "third_party/icu",
        build_file = "@//tools/bazel:third_party_overlays/icu/BUILD.bazel.snap",
    )

    # 2. Zlib Dynamic Overlay Repository
    overlay_repository(
        name = "zlib",
        repo_type = "zlib",
        path = "third_party/zlib",
        prefix = "zlib",
        build_file = "@//tools/bazel:third_party_overlays/zlib/BUILD.bazel.snap",
    )

    # 3. BoringSSL Dynamic Overlay Repository
    overlay_repository(
        name = "boringssl",
        repo_type = "boringssl",
        path = "third_party/boringssl/src",
        prefix = "src",
        build_file = "@//tools/bazel:third_party_overlays/boringssl/BUILD.bazel.snap",
        clean_upstream_build_files = True,
    )

    # 4. Perfetto Dynamic Overlay Repository
    overlay_repository(
        name = "perfetto",
        repo_type = "perfetto",
        path = "third_party/perfetto/src",
        prefix = "src",
        build_file = "@//tools/bazel:third_party_overlays/perfetto/BUILD.bazel.snap",
        clean_upstream_build_files = True,
    )

    # 5. Prebuilt Dart SDK Dynamic Overlay Repository
    overlay_repository(
        name = "prebuilt_dart_sdk",
        repo_type = "prebuilt_dart_sdk",
        path = "tools/sdks/dart-sdk",
        build_file = "@//tools/bazel:third_party_overlays/tools/sdks/dart-sdk/BUILD.bazel.snap",
    )

    # 6. Chrome Browser Dynamic Overlay Repository
    overlay_repository(
        name = "chrome",
        repo_type = "chrome",
        path = "third_party/browsers/chrome",
        build_file = "@//tools/bazel:third_party_overlays/chrome/BUILD.bazel.snap",
    )

    # 7. ChromeDriver Dynamic Overlay Repository
    overlay_repository(
        name = "chromedriver",
        repo_type = "chromedriver",
        path = "third_party/webdriver/chrome",
        build_file = "@//tools/bazel:third_party_overlays/chromedriver/BUILD.bazel.snap",
    )

    # 8. Firefox Browser Dynamic Overlay Repository
    overlay_repository(
        name = "firefox",
        repo_type = "firefox",
        path = "third_party/browsers/firefox",
        build_file = "@//tools/bazel:third_party_overlays/firefox/BUILD.bazel.snap",
    )

    # 9. Binaryen Dynamic Overlay Repository
    overlay_repository(
        name = "binaryen",
        repo_type = "binaryen",
        path = "third_party/binaryen/src",
        prefix = "src",
        build_file = "@//tools/bazel:third_party_overlays/binaryen/BUILD.bazel.snap",
        clean_upstream_build_files = True,
    )

    # 10. DevTools Prebuilt Overlay Repository
    overlay_repository(
        name = "devtools",
        repo_type = "devtools",
        path = "third_party/devtools",
        build_file = "@//tools/bazel:third_party_overlays/devtools/BUILD.bazel.snap",
        force_remote = True,
    )

    # 11. co19 Conformance Suite Dynamic Overlay Repository
    overlay_repository(
        name = "dart_co19_tests",
        repo_type = "co19",
        path = "tests/co19/src",
        build_file = "@//tools/bazel:third_party_overlays/co19/BUILD.bazel.snap",
        force_remote = True,
        clean_upstream_build_files = True,
    )
    return ctx.extension_metadata(reproducible = True)

third_party_extension = module_extension(implementation = _third_party_ext_impl)
