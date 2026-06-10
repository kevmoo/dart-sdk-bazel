# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Rules for compiling packages and the SDK with DDC (Dart Development Compiler) under Bazel."""

EXPECT_SOURCES = [
    "//:pkg/expect/lib/async_helper.dart",
    "//:pkg/expect/lib/config.dart",
    "//:pkg/expect/lib/expect.dart",
    "//:pkg/expect/lib/legacy/async_minitest.dart",
    "//:pkg/expect/lib/legacy/minitest.dart",
    "//:pkg/expect/lib/minitest.dart",
    "//:pkg/expect/lib/static_type_helper.dart",
    "//:pkg/expect/lib/variations.dart",
]

JS_SOURCES = [
    "//:pkg/js/lib/js.dart",
    "//:pkg/js/lib/js_util.dart",
]

META_SOURCES = [
    "//:pkg/meta/lib/dart2js.dart",
    "//:pkg/meta/lib/meta.dart",
    "//:pkg/meta/lib/meta_meta.dart",
]

_SOURCES_MAP = {
    "expect": EXPECT_SOURCES,
    "js": JS_SOURCES,
    "meta": META_SOURCES,
}

def package_kernel_outline(name, package, extra_libraries = []):
    """Compiles a package to an outline .dill file with the ddc target option.

    Args:
      name: The name of the genrule target.
      package: The package name to compile (e.g., "expect", "js", "meta").
      extra_libraries: Optional list of additional library entrypoints in the package.
    """
    srcs = _SOURCES_MAP[package]
    output = name + ".dill"

    native.genrule(
        name = name,
        srcs = srcs + [
            "//utils/bazel:kernel_worker",
            "//utils/ddc:ddc_outline.dill",
            "//:package_config_json",
        ],
        outs = [output],
        cmd = "$(location //runtime/bin:dartvm) " +
              "$(location //utils/bazel:kernel_worker) " +
              "--packages-file $(location //:package_config_json) " +
              "--summary-only " +
              "--target ddc " +
              "--dart-sdk-summary $(location //utils/ddc:ddc_outline.dill) " +
              "--source package:%s/%s.dart " % (package, package) +
              " ".join(["--source package:%s/%s.dart" % (package, lib) for lib in extra_libraries]) +
              " --output $@",
        tools = ["//runtime/bin:dartvm"],
    )

def ddc_compile(name, package, canary, modules, extra_libraries = []):
    """Compiles a package to JavaScript using dartdevc.

    Args:
      name: The name of the genrule target.
      package: The package name to compile (e.g., "expect", "js", "meta").
      canary: Whether to compile with canary features and output to canary directory.
      modules: List of module formats to output (e.g., "amd", "common", "es6").
      extra_libraries: Optional list of additional library entrypoints in the package.
    """
    srcs = _SOURCES_MAP[package]

    js_dir = "canary/pkg" if canary else "stable/pkg"
    outputs = []
    for module in modules:
        outputs.append("%s/%s/%s.js" % (js_dir, module, package))
        outputs.append("%s/%s/%s.js.map" % (js_dir, module, package))

    cmd = "$(location //runtime/bin:dartvm) $(location //utils/ddc:dartdevc) "

    args = []
    for module in modules:
        out_js = "$(RULEDIR)/%s/%s/%s.js" % (js_dir, module, package)
        args.append("--modules=%s" % module)
        args.append("-o %s" % out_js)

    cmd += " ".join(args)
    cmd += " --no-summarize"
    cmd += " --dart-sdk-summary $(location //utils/ddc:ddc_outline.dill)"
    cmd += " --multi-root-output-path=$(RULEDIR)"
    if canary:
        cmd += " --canary"

    cmd += " package:%s/%s.dart" % (package, package)
    for lib in extra_libraries:
        cmd += " package:%s/%s.dart" % (package, lib)

    native.genrule(
        name = name,
        srcs = srcs + [
            "//utils/ddc:dartdevc",
            "//utils/ddc:ddc_outline.dill",
            "//:package_config_json",
        ],
        outs = outputs,
        cmd = cmd + " --packages=$(location //:package_config_json)",
        tools = ["//runtime/bin:dartvm"],
    )

