# Implementation Plan: Align Bazel Migration with Recent Upstream Improvements

This plan breaks down the alignment tasks into structured phases. Each phase concludes with a verification and checkpointing task.

---

## Phase 1: RBE Relative Paths & Translator Simplification

- [ ] Task: Audit and Update Custom Bazel Rules for Relative Paths
    - [ ] Identify all custom Starlark rules in `tools/bazel/dart/defs.bzl` and `test_rules.bzl` that wrap SDK tools or test runners.
    - [ ] Prune obsolete path-translation wrappers or hacks that were working around absolute-path requirements.
    - [ ] Verify that rules pass relative paths directly to the underlying tools.
- [ ] Task: Update GN-to-Bazel Translator and Prune Deprecated Templates
    - [ ] Modify `tools/bazel/translate_gn_desc.py` to handle the updated relative paths in GN descriptions.
    - [ ] Remove translation logic for deprecated templates (like `copy_trees`) that have been deleted upstream.
    - [ ] Run a translation dry-run to verify that `BUILD.bazel` files are generated correctly and contain no broken paths.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: RBE Relative Paths & Translator Simplification' (Protocol in workflow.md)

---

## Phase 2: Toolchain Bootstrapping (AOT Compiler)

- [ ] Task: Configure AOT Bootstrap Compilers in Starlark Toolchain
    - [ ] Locate the Dart toolchain definition inside `tools/bazel/dart/defs.bzl`.
    - [ ] Update the compiler paths to point to the AOT-compiled bootstrap `gen_kernel` and `compile_platform` binaries instead of JIT snapshots.
    - [ ] Remove any references to the deleted DDC JIT snapshot.
- [ ] Task: Verify Toolchain Compiles and Measure Startup Latency
    - [ ] Compile a basic Dart target using the updated AOT-compiled bootstrap toolchain.
    - [ ] Verify that the compilation succeeds hermetically.
    - [ ] Perform a simple timing check to verify that build startup latency for Dart targets is improved or stable.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Toolchain Bootstrapping (AOT compiler)' (Protocol in workflow.md)

---

## Phase 3: macOS Apple Silicon Signing & Entitlements

- [ ] Task: Implement Code Signing in Bazel Packaging Rules
    - [ ] Replicate the signing logic from CL 506341 in the Bazel packaging targets in `//sdk:create_sdk`.
    - [ ] Ensure that all `.dylib` shared libraries and executable binaries are signed correctly during the Bazel build.
    - [ ] Define proper Bazel inputs (signing files or entitlements) to ensure incremental builds function correctly when they change.
- [ ] Task: Verify Binaries and Memory Permissions on macOS ARM64
    - [ ] Build the SDK package on macOS ARM64 using `bazel build //sdk:create_sdk`.
    - [ ] Inspect the built `dart` and `gen_snapshot` binaries using macOS commands (e.g. `codesign -d --entitlements -`) to verify they have the correct signature and do not request unnecessary executable memory permissions.
    - [ ] Verify that incremental builds work correctly when touching source code vs. modifying entitlements.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: macOS Apple Silicon Signing & Entitlements' (Protocol in workflow.md)
