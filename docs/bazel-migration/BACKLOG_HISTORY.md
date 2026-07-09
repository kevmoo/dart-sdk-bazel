# Dart SDK Bazel Migration: Completed Tasks History

This file lists all completed tasks in the Bazel migration. It is generated from the beads issue DB by `docs/bazel-migration/gen_board_from_beads.dart`.

---

## 📜 Completed Tasks

### 🎯 [sdk-0dc] Retire `restore.sh` entirely
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_021`
- **Prerequisites**: `sdk-31k`, `sdk-3jc`
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

### 🎯 [sdk-10p] Print periodic progress updates to stdout in test_runner.dart
- **Status**: `[COMPLETED]`
- **Tags**: `tools`, `user-experience`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  To prevent long periods of silence in the test runner log (especially during the first chunk compilation), add a periodic timer in test_runner.dart to print status updates (elapsed time, current chunk, memory usage) to stdout.
- **Success Criteria**:

---

### 🎯 [sdk-2f2] Investigate Upstreaming Non-Bazel Fixes to Main
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_027`
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

### 🎯 [sdk-31k] Migrate Third-Party Dependencies to Hermetic Bzlmod Overlays
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_017`
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

### 🎯 [sdk-3jc] Migrate `packages.bzl` target generation to a dynamic Bzlmod extension
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_020`
- **Prerequisites**: `sdk-31k`
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

### 🎯 [sdk-3la] Investigate remote build and cache using Buildfarm or Buildbarn
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Evaluate and compare Bazel Buildfarm (Java/Redis-based, mature ecosystem) and Buildbarn (Go/Kubernetes-native, high-performance modular architecture) as open-source self-hosted Remote Build Execution (RBE) and remote caching solutions. Assess their deployment complexity, infrastructure requirements, maintenance overhead, and suitability for the Dart SDK Bazel migration workspace.
- **Success Criteria**:

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

### 🎯 [sdk-4mq] Align Bazel migration with recent upstream improvements
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Analyze and integrate recent upstream improvements by Ryan Macnak (rmacnak@) into the local Bazel migration. Key areas: RBE relative paths, macOS signing, AOT compiler bootstrapping, and GN cleanup. Detailed analysis in docs/bazel-migration/upstream_alignments.md.
- **Success Criteria**:

---

### 🎯 [sdk-4rb] Unified Test Repository with Configuration Subtargets
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_013`
- **Prerequisites**: `sdk-5uz`
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

### 🎯 [sdk-4z5] Migrate VM runtime regression, debugger, observatory, and service suites to Bazel
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `vm`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-4z8] Skill: Create agent skill for automated upstream PR/CL triage in Bazel
- **Status**: `[COMPLETED]`
- **Tags**: `agent-skill`, `bazel-migration`, `tooling`
- **Prerequisites**: `sdk-fnn`, `sdk-zi3`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Create a custom Agent Skill (in .agents/skills/) that equips AI agents to autonomously execute the bridge workflow (fetch, import, test under Bazel, and report results) using the import/export scripts.
- **Success Criteria**:

---

### 🎯 [sdk-50x] Non-Flattened Direct Import Mapping for Test Caching
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_010`
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

### 🎯 [sdk-5db] Minor SDK Assembly Stubs Resolution
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_008`
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

### 🎯 [sdk-5m4] Epic: 100% Zero-Prerequisite 'Test Everything' for Dart SDK
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Achieve 100% zero-prerequisite build, test execution, and pass rates across all 5,788 test targets on fresh checkouts using Bazel.
- **Success Criteria**:

---

### 🎯 [sdk-5m4.1] Workstream 1: Declare Hermetic Toolchains & Sysroots in Bazel Repository Rules
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-5m4`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Ensure Bazel repository rules (@prebuilt_dart_sdk, @dart_clang, etc.) fetch/declare all host toolchains and C++ sysroots automatically so clean checkouts require zero pre-installed system compilers or pre-built GN artifacts. Once hermetic toolchains land, update .bazelrc to scope  so --config=ci and default builds can utilize remote C++ action caching.
- **Success Criteria**:

---