def ddc_compile_sdk(name, canary, modules):
    """Compiles the DDC SDK JavaScript modules from the platform .dill file.

    Args:
      name: The name of the genrule target.
      canary: Whether to compile with canary features and output to canary directory.
      modules: List of module formats to output (e.g., "amd", "common", "es6").
    """
    js_dir = "canary/sdk" if canary else "stable/sdk"
    outputs = []
    for module in modules:
        outputs.append("%s/%s/dart_sdk.js" % (js_dir, module))
        outputs.append("%s/%s/dart_sdk.js.map" % (js_dir, module))

    cmd = "$(location //runtime/bin:dartvm) $(location //utils/ddc:dartdevc) "

    args = []
    for module in modules:
        out_js = "$(RULEDIR)/%s/%s/dart_sdk.js" % (js_dir, module)
        args.append("--modules=%s" % module)
        args.append("-o %s" % out_js)

    cmd += " ".join(args)
    cmd += " --multi-root-scheme org-dartlang-sdk"
    cmd += " --multi-root-output-path=$(RULEDIR)/../../../dart-sdk"
    if canary:
        cmd += " --canary"

    cmd += " $(location //utils/ddc:ddc_platform.dill)"

    native.genrule(
        name = name,
        srcs = [
            "//utils/ddc:dartdevc",
            "//utils/ddc:ddc_platform.dill",
        ],
        outs = outputs,
        cmd = cmd,
        tools = ["//runtime/bin:dartvm"],
    )

# --- Parallel AOT DDC Compilation Rules ---
# Inspired by upstream CL: https://dart-review.googlesource.com/c/sdk/+/510143

def ddc_compile_aot(name, package, canary, modules, extra_libraries = []):
    """Compiles a package to JavaScript using the AOT-compiled dartdevc."""
    srcs = _SOURCES_MAP[package]

    js_dir = "canary_aot/pkg" if canary else "stable_aot/pkg"
    outputs = []
    for module in modules:
        outputs.append("%s/%s/%s.js" % (js_dir, module, package))
        outputs.append("%s/%s/%s.js.map" % (js_dir, module, package))

    cmd = "$(location @prebuilt_dart_sdk//:bin/dartaotruntime) $(location //utils/ddc:dartdevc_aot) "

    args = []
    for module in modules:
        out_js = "$(RULEDIR)/%s/%s/%s.js" % (js_dir, module, package)
        args.append("--modules=%s" % module)
        args.append("-o %s" % out_js)

    cmd += " ".join(args)
    cmd += " --no-summarize"
    cmd += " --dart-sdk-summary $(location //utils/ddc:ddc_outline.dill)"
    cmd += " --multi-root-output-path=$(RULEDIR)"
    if canary:
        cmd += " --canary"

    cmd += " package:%s/%s.dart" % (package, package)
    for lib in extra_libraries:
        cmd += " package:%s/%s.dart" % (package, lib)

    native.genrule(
        name = name,
        srcs = srcs + [
            "//utils/ddc:dartdevc_aot",
            "//utils/ddc:ddc_outline.dill",
            "//:package_config_json",
            "@prebuilt_dart_sdk//:bin/dartaotruntime",
        ],
        outs = outputs,
        cmd = cmd + " --packages=$(location //:package_config_json)",
        tools = ["@prebuilt_dart_sdk//:bin/dartaotruntime"],
    )

def ddc_compile_sdk_aot(name, canary, modules):
    """Compiles the DDC SDK JavaScript modules from the platform .dill file using AOT dartdevc."""
    js_dir = "canary_aot/sdk" if canary else "stable_aot/sdk"
    outputs = []
    for module in modules:
        outputs.append("%s/%s/dart_sdk.js" % (js_dir, module))
        outputs.append("%s/%s/dart_sdk.js.map" % (js_dir, module))

    cmd = "$(location @prebuilt_dart_sdk//:bin/dartaotruntime) $(location //utils/ddc:dartdevc_aot) "

    args = []
    for module in modules:
        out_js = "$(RULEDIR)/%s/%s/dart_sdk.js" % (js_dir, module)
        args.append("--modules=%s" % module)
        args.append("-o %s" % out_js)

    cmd += " ".join(args)
    cmd += " --multi-root-scheme org-dartlang-sdk"
    cmd += " --multi-root-output-path=$(RULEDIR)/../../../dart-sdk"
    if canary:
        cmd += " --canary"

    cmd += " $(location //utils/ddc:ddc_platform.dill)"

    native.genrule(
        name = name,
        srcs = [
            "//utils/ddc:dartdevc_aot",
            "//utils/ddc:ddc_platform.dill",
            "@prebuilt_dart_sdk//:bin/dartaotruntime",
        ],
        outs = outputs,
        cmd = cmd,
        tools = ["@prebuilt_dart_sdk//:bin/dartaotruntime"],
    )
