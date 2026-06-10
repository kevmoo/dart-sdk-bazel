"""Minimal Dart-compilation rules for the Bazel migration (rules_dart Step 0).

Ports the GN `aot_snapshot` template (utils/aot_snapshot.gni) and the
`bootstrap_gen_kernel` prebuilt-dart action (utils/gen_kernel/BUILD.gn) as
genrule-based macros. Scope is deliberately minimal — this is the first proof
that a Bazel rule can produce a real Dart AOT snapshot. See
docs/todo_issues/rules_dart_scoping.md for the full plan and the open
deps-model / Bzlmod decisions this intentionally defers.

Deps model: OPAQUE. Every macro takes a `sources` label (a filegroup of the
whole Dart package closure) rather than a per-package dep graph. This mirrors
today's non-hermetic GN build and unblocks the first proof; the gazelle-style
pubspec->deps generator that recovers incrementality is a later step.

sdk_hash discipline: the prebuilt `dart` and the Bazel-built `gen_snapshot`
both bake sdk_hash=0000000000, so every snapshot here must compile with the
same hash or the VM rejects it at load. The default below matches.
"""

DartToolchainInfo = provider(
    doc = "Information about the Dart toolchain (compiler and SDK files).",
    fields = {
        "dart_executable": "File object representing the prebuilt dart compiler",
        "sdk_files": "Target representing the SDK standard library files",
        "sdk_hash": "String configuration for sdk_hash",
    },
)

def _dart_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        dartinfo = DartToolchainInfo(
            dart_executable = ctx.file.dart_executable,
            sdk_files = ctx.attr.sdk_files,
            sdk_hash = ctx.attr.sdk_hash,
        ),
    )
    return [toolchain_info]

dart_toolchain = rule(
    implementation = _dart_toolchain_impl,
    attrs = {
        "dart_executable": attr.label(mandatory = True, allow_single_file = True, executable = True, cfg = "exec"),
        "sdk_files": attr.label(mandatory = True),
        "sdk_hash": attr.string(default = "0000000000"),
    },
)

# rules_dart Step 3 (per-package deps): a real per-package dependency graph that
# feeds each tool its own closure. DartLibraryInfo carries the transitive
# closure of a package's .dart sources as a depset; DefaultInfo exposes it so a
# snapshot genrule can take a single dart_library as `sources` and materialize
# exactly that package's closure (not all ~197 packages). Edges come from each
# pubspec's `dependencies:` (a cycle-free safe superset of real imports — see
# docs/todo_issues/rules_dart_scoping.md §8). The graph is generated into
# packages.bzl by gen_packages.py.

DartLibraryInfo = provider(
    doc = "Transitive closure of a Dart package's library sources.",
    fields = {"transitive_srcs": "depset of .dart files in this package + its deps"},
)

def _dart_library_impl(ctx):
    transitive = depset(
        direct = ctx.files.srcs,
        transitive = [d[DartLibraryInfo].transitive_srcs for d in ctx.attr.deps],
    )
    return [
        DefaultInfo(files = transitive),
        DartLibraryInfo(transitive_srcs = transitive),
    ]

dart_library = rule(
    implementation = _dart_library_impl,
    doc = "A Dart package: its own lib sources plus its transitive dep closure.",
    # buildifier: disable=unsorted-dict-items
    attrs = {
        "srcs": attr.label_list(allow_files = [".dart"]),
        "deps": attr.label_list(providers = [DartLibraryInfo]),
    },
)

# rules_dart Step 5 (sdk/ assembly): the SDK platform libraries (dart:core et al.)
# staged into the final dart-sdk/lib/<name> layout. Ports the GN copy_tree
# template (build/dart/copy_tree.gni -> tools/copy_tree.py): each
# copy_${library}_library copies sdk/lib/<library> with the same exclude globs.
_SDK_LIB_EXCLUDE = "*.svn,doc,*.py,*.gypi,*.sh,.git*,*.gn,*.gni"

def _copy_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.out_dir)
    ctx.actions.run_shell(
        command = "python3 {tool} --from {src} --to {to} --exclude '{exclude}'".format(
            tool = ctx.file._tool.path,
            src = ctx.attr.src_dir,
            to = out.path,
            exclude = ctx.attr.exclude,
        ),
        inputs = ctx.files.srcs + [ctx.file._tool],
        outputs = [out],
        mnemonic = "CopyTree",
        progress_message = "Staging SDK tree %s" % ctx.attr.out_dir,
    )
    return [DefaultInfo(files = depset([out]))]