### 🎯 [sdk-5m4.2] Workstream 2: Resolve 2,296 Target Build Errors in test_rules.bzl
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-5m4`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Remediate the 2,296 target build-step errors by fixing runfile lookups, header include quotes, C++ compilation dependencies, and package_config.json resolution.
- **Success Criteria**:

---

### 🎯 [sdk-5m4.3] Workstream 3: Synchronize .status Expectations with Bazel Quarantine Filters
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-5m4`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Map Dart test runner .status file expectations (e.g. simarm64, simriscv64, analyzer skips/failures) into generate_test_targets.dart quarantine tags so platform-specific expected failures are not flagged as Bazel regressions.
- **Success Criteria**:

---

### 🎯 [sdk-5m4.4] Workstream 4: Implement One-Command Developer Entrypoint Script
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-5m4`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Create a clean ./tools/bazel/test_everything.sh wrapper script that bootstraps prebuilt Dart SDK, checks disk/RAM bounds, sets optimal sandbox_base=/tmp flags, and invokes run_test_universe.dart.
- **Success Criteria**:

---

### 🎯 [sdk-5m4.5] Workstream 5: CI Path Filtering & Remote Action Cache Setup
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-5m4`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Configure paths-filter in bazel.yml to skip C++ builds on documentation/backlog PRs and enable Bazel remote action caching.
- **Success Criteria**:

---

### 🎯 [sdk-5uz] Coarse-Grained Test Suite Clustering
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_012`
- **Prerequisites**: `sdk-50x`
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

### 🎯 [sdk-5zs] Resolve Bzlmod Lockfile Drift
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_015`
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

### 🎯 [sdk-67o] Implement Bazel test matrix optimization and remediation recommendations
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Execute prioritized speed & remediation recommendations from docs/bazel-migration/BAZEL_MATRIX_INSIGHTS_AND_RECOMMENDATIONS.md (REC-FAST-1..4 and REC-FIX-1..3).
- **Success Criteria**:

---

### 🎯 [sdk-67o.1] [REC-FAST-4] Dynamic Test Timeout Tiers (timeout = "long") for heavy AOT/WASM suites
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Update Starlark test macros to explicitly assign timeout = 'long' (900s) or 'eternal' (3600s) to heavy WASM/AOT compiled suites instead of relying on default 'moderate' (300s).
- **Success Criteria**:

---

### 🎯 [sdk-67o.2] [REC-FIX-3] Target Quarantining Allowlist (tags = ["quarantine"])
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Apply tags = ['manual', 'quarantine'] to currently unmigrated or flaky test targets so bazel test //... runs 100% green.
- **Success Criteria**:

---

### 🎯 [sdk-67o.3] [REC-FIX-1] Migrate pkg/... test harnesses to package:runfiles lookup
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Refactor relative filesystem path lookups across pkg/analyzer, pkg/analysis_server, and pkg/front_end to resolve assets dynamically via package:runfiles.
- **Success Criteria**:

---

