# Upstream Alignments: Lessons from Ryan Macnak's Recent Work

**Task/Bead Link:** [sdk-4mq](BACKLOG.md#sdk-4mq)

## Overview
This document captures the analysis of recent upstream changes (May-June 2026) by Ryan Macnak (`rmacnak@google.com`) and outlines how they can be leveraged to simplify, optimize, and robustify the Dart SDK Bazel migration.

Ryan's work primarily focuses on build performance, remote execution (RBE) compatibility, macOS Apple Silicon support, and build reproducibility. These areas are highly aligned with the core goals of the Bazel migration.

---

## 🔑 Key Alignment Areas & Action Items

### 1. RBE Sandboxing & Relative Paths
*   **Upstream Changes:**
    *   `[build] Remove the last absolute paths from RBE builds` ([CL 506505](https://dart-review.googlesource.com/c/sdk/+/506505))
    *   `Invoke tests with relative paths` ([CL 508364](https://dart-review.googlesource.com/c/sdk/+/508364))
    *   `[build] Expect commands already relative` ([CL 506841](https://dart-review.googlesource.com/c/sdk/+/506841))
*   **Impact on Bazel Migration:**
    *   Bazel executes actions in a strict sandbox where absolute paths break caching and compilation.
    *   Previously, wrapping SDK tools (like `test.py` or `gen_snapshot`) in Bazel might have required complex path-translation wrappers.
    *   Now, these tools natively support and expect the relative-path layout that Bazel naturally uses.
*   **Action Items:**
    *   [ ] Audit custom Bazel rules in `tools/bazel/dart/defs.bzl` and `test_rules.bzl` that invoke SDK tools/tests.
    *   [ ] Remove any temporary path-translation wrappers or hacks that were working around absolute path requirements.
    *   [ ] Ensure `tools/bazel/translate_gn_desc.py` correctly handles the now-relative paths in GN descriptions.

### 2. macOS Apple Silicon Signing & Entitlements
*   **Upstream Changes:**
    *   `[build, mac] Sign shared libraries and fix incremental build...` ([CL 506341](https://dart-review.googlesource.com/c/sdk/+/506341))
    *   `[build] Remove unsigned executable memory permissions from the AOT runtime on Mac` ([CL 505200](https://dart-review.googlesource.com/c/sdk/+/505200))
*   **Impact on Bazel Migration:**
    *   Our macOS Apple Silicon (ARM64) builds (tracked in `MAC_AGENT_HANDOFF.md`) must comply with strict macOS code signing and memory protection policies.
    *   Ryan's work to remove unsigned executable memory permissions from the AOT runtime makes the resulting binaries cleaner and easier to sign (no dangerous JIT-like permissions needed for AOT).
    *   His work on signing shared libraries in GN provides a blueprint for how to handle this in Bazel.
*   **Action Items:**
    *   [ ] Replicate the signing logic from CL 506341 in the Bazel packaging rules (`//sdk:create_sdk`). Specifically, ensure `.dylib` files are signed correctly during the Bazel build.
    *   [ ] Verify that the Bazel-built `dart` and `gen_snapshot` binaries on macOS ARM64 do not request unnecessary executable memory permissions, making them easier to distribute and run.
    *   [ ] Ensure incremental builds work correctly when signing files or entitlements change by defining proper Bazel inputs.

### 3. Toolchain Bootstrapping (AOT vs. JIT)
*   **Upstream Changes:**
    *   `[build] Switch to AOT bootstrap gen_kernel/compile_platform` ([CL 510221](https://dart-review.googlesource.com/c/sdk/+/510221))
    *   `Remove DDC JIT snapshot` ([CL 510143](https://dart-review.googlesource.com/c/sdk/+/510143))
*   **Impact on Bazel Migration:**
    *   Bazel toolchains need fast, hermetic compiler binaries to compile Dart code to Kernel (`.dill`).
    *   JIT-compiled compilers have slow startup times (unless using persistent workers) and require JIT permissions.
    *   AOT-compiled bootstrap tools start up instantly and are much friendlier to Bazel sandboxing.
*   **Action Items:**
    *   [ ] Update Bazel Dart toolchain definitions (`tools/bazel/dart/defs.bzl`) to use the AOT-compiled bootstrap `gen_kernel` and `compile_platform` instead of JIT snapshots.
    *   [ ] Verify this improves build startup latency for Dart targets.

### 4. GN-to-Bazel Translator Simplification
*   **Upstream Changes:**
    *   Removing dead tools ([CL 506460](https://dart-review.googlesource.com/c/sdk/+/506460)), dead configs ([CL 506461](https://dart-review.googlesource.com/c/sdk/+/506461)), and deprecated templates like `copy_trees` ([CL 508163](https://dart-review.googlesource.com/c/sdk/+/508163)).
*   **Impact on Bazel Migration:**
    *   A simpler GN build means a simpler translation to Bazel.
*   **Action Items:**
    *   [ ] Audit `tools/bazel/translate_gn_desc.py`.
    *   [ ] Remove translation logic for deprecated templates (like `copy_trees`) that have been deleted upstream, reducing maintainability overhead of the translator.

---

## 📋 Verification Plan
*   Run `bazel build //sdk:create_sdk` on both Linux and macOS ARM64 to verify that the signing and relative-path changes are integrated and compile green.
*   Verify RBE cache hit rates using the updated relative-path configurations.
