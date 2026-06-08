# Dart SDK Bazel Migration: Completed Tasks History

This file lists all completed tasks in the Bazel migration. It is generated from the beads issue DB by `docs/bazel-migration/gen_board_from_beads.dart`.

---

## 📜 Completed Tasks

### 🎯 [TASK_001] Dynamic Package Dependency Mapping
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[4bbcd110701]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Implement dynamic package dependency mapping inside the test target generator. For any test target generated under `pkg/<package_name>`, the generator must dynamically inject `@//:dart_pkg_<package_name>` into its Bazel `data` dependencies. This ensures package library files and their complete transitive closures are staged inside the hermetic sandbox, resolving missing imports during JIT VM test runs and establishing perfect cache invalidation boundaries.
- **Success Criteria**:
  - [x] `generate_test_targets.dart` dynamically adds `@//:dart_pkg_<pkgName>` to test targets generated for `pkg/` subdirectories.
  - [x] Hardcoded package mappings in `dataDeps` are minimized to baseline frameworks.
  - [x] Package tests execute cleanly JIT inside the hermetic sandbox and changes to `pkg/smith/lib/` correctly invalidate the test cache.

---

### 🎯 [TASK_002] Pre-Computed Package Import Mapping (Fine-Grained Opt-in)
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[dynamic]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/gen_test_imports.dart`
- **Description**:
  Provide a high-performance developer tool to generate a static dependency map `test_imports.json` for huge packages like `pkg/analyzer`. Upgraded `generate_test_targets.dart` must consume this pre-computed JSON file to output individual fine-grained test targets with surgically precise file-level `data` dependencies, unlocking ultra-granular Bazel caching within packages without scanning overhead at Bazel runtime.
- **Success Criteria**:
  - [x] A high-performance CLI tool `gen_test_imports.dart` is created to recursively parse imports and output `test_imports.json`.
  - [x] `generate_test_targets.dart` detects `test_imports.json` in package directories and dynamically outputs individual `sh_test` targets for each test case.
  - [x] Modifying a single library file under `pkg/analyzer/lib/` only invalidates the specific, transitively importing JIT VM test targets inside the Bazel sandbox.

---

### 🎯 [TASK_005] Dynamic Browser Testing Downloads
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/test_rules.bzl`
  - `MODULE.bazel`
- **Description**:
  WASM and Web tests are currently limited to the D8 runtime. Integrate dynamic browser downloads (Chrome, Firefox, ChromeDriver) using Bzlmod `http_archive` rules and stage them dynamically in test runfiles to enable browser-based web testing under the sandbox.
- **Success Criteria**:
  - [x] Chrome and ChromeDriver archives are downloaded dynamically via Bzlmod on first run.
  - [x] Browser-based WASM/Web tests execute and pass inside the sandbox.

---

### 🎯 [TASK_007] Sanitizer Suite Verification
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[local]`
- **Target Files**:
  - `build/toolchain/linux/cc_toolchain_config.bzl`
- **Description**:
  Activate and verify the full sanitizer test suites (`asan`, `msan`, `tsan`) at scale in Bazel. Ensure compiler option selections for sanitizers map cleanly to execution environments.
- **Success Criteria**:
  - [x] Sanitizer configurations compile without linker errors.
  - [x] Sanitizer tests execute and report diagnostic outputs correctly.

---

### 🎯 [TASK_008] Minor SDK Assembly Stubs Resolution
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `sdk/BUILD.bazel`
- **Description**:
  Resolve the remaining minor packaging stubs in the SDK assembly:
    1. Implement `dart2bytecode` AOT snapshot compilation and staging.
    2. Implement dynamic compilation of DevTools from source under Bazel instead of copying prebuilt assets via `copy_prebuilt_devtools` (if `build_devtools_from_sources` is enabled).
- **Success Criteria**:
  - [x] `dart2bytecode` snapshot is built and staged successfully under `dart-sdk/bin/snapshots/`.
  - [x] DevTools builds hermetically from source when required.

---

### 🎯 [TASK_009] Relocate and Migrate Worktree Symlinker to Dart
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/setup_worktree_links.sh`
  - `tools/setup_worktree_links.dart`
- **Description**:
  Relocate the git worktree helper script `setup_worktree_links.sh` from `tools/bazel/dart/` to the root of the `tools/` directory to make it a prominent, standard tool, and migrate its bash scripting logic to a robust, cross-platform Dart CLI tool (`tools/setup_worktree_links.dart`). The new Dart tool should recursively resolve the parent git checkout path using git worktree metadata, verify directories, and safely establish symlinks for untracked gclient dependencies (`third_party/`, `buildtools/`, prebuilt SDKs) across all supported platforms (Linux, macOS, and Windows).