copy_tree = rule(
    implementation = _copy_tree_impl,
    doc = "Stage src_dir into an output tree, mirroring GN copy_tree " +
          "(tools/copy_tree.py): same shutil.copytree + ignore_patterns(exclude).",
    attrs = {
        "exclude": attr.string(
            default = "",
            doc = "GN-style comma-separated ignore_patterns globs.",
        ),
        "out_dir": attr.string(
            mandatory = True,
            doc = "Output tree path under the package's bin dir, e.g. lib/core.",
        ),
        "src_dir": attr.string(
            mandatory = True,
            doc = "Execroot-relative source directory, e.g. sdk/lib/core.",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Every file under src_dir (a glob); excluded files are " +
                  "harmless extra inputs, the action filters them out.",
        ),
        "_tool": attr.label(
            default = "//tools/bazel/dart:copytree.py",
            allow_single_file = True,
        ),
    },
)

def _is_excluded(f, exclude_list):
    for pattern in exclude_list:
        if pattern.startswith("*."):
            ext = pattern[2:]
            if f.extension == ext:
                return True
        elif pattern.endswith("*"):
            prefix = pattern[:-1]
            if f.basename.startswith(prefix):
                return True
        elif pattern in f.path.split("/"):
            return True
    return False

def _copy_internal_with_dills_impl(ctx):
    outputs = []
    inputs = []
    exclude_list = ctx.attr.exclude.split(",")

    for f in ctx.files.srcs:
        if _is_excluded(f, exclude_list):
            continue

        if not f.path.startswith(ctx.attr.src_dir + "/"):
            fail("Source file %s is not under src_dir %s" % (f.path, ctx.attr.src_dir))

        rel_path = f.path[len(ctx.attr.src_dir) + 1:]
        out_file_path = ctx.attr.out_dir + "/" + rel_path
        out_file = ctx.actions.declare_file(out_file_path)
        outputs.append(out_file)
        inputs.append(f)

    for f in ctx.files.additional_dills:
        out_file_path = ctx.attr.out_dir + "/" + f.basename
        out_file = ctx.actions.declare_file(out_file_path)
        outputs.append(out_file)
        inputs.append(f)

    cmds = []
    for src, dest in zip(inputs, outputs):
        cmds.append("mkdir -p {dir} && cp {src} {dest}".format(
            dir = dest.dirname,
            src = src.path,
            dest = dest.path,
        ))

    ctx.actions.run_shell(
        command = " && ".join(cmds),
        inputs = inputs,
        outputs = outputs,
        mnemonic = "CopyInternalWithDills",
        progress_message = "Staging SDK internal library with VM and web platform dills individually",
    )
    return [DefaultInfo(files = depset(outputs))]

copy_internal_with_dills = rule(
    implementation = _copy_internal_with_dills_impl,
    attrs = {
        "additional_dills": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "exclude": attr.string(
            default = "",
        ),
        "out_dir": attr.string(
            mandatory = True,
        ),
        "src_dir": attr.string(
            mandatory = True,
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "vm_platform": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "vm_platform_product": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_tool": attr.label(
            default = "//tools/bazel/dart:copytree.py",
            allow_single_file = True,
        ),
    },
)

def copy_sdk_library(name, lib, exclude = _SDK_LIB_EXCLUDE, **kwargs):
    """Stage sdk/lib/<lib> -> <bin>/dart-sdk/lib/<lib>, porting GN copy_${lib}_library.

    Rooted under the GN dart_sdk_output ("dart-sdk/") prefix so the assembled
    tree matches out/ReleaseX64/dart-sdk/ and single-file outputs (libraries.json,
    version) don't collide with the same-named //sdk source labels.
    """
    copy_tree(
        name = name,
        srcs = native.glob(["lib/%s/**" % lib], allow_empty = False),
        src_dir = native.package_name() + "/lib/" + lib,
        out_dir = "dart-sdk/lib/" + lib,
        exclude = exclude,
        **kwargs
    )