### 🎯 [sdk-67o.4] [REC-FAST-2] Granular shard sizing & subdirectory target splitting
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Split massive test suites like co19 and pkg by subdirectory (e.g. @dart_tests//co19/LanguageFeatures/...) to prevent shard timeouts and improve cache granularity.
- **Success Criteria**:

---

### 🎯 [sdk-67o.6] [REC-FIX-2] Automated hermetic asset scanning in Starlark macros
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Enhance Starlark test generation macros to automatically detect and append required .dill, .snapshot, and helper .dart files to target data attributes.
- **Success Criteria**:

---

### 🎯 [sdk-67o.7] [REC-FAST-3] Document RAM-backed Bazel output base (tmpfs / /dev/shm)
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Document workstation setup to mount --output_base on tmpfs to accelerate symlink creation/deletion by 5x.
- **Success Criteria**:

---

### 🎯 [sdk-67o.8] Investigate and silence GCS remote cache auth errors in Bazel CI on PRs
- **Status**: `[COMPLETED]`
- **Prerequisites**: `sdk-67o`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  In .github/workflows/bazel.yml and infra/remote_execution/bazelrc, PR builds use --remote_cache=https://storage.googleapis.com/dart-sdk-bazel-cache with --remote_upload_local_results=false and --remote_local_fallback=true. When Google Cloud Application Default Credentials (ADC) fail or rate-limit on PR runs, Bazel falls back to local execution but floods the CI log with HTTP cache connection/auth errors. We should investigate cleanly handling or silencing GCS cache errors when running on PRs or untrusted workers without write credentials.
- **Success Criteria**:

---

### 🎯 [sdk-6tn] Establish test completion matrix for Bazel migration
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Track test completion parity and test suite matrix across platforms for Bazel migration
- **Success Criteria**:

---

### 🎯 [sdk-6uq] [bazel] @dart_tests extension: replace manual 'Force refetch trigger: N' with automatic invalidation
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  tools/bazel/dart/test_rules.bzl ends with '# Force refetch trigger: 21' — a hand-bumped counter that is the only way to invalidate the reproducible module extension after generator changes (21 bumps so far). Forgetting the bump means tests silently run against stale generated targets. Make invalidation automatic, e.g. depend on the generator sources via ctx.path(Label(...))/digest so edits re-fetch. See fable_thoughts.md R3.
- **Success Criteria**:

---

### 🎯 [sdk-7nj] Emit canonical `cc_test` rules for self-contained test binaries
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:pending`, `task:TASK_041`
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

### 🎯 [sdk-84z] VM: Fix pre-existing buildifier lint warnings in utils/ddc/rules.bzl
- **Status**: `[COMPLETED]`
- **Tags**: `sdk-cleanup`
- **PR/External Ref**: [PR #20](https://github.com/kevmoo/sdk/pull/20)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Fix pre-existing Buildifier lint warnings in utils/ddc/rules.bzl to unblock CI runs.
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

### 🎯 [sdk-91p] Port `samples/embedder` targets to Bazel
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_019`
- **Prerequisites**: `sdk-e8u`
- **Owner**: `[none]`
- **Commit**: `[local]`
- **Target Files**:
  - `samples/embedder/BUILD.bazel`
- **Description**:
  Resolve all `TODO(M3)` compilation and copy stubs in `samples/embedder/BUILD.bazel` to enable building the embedder samples (compiling Dart programs to dills/AOT and linking/running them).
- **Success Criteria**:
  - [x] All embedder sample executables build green.

---

### 🎯 [sdk-95q] Migrate leaf C++ integration tests (abstract_socket_test & process_test) to cc_test
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Convert the remaining leaf C++ integration tests in runtime/bin (abstract_socket_test and process_test) into canonical Bazel cc_test targets. Package create_process_test_helper into the data attribute of process_test so it is available in the sandbox at runtime.
- **Success Criteria**:

---

### 🎯 [sdk-9qx] Design: Bazel-powered developer workflow bridge for upstream work
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `design`, `tooling`
- **Prerequisites**: `sdk-9ep`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Draft a design document detailing the workflow for importing upstream Gerrit CLs/PRs into a bazel-based branch, iterating/testing using Bazel, and exporting verified changes back to a main-based branch. Define CLI specs for bridge scripts.
- **Success Criteria**:

---

### 🎯 [sdk-9zx] [ci] caching: external-cache, per-workflow disk keys, no PR cache writes, third_party/pkg clone cache
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Implements the three cache fixes from the 2026-06-11 caching review (same PR as nightly.yml): (1) setup-bazel external-cache:true in both workflows — caches output_base/external (clang, sysroot, CIPD prebuilt SDK, browsers), which Bazel's own repository cache can NEVER hold because no download in third_party.bzl/clang_repo.bzl passes sha256; (2) disk-cache keyed per workflow + cache-save only on non-PR events so the nightly's multi-GB disk cache and PR-branch duplicates stop evicting each other inside the 10GB repo budget; (3) actions/cache on third_party/pkg keyed on hashFiles(DEPS) — clone_dependencies.py's 18 shallow clones land in the workspace, invisible to all bazel-level caches. EXACT key only, NO restore-keys: clone_dependencies.py skips existing non-empty dirs without revision-checking, so a stale partial restore would silently pin wrong revisions.
- **Success Criteria**:

---

### 🎯 [sdk-amv] Migrate Fuzzer test suite to Bazel
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Track Starlark test generation and execution for fuzzer suite
- **Success Criteria**:

---

### 🎯 [sdk-arr] Enable standard Bazel lint and formatting checks (Buildifier)
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_039`
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

### 🎯 [sdk-b0q] Fix SDK packaging VM product mode configuration mismatch
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_033`
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

### 🎯 [sdk-b34] GN: Split C-only and C++-only flags in compiler configs
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `sdk-cleanup`
- **PR/External Ref**: [Link](https://dart-review.googlesource.com/c/sdk/+/510181)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Move C++-only flags/warnings (like -Wheader-hygiene) from shared cflags to cflags_cc in build/config/compiler/BUILD.gn. This prevents language-mismatch warnings on pure C targets and ensures accurate compilation databases. Ref: docs/bazel-migration/todo_issues/issue_00001_split_conlyopts_cxxopts.md
- **Success Criteria**:

---

### 🎯 [sdk-b5h] Follow-up PR #44: convert unmigrated suites to Suite -> Bead ID map
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Update unmigratedGnSuites in run_test_universe.dart to map Suite names to tracking Bead IDs
- **Success Criteria**:

---

### 🎯 [sdk-baw] Debian Package Build Target
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_025`
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

### 🎯 [sdk-brm] Merge upstream Dart SDK at 3.13.0-207.0.dev
- **Status**: `[COMPLETED]`
- **PR/External Ref**: [PR #29](https://github.com/kevmoo/dart-sdk-bazel/pull/29)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-c1x] Audit and Apply Code Review Learnings across Bazel codebase
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_031`
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

### 🎯 [sdk-cfi] ICU: Expose checked-in data headers in build definitions
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `sdk-cleanup`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Resolve the silent reliance on implicit include paths for ICU data headers (norm2_nfc_data.h, etc.). Either implement the regeneration step in GN/Bazel to match upstream, or explicitly expose the checked-in data tables in third_party/icu/BUILD.gn and document the divergence. Ref: docs/bazel-migration/todo_issues/issue_00006_icu_data_headers_inconsistency.md
- **Success Criteria**:

---

### 🎯 [sdk-cte] Fix Bazel wildcard target evaluation and package loading errors
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_035`
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

### 🎯 [sdk-d3p] [bazel] CI: widen analysis surface beyond //runtime/bin:dartvm
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  bazel.yml builds only dartvm. PR #15 merged while breaking //sdk:create_sdk at ANALYSIS time (missing $(location) prerequisite) and at execution time (package_config rootUri depth) — caught only by fable's review session 2026-06-10. Add 'bazel build --nobuild //sdk:create_sdk' (pure analysis, ~17s warm) and a bazel query of @dart_tests//... to CI; consider a scheduled full create_sdk + smoke job with disk cache. See docs/bazel-migration/fable_thoughts.md O1/R1.
- **Success Criteria**:

---

### 🎯 [sdk-dj6] Full project review: bugs + improvement opportunities (fable_thoughts.md)
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Comprehensive stability-focused review of the Bazel migration branch; artifact at docs/bazel-migration/fable_thoughts.md. Requested by kevmoo 2026-06-10.
- **Success Criteria**:

---

### 🎯 [sdk-duv.1] Relocate macOS C++ flag filtering to select{} blocks
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:pending`, `task:TASK_029`
- **Prerequisites**: `sdk-duv`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-duv.3] Decouple test cache dependencies via depset dill summaries
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:pending`, `task:TASK_029`
- **Prerequisites**: `sdk-duv`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Refactor dart_library to propagate depset compilation summaries so touching un-imported SDK library files does not invalidate repository-wide test caches.
- **Success Criteria**:

---

### 🎯 [sdk-duv.4] Optimize GitHub Actions CI Bazel caching and sandbox execution
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:pending`, `task:TASK_029`
- **Prerequisites**: `sdk-duv`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-duv.5] Evaluate and deploy gRPC/HTTP Remote Cache cluster (BuildBuddy/GCS) for shared team and CI caching
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:pending`, `task:TASK_029`
- **Prerequisites**: `sdk-duv`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Replace GitHub Actions monolithic tarball disk-cache restoration with streaming datacenter remote cache cluster to eliminate 30s job startup extraction penalty.
- **Success Criteria**:

---

### 🎯 [sdk-dz3] Relocate and Migrate Worktree Symlinker to Dart
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_009`
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