- **Success Criteria**:
  - [x] **Task 1.1 (Port Symlinker):** Author the cross-platform Dart worktree symlinker at `tools/setup_worktree_links.dart`.
  - [x] **Task 1.2 (Excise Shell Script):** Delete the legacy shell script `tools/bazel/dart/setup_worktree_links.sh` completely.
  - [x] It successfully resolves parent git checkouts and establishes symlinks under secondary git worktrees.
  - [x] It handles file existences, skips tracked configurations safely, and works cleanly on Linux, macOS, and Windows.

---

### 🎯 [TASK_010] Non-Flattened Direct Import Mapping for Test Caching
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[304f78ec535]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/gen_test_imports.dart`
- **Description**:
  Refactor `test_imports.json` from storing fully-flattened transitive dependency lists to storing a minimal, non-flattened graph of **direct local imports/exports** for each file in the package (tests and libs). Upgrade `generate_test_targets.dart` to load this direct import graph and dynamically compute the transitive closure for each test using a memoized, cycle-safe Depth-First Search (DFS) traversal at generation time. This shrinks the JSON database sizes by ~95% (from 3.4MB to <150KB) and keeps Git history clean by ensuring changes to library imports only touch a single line in the JSON file.
- **Success Criteria**:
  - [x] `gen_test_imports.dart` is updated to only write out direct local imports for each file in `test_imports.json`, resulting in a vastly smaller JSON size.
  - [x] `generate_test_targets.dart` successfully implements a cycle-safe DFS with memoization to resolve closures in under 50ms.
  - [x] Running tests via `tools/test.py --bazel` yields identical dynamic sandboxed targets and passes completely green.

---

### 🎯 [TASK_011] Repo-Local Upstream SDK Merge Flow Skill
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[648fea99a8d]`
- **Target Files**:
  - `.agents/skills/merge_main_to_bazel.md`
- **Description**:
  Design and document a dedicated repo-local skill for the synchronization and merge of the local `bazel` branch with the upstream SDK `origin/main`. Document the fetch, dry-run merge, out-of-band restore flow, visibility fixes for prebuilts, and PATH-aware git commit hook handling to allow future agents to handle merges cleanly.
- **Success Criteria**:
  - [x] A dedicated, repo-local skill file `.agents/skills/merge_main_to_bazel.md` is authored to document the merge sequence, conflict resolution, restore workflow, and pre-commit formatting.
  - [x] The upstream branch `origin/main` is successfully merged into `bazel` via a merge commit and verified buildable.

---

### 🎯 [TASK_012] Coarse-Grained Test Suite Clustering
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_010`
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Optimize Starlark loading times and minimize filesystem overhead by grouping core test suites under unified package directories. For coarse-grained suites (`corelib`, `standalone`, `ffi`, `language`), replace the deeply nested sub-package folder generation (e.g., creating `corelib/list/BUILD.bazel`) with a single package-level `BUILD.bazel` in the suite root (e.g., `@dart_tests//corelib`). Declare all tests belonging to that suite inside this unified package, utilizing explicit target labels to preserve fine-grained file-level cache invalidation boundaries.
- **Success Criteria**:
  - [x] `generate_test_targets.dart` clusters generated targets under root suite directories (`corelib/BUILD.bazel`).
  - [x] Generated `BUILD.bazel` files are reduced by 700+ packages.
  - [x] Modifying a single `.dart` test file still invalidates **only** its specific `sh_test` target.
  - [x] Sandbox JIT execution is completely green.

---

### 🎯 [TASK_013] Unified Test Repository with Configuration Subtargets
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_012`
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - None
- **Description**:
  Consolidate the 7 redundant external Starlark test repositories into a single unified external repository `@dart_tests` to eliminate sequential Bazel repository fetch runs. Refactor target generation to define configuration subtargets inside the package `BUILD` files using configuration suffixes (e.g., `_vm_debug`, `_wasm_d8`) rather than distinct repository namespaces. Upgrade `generate_test_targets.dart` to run the 7 dry-run sweeps concurrently via Dart's `Future.wait` to complete target discovery under 2 seconds.
- **Success Criteria**:
  - [x] `MODULE.bazel` is refactored to define exactly **one** dynamic test repository (`@dart_tests`).
  - [x] `generate_test_targets.dart` parallelizes dry-run sweeps using `Future.wait` and completes target discovery in <2.5 seconds.
  - [x] `test_rules.bzl` defines configuration-suffixed test targets inside the root suite packages.
  - [x] `tools/test.py` routes different configuration runs correctly to their corresponding suffixed targets.
  - [x] All configurations compile and execute green inside the sandboxed repository.

---

### 🎯 [TASK_014] Python Test Wrapper Unit Testing
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/test_wrapper_test.py`
- **Description**:
  Implement a comprehensive Python unit test suite `tools/test_wrapper_test.py` to verify the target resolution and flag translation logic inside `tools/test.py` (`TestWithBazel` and `ResolveConfig`). The test suite must mock Bazel query executions and test various selector inputs (coarse-grained, fine-grained, broad directory, and completely invalid). It must assert that valid selectors resolve to correct targets without emitting any warning or error outputs, and invalid selectors emit the correct warning message.
