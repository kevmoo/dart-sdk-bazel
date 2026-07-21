"""Bazel C++ toolchain config for Apple iOS Clang.

Configures compiler and linker flags for iOS ARM64 (device & simulator) and x86_64 targets.
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
    is_simulator = ctx.attr.is_simulator

    sysroot_attr = getattr(ctx.attr, "_sysroot", None)
    sysroot_repo = getattr(sysroot_attr.label, "repo_name", sysroot_attr.label.workspace_name) if sysroot_attr else "dart_ios_sdk"
    sdk_sub = "iphonesimulator_sdk" if is_simulator else "iphoneos_sdk"
    ios_sysroot = "external/" + sysroot_repo + "/" + sdk_sub

    min_os_flag = "-mios-simulator-version-min=15.0" if is_simulator else "-miphoneos-version-min=15.0"

    tool_paths = [
        tool_path(name = "gcc", path = "bazel_ios_clang_wrapper.py"),
        tool_path(name = "ld", path = "bazel_ios_clang_wrapper.py"),
        tool_path(name = "ar", path = "bazel_ios_ar_wrapper.py"),
        tool_path(name = "cpp", path = "bazel_ios_clang_wrapper.py"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = "bazel_ios_nm_wrapper.py"),
        tool_path(name = "objdump", path = "bazel_ios_objdump_wrapper.py"),
        tool_path(name = "strip", path = "bazel_ios_strip_wrapper.py"),
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
                                "-target",
                                triple,
                                "-isysroot",
                                ios_sysroot,
                                min_os_flag,
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
                                "-target",
                                triple,
                                "-isysroot",
                                ios_sysroot,
                                min_os_flag,
                                "-Wl,-dead_strip",
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
            "/",
        ],
        toolchain_identifier = "ios_clang_" + cpu + "_macos",
        host_system_name = "darwin-x86_64",
        target_system_name = triple,
        target_cpu = cpu,
        target_libc = "darwin",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        builtin_sysroot = ios_sysroot,
    )

ios_cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True),
        "is_simulator": attr.bool(default = False),
        "target_triple": attr.string(mandatory = True),
        "_sysroot": attr.label(default = Label("@dart_ios_sdk//:all_files")),
    },
)
