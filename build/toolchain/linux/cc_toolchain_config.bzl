"""Bazel C++ toolchain config for the in-tree clang at buildtools/linux-x64.

Mirrors the GN `clang_x64` suite in build/toolchain/linux/BUILD.gn. Per-target
compile / link flags are NOT defined here — they ride in via cc_library.copts
produced by the gn-desc-driven translator (M2/M3). M1 scope is just tool paths
plus Bazel's legacy feature set, which auto-supplies depfile + standard
compile/link flag plumbing.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)
load("@dart_linux_x64_clang//:paths.bzl", "CLANG_ROOT_REAL")

# SYSROOT_ROOT loaded dynamically below
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

# Clang bin is resolved via wrappers

def _impl(ctx):
    cpu = ctx.attr.cpu
    triple = ctx.attr.target_triple
    sysroot_repo_canonical = str(Label("@dart_linux_x64_sysroot//:dummy")).split("//")[0].lstrip("@")
    SYSROOT_ROOT = "external/" + sysroot_repo_canonical

    tool_paths = [
        # Use clang++ as the "gcc" driver so cc_binary links auto-pull
        # libc++/libm (libstdc++ implicit deps); clang++ still compiles
        # .c files as C based on extension.
        tool_path(name = "gcc", path = "bazel_clang_wrapper.sh"),
        tool_path(name = "ld", path = "bazel_clang_wrapper.sh"),
        tool_path(name = "ar", path = "bazel_ar_wrapper.sh"),
        tool_path(name = "cpp", path = "bazel_cpp_wrapper.py"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = "bazel_nm_wrapper.py"),
        tool_path(name = "objdump", path = "bazel_objdump_wrapper.py"),
        tool_path(name = "strip", path = "bazel_strip_wrapper.sh"),
        tool_path(name = "dwp", path = "/bin/false"),
        tool_path(name = "llvm-cov", path = "/bin/false"),
        tool_path(name = "llvm-profdata", path = "/bin/false"),
    ]

    # The "gcc" tool_path above is clang++. clang++ as the driver on a
    # .c file otherwise (a) errors with `-Werror,-Wdeprecated` ("treating
    # 'c' input as 'c++' when in C++ mode") and (b) applies C++ semantics
    # (e.g., rejects C-only `register`). Pass `-x c` for the C compile
    # action so the driver treats the input as C.
    force_c_language = feature(
        name = "dart_force_c_language",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.c_compile],
                flag_groups = [flag_group(flags = ["-x", "c"])],
            ),
        ],
    )

    pic_feature = feature(
        name = "pic",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                ],
                flag_groups = [flag_group(flags = ["-fPIC"])],
            ),
        ],
    )

    asan_feature = feature(
        name = "asan",
        enabled = False,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "address",
                            "-m" + "llvm",
                            "-asan-globals=" + "0",
                            "-fno-omit-frame-pointer",
                            "-DTARGET_USES_ADDRESS_SANITIZER",
                        ],
                    ),
                ],
            ),
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_link_executable,
                    ACTION_NAMES.cpp_link_dynamic_library,
                    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "address",
                        ],
                    ),
                ],
            ),
        ],
    )

    msan_feature = feature(
        name = "msan",
        enabled = False,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "memory",
                            "-m" + "llvm",
                            "-inline-instr-cost=" + "20",
                            "-m" + "llvm",
                            "-inline-memaccess-cost=" + "20",
                            "-DTARGET_USES_MEMORY_SANITIZER",
                        ],
                    ),
                ],
            ),
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_link_executable,
                    ACTION_NAMES.cpp_link_dynamic_library,
                    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "memory",
                        ],
                    ),
                ],
            ),
        ],
    )

    tsan_feature = feature(
        name = "tsan",
        enabled = False,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "thread",
                            "-DTARGET_USES_THREAD_SANITIZER",
                        ],
                    ),
                ],
            ),
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_link_executable,
                    ACTION_NAMES.cpp_link_dynamic_library,
                    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                ],
                flag_groups = [
                    flag_group(
                        flags = [
                            "-fsanitize=" + "thread",
                        ],
                    ),
                ],
            ),
        ],
    )

    # Target architecture specific flags (triple, ISA, sysroot)
    target_flags = [
        "--sysroot=" + SYSROOT_ROOT,
        "-D_FILE_OFFSET_BITS=64",
        "-D_LARGEFILE_SOURCE",
        "-D_LARGEFILE64_SOURCE",
        "-no-canonical-prefixes",
        "-ffile-prefix-map=__BAZEL_EXECROOT__=.",
        "-Wno-builtin-macro-redefined",
    ]
    target_linkopts = ["--sysroot=" + SYSROOT_ROOT]

    if cpu == "aarch64":
        target_flags.append("--target=" + triple)
        target_linkopts.extend([
            "--target=" + triple,
            "-Wl,--fix-cortex-a53-843419",
        ])
    else:
        target_flags.extend([
            "--target=" + triple,
            "-march=" + "x86-64",
            "-m" + "64",
            "-m" + "sse2",
        ])
        target_linkopts.extend([
            "--target=" + triple,
            "-m" + "64",
        ])

    target_arch_feature = feature(
        name = "dart_target_arch_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
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
    )

    # System include roots Bazel treats as toolchain-builtin (suppresses
    # the "absolute path inclusion(s) found" error from strict-includes).
    clang_repo_canonical = str(Label("@dart_linux_x64_clang//:dummy")).split("//")[0]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "clang_" + cpu,
        host_system_name = "x86_64-linux-gnu",
        target_system_name = triple,
        target_cpu = cpu,
        target_libc = "glibc",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        builtin_sysroot = SYSROOT_ROOT,
        features = [
            force_c_language,
            target_arch_feature,
            pic_feature,
            asan_feature,
            msan_feature,
            tsan_feature,
        ],
        cxx_builtin_include_directories = [
            CLANG_ROOT_REAL + "/include",
            CLANG_ROOT_REAL + "/lib/clang",
            "%package(" + clang_repo_canonical + "//)%/include",
            "%package(" + clang_repo_canonical + "//)%/lib/clang",
            "%sysroot%/usr/include",
            "%sysroot%/usr/include/aarch64-linux-gnu",
            "%sysroot%/usr/include/x86_64-linux-gnu",
        ],
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True),
        "target_triple": attr.string(mandatory = True),
    },
)