- **Success Criteria**:
  - [x] `tools/test_wrapper_test.py` is authored utilizing Python's `unittest` standard library.
  - [x] Test cases verify configuration resolutions and flag conversions.
  - [x] Test cases verify that valid selectors resolve to correct targets warning-free.
  - [x] Test cases verify that invalid selectors emit the appropriate target warning.
  - [x] Executing `python3 tools/test_wrapper_test.py` runs and passes completely green.

---

### 🎯 [TASK_015] Resolve Bzlmod Lockfile Drift
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/test_rules.bzl`
  - `tools/bazel/third_party.bzl`
  - `MODULE.bazel.lock`
- **Description**:
  Resolve the platform-induced `bzlTransitiveDigest` drift in `MODULE.bazel.lock` by marking our custom local repository extensions (`dart_tests_extension` and `third_party_extension`) as reproducible. This tells Bazel that their repository generations are deterministic and do not need to be locked, removing their digests from the lockfile and eliminating cross-platform Git churn.
- **Success Criteria**:
  - [x] `test_rules.bzl` returns `reproducible = True` in its extension metadata.
  - [x] `third_party.bzl` returns `reproducible = True` in its extension metadata.
  - [x] `MODULE.bazel.lock` no longer contains entries for these two extensions, preventing platform-specific digest changes.

---

### 🎯 [TASK_016] Migrate VM Platform and Kernel Service Dill Compilation to Starlark
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_008`
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `sdk/BUILD.bazel`
  - `runtime/bin/BUILD.bazel`
  - `tools/bazel/dart/defs.bzl`
- **Description**:
  Replace the temporary `genrule` copies (which pull `kernel_service.dill` and `vm_platform*.dill` from the GN output directory `out/ReleaseX64/`) with native Bazel Starlark rules that compile these targets directly from Dart source code. This involves resolving the complex "Dart-builds-Dart" bootstrap loops (using the prebuilt SDK toolchain to compile the front-end compiler, which then compiles the platform libraries) hermetically within the Bazel graph.
- **Success Criteria**:
  - [x] Bazel targets `//runtime/bin:dartvm` and `//sdk:create_sdk` build successfully without requiring `out/ReleaseX64/` to exist or contain any pre-built dills.
  - [x] Modifying an SDK library source file (e.g. `sdk/lib/core/core.dart`) or compiler source file (under `pkg/front_end/`) correctly triggers incremental rebuilds of the dills and re-links the VM under Bazel.
  - [x] The `restore.sh` sanity check for GN build artifacts is retired.

---

### 🎯 [TASK_017] Migrate Third-Party Dependencies to Hermetic Bzlmod Overlays
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/third_party.bzl`
  - `MODULE.bazel`
  - `tools/bazel/translate_gn_desc.py`
  - `tools/bazel/out_of_band/restore.sh`
- **Description**:
  Eliminate the workspace-modifying steps in `restore.sh` by migrating third-party dependencies to hermetic Bzlmod overlays.
    1. Add `boringssl` and `perfetto` to the `third_party_extension` module extension as local overlay repositories. This automatically bypasses upstream `BUILD` files via symlinking, removing the need for renaming `.disabled` files in the source tree.
    2. Add the prebuilt SDK (`tools/sdks/dart-sdk`) as a local repository overlay, referencing a tracked BUILD file under `tools/bazel/` to avoid placing `BUILD.bazel` in the CIPD directory.
    3. Add `third_party/icu` and `third_party/zlib` to the skip list in `translate_gn_desc.py` so they are never translated locally.
    4. Retire the copying and renaming sections of `restore.sh`.
- **Success Criteria**:
  - [x] No `.disabled-for-dart-bazel-migration` files exist in the workspace.
  - [x] No `BUILD.bazel` files are copied into `third_party/icu` or `third_party/zlib` source directories.
  - [x] `@boringssl`, `@perfetto`, and `@prebuilt_dart_sdk` are resolved hermetically via Bzlmod overlays.

---

### 🎯 [TASK_018] Compile `dart_engine` Shared Libraries JIT/AOT
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_017`
- **Owner**: `[none]`
- **Commit**: `[local]`
- **Target Files**:
  - `runtime/engine/BUILD.bazel`