def dart_kernel_snapshot(name, main, sources, **kwargs):
    """Compile a Dart script to a *kernel* snapshot with the prebuilt SDK.

    Mirrors utils/gen_kernel/BUILD.gn:bootstrap_gen_kernel — i.e.
    `dart --snapshot-kind=kernel --snapshot=OUT <main>`. Used to (re)build
    bootstrap_gen_kernel.dill itself, avoiding the stale checked-in blob.
    """
    dart_kernel_snapshot_rule(
        name = name,
        main = main,
        sources = sources,
        out = name + ".dill",
        **kwargs
    )

def dart_compile_platform(
        name,
        sources,
        sdk_sources,
        libraries_spec = "org-dartlang-sdk:///sdk/lib/libraries.json",
        product = False,
        exclude_source = False,
        outline = None,
        platform_out = None,
        platform_args = None,
        single_root_base = None,
        deps_outline = None,
        **kwargs):
    """Compile a platform .dill + outline with the prebuilt SDK."""
    platform_out_file = platform_out or (name + ".dill")
    outline_out_file = outline or (name + "_outline.dill")

    dart_compile_platform_rule(
        name = name,
        sources = sources,
        sdk_sources = sdk_sources,
        libraries_spec = libraries_spec,
        product = product,
        exclude_source = exclude_source,
        platform_args = platform_args,
        single_root_base = single_root_base,
        deps_outline = deps_outline,
        platform_out = platform_out_file,
        outline_out = outline_out_file,
        **kwargs
    )

# buildifier: disable=function-docstring-args
def dart_aot_snapshot(
        name,
        main,
        sources,
        gen_kernel_dill,
        platform_dill,
        gen_snapshot,
        product = True,
        gen_kernel_args = None,
        gen_snapshot_args = None,
        out = None,
        **kwargs):
    """Build a Dart AOT (app-aot-elf) snapshot. Ports utils/aot_snapshot.gni."""
    dill_target = name + "_dill"
    dill_file = name + ".dart.dill"
    out_snapshot = out or (name + ".snapshot")

    dart_compile_dill(
        name = dill_target,
        main = main,
        sources = sources,
        gen_kernel_dill = gen_kernel_dill,
        platform_dill = platform_dill,
        product = product,
        mode_flags = ["--aot"],
        gen_kernel_args = gen_kernel_args or [],
        out = dill_file,
    )

    dart_aot_elf(
        name = name,
        dill = dill_target,
        gen_snapshot = gen_snapshot,
        gen_snapshot_args = gen_snapshot_args or [],
        out = out_snapshot,
        **kwargs
    )

# buildifier: disable=function-docstring-args
def dart_app_jit_snapshot(
        name,
        main,
        sources,
        training_args,
        gen_kernel_dill,
        platform_dill,
        dart_vm,
        product = False,
        gen_kernel_args = None,
        vm_args = None,
        training_srcs = None,
        out = None,
        link_platform = False,
        **kwargs):
    """Build a Dart app-jit snapshot via a training run. Ports utils/application_snapshot.gni."""
    dill_target = name + "_dill"
    dill_file = name + ".dart.dill"
    out_snapshot = out or (name + ".dart.snapshot")

    mode_flags = ["--no-aot", "--no-embed-sources"]
    if not link_platform:
        mode_flags.append("--no-link-platform")

    dart_compile_dill(
        name = dill_target,
        main = main,
        sources = sources,
        gen_kernel_dill = gen_kernel_dill,
        platform_dill = platform_dill,
        product = product,
        mode_flags = mode_flags,
        gen_kernel_args = gen_kernel_args or [],
        out = dill_file,
    )

    dart_app_jit_training(
        name = name,
        dill = dill_target,
        dart_vm = dart_vm,
        sources = sources,
        main = main,
        training_srcs = training_srcs or [],
        vm_args = vm_args or [],
        training_args = training_args,
        out = out_snapshot,
        **kwargs
    )

# Custom Starlark rules utilizing the Dart toolchain system