### 🎯 [sdk-e8u] Compile `dart_engine` Shared Libraries JIT/AOT
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_018`
- **Prerequisites**: `sdk-31k`
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

### 🎯 [sdk-fnn] Tooling: Implement script to export Bazel-tested changes back to Main
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `tooling`
- **Prerequisites**: `sdk-9qx`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Create a developer script (e.g., tools/bazel/bridge/export.dart) to extract the core SDK changes from a Bazel branch and apply them cleanly to a main-based branch, filtering out Bazel-specific migration files.
- **Success Criteria**:

---

### 🎯 [sdk-fok] Pre-Computed Package Import Mapping (Fine-Grained Opt-in)
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_002`
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
- **Tags**: `bazel-migration`, `sdk-cleanup`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Update SDK roll/import scripts to exclude BUILD, BUILD.bazel, WORKSPACE, and MODULE.bazel files. Prune the existing renamed *.disabled-for-dart-bazel-migration files from the tree. Ref: docs/bazel-migration/todo_issues/issue_00005_vendored_third_party_build_files.md
- **Success Criteria**:

---

### 🎯 [sdk-hw2] Merge upstream origin/dev 3.13.0-201.0.dev
- **Status**: `[COMPLETED]`
- **PR/External Ref**: [PR #24](https://github.com/kevmoo/dart-sdk-bazel/pull/24)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Routine upstream merge per merge_main_to_bazel skill. 90 commits since 3.13.0-189. Includes boringssl roll fallout fix in the BUILD.bazel.snap overlay (P-256 nistz code replaced with C upstream; asm sources now required). Validated: dartvm builds+runs 3.13.0-201, tools/bazel/presubmit.sh green. Landed on branch merge-dev-3.13.0-201.
- **Success Criteria**:

---

### 🎯 [sdk-i4n] Migrate VM Platform and Kernel Service Dill Compilation to Starlark
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_016`
- **Prerequisites**: `sdk-5db`
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

### 🎯 [sdk-izv] Migrate GCS remote cache bucket to single region us-west1 (Oregon)
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Recreate gs://dart-sdk-bazel-cache in single region us-west1 to reduce Class A PUT upload costs by 50% ($0.05 per 10k vs $0.10) and drop developer RTT latency in Seattle to ~5-10ms.
- **Success Criteria**:

---

### 🎯 [sdk-j1a] Python Test Wrapper Unit Testing
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_014`
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

### 🎯 [sdk-jrr] Repo-Local Upstream SDK Merge Flow Skill
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_011`
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

### 🎯 [sdk-k3n] Implement `bazel run` support for running Dart scripts
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_040`
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

### 🎯 [sdk-k9l] Design and implement Dart Dev Compiler (ddc) web test execution architecture
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `ddc`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-mpb] Migrate co19 conformance tests to Bazel as isolated Bzlmod repo (@dart_co19_tests)
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `co19`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
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

