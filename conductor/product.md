# Product Guide: Dart SDK Bazel Migration

## 🎯 Vision
Transition the Dart SDK's build, packaging, and testing infrastructure from GN+Ninja to Bazel. The goal is to establish a modern, fully hermetic, highly cacheable, and remote-execution-ready (RBE) build engine that improves developer velocity, guarantees build reproducibility, and simplifies multi-platform targeting.

## 🚀 Key Objectives
1. **100% Hermeticity**: Eliminate all host-implicit dependencies, absolute paths, and manual synchronization scripts (e.g., the retired `restore.sh`). All third-party dependencies are fetched and managed hermetically via Bazel's Bzlmod overlays.
2. **Extreme Cacheability**: Ensure build actions are perfectly sandboxed so that compiler outputs, snapshots, and test results can be safely cached both locally and remotely, achieving high RBE cache hit rates.
3. **Seamless Developer Ergonomics**: Keep the transition friction-free for developers by integrating Bazel directly into the existing `tools/build.py` and `tools/test.py` interfaces (using the `--bazel` flag), while supporting direct `bazel build` and `bazel run` commands.
4. **Bootstrapping & Toolchain Performance**: Transition the Dart compiler toolchain to use fast, hermetic, AOT-compiled bootstrap binaries (`gen_kernel`, `compile_platform`) instead of slower JIT snapshots, maximizing compiler startup speeds.
5. **Robust CI/CD Integration**: Migrate LUCI recipes to build and test the SDK hermetically via Bazel and upload verified release artifacts to CIPD/GCS.

## 🛠️ Core Features & Deliverables
*   **Unified SDK Packaging (`//sdk:create_sdk`)**: A single Bazel target that builds and assembles the complete Dart SDK (binaries, snapshots, and core libraries) for Linux, macOS, and Windows.
*   **Standalone VM Compilation (`//runtime/bin:dartvm`)**: A hermetic target compiling the Dart VM with all necessary assets (such as Unicode ICU data tables) embedded from source.
*   **Sandbox-Friendly Web/Browser Testing**: Integrated Starlark rules that dynamically fetch browser runtimes (Chrome, Firefox) via Bzlmod `http_archive` and stage them in the sandbox for hermetic test execution.
*   **GN-to-Bazel Translation Tooling**: A robust translator script (`translate_gn_desc.py`) to automate and maintain the mapping between GN descriptions and Starlark targets.
*   **Multi-Platform Native Support**: Robust toolchain configurations including macOS Apple Silicon code-signing/entitlements and MSVC on Windows hosts.