dart_compile_dill = rule(
    implementation = lambda ctx: _dart_compile_dill_impl(ctx),
    attrs = {
        "gen_kernel_args": attr.string_list(default = []),
        "gen_kernel_dill": attr.label(mandatory = True, allow_single_file = True),
        "main": attr.label(mandatory = True, allow_single_file = [".dart"]),
        "mode_flags": attr.string_list(default = []),
        "out": attr.output(mandatory = True),
        "package_config": attr.label(default = "//:package_config_json", allow_single_file = True),
        "platform_dill": attr.label(mandatory = True, allow_single_file = True),
        "product": attr.bool(default = False),
        "sources": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "_dartaotruntime": attr.label(default = Label("@prebuilt_dart_sdk//:bin/dartaotruntime"), executable = True, allow_single_file = True, cfg = "exec"),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

def _dart_compile_dill_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    out_file = ctx.outputs.out
    boot_file = ctx.file.gen_kernel_dill

    # Dynamically choose executor and inputs based on whether the bootstrap
    # compiler is a JIT (.dill) or an AOT (.snapshot) binary.
    if boot_file.extension == "dill":
        compiler_cmd = "{dart} -Dsdk_hash={hash} {boot}".format(
            dart = toolchain.dart_executable.path,
            hash = toolchain.sdk_hash,
            boot = boot_file.path,
        )
        extra_inputs = [toolchain.dart_executable]
    else:
        compiler_cmd = "{dartaotruntime} {boot}".format(
            dartaotruntime = ctx.executable._dartaotruntime.path,
            boot = boot_file.path,
        )
        extra_inputs = [ctx.executable._dartaotruntime]

    inputs = depset(
        direct = [
            ctx.file.main,
            ctx.file.gen_kernel_dill,
            ctx.file.platform_dill,
            ctx.file.package_config,
        ] + extra_inputs,
        transitive = [
            toolchain.sdk_files[DefaultInfo].files,
            ctx.attr.sources[DartLibraryInfo].transitive_srcs,
        ],
    )

    extra_args = " ".join(ctx.attr.gen_kernel_args)

    ctx.actions.run_shell(
        outputs = [out_file],
        inputs = inputs,
        command = (
            "{compiler_cmd} " +
            "--packages={pkg} --platform={plat} {mode_flags} --output={out} " +
            "-Dsdk_hash={hash} -Ddart.vm.product={product} " +
            "-Ddart.vm.asan=false -Ddart.vm.msan=false -Ddart.vm.tsan=false " +
            "{extra} {main}"
        ).format(
            compiler_cmd = compiler_cmd,
            pkg = ctx.file.package_config.path,
            plat = ctx.file.platform_dill.path,
            mode_flags = " ".join(ctx.attr.mode_flags),
            out = out_file.path,
            hash = toolchain.sdk_hash,
            product = "true" if ctx.attr.product else "false",
            extra = extra_args,
            main = ctx.file.main.path,
        ),
        mnemonic = "DartCompileDill",
        progress_message = "Compiling Dart kernel dill %{label}",
    )

    return [DefaultInfo(files = depset([out_file]))]

dart_aot_elf = rule(
    implementation = lambda ctx: _dart_aot_elf_impl(ctx),
    attrs = {
        "dill": attr.label(mandatory = True, allow_single_file = True),
        "gen_snapshot": attr.label(mandatory = True, executable = True, cfg = "exec"),
        "gen_snapshot_args": attr.string_list(default = []),
        "out": attr.output(mandatory = True),
    },
)

def _dart_aot_elf_impl(ctx):
    out_snapshot = ctx.outputs.out

    args = ctx.actions.args()
    args.add("--deterministic")
    args.add("--snapshot-kind=app-aot-elf")
    args.add("--elf=" + out_snapshot.path)
    if ctx.attr.gen_snapshot_args:
        args.add_all(ctx.attr.gen_snapshot_args)
    args.add(ctx.file.dill.path)

    ctx.actions.run(
        outputs = [out_snapshot],
        inputs = [ctx.file.dill],
        executable = ctx.executable.gen_snapshot,
        arguments = [args],
        mnemonic = "DartAotElf",
        progress_message = "Generating Dart AOT ELF snapshot %{label}",
    )

    return [DefaultInfo(files = depset([out_snapshot]))]

dart_app_jit_training = rule(
    implementation = lambda ctx: _dart_app_jit_training_impl(ctx),
    attrs = {
        "dart_vm": attr.label(mandatory = True, executable = True, cfg = "exec"),
        "dill": attr.label(mandatory = True, allow_single_file = True),
        "main": attr.label(mandatory = True, allow_single_file = True),
        "out": attr.output(mandatory = True),
        "package_config": attr.label(default = "//:package_config_json", allow_single_file = True),
        "sources": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "training_args": attr.string_list(default = []),
        "training_srcs": attr.label_list(allow_files = True, default = []),
        "vm_args": attr.string_list(default = []),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

def _dart_app_jit_training_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    out_snapshot = ctx.outputs.out

    inputs = depset(
        direct = [ctx.file.dill, ctx.file.package_config, ctx.file.main] + ctx.files.training_srcs + [toolchain.dart_executable],
        transitive = [
            toolchain.sdk_files[DefaultInfo].files,
            ctx.attr.sources[DartLibraryInfo].transitive_srcs,
        ],
    )

    vm_args = list(ctx.attr.vm_args)
    if not [a for a in vm_args if a.startswith("--coverage")]:
        vm_args = vm_args + ["--coverage=false", "--ignore-unrecognized-flags"]

    expanded_targs = []
    for arg in ctx.attr.training_args:
        if "$(" in arg:
            expanded_arg = ctx.expand_location(arg, targets = ctx.attr.training_srcs + [ctx.attr.package_config])
        else:
            expanded_arg = arg
        expanded_targs.append(expanded_arg)

    ctx.actions.run_shell(
        outputs = [out_snapshot],
        inputs = inputs,
        command = (
            "mkdir -p {vm_dir} && touch {vm_dir}/dartdev_aot.dart.snapshot && " +
            "{vm} --deterministic --packages={pkg} " +
            "--snapshot={out} --snapshot-kind=app-jit --dfe=NEVER_LOADED " +
            "{vmargs} {dill} {targs}"
        ).format(
            vm_dir = ctx.executable.dart_vm.dirname,
            vm = ctx.executable.dart_vm.path,
            pkg = ctx.file.package_config.path,
            out = out_snapshot.path,
            vmargs = " ".join(vm_args),
            dill = ctx.file.dill.path,
            targs = " ".join(expanded_targs),
        ),
        tools = [ctx.executable.dart_vm],
        mnemonic = "DartAppJitTraining",
        progress_message = "Running JIT training for %{label}",
    )

    return [DefaultInfo(files = depset([out_snapshot]))]

dart_compile_platform_rule = rule(
    implementation = lambda ctx: _dart_compile_platform_rule_impl(ctx),
    attrs = {
        "deps_outline": attr.label(allow_single_file = True),
        "exclude_source": attr.bool(default = False),
        "libraries_spec": attr.string(default = "org-dartlang-sdk:///sdk/lib/libraries.json"),
        "outline_out": attr.output(mandatory = True),
        "package_config": attr.label(default = "//:package_config_json", allow_single_file = True),
        "platform_args": attr.string_list(default = []),
        "platform_out": attr.output(mandatory = True),
        "product": attr.bool(default = False),
        "sdk_sources": attr.label(mandatory = True),
        "single_root_base": attr.string(default = ""),
        "sources": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "tool": attr.label(default = "//:pkg/front_end/tool/compile_platform.dart", allow_single_file = True),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

def _dart_compile_platform_rule_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    platform_out = ctx.outputs.platform_out
    outline_out = ctx.outputs.outline_out

    inputs_list = [ctx.file.tool, ctx.file.package_config]
    if ctx.file.deps_outline:
        inputs_list.append(ctx.file.deps_outline)

    inputs = depset(
        direct = inputs_list + [toolchain.dart_executable] + ctx.files.sdk_sources,
        transitive = [
            toolchain.sdk_files[DefaultInfo].files,
            ctx.attr.sources[DartLibraryInfo].transitive_srcs,
        ],
    )

    base = ctx.attr.single_root_base or "$(pwd)"

    if not ctx.attr.platform_args:
        mid = (
            "dart:core -Ddart.vm.product={product} -Ddart.vm.asan=false " +
            "-Ddart.vm.msan=false -Ddart.vm.tsan=false -Ddart.isVM=true {exclude}"
        ).format(
            product = "true" if ctx.attr.product else "false",
            exclude = "--exclude-source " if ctx.attr.exclude_source else "",
        )
    else:
        mid = " ".join(ctx.attr.platform_args) + " "

    if not ctx.file.deps_outline:
        deps_pos = outline_out.path
    else:
        deps_pos = ctx.file.deps_outline.path

    ctx.actions.run_shell(
        outputs = [platform_out, outline_out],
        inputs = inputs,
        command = (
            "{dart} -Dsdk_hash={hash} --packages={pkg} {tool} " +
            "{mid}" +
            "--single-root-scheme=org-dartlang-sdk --single-root-base={base} " +
            "{spec} {deps_pos} {platform} {outline}"
        ).format(
            dart = toolchain.dart_executable.path,
            hash = toolchain.sdk_hash,
            pkg = ctx.file.package_config.path,
            tool = ctx.file.tool.path,
            mid = mid,
            base = base,
            spec = ctx.attr.libraries_spec,
            deps_pos = deps_pos,
            outline = outline_out.path,
            platform = platform_out.path,
        ),
        mnemonic = "DartCompilePlatform",
        progress_message = "Compiling Dart platform dill %{label}",
    )

    return [DefaultInfo(files = depset([platform_out, outline_out]))]

dart_kernel_snapshot_rule = rule(
    implementation = lambda ctx: _dart_kernel_snapshot_rule_impl(ctx),
    attrs = {
        "main": attr.label(mandatory = True, allow_single_file = [".dart"]),
        "out": attr.output(mandatory = True),
        "package_config": attr.label(default = "//:package_config_json", allow_single_file = True),
        "sources": attr.label(mandatory = True, providers = [DartLibraryInfo]),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

def _dart_kernel_snapshot_rule_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    out_dill = ctx.outputs.out

    inputs = depset(
        direct = [ctx.file.main, ctx.file.package_config, toolchain.dart_executable],
        transitive = [
            toolchain.sdk_files[DefaultInfo].files,
            ctx.attr.sources[DartLibraryInfo].transitive_srcs,
        ],
    )

    ctx.actions.run_shell(
        outputs = [out_dill],
        inputs = inputs,
        command = (
            "{dart} --snapshot-kind=kernel --snapshot={out} " +
            "-Dsdk_hash={hash} --packages={pkg} {main}"
        ).format(
            dart = toolchain.dart_executable.path,
            out = out_dill.path,
            hash = toolchain.sdk_hash,
            pkg = ctx.file.package_config.path,
            main = ctx.file.main.path,
        ),
        mnemonic = "DartKernelSnapshot",
        progress_message = "Compiling Dart kernel snapshot %{label}",
    )
    return [DefaultInfo(files = depset([out_dill]))]

def _build_devtools_impl(ctx):
    out = ctx.actions.declare_directory(ctx.attr.out_dir)
    ctx.actions.run(
        outputs = [out],
        inputs = ctx.files.srcs,
        executable = ctx.executable._tool,
        arguments = ["--output", out.path],
        mnemonic = "BuildDevTools",
        progress_message = "Building DevTools from source",
        execution_requirements = {"local": "1"},
    )
    return [DefaultInfo(files = depset([out]))]

build_devtools_rule = rule(
    implementation = _build_devtools_impl,
    doc = "Build DevTools from source using tools/build_devtools.py",
    attrs = {
        "out_dir": attr.string(
            mandatory = True,
        ),
        "srcs": attr.label_list(
            allow_files = True,
        ),
        "_tool": attr.label(
            default = "//tools:build_devtools.py",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)

def _runfiles_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    workspace = ctx.workspace_name
    if not workspace:
        workspace = "_main"
    return workspace + "/" + file.short_path

def _dart_binary_impl(ctx):
    toolchain = ctx.toolchains["//tools/bazel/dart:toolchain_type"].dartinfo
    runner = ctx.actions.declare_file(ctx.label.name)

    dart_path = _runfiles_path(ctx, toolchain.dart_executable)
    main_path = _runfiles_path(ctx, ctx.file.main)
    pkg_config_path = _runfiles_path(ctx, ctx.file._package_config)

    vm_args_list = []
    for arg in ctx.attr.vm_args:
        vm_args_list.append("'" + arg.replace("'", "'\\''") + "'")
    vm_args_str = " ".join(vm_args_list)

    script_content = """#!/bin/bash
if [ -n "$RUNFILES_DIR" ]; then
  rdir="$RUNFILES_DIR"
else
  rdir="$0.runfiles"
fi

exec "${rdir}/%s" --packages="${rdir}/%s" %s "${rdir}/%s" "$@"
""" % (
        dart_path,
        pkg_config_path,
        vm_args_str,
        main_path,
    )

    ctx.actions.write(
        output = runner,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [
            toolchain.dart_executable,
            ctx.file.main,
            ctx.file._package_config,
        ],
        transitive_files = depset(
            transitive = [
                toolchain.sdk_files[DefaultInfo].files,
                ctx.attr.sources[DartLibraryInfo].transitive_srcs,
            ],
        ),
    )

    return [
        DefaultInfo(
            executable = runner,
            runfiles = runfiles,
        ),
    ]

dart_binary = rule(
    implementation = _dart_binary_impl,
    executable = True,
    attrs = {
        "main": attr.label(mandatory = True, allow_single_file = [".dart"]),
        "sources": attr.label(mandatory = True, providers = [DartLibraryInfo]),
        "vm_args": attr.string_list(default = []),
        "_package_config": attr.label(
            default = "//tools/bazel/dart:runfiles_package_config",
            allow_single_file = True,
        ),
    },
    toolchains = ["//tools/bazel/dart:toolchain_type"],
)

# --- Prebuilt AOT Snapshot Compilation (Bootstrap) ---
# Inspired by upstream CL: https://dart-review.googlesource.com/c/sdk/+/510221

def _prebuilt_dart_aot_snapshot_impl(ctx):
    dill = ctx.actions.declare_file(ctx.label.name + ".dill")
    elf = ctx.outputs.out

    # Step 1: Compile to AOT kernel dill using prebuilt AOT compiler
    ctx.actions.run(
        inputs = ctx.files.srcs + [
            ctx.file.main,
            ctx.file._gen_kernel_aot,
            ctx.file._platform,
            ctx.file._package_config,
        ],
        outputs = [dill],
        executable = ctx.executable._dartaotruntime,
        arguments = [
            ctx.file._gen_kernel_aot.path,
            "--packages=" + ctx.file._package_config.path,
            "--platform=" + ctx.file._platform.path,
            "--aot",
            "--output=" + dill.path,
            ctx.file.main.path,
        ],
        mnemonic = "PrebuiltDartCompileKernelAOT",
        progress_message = "Compiling %{label} to AOT Kernel (prebuilt)",
    )

    # Step 2: Compile dill to AOT ELF snapshot using prebuilt gen_snapshot
    ctx.actions.run(
        inputs = [dill],
        outputs = [elf],
        executable = ctx.executable._gen_snapshot,
        arguments = [
            "--deterministic",
            "--snapshot-kind=app-aot-elf",
            "--elf=" + elf.path,
            dill.path,
        ],
        mnemonic = "PrebuiltDartAotElf",
        progress_message = "Generating AOT ELF snapshot %{label} (prebuilt)",
    )

    return [DefaultInfo(files = depset([elf]))]

prebuilt_dart_aot_snapshot_rule = rule(
    implementation = _prebuilt_dart_aot_snapshot_impl,
    attrs = {
        "main": attr.label(mandatory = True, allow_single_file = [".dart"]),
        "out": attr.output(mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "_dartaotruntime": attr.label(default = Label("@prebuilt_dart_sdk//:bin/dartaotruntime"), executable = True, allow_single_file = True, cfg = "exec"),
        "_gen_kernel_aot": attr.label(default = Label("@prebuilt_dart_sdk//:bin/snapshots/gen_kernel_aot.dart.snapshot"), allow_single_file = True),
        "_gen_snapshot": attr.label(default = Label("@prebuilt_dart_sdk//:bin/utils/gen_snapshot"), executable = True, allow_single_file = True, cfg = "exec"),
        "_package_config": attr.label(default = Label("//:package_config_json"), allow_single_file = True),
        "_platform": attr.label(default = Label("@prebuilt_dart_sdk//:lib/_internal/vm_platform_product.dill"), allow_single_file = True),
    },
)

def prebuilt_dart_aot_snapshot(name, main, srcs = [], **kwargs):
    """Compile a Dart script to an AOT ELF snapshot using the prebuilt SDK.

    Used for bootstrapping compiler tools (like bootstrap_gen_kernel) to AOT
    without relying on the JIT VM or custom-built tools.
    """
    prebuilt_dart_aot_snapshot_rule(
        name = name,
        main = main,
        srcs = srcs,
        out = name + ".snapshot",
        **kwargs
    )