- **Description**:
  Replace the copy stubs in `runtime/engine/BUILD.bazel` with actual shared library targets that compile `libdart_engine_jit_shared.so` and `libdart_engine_aot_shared.so` natively under Bazel.
- **Success Criteria**:
  - [x] Shared libraries compile and link successfully.
  - [x] Symbols match those exported in the GN build.

---

### 🎯 [TASK_019] Port `samples/embedder` targets to Bazel
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_018`
- **Owner**: `[none]`
- **Commit**: `[local]`
- **Target Files**:
  - `samples/embedder/BUILD.bazel`
- **Description**:
  Resolve all `TODO(M3)` compilation and copy stubs in `samples/embedder/BUILD.bazel` to enable building the embedder samples (compiling Dart programs to dills/AOT and linking/running them).
- **Success Criteria**:
  - [x] All embedder sample executables build green.

---

### 🎯 [TASK_020] Migrate `packages.bzl` target generation to a dynamic Bzlmod extension
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_017`
- **Owner**: `[none]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/packages.bzl`
  - `tools/bazel/dart/gen_packages.py`
  - `MODULE.bazel`
  - `BUILD.bazel`
- **Description**:
  Replace the static, committed `tools/bazel/dart/packages.bzl` file with a dynamic Bzlmod module extension. The extension must read `.dart_tool/package_config.json` and the package `pubspec.yaml` files to dynamically generate `dart_library` targets in an external repository (e.g. `@dart_packages`). This removes `packages.bzl` from git and eliminates the need for `gen_packages.py`.
- **Success Criteria**:
  - [x] `tools/bazel/dart/packages.bzl` and `tools/bazel/dart/gen_packages.py` are deleted.
  - [x] A Bzlmod extension dynamically generates package targets.
  - [x] Build succeeds using dynamic targets.

---

### 🎯 [TASK_021] Retire `restore.sh` entirely
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_017`, `TASK_020`
- **Owner**: `[jetski]`
- **Commit**: `[be97c7e236f]`
- **Target Files**:
  - `tools/bazel/out_of_band/restore.sh`
  - `tools/bazel/out_of_band/README.md`
  - `tools/test.py`
- **Description**:
  Delete `restore.sh` and its documentation. Remove the sanity check in `tools/test.py` that references `restore.sh` and `tools/sdks/dart-sdk/BUILD.bazel`. Ensure the development workflow relies solely on `gclient sync` for dependency alignment.
- **Success Criteria**:
  - [x] `restore.sh` and `README.md` are deleted.
  - [x] `tools/test.py` check is removed.
  - [x] Build works after a fresh `gclient sync` without running any restore scripts.

---

### 🎯 [TASK_022] VM AOT Test Suite Integration
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/test.py`
- **Description**:
  Define AOT compilation and execution configurations in `generate_test_targets.dart` and add AOT configuration mapping in `tools/test.py` `ResolveConfig` to run sandboxed VM AOT tests using the packaged `dartaotruntime`.
- **Success Criteria**:
  - [x] AOT test targets are generated for core suites.
  - [x] `ResolveConfig` maps AOT configurations correctly to AOT target suffixes.
  - [x] VM AOT tests compile to ELF and execute green under the sandboxed dartaotruntime.

---

### 🎯 [TASK_023] Sanitizer Test Configuration Mapping
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/test.py`
- **Description**:
  Extend `ResolveConfig` in `tools/test.py` to parse sanitizer suffixes (e.g. `asan`, `msan`, `tsan`) and inject compiler configuration flags for Bazel-built sanitizer tests.
- **Success Criteria**:
  - [x] `ResolveConfig` detects `asan` suffix and injects `--features=asan` or corresponding flags.
  - [x] Sanitizer tests execute and pass cleanly under Bazel.

---

### 🎯 [TASK_024] Simulator Target Configurations
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `build/config/BUILD.bazel`
  - `tools/bazel/rules.bzl`
  - `tools/bazel/dart/generate_test_targets.dart`
  - `tools/bazel/dart/test_rules.bzl`
  - `tools/test.py`
- **Description**:
  Register simulator CPU configurations (`simarm`, `simarm64`, `simriscv32`, `simriscv64`) in `build/config/BUILD.bazel` to enable cross-architecture simulator testing. Update `tools/test.py` and `generate_test_targets.dart` to support running simulator JIT and AOT tests under Bazel.
- **Success Criteria**:
  - [x] Simulator architectures are registered as valid configurations.
  - [x] VM compiles successfully targeting simulated CPU architectures.
  - [x] 64-bit simulator targets (simarm64, simriscv64) pass JIT and AOT tests end-to-end under Bazel.

---

### 🎯 [TASK_025] Debian Package Build Target
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/debian_package/BUILD.bazel`
- **Description**:
  Replace the `debian_package` placeholder stub in `tools/debian_package/BUILD.bazel` with a functional rule porting the Debian packaging logic.
