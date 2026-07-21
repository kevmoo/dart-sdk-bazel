"""Repository rule and Bzlmod extension for locating and exposing the Xcode iOS SDKs.

Discovers the installed Apple iOS SDKs (iPhoneOS.sdk, iPhoneSimulator.sdk) and Xcode toolchain
so that Bazel sandbox actions have access to all Apple Clang compiler and sysroot files.
"""

_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

exports_files(glob(["**/*"], allow_empty = True))

filegroup(
    name = "all_files",
    srcs = glob(["**"], allow_empty = True),
)
"""

def _ios_sdk_repository_impl(repository_ctx):
    module_label = Label("@//:MODULE.bazel")
    module_path = repository_ctx.path(module_label)
    repository_ctx.watch(module_path)

    # 1. Discover iPhoneOS SDK path
    res = repository_ctx.execute(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])
    iphoneos_sdk_path = res.stdout.strip() if res.return_code == 0 else ""

    # 2. Discover iPhoneSimulator SDK path
    res_sim = repository_ctx.execute(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
    iphonesimulator_sdk_path = res_sim.stdout.strip() if res_sim.return_code == 0 else ""

    # 3. Discover Xcode developer directory
    res_xcode = repository_ctx.execute(["xcode-select", "-p"])
    xcode_path = res_xcode.stdout.strip() if res_xcode.return_code == 0 else ""

    sdk_found = False
    if iphoneos_sdk_path:
        sdk_dir = repository_ctx.path(iphoneos_sdk_path)
        if sdk_dir.exists:
            sdk_found = True
            repository_ctx.symlink(sdk_dir, "iphoneos_sdk")

    if iphonesimulator_sdk_path:
        sim_dir = repository_ctx.path(iphonesimulator_sdk_path)
        if sim_dir.exists:
            repository_ctx.symlink(sim_dir, "iphonesimulator_sdk")

    if xcode_path:
        toolchain_dir = repository_ctx.path(xcode_path + "/Toolchains/XcodeDefault.xctoolchain")
        if toolchain_dir.exists:
            repository_ctx.symlink(toolchain_dir, "xcode_toolchain")

    repository_ctx.file("paths.bzl", "SDK_FOUND = %s\nIPHONEOS_SDK = %r\nIPHONESIMULATOR_SDK = %r\n" % (
        sdk_found,
        iphoneos_sdk_path,
        iphonesimulator_sdk_path,
    ))
    repository_ctx.file("BUILD.bazel", _BUILD_FILE)

ios_sdk_repository = repository_rule(
    implementation = _ios_sdk_repository_impl,
    environ = ["DEVELOPER_DIR", "SDKROOT"],
)

def _dart_ios_sdk_impl(_module_ctx):
    ios_sdk_repository(name = "dart_ios_sdk")

dart_ios_sdk = module_extension(
    implementation = _dart_ios_sdk_impl,
)