### 🎯 [sdk-n0q] Setup Bazel cache auto-cleanup
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Configure lifecycle rules on the GCS bucket 'dart-sdk-bazel-cache' (or the configured remote cache) to automatically clean up old cache artifacts and prevent storage costs from growing indefinitely.
- **Success Criteria**:

---

### 🎯 [sdk-n4o] Dynamic Browser Testing Downloads
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_005`
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

### 🎯 [sdk-njh] [bazel] tools/test.py: unmatched test selectors only warn — silent coverage loss
- **Status**: `[COMPLETED]`
- **PR/External Ref**: [PR #25](https://github.com/kevmoo/dart-sdk-bazel/pull/25)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  tools/test.py:283-296 (--bazel path): a selector matching zero Bazel targets prints a warning and is dropped; the run fails only if ALL selectors are empty. A CI invocation with one typo'd suite silently runs partial coverage and exits 0. Decide: hard-fail on any unmatched selector, or add --strict-selectors. See fable_thoughts.md B4.
- **Success Criteria**:

---

### 🎯 [sdk-o1h] Live-Parse DEPS in Bzlmod Extension for Dynamic Dependency Downloads
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_030`
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

### 🎯 [sdk-p5r] {REC-FAST-5} Add default Bazel flags (--nobuild_runfile_links) to eliminate inode churn
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Add --nobuild_runfile_links and --experimental_convenience_symlinks=ignore to the default Bazel arguments in run_test_universe.dart to prevent unnecessary runfile symlink creation and convenience symlink generation, reducing inode churn.
- **Success Criteria**:

