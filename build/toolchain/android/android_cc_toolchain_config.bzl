"""Bazel C++ toolchain config for the Android NDK LLVM Clang toolchain.

Configures compiler and linker flags for Android ARM64, x86_64, ARMv7, and RISC-V targets.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _impl(ctx):
    cpu = ctx.attr.cpu
    triple = ctx.attr.target_triple
    host_os = ctx.attr.host_os

    host_tag = "linux-x86_64"
    if host_os == "macos":
        host_tag = "darwin-x86_64"

    ndk_sysroot = "external/dart_android_ndk/toolchains/llvm/prebuilt/" + host_tag + "/sysroot"

    tool_paths = [
        tool_path(name = "gcc", path = "bazel_android_clang_wrapper.py"),
        tool_path(name = "ld", path = "bazel_android_clang_wrapper.py"),
        tool_path(name = "ar", path = "bazel_android_ar_wrapper.py"),
        tool_path(name = "cpp", path = "bazel_android_cpp_wrapper.py"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = "bazel_android_nm_wrapper.py"),
        tool_path(name = "objdump", path = "bazel_android_objdump_wrapper.py"),
        tool_path(name = "strip", path = "bazel_android_strip_wrapper.py"),
        tool_path(name = "dwp", path = "/bin/false"),
        tool_path(name = "llvm-cov", path = "/bin/false"),
        tool_path(name = "llvm-profdata", path = "/bin/false"),
    ]

    target_flags = [
        "--target=" + triple,
        "--sysroot=" + ndk_sysroot,
        "-D_FILE_OFFSET_BITS=64",
        "-D_LARGEFILE_SOURCE",
        "-D_LARGEFILE64_SOURCE",
        "-no-canonical-prefixes",
        "-fPIC",
        "-fPIE",
    ]

    cpp_flags = target_flags + [
        "-std=c++20",
    ]

    c_flags = target_flags + [
        "-std=c17",
    ]

    target_linkopts = [
        "--target=" + triple,
        "--sysroot=" + ndk_sysroot,
        "-pie",
        "-Wl,-z,max-page-size=65536",
        "-Wl,--exclude-libs=libc++_static.a",
        "-llog",
        "-landroid",
        "-ldl",
    ]

    features = [
        feature(
            name = "dart_android_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [
                        ACTION_NAMES.c_compile,
                    ],
                    flag_groups = [flag_group(flags = c_flags)],
                ),
                flag_set(
                    actions = [
                        ACTION_NAMES.cpp_compile,
                        ACTION_NAMES.cpp_header_parsing,
                        ACTION_NAMES.cpp_module_compile,
                        ACTION_NAMES.cpp_module_codegen,
                    ],
                    flag_groups = [flag_group(flags = cpp_flags)],
                ),
                flag_set(
                    actions = [
                        ACTION_NAMES.assemble,
                        ACTION_NAMES.preprocess_assemble,
                    ],
                    flag_groups = [flag_group(flags = target_flags)],
                ),
                flag_set(
                    actions = [
                        ACTION_NAMES.cpp_link_executable,
                        ACTION_NAMES.cpp_link_dynamic_library,
                        ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                    ],
                    flag_groups = [flag_group(flags = target_linkopts)],
                ),
            ],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "android_clang_" + cpu + "_" + host_os,
        host_system_name = host_tag,
        target_system_name = triple,
        target_cpu = cpu,
        target_libc = "bionic",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        builtin_sysroot = ndk_sysroot,
        features = features,
        cxx_builtin_include_directories = ["/"],
    )

android_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True),
        "target_triple": attr.string(mandatory = True),
        "host_os": attr.string(default = "linux"),
    },
)
