"""Analysis-phase tests for custom Dart Starlark rules."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//tools/bazel/dart:defs.bzl",
    "DartLibraryInfo",
    "copy_tree",
    "dart_compile_dill",
    "dart_library",
)

# 1. dart_library test
def _dart_library_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    asserts.true(env, DartLibraryInfo in target_under_test, "DartLibraryInfo provider missing")
    transitive_srcs = target_under_test[DartLibraryInfo].transitive_srcs.to_list()

    basenames = [f.basename for f in transitive_srcs]
    asserts.true(env, "a.dart" in basenames, "Expected a.dart in transitive sources")
    asserts.true(env, "b.dart" in basenames, "Expected b.dart in transitive sources")

    return analysistest.end(env)

dart_library_test = analysistest.make(_dart_library_test_impl)

# 2. copy_tree test
def _copy_tree_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    copy_tree_action = None
    for action in actions:
        if action.mnemonic == "CopyTree":
            copy_tree_action = action
            break

    asserts.true(env, copy_tree_action != None, "CopyTree action not registered")

    # Verify outputs
    outputs = copy_tree_action.outputs.to_list()
    asserts.equals(env, 1, len(outputs), "Expected 1 output from CopyTree")

    return analysistest.end(env)

copy_tree_test = analysistest.make(_copy_tree_test_impl)

# 3. dart_compile_dill test
def _dart_compile_dill_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    actions = analysistest.target_actions(env)
    compile_action = None
    for action in actions:
        if action.mnemonic == "DartCompileDill":
            compile_action = action
            break

    asserts.true(env, compile_action != None, "DartCompileDill action not registered")

    outputs = compile_action.outputs.to_list()
    asserts.equals(env, 1, len(outputs), "Expected 1 output file")
    asserts.equals(env, ctx.attr.expected_out_name, outputs[0].basename, "Unexpected output filename")

    return analysistest.end(env)

dart_compile_dill_test = analysistest.make(
    _dart_compile_dill_test_impl,
    attrs = {
        "expected_out_name": attr.string(mandatory = True),
    },
)

# Macro to instantiate the tests
def dart_rules_test_suite(name):
    # Setup dummy targets for dart_library test
    # (The actual files are created via write_file in the BUILD file)
    dart_library(
        name = "lib_a",
        srcs = ["a.dart"],
        tags = ["manual"],
    )

    dart_library(
        name = "lib_b",
        srcs = ["b.dart"],
        deps = [":lib_a"],
        tags = ["manual"],
    )

    dart_library_test(
        name = "dart_library_dep_test",
        target_under_test = ":lib_b",
    )

    # Setup dummy targets for copy_tree test
    copy_tree(
        name = "dummy_copy_tree",
        srcs = ["a.dart"],
        src_dir = "tools/bazel/dart/tests",
        out_dir = "dummy_out",
        tags = ["manual"],
    )

    copy_tree_test(
        name = "copy_tree_action_test",
        target_under_test = ":dummy_copy_tree",
    )

    # Setup dummy targets for dart_compile_dill test
    dart_compile_dill(
        name = "dummy_compile_dill",
        main = "a.dart",
        sources = ":lib_b",
        gen_kernel_dill = "dummy.dill",
        platform_dill = "dummy.dill",
        package_config = "dummy_package_config.json",
        out = "output.dill",
        tags = ["manual"],
    )

    dart_compile_dill_test(
        name = "dart_compile_dill_action_test",
        target_under_test = ":dummy_compile_dill",
        expected_out_name = "output.dill",
    )

    # Test suite
    native.test_suite(
        name = name,
        tests = [
            ":dart_library_dep_test",
            ":copy_tree_action_test",
            ":dart_compile_dill_action_test",
        ],
    )