---

### 🎯 [sdk-qtd] Cleanup migration documentation and legacy instructions
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_037`
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

### 🎯 [sdk-qzb] Refactor sh_test generation to use explicit rlocationpath runfiles manifests instead of runtime find sweeps
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `rbe`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-rog] VM: Define formal GN target for public VM embedding C API
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `sdk-cleanup`
- **PR/External Ref**: [PR #19](https://github.com/kevmoo/sdk/pull/19)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Create a header-only source_set('public_api_headers') in runtime/include/BUILD.gn containing only the public embedding API headers (dart_api.h, etc.). Update internal VM targets to depend on it, and align the Bazel translation to remove the hand-written shim. Ref: docs/bazel-migration/todo_issues/issue_00007_runtime_include_public_api_target.md
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

### 🎯 [sdk-s5g] Dynamic Package Dependency Mapping
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_001`
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

### 🎯 [sdk-s7k] Investigate Bazel aspects for formatting and analysis checks
- **Status**: `[COMPLETED]`
- **Tags**: `pending`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Research and brainstorm the design for running static analysis (dart analyze) and formatting (dart format) via Bazel Aspects (similar to aspect_rules_lint) or macro-generated test targets. This will ensure that formatting and lints are checked as part of the Bazel test/build graph with proper caching, rather than relying solely on pre-commit hooks.
- **Success Criteria**:

---

### 🎯 [sdk-tjm] Simulator Target Configurations
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_024`
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

### 🎯 [sdk-trr] Bump Bazel to 9.1.1
- **Status**: `[COMPLETED]`
- **PR/External Ref**: [PR #29](https://github.com/kevmoo/dart-sdk-bazel/pull/29)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-u0p] Define Bazel test targets for core library API tests (tests/lib)
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  
- **Success Criteria**:

---

### 🎯 [sdk-u24] [test_runner] --built-with-bazel: 'bazel info' probe has no timeout
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  pkg/test_runner/lib/src/options.dart ~162: Process.runSync('bazel',['info','bazel-bin']) HAS proper error handling (try/catch + exit-code check, added after gemini review on PR #11) but no timeout — a wedged bazel server hangs the test runner forever (.agents/rules/bazel_hang_detection.md documents this exact failure mode), and the PATH-only lookup ignores tools/utils.py ResolveBazelPath() fallbacks. Add a timeout; consider sharing bazel resolution logic. See fable_thoughts.md B5 (corrected).
- **Success Criteria**:

---

### 🎯 [sdk-u2u] [bazel] pre-commit arch audit is evaded by 'TARGET_ARCH_' + 'X64' concat — decide policy
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  tools/bazel/hooks/pre-commit greps staged Bazel files for the literal "TARGET_ARCH_X64". Four checked-in targets (runtime/BUILD.bazel:1433, runtime/bin/BUILD.bazel:2656,3257,4320 — all *_linux_x64 product variants, introduced in be081364145) write "TARGET_ARCH_" + "X64", which evaluates identically but evades the grep. The defines are semantically defensible for arch-pinned cross variants (arm64 literals are not even forbidden); the gate evasion is the problem. Decide: structured allowlist in the hook + honest literals, or narrow the hook to non-variant targets. Also make the hook catch the concat form, and run the audit in CI (local hook is skippable via --no-verify). See fable_thoughts.md B2.
- **Success Criteria**:

---

### 🎯 [sdk-uft] VM AOT Test Suite Integration
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_022`
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

### 🎯 [sdk-uj3] Audit and convert remaining cc_library stubs to filegroup or alias
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_036`
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

### 🎯 [sdk-ur8] Add Chrome/Firefox test configurations to Bazel target generator
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_034`
- **Prerequisites**: `sdk-b0q`
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

