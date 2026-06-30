"""Exposes the in-tree clang at buildtools/linux-x64/clang as an external repo.

Why: tool_paths in cc_toolchain_config can't contain `..` segments (Bazel
normalizes them and rejects un-normalized strings). And glob() can't escape
its package. Wrapping the clang dir in an external repo lets the cc_toolchain
reference `external/<canonical>/bin/clang` via forward-only paths.

The repository_rule symlinks the in-tree clang dir into the repo overlay and
generates a BUILD.bazel exposing the binaries as a filegroup.
"""

_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["bin/*", "lib/**", "include/**"], allow_empty = True),
)
"""

def _dart_linux_clang_impl(repo_ctx):
    # repo_ctx.workspace_root is the main repo root in Bazel 7+.
    src = repo_ctx.workspace_root.get_child("buildtools").get_child(
        "linux-x64",
    ).get_child("clang")
    use_local = src.exists

    if use_local:
        repo_ctx.watch_tree(src)
        for sub in ["bin", "lib", "include"]:
            child = src.get_child(sub)
            if child.exists:
                repo_ctx.symlink(child, sub)

        CLANG_BIN_VAL = "external/{}/bin".format(repo_ctx.name)

        # Use relative paths under external repository to ensure sandbox safety
        CLANG_ROOT_REAL_VAL = "external/{}".format(repo_ctx.name)
    else:
        # Fetch dynamically!
        deps_file = repo_ctx.path(Label("@//:DEPS"))
        parse_script = repo_ctx.path(Label("@//tools/bazel:parse_deps.py"))

        res = repo_ctx.execute([
            "python3",
            str(parse_script),
            str(deps_file),
            "clang",
        ])
        if res.return_code != 0:
            fail("Failed to parse DEPS for clang: " + res.stderr)

        dep_info = json.decode(res.stdout.strip())
        package = dep_info["package"]
        version = dep_info["version"]

        url = "https://chrome-infra-packages.appspot.com/dl/" + package + "/+/" + version

        # Extract directly to the root of the external repository
        repo_ctx.download_and_extract(
            url = url,
            output = ".",
            type = "zip",
        )
        CLANG_BIN_VAL = "external/{}/bin".format(repo_ctx.name)

        # Use relative paths under external repository to ensure sandbox safety
        CLANG_ROOT_REAL_VAL = "external/{}".format(repo_ctx.name)

    repo_ctx.file("BUILD.bazel", _BUILD_FILE)
    repo_ctx.file(
        "paths.bzl",
        "CLANG_BIN = \"{}\"\nCLANG_ROOT_REAL = \"{}\"\n".format(CLANG_BIN_VAL, CLANG_ROOT_REAL_VAL),
    )

_SYSROOT_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["**"], allow_empty = True),
)
"""

def _dart_linux_sysroot_impl(repo_ctx):
    src = repo_ctx.workspace_root.get_child("buildtools").get_child("sysroot").get_child("linux")
    use_local = src.exists

    if use_local:
        repo_ctx.watch_tree(src)
        py_script = repo_ctx.path("symlink_sysroot.py")
        repo_ctx.file(py_script, content = """
import os
import sys

src = sys.argv[1]
dest = sys.argv[2]

for root, dirs, files in os.walk(src, followlinks=True):
    rel = os.path.relpath(root, src)
    if rel == ".":
        td = dest
    else:
        td = os.path.join(dest, rel)
    os.makedirs(td, exist_ok=True)
    for f in files:
        src_file = os.path.join(root, f)
        dest_file = os.path.join(td, f)
        try:
            os.symlink(src_file, dest_file)
        except FileExistsError:
            pass
""")
        res = repo_ctx.execute(["python3", str(py_script), str(src), "."])
        repo_ctx.delete(py_script)
        if res.return_code != 0:
            fail("Failed to symlink sysroot: " + res.stderr)

        # Use relative paths under external repository to ensure sandbox safety
        SYSROOT_ROOT_VAL = "external/{}".format(repo_ctx.name)
    else:
        # Fetch dynamically!
        deps_file = repo_ctx.path(Label("@//:DEPS"))
        parse_script = repo_ctx.path(Label("@//tools/bazel:parse_deps.py"))

        res = repo_ctx.execute([
            "python3",
            str(parse_script),
            str(deps_file),
            "sysroot/linux",
        ])
        if res.return_code != 0:
            fail("Failed to parse DEPS for sysroot/linux: " + res.stderr)

        dep_info = json.decode(res.stdout.strip())
        package = dep_info["package"]
        version = dep_info["version"]

        url = "https://chrome-infra-packages.appspot.com/dl/" + package + "/+/" + version

        repo_ctx.download_and_extract(
            url = url,
            output = ".",
            type = "zip",
        )

        # Use relative paths under external repository to ensure sandbox safety
        SYSROOT_ROOT_VAL = "external/{}".format(repo_ctx.name)

    repo_ctx.file("BUILD.bazel", _SYSROOT_BUILD_FILE)
    repo_ctx.file(
        "paths.bzl",
        "SYSROOT_ROOT = \"{}\"\n".format(SYSROOT_ROOT_VAL),
    )

_dart_linux_sysroot = repository_rule(
    implementation = _dart_linux_sysroot_impl,
)

_dart_linux_clang = repository_rule(
    implementation = _dart_linux_clang_impl,
)

def _ext_impl(_ctx):
    _dart_linux_clang(name = "dart_linux_x64_clang")
    _dart_linux_sysroot(name = "dart_linux_x64_sysroot")

dart_clang = module_extension(implementation = _ext_impl)