- **Success Criteria**:
  - [x] Debian package target is compiled and packages all binaries hermetically.

---

### 🎯 [TASK_027] Investigate Upstreaming Non-Bazel Fixes to Main
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `docs/bazelmigration/UPSTREAM_CANDIDATES.md`
- **Description**:
  Audit the diff between the `bazel` branch and `main` (merge base) to isolate non-Bazel changes (VM bug fixes, test runner improvements, third-party decoupling). Categorize these changes and prepare them for upstreaming to `main` via Gerrit CLs.
- **Success Criteria**:
  - [x] Audit report created at `docs/bazel-migration/UPSTREAM_CANDIDATES.md` listing all candidate changes for upstreaming.
  - [x] Upstream Gerrit CLs submitted and linked for approved core fixes.

---

### 🎯 [TASK_029] Streamline and Optimize Bazel Build Definitions
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_003`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/dart/defs.bzl`
  - `tools/bazel/rules.bzl`
- **Description**:
  Audit current Bazel build files and custom Starlark rules (`tools/bazel/dart/defs.bzl`, `tools/bazel/rules.bzl`) to simplify flag propagation, reduce macro complexity, and optimize build graph analysis times.
- **Success Criteria**:
  - [ ] macOS flag filtering moved from macro wrappers to toolchain definitions where possible.
  - [ ] Starlark macro complexity reduced (audited by a senior engineer review).

---

### 🎯 [TASK_030] Live-Parse DEPS in Bzlmod Extension for Dynamic Dependency Downloads
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/third_party.bzl`
  - `DEPS`
- **Description**:
  Implement a dynamic Bzlmod module extension (or custom repository rule) that reads the `DEPS` file at the repository root, uses a Python helper script to parse git repository pins, and dynamically downloads them via Bazel's `git_repository` or `http_archive` rules. This allows building the project with Bazel without requiring a prior `gclient sync` on the host machine.
- **Success Criteria**:
  - [x] A Bzlmod extension or repository rule dynamically parses the root `DEPS` file.
  - [x] Git repository dependencies (e.g. BoringSSL, Perfetto) are fetched hermetically by Bazel based on `DEPS` pins.
  - [x] Bazel build succeeds without relying on local workspace directories for these dependencies.

---

### 🎯 [TASK_031] Audit and Apply Code Review Learnings across Bazel codebase
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/`
  - `build/toolchain/`
  - `tools/debian_package/`
- **Description**:
  Audit all custom Python parsing scripts, genrules, and Starlark definitions in the repository to systematically apply the code quality, safety, and compatibility improvements learned during the gemini-code-assist reviews (documented in docs/bazel-migration/review_learnings.md). Verify safe dictionary evaluations, process ID (PID) locks for repository rules, strict sandboxing compatibility by avoiding absolute host paths in toolchains, comment stripping in naive YAML/properties parsers, and multi-architecture portability (supporting ARM64 alongside x86_64, and using hermetic sysroot references instead of host libraries).
- **Success Criteria**:
  - [x] All custom Python parsing scripts under `tools/bazel` are audited and use defensive `.get()` lookups.
  - [x] Custom repository setup scripts are audited for process ID (PID) locking to prevent parallel build deadlocks.
  - [x] Starlark toolchain configurations under `build/toolchain` are verified to use sandbox-safe label/external paths.
  - [x] Property configuration generators are verified to strip inline comments and outer quotes.
  - [x] genrules and packaging scripts are verified to use hermetic dynamic sysroot references instead of host paths, dynamically check architecture using `uname -m`, and support ARM64.

---

