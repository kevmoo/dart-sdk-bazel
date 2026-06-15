# Bazel Build Tooling & Scripts

This directory (`tools/bazel/`) houses the core infrastructure, helper scripts, and migration utilities for the Dart SDK Bazel build ecosystem.

---

## 🧭 Active Tooling Map

Here is a quick reference guide explaining exactly what each script does and how to invoke it:

### 🔍 1. Fork Delta & Upstream CL Auditor (`fork_delta.dart`)
Trivial delta inspection utility that compares our long-running Bazel fork directly against the official upstream Dart SDK repository (`official/main`), sorting all differences into structured buckets.
```bash
# See a categorized summary of the entire fork delta (Bazel infra, Agent metadata, SDK edits)
dart tools/bazel/fork_delta.dart

# Display exactly and only the Dart SDK source files modified or deleted to form an upstream CL
dart tools/bazel/fork_delta.dart --upstream-cl

# View the actual Git code diff for our modified SDK tooling or C++ source files
dart tools/bazel/fork_delta.dart --diff modified-tools
```

### 🚀 2. Presubmit Quality Gate (`presubmit.sh`)
The one-stop validation script run by developers before sending a PR and executed automatically by CI.
```bash
./tools/bazel/presubmit.sh
```
Executes `buildifier` Starlark formatting and linting, hardcoded-architecture reference audits, Python byte-compilation, `--nobuild` Bazel loading/analysis of all core targets (`//sdk:create_sdk`, `//runtime/bin:dartvm`, utility exes), Bzlmod module extension evaluations (`@dart_packages`, `@dart_tests`), and `dart analyze` over all Bazel tooling scripts.

### 📦 3. Dependency Management & Workspace Sync
These scripts are orchestrated internally by Bazel repository rules and module extensions to hermetically sync dependencies:
*   **`fetch_cipd_dependencies.py`**: Fetches Google CIPD prebuilt binary packages (such as GN, Ninja, and third-party prebuilts) exactly matching the revisions pinned in `DEPS`.
*   **`clone_dependencies.py`**: Parses Git dependencies in `DEPS` and clones/syncs them into isolated external repository directories.
*   **`generate_debug_package_config.py`**: Assembles local `package_config.json` manifests required for hermetic Dart action execution and CFE compiler bootstrapping.
*   **`parse_deps.py`**: Standalone parser that extracts pinned Git URLs and exact commit revisions from `DEPS` to feed Bzlmod external overlays.

### 🏗️ 4. GN to Bazel Migration Utilities
*   **`translate_gn_desc.py`**: Powerful translation engine that reads GN target execution graphs (`gn desc`) and automatically scaffolds equivalent Starlark rules and macros (`BUILD.bazel`, `.bzl`).

### 🏷️ 6. Build Stamping (`workspace_status.py`)
Invoked automatically by Bazel when building with `--stamp` to inject volatile and stable status variables (such as exact Git commit SHA, branch name, and compilation timestamps) into embedded SDK manifests and `dart --version` output.

---

## 📂 Subdirectories
*   **`bridge/`**: Upstream Gerrit CL and GitHub PR import/export bridge synchronization tooling.
*   **`dart/`**: Core Bazel rules, Starlark macros (`defs.bzl`), and dynamic target generators for compiling and running Dart libraries, binaries, and test suites inside the sandbox.
*   **`hooks/`**: Shared Git pre-commit hooks (such as automated `buildifier` Starlark formatting).
*   **`third_party_overlays/`**: Supplemental `BUILD.bazel` files and Starlark patches injected over vendored third-party repositories that lack native Bazel support.
