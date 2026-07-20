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

    sysroot_attr = getattr(ctx.attr, "_sysroot", None)
    sysroot_repo = getattr(sysroot_attr.label, "repo_name", sysroot_attr.label.workspace_name) if sysroot_attr else "dart_android_ndk"
    ndk_sysroot = "external/" + sysroot_repo + "/toolchains/llvm/prebuilt/" + host_tag + "/sysroot"

    tool_paths = [
        tool_path(name = "gcc", path = "bazel_android_clang_wrapper.py"),
        tool_path(name = "ld", path = "bazel_android_clang_wrapper.py"),
        tool_path(name = "ar", path = "bazel_android_ar_wrapper.py"),
        tool_path(name = "cpp", path = "bazel_android_clang_wrapper.py"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = "bazel_android_nm_wrapper.py"),
        tool_path(name = "objdump", path = "bazel_android_objdump_wrapper.py"),
        tool_path(name = "strip", path = "bazel_android_strip_wrapper.py"),
        tool_path(name = "dwp", path = "/bin/false"),
        tool_path(name = "llvm-cov", path = "/bin/false"),
        tool_path(name = "llvm-profdata", path = "/bin/false"),
    ]

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [
                        ACTION_NAMES.c_compile,
                        ACTION_NAMES.cpp_compile,
                        ACTION_NAMES.cpp_header_parsing,
                        ACTION_NAMES.cpp_module_compile,
                        ACTION_NAMES.assemble,
                        ACTION_NAMES.preprocess_assemble,
                    ],
                    flag_groups = [
                        flag_group(
                            flags = [
                                "--target=" + triple,
                                "--sysroot=" + ndk_sysroot,
                                "-ffunction-sections",
                                "-fdata-sections",
                                "-no-canonical-prefixes",
                                "-fPIC",
                            ],
                        ),
                    ],
                ),
            ],
        ),
        feature(
            name = "default_link_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = [
                        ACTION_NAMES.cpp_link_executable,
                        ACTION_NAMES.cpp_link_dynamic_library,
                        ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                    ],
                    flag_groups = [
                        flag_group(
                            flags = [
                                "--target=" + triple,
                                "--sysroot=" + ndk_sysroot,
                                "-Wl,--gc-sections",
                                "-Wl,-z,nocopyreloc",
                                "-Wl,--no-undefined",
                                "-pie",
                                "-static-libstdc++",
                            ],
                        ),
                    ],
                ),
            ],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        cxx_builtin_include_directories = [
            ndk_sysroot,
            "external/" + sysroot_repo,
            "build/toolchain/android/include",
        ],
        toolchain_identifier = "android_clang_" + cpu + "_" + host_os,
        host_system_name = host_os + "-x86_64",
        target_system_name = triple,
        target_cpu = cpu,
        target_libc = "bionic",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        builtin_sysroot = ndk_sysroot,
    )

android_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True),
        "host_os": attr.string(default = "linux"),
        "target_triple": attr.string(mandatory = True),
        "_sysroot": attr.label(default = Label("@dart_android_ndk//:all_files")),
    },
)