### 🎯 [TASK_032] Fix package config generator for workspace packages and dynamic language versions
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/generate_debug_package_config.py`
- **Description**:
  Fix the synthetic package config generator to correctly scan workspace packages from the root `pubspec.yaml` (including nested `third_party/pkg/` packages like `dap` and `language_server_protocol`) and dynamically resolve their target language versions from their individual `pubspec.yaml` files, resolving build failures caused by hardcoded SDK version mismatches (e.g. `protobuf` compilation failing on Dart 3.13 due to legacy `var` in parameters).
- **Success Criteria**:
  - [x] Workspace packages in `third_party/pkg` are discovered and included in the synthetic package config.
  - [x] Language versions are dynamically resolved from `pubspec.yaml` files.
  - [x] SDK builds successfully under Bazel.

---

### 🎯 [TASK_033] Fix SDK packaging VM product mode configuration mismatch
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `sdk/BUILD.bazel`
- **Description**:
  Resolve VM snapshot incompatibility failures (where prebuilt compiler snapshots compiled as `release` fail to execute under the staged `dartaotruntime` because it compiles as a `product` VM). Dynamically select between product and non-product VM targets (`//runtime/bin:dartaotruntime` vs `//runtime/bin:dartaotruntime_product`, and `gen_snapshot` counterparts) using Bazel `select()` based on the `//build/config:product` constraint.
- **Success Criteria**:
  - [x] `copy_dart_aotruntime` and `copy_gen_snapshot_exe` genrules dynamically select the non-product VM target in default config and the product variant when product mode is true.
  - [x] E2E browser test target compilations execute and pass cleanly without snapshot configuration mismatch errors.

---

### 🎯 [TASK_034] Add Chrome/Firefox test configurations to Bazel target generator
- **Status**: `[COMPLETED]`
- **Prerequisites**: `TASK_033`
- **Owner**: `[local]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/generate_test_targets.dart`
- **Description**:
  Add Chrome and Firefox browser test configurations to the target generator (`_configs` list) so Bazel outputs targets with browser runtimes (e.g. `tests_wasm_chrome_release` or `tests_dart2js_chrome_release`). This will ensure `@chrome//:chrome_files` and `@chromedriver//:chromedriver_files` are linked into the runfiles sandbox and executed E2E.
- **Success Criteria**:
  - [x] Chrome/Firefox test configurations are defined in `generate_test_targets.dart`.
  - [x] Bazel generates `tests_wasm_chrome_release` targets under the `@dart_tests` repository.
  - [x] E2E browser tests compile, spin up Chrome via chromedriver in the sandbox, and pass cleanly.

---

### 🎯 [TASK_035] Fix Bazel wildcard target evaluation and package loading errors
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/BUILD.bazel`
  - `.bazelignore`
  - `BUILD.bazel`
  - `sdk/BUILD.bazel`
  - `tools/bazel/dart/defs.bzl`
  - `utils/ddc/BUILD.bazel`
- **Description**:
  Resolve workspace-wide wildcard parsing (`//...`) failures and package loading errors by:
    1. Removing deleted `out_of_band` directories from the exports glob.
    2. Adding unignored upstream third-party checkouts under `third_party/` to `.bazelignore`.
    3. Converting generic wrapper/stub targets in `BUILD.bazel` and `utils/ddc/BUILD.bazel` from `cc_library` to `filegroup`.
    4. Resolving DevTools target output path conflicts by introducing a staging rule `copy_directory`.
- **Success Criteria**:
  - [x] Wildcard target queries (`bazel fetch //...`) complete successfully without package loading or analysis errors.
  - [x] Conflicting action issues for built-from-source vs. prebuilt DevTools targets are resolved.

---

### 🎯 [TASK_036] Audit and convert remaining cc_library stubs to filegroup or alias
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[a047d5e924f]`
- **Target Files**:
  - `sdk/BUILD.bazel`
  - `utils/BUILD.bazel`
  - `utils/kernelservice/BUILD.bazel`
  - `utils/bazel/BUILD.bazel`
  - `samples/embedder/BUILD.bazel`
- **Description**:
  Audit the remaining `cc_library` targets in the workspace that do not contain C++ source files (such as placeholders, copies, or stubs) and convert them to `filegroup` or `alias`. This ensures cleaner target definitions and prevents unnecessary C++ toolchain resolution or potential provider errors.
- **Success Criteria**:
  - [x] Candidate stub targets are converted to `filegroup` or `alias`.
  - [x] Dependents are updated to reference them via `srcs` (for `filegroup`) or remain unchanged (for `alias`).
  - [x] `bazel fetch //...` and standard builds continue to pass cleanly.

---

### 🎯 [TASK_037] Cleanup migration documentation and legacy instructions
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `docs/bazelmigration/README.md`
- **Description**:
  Audit and clean up the Bazel migration documentation. Modernize and simplify "getting started" guidelines to ensure they are optimized for both human developers and autonomous agents. Identify and archive legacy instruction files, outdated setup scripts, or superseded guides into an `archive/` subfolder.
