"""Custom rules wrapper to dynamically inject platform and architecture configuration flags.

Intercepts compiles and automatically injects target OS and target CPU defines and cflags,
enabling clean cross-compilation of targets across x86_64 and ARM64 (Apple Silicon/M-series).
"""

load("@rules_cc//cc:defs.bzl", _cc_binary = "cc_binary", _cc_library = "cc_library", _cc_shared_library = "cc_shared_library", _cc_test = "cc_test")

cc_shared_library = _cc_shared_library

def _inject_local_defines(local_defines, defines):
    custom_local_defines = local_defines + select({
        "@platforms//os:linux": ["DART_TARGET_OS_LINUX"],
        "@platforms//os:macos": ["DART_TARGET_OS_MACOS", "_DARWIN_C_SOURCE"],
        "//conditions:default": [],
    })

    has_target_arch = False
    if type(defines) == "list":
        for d in defines:
            if type(d) == "string" and d.strip("\"'").startswith("TARGET_ARCH_"):
                has_target_arch = True
    if type(local_defines) == "list":
        for d in local_defines:
            if type(d) == "string" and d.strip("\"'").startswith("TARGET_ARCH_"):
                has_target_arch = True

    if not has_target_arch:
        custom_local_defines = custom_local_defines + select({
            "@//build/config:target_arch_arm64": ["TARGET_ARCH_ARM64"],
            "@//build/config:target_arch_default_arm64": ["TARGET_ARCH_ARM64"],
            "@//build/config:target_arch_default_x64": ["TARGET_ARCH_X64"],
            "@//build/config:target_arch_simarm": ["TARGET_ARCH_ARM"],
            "@//build/config:target_arch_simarm64": ["TARGET_ARCH_ARM64"],
            "@//build/config:target_arch_simriscv32": ["TARGET_ARCH_RISCV32"],
            "@//build/config:target_arch_simriscv64": ["TARGET_ARCH_RISCV64"],
            "@//build/config:target_arch_x64": ["TARGET_ARCH_X64"],
            "//conditions:default": [],
        })
    return custom_local_defines

def _inject_copts(copts):
    return copts + [
        "-Wno-builtin-macro-redefined",
        "-D__DATE__=\"\"",
        "-D__TIME__=\"\"",
    ] + select({
        "@platforms//os:macos": [
            "-mmacosx-version-min=14.0",
        ],
        "//conditions:default": [],
    }) + select({
        "@//build/config:linux_x64": [
            "-m64",
            "-march=x86-64",
            "-msse2",
            "--target=x86_64-linux-gnu",
        ],
        "//conditions:default": [],
    })

def cc_library(name, defines = [], local_defines = [], copts = [], linkopts = [], **kwargs):
    """Wrapper for cc_library that injects platform and architecture defines/copts."""
    _cc_library(
        name = name,
        defines = defines,
        local_defines = _inject_local_defines(local_defines, defines),
        copts = _inject_copts(copts),
        linkopts = linkopts,
        **kwargs
    )

def cc_binary(name, defines = [], local_defines = [], copts = [], linkopts = [], **kwargs):
    """Wrapper for cc_binary that injects platform and architecture defines/copts."""
    _cc_binary(
        name = name,
        defines = defines,
        local_defines = _inject_local_defines(local_defines, defines),
        copts = _inject_copts(copts),
        linkopts = linkopts + select({
            "@platforms//os:macos": [
                "-mmacosx-version-min=14.0",
            ],
            "//conditions:default": [],
        }),
        **kwargs
    )

def cc_test(name, defines = [], local_defines = [], copts = [], linkopts = [], **kwargs):
    """Wrapper for cc_test that injects platform and architecture defines/copts."""
    _cc_test(
        name = name,
        defines = defines,
        local_defines = _inject_local_defines(local_defines, defines),
        copts = _inject_copts(copts),
        linkopts = linkopts + select({
            "@platforms//os:macos": [
                "-mmacosx-version-min=14.0",
            ],
            "//conditions:default": [],
        }),
        **kwargs
    )
