# Track Specification: Align Bazel Migration with Recent Upstream Improvements

## 📝 Background & Context
Ryan Macnak (`rmacnak@google.com`) has recently checked in several critical upstream improvements (May-June 2026) to the Dart SDK build engine. These changes focus on build performance, remote execution (RBE) compatibility, macOS Apple Silicon support, and build reproducibility. 

By aligning our Bazel migration with these upstream changes, we can significantly simplify our custom Starlark rules, optimize compiler bootstrapping times, and ensure robust code signing on macOS.

---

## 🎯 Goals & Scope

### 1. RBE Sandboxing & Relative Paths
*   **Context**: Upstream CLs 506505, 508364, and 506841 have removed the remaining absolute paths from RBE builds and configured SDK tools to expect relative paths.
*   **Goal**: Audit our custom Bazel rules to remove any obsolete path-translation wrappers, and update the GN-to-Bazel translator to handle the new relative-path structures.

### 2. macOS Apple Silicon Signing & Entitlements
*   **Context**: Upstream CLs 506341 and 505200 signed shared libraries in GN and removed unsigned executable memory permissions from the AOT runtime on Mac.
*   **Goal**: Replicate this signing logic in the Bazel packaging rules (`//sdk:create_sdk`) for `.dylib` files. Ensure that the AOT runtime binaries do not request unnecessary executable memory permissions and remain fully compliant with macOS arm64 code signing.

### 3. Toolchain Bootstrapping (AOT vs. JIT)
*   **Context**: Upstream CL 510221 switched to AOT-compiled bootstrap compilers (`gen_kernel`, `compile_platform`) instead of JIT snapshots, and CL 510143 removed the DDC JIT snapshot.
*   **Goal**: Update our Starlark Dart toolchain definitions to use these AOT-compiled bootstrap binaries, reducing compiler startup latency inside the Bazel sandbox.

### 4. GN-to-Bazel Translator Simplification
*   **Context**: Upstream has removed deprecated templates like `copy_trees` (CL 508163) and dead configs.
*   **Goal**: Prune the corresponding translation logic from `translate_gn_desc.py` to reduce maintainability overhead.

---

## 📋 Target Files
*   `tools/bazel/dart/defs.bzl`
*   `tools/bazel/dart/test_rules.bzl`
*   `tools/bazel/translate_gn_desc.py`
*   `sdk/BUILD.bazel` (or corresponding Bazel packaging rules)

---

## 🏁 Acceptance Criteria
*   [ ] The Starlark Dart toolchain is updated and compiles Dart files using AOT-compiled bootstrap compilers.
*   [ ] The Bazel-built macOS Apple Silicon SDK package (`//sdk:create_sdk`) successfully signs all `.dylib` files and binaries.
*   [ ] The AOT runtime binaries request only necessary memory permissions on macOS ARM64.
*   [ ] Incremental builds function correctly on macOS when signing/entitlements change.
*   [ ] Obsolete absolute-path wrappers are completely pruned from Starlark rules and translation scripts, and the full test suite runs successfully.