- **Success Criteria**:
  - [x] Legacy instructions/guides are deleted entirely, relying on Git history for preservation.
  - [x] A concise, agent-optimized "Getting Started" guide exists in README.md and specifies prerequisites.
  - [x] All active docs are clean of obsolete configurations or defunct hooks references.

---

### 🎯 [TASK_039] Enable standard Bazel lint and formatting checks (Buildifier)
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/dart/defs.bzl`
  - `runtime/platform/BUILD.bazel`
  - `runtime/bin/BUILD.bazel`
  - `runtime/engine/BUILD.bazel`
  - `BUILD.bazel`
  - `build/config/BUILD.bazel`
  - `build/config/sanitizers/BUILD.bazel`
  - `.agents/rules/code_quality_gates.md`
  - `.github/workflows/buildifier.yml`
- **Description**:
  Enable standard Bazel formatting and linting (buildifier) across the repository. Fix formatting issues and resolve lint warnings repository-wide (excluding third_party and gen_targets). Add buildifier linter gate to CI and agent quality gates.
- **Success Criteria**:
  - [x] All internal Bazel files are formatted and clean of buildifier warnings.
  - [x] Unused variables and parameters removed from `defs.bzl`.
  - [x] C++ stub libraries marked `alwayslink = True` to fix lints and potential linking issues.
  - [x] GitHub CI workflow checks formatting and linting on PRs using a custom step that downloads buildifier.
  - [x] Agent rules updated with the new Bazel Quality Gate.

---

### 🎯 [TASK_040] Implement `bazel run` support for running Dart scripts
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[jetski]`
- **Commit**: `[local]`
- **Target Files**:
  - `tools/bazel/dart/defs.bzl`
  - `tools/bazel/dart/BUILD.bazel`
  - `tools/bazel/third_party.bzl`
- **Description**:
  Implement the `dart_binary` rule to enable running Dart scripts inside the Bazel sandbox using `bazel run`. Generate a bash launcher wrapper that executes the prebuilt Dart VM, passing package configurations (staged at a specific depth in runfiles to resolve relative paths starting with `../../../`) and forwarding user command-line arguments. Add a bypass for Firefox remote downloads on non-Linux platforms to unblock macOS execution.
- **Success Criteria**:
  - [x] `dart_binary` rule is implemented in `defs.bzl` and correctly bundles transitive dependencies (from `DartLibraryInfo`), the prebuilt Dart SDK, and the runfiles package config.
  - [x] Package config helper `runfiles_package_config` is declared in `tools/bazel/dart/BUILD.bazel`.
  - [x] Remote fetch of Firefox on macOS/Windows is bypassed gracefully by skipping download instead of failing.
  - [x] Running the `test_hello` target via `bazel run` successfully executes and parses arguments cleanly.

---

### 🎯 [TASK_041] Emit canonical `cc_test` rules for self-contained test binaries
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - `tools/bazel/translate_gn_desc.py`
  - `tools/bazel/rules.bzl`
  - `runtime/bin/ffi_unit_test/BUILD.bazel`
- **Description**:
  Today every test executable is emitted as a `cc_binary`/`cc_library` (e.g. `//runtime/bin/ffi_unit_test:run_ffi_unit_tests_x64_linux`, `//runtime/bin:run_vm_tests`), so `bazel test //...` finds nothing (`tests(//...)` returns empty) and Bazel never test-result-caches a pass — the binaries only get the build cache, and are run via `bazel run` or `tools/test.py`. Make the host-runnable, self-contained leaf — `run_ffi_unit_tests_x64_linux`, which runs its ~43 C++ FFI unit tests and exits — a real `cc_test` so it becomes discoverable and cacheable, as a first proof of the canonical shape. This is a translator/macro change, NOT a hand-edit: the BUILD file is AUTO-GENERATED by translate_gn_desc.py, so a manual `cc_test` flip is clobbered on regen (and may collide with the `_is_hand_authored_overlay` guard). Three risks surfaced during investigation: (1) dep edge — the grouping `cc_library` `//runtime/bin/ffi_unit_test:run_ffi_unit_tests` lists the leaf in its `deps`, and a `cc_test` generally cannot sit in another rule's `deps`; verify the custom `rules.bzl` macros tolerate it or restructure the group. (2) silent false-green — the binary defaults to `run_filter = kNone` ("No Test") and only runs tests when passed `--all`, so the `cc_test` MUST set `args = ["--all"]` or it will "PASS" while running zero tests. (3) scope — only the `x64_linux` leaf is host-runnable; its 18 cross-compiled siblings (android/ios/win/fuchsia/riscv) stay `cc_binary`, so the translator must special-case just the host-runnable target. NOTE: `run_vm_tests` is a dispatcher driven by `tools/test.py` + `.status` expectation files and deliberately stays harness-driven — it is NOT a `cc_test` candidate. Related to TASK_029 (build-definition streamlining) but independently actionable.
