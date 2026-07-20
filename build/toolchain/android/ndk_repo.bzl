"""Repository rule and Bzlmod extension for locating and exposing the Android NDK.

Recursively mirrors/symlinks the Android NDK into the external repository
so that Bazel sandbox actions have access to all Clang toolchain and sysroot files.
"""

_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

exports_files(glob(["**/*"], allow_empty = True))

filegroup(
    name = "all_files",
    srcs = glob(["**"], allow_empty = True),
)
"""

def _android_ndk_repository_impl(repository_ctx):
    module_label = Label("@//:MODULE.bazel")
    module_path = repository_ctx.path(module_label)
    repository_ctx.watch(module_path)
    workspace_root = module_path.dirname
    in_tree_ndk = workspace_root.get_child("third_party").get_child("android_tools").get_child("ndk")

    ndk_path = None
    if in_tree_ndk.exists:
        ndk_path = str(in_tree_ndk)
    elif "ANDROID_NDK_HOME" in repository_ctx.os.environ:
        ndk_path = repository_ctx.os.environ["ANDROID_NDK_HOME"]
    elif "ANDROID_NDK_ROOT" in repository_ctx.os.environ:
        ndk_path = repository_ctx.os.environ["ANDROID_NDK_ROOT"]

    if ndk_path:
        ndk_dir = repository_ctx.path(ndk_path)
        if ndk_dir.exists:
            for entry in ndk_dir.readdir():
                if entry.basename in ["BUILD", "BUILD.bazel", "paths.bzl"]:
                    continue
                repository_ctx.symlink(entry, entry.basename)

            repository_ctx.file("paths.bzl", "NDK_FOUND = True\n")
            repository_ctx.file("BUILD.bazel", _BUILD_FILE)
            return

    repository_ctx.file("paths.bzl", "NDK_FOUND = False\n")
    repository_ctx.file("BUILD.bazel", _BUILD_FILE)

android_ndk_repository = repository_rule(
    implementation = _android_ndk_repository_impl,
    environ = ["ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"],
)

def _dart_android_ndk_impl(_module_ctx):
    android_ndk_repository(name = "dart_android_ndk")

dart_android_ndk = module_extension(
    implementation = _dart_android_ndk_impl,
)