### 🎯 [sdk-v49] Design and implement virtual namespaced package targets
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `review-pending`
- **PR/External Ref**: [PR #15](https://github.com/kevmoo/dart-sdk-bazel/pull/15)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Refactor dart_packages_extension to generate nested BUILD.bazel files inside the virtual @dart_packages repository (e.g. @dart_packages//pkg/<name>:BUILD.bazel). Expose analyze and format targets there, enabling native Bazel wildcard testing (@dart_packages//pkg/<name>/...) and removing flat target clutter from the root BUILD file.
- **Success Criteria**:

---

### 🎯 [sdk-vlg] Sanitizer Test Configuration Mapping
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_023`
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

### 🎯 [sdk-w7m] VM: Eliminate preprocessor symbol toggles in dfe.cc
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `sdk-cleanup`
- **PR/External Ref**: [PR #18](https://github.com/kevmoo/sdk/pull/18)
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Refactor runtime/bin/dfe.cc to split the CFE/Kernel stubs into separate files (dfe_empty_kernel_stubs.cc and dfe_real_kernel_stubs.cc) and select them via GN/Bazel build files, eliminating the EXCLUDE_CFE_AND_KERNEL_PLATFORM preprocessor toggles. Ref: docs/bazel-migration/todo_issues/issue_00008_dfe_ifdef_toggled_symbol_definition.md
- **Success Criteria**:

---

### 🎯 [sdk-we0] Sanitizer Suite Verification
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_007`
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

### 🎯 [sdk-xfm] Migrate Dart VM C++ test runner (run_vm_tests) to cc_test
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Convert the monolithic Dart VM C++ test runner run_vm_tests into a canonical Bazel cc_test target. Audit and package all necessary runtime data dependencies (snapshots, test scripts, etc.) into its data attribute so they are available in the sandbox.
- **Success Criteria**:

---

### 🎯 [sdk-xn9] Audit, integrate, and delete legacy Bazel branches
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Go through legacy Bazel branches (origin/bazel_mac_more, origin/bazel_other_agent_learnings, origin/kevmoo-bazel-mac-builds) to ensure all useful knowledge and code have been integrated into the main branch, then delete them.
- **Success Criteria**:

---

### 🎯 [sdk-xnx] [tools] Add Phase 1 (Build) vs Phase 2 (Test Execution) BEP progress reporting to run_test_universe.dart
- **Status**: `[COMPLETED]`
- **Tags**: `tools`, `user-experience`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Update tools/bazel/run_test_universe.dart to parse BEP actionCompleted / targetComplete events during Phase 1 (Build & Dependency Compilation) before switching to testSummary events during Phase 2 (Test Target Execution). Currently the runner outputs 0/5788 during Phase 1, which obscures early compilation progress.
- **Success Criteria**:

---

### 🎯 [sdk-xql] Fix package config generator for workspace packages and dynamic language versions
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `status:completed`, `task:TASK_032`
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

### 🎯 [sdk-xw2] [bazel] CI: scheduled nightly full //sdk:create_sdk build + packaged-SDK smoke
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Expensive tier of fable_thoughts.md §10 (step 6), split from sdk-d3p when its analysis tier landed in presubmit.sh. Add a scheduled GitHub Actions job: full bazel build //sdk:create_sdk with disk cache, then smoke the packaged SDK (bazel-bin/sdk/dart-sdk/bin/dart --version + hello.dart), optionally one tools/test.py --bazel suite. Catches B1b-class execution regressions and toolchain drift at bounded cost. Promote to PR-time once remote caching (Buildfarm/BuildBuddy) stabilizes.
- **Success Criteria**:

---

### 🎯 [sdk-z4d] Migrate DDC test suite to Bazel
- **Status**: `[COMPLETED]`
- **Prerequisites**: None
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Track Starlark test generation and execution for dartdevc suite
- **Success Criteria**:

---

### 🎯 [sdk-zi3] Tooling: Implement script to import upstream CL/PR into Bazel workspace
- **Status**: `[COMPLETED]`
- **Tags**: `bazel-migration`, `tooling`
- **Prerequisites**: `sdk-9qx`
- **Owner**: `[none]`
- **Commit**: `[none]`
- **Target Files**:
  - None
- **Description**:
  Create a developer script (e.g., tools/bazel/bridge/import.dart) to fetch a Gerrit CL or GitHub PR patch, create a local branch off bazel, and apply the patch cleanly.
- **Success Criteria**:

---