- **Verification Command**:
  ```bash
  bazel query 'tests(//...)'   # now lists run_ffi_unit_tests_x64_linux
  bazel test //runtime/bin/ffi_unit_test:run_ffi_unit_tests_x64_linux   # PASSED
  bazel test //runtime/bin/ffi_unit_test:run_ffi_unit_tests_x64_linux   # (cached) PASSED
  ```
- **Success Criteria**:
  - [ ] The translator emits `cc_test` (with `args = ["--all"]`) for the host-runnable FFI leaf; a regen does not clobber it.
  - [ ] `bazel query 'tests(//...)'` lists the FFI test target (no longer empty).
  - [ ] `bazel test` on the leaf PASSES, and a second invocation reports `(cached)` without re-running.
  - [ ] The grouping `cc_library` and root `//:run_ffi_unit_tests` still build (dep edge into the leaf verified intact or restructured).
  - [ ] Cross-compiled sibling leaves and `run_vm_tests` are unchanged.

---

### 🎯 [sdk-3ld] [M3] Wire up Dart MCP Server Snapshots
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-oce`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Wire up the 6 JIT/AOT snapshots for the dart_mcp_server utility in utils/dart_mcp_server/BUILD.bazel to enable building its executable from source under Bazel.
- **Success Criteria**:

---

### 🎯 [sdk-90d] [M3] Wire up Dart Dev Compiler (DDC) Snapshots
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-oce`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Replace the 16 DDC filegroup stubs (canary, stable, outline JS snapshots) in utils/ddc/BUILD.bazel with real, functional dart_aot_snapshot and dart_kernel_snapshot targets.
- **Success Criteria**:

---

### 🎯 [sdk-cfi] ICU: Expose checked-in data headers in build definitions
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Resolve the silent reliance on implicit include paths for ICU data headers (norm2_nfc_data.h, etc.). Either implement the regeneration step in GN/Bazel to match upstream, or explicitly expose the checked-in data tables in third_party/icu/BUILD.gn and document the divergence. Ref: docs/bazel-migration/todo_issues/issue_00006_icu_data_headers_inconsistency.md
- **Success Criteria**:

---

### 🎯 [sdk-g2l] [M3] Wire up Dart2JS and Dartdoc Snapshots
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-oce`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Replace the 6 dart2js_aot and dartdoc stubs in utils/compiler/BUILD.bazel with real Starlark snapshot rules to enable compiling Dart-to-JS under Bazel.
- **Success Criteria**:

---

### 🎯 [sdk-gmk] Prune upstream Bazel files from vendored third_party
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Update SDK roll/import scripts to exclude BUILD, BUILD.bazel, WORKSPACE, and MODULE.bazel files. Prune the existing renamed *.disabled-for-dart-bazel-migration files from the tree. Ref: docs/bazel-migration/todo_issues/issue_00005_vendored_third_party_build_files.md
- **Success Criteria**:

---

### 🎯 [sdk-mv2] [M3] Wire up DevTools and Core Utility Binaries
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Wire up the remaining helper stubs (copy_prebuilt_devtools, compile_platform.exe, gen_kernel.exe, git_version) in utils/dartdev/BUILD.bazel and utils/BUILD.bazel to finalize SDK assembly.
- **Success Criteria**:

---

### 🎯 [sdk-oce] [M3] Wire up Kernel Worker Snapshot
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Wire up the persistent compiler kernel_worker JIT/AOT snapshots (kernel_worker_dill) in utils/bazel/BUILD.bazel to enable fast, persistent-worker compiles.
- **Success Criteria**:

---

### 🎯 [sdk-rwz] [M3] Wire up Sanitizer SDK AOT Runtimes
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Wire up the ASAN, MSAN, and TSAN AOT runtime copy actions (copy_dart_aotruntime_asan, etc.) in sdk/BUILD.bazel to enable packaging sanitizer-configured SDKs.
- **Success Criteria**:

---

### 🎯 [sdk-w7m] VM: Eliminate preprocessor symbol toggles in dfe.cc
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Refactor runtime/bin/dfe.cc to split the CFE/Kernel stubs into separate files (dfe_empty_kernel_stubs.cc and dfe_real_kernel_stubs.cc) and select them via GN/Bazel build files, eliminating the EXCLUDE_CFE_AND_KERNEL_PLATFORM preprocessor toggles. Ref: docs/bazel-migration/todo_issues/issue_00008_dfe_ifdef_toggled_symbol_definition.md
- **Success Criteria**:

---

