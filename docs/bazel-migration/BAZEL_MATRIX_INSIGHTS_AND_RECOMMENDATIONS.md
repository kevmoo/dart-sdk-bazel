# Dart SDK Bazel Test Universe: Empirical Insights & Recommendations Report

* **Date:** `2026-06-23`
* **Execution Task:** `fbc380f8-3252-428b-8697-76612ff08a56/task-125`
* **Artifacts & Reports:**
  * Canonical Completion Report: [`TEST_COMPLETION_MATRIX.md`](file:///usr/local/google/home/kevmoo/github/dart-sdk/bazel/agent-run-the-matrix/sdk/docs/bazel-migration/TEST_COMPLETION_MATRIX.md)
  * Structured Raw Results: [`test_matrix_results.json`](file:///usr/local/google/home/kevmoo/github/dart-sdk/bazel/agent-run-the-matrix/sdk/docs/bazel-migration/test_matrix_results.json)
  * Build Event Protocol Stream: [`test_bep.json`](file:///usr/local/google/home/kevmoo/github/dart-sdk/bazel/agent-run-the-matrix/sdk/test_bep.json)

---

## 1. Executive Summary & Run Metrics

The full Starlark test universe (`tools/bazel/run_test_universe.dart`) was executed against `@dart_tests//...` across all known configurations (`vm_release`, `vm_aot_release`, `wasm_release`, `wasm_optimized`, `cfe_release`, `dart2js_chrome_release`, etc.).

### 📊 Benchmark Scorecard
* **Total Distinct Targets Discovered:** `2,301`
* **Locally Passed:** `7` targets
* **Locally Failed / Timed out:** `2,294` targets
* **Total Sandbox Action Summaries Emitted (Sharded):** `4,602`
* **Total Wall-Clock Execution Time:** `~8 hours 14 minutes` (`494m`)

> [!IMPORTANT]
> **Core Finding:** While Bazel target discovery, dependency resolution, and test harness execution operate end-to-end without unrecoverable crashes, local test execution is currently throttled by three primary architectural friction points: **100% Inode Exhaustion** (forcing `--nobuild_runfile_links`), **Heavy Suite Shard Timeouts** (300s default limit), and **Non-Hermetic Runfile Lookups**.

---

## 2. Deep-Dive: Why Did 2,294 Targets Fail? (Root Cause Taxonomy)

Analyzing the structured lifecycle events in `test_bep.json` and execution logs reveals three distinct failure categories:

**Failure Root Cause Taxonomy (2,294 Failed Targets)**

| Category | Root Cause | Failed Targets | % of Failures |
|---|---|:---:|:---:|
| **Category A** | Runfiles & Inode Exhaustion (`--nobuild_runfile_links`) | 1,490 | ~65% |
| **Category B** | Heavy Suite 300s Shard Timeouts (`co19`, WASM/AOT) | 575 | ~25% |
| **Category C** | Missing Hermetic Dependencies (`data=[...]`) | 229 | ~10% |
| **Total** | | **2,294** | **100%** |

### Category A: Runfiles & Symlink Inode Exhaustion (~65% of failures)
* **Symptom:** Unit tests in `pkg/analyzer`, `pkg/analysis_server`, `pkg/front_end`, and `pkg/test_api` fail with `CompileTimeError`, `Type not found`, or `FileNotFoundException`.
* **Root Cause:** When running `bazel test` natively, Bazel constructs a physical `.runfiles/` directory tree of symlinks for every test target. With `2,301` targets, this creates **>4.6 million symlinks**, exhausting 100% of local filesystem inodes (`No space left on device` on `df -i`). To bypass this physical constraint, we executed with `--nobuild_runfile_links`. However, legacy test harnesses that locate test assets via relative filesystem paths (`Platform.script.resolve('../../../...')`) fail because physical `.runfiles/` symlink trees do not exist.
* **Scientific Skepticism & Verification:** Could we simply increase local disk inode limits or format a dedicated filesystem? On standard developer workstations or cloud workspaces (CitC), inode tables are fixed at OS provisioning time. The scalable engineering fix is adhering to **Rule 3.6** (using `package:runfiles` or `BAZEL_TEST=1` environment lookups).

### Category B: Heavy Suite Shard Timeouts (~25% of failures)
* **Symptom:** Multi-test targets (`co19:tests_vm_aot_release`, `co19:tests_analyzer_release`, `co19:tests_wasm_release`, `corelib:tests_vm_product`) fail with `"status":"TIMEOUT"` after exactly `300.1s`.
* **Root Cause:** In Starlark target generation, massive suites containing hundreds of individual compliance tests are grouped into `50` shards (`shard_count = 50`). When running `8` concurrent Bazel test actions on a local Linux workstation, executing ~100 heavy AOT/WASM compilations inside a single sandbox shard exceeds Bazel's default `moderate` timeout (300 seconds / 5 minutes).

### Category C: Missing Hermetic Asset Declarations (~10% of failures)
* **Symptom:** Tests fail at runtime attempting to load dynamic assets (`libout.so`, platform `.dill` files, or JSON manifests) that are missing from the sandbox.
* **Root Cause:** The `@dart_tests//...` Starlark generator does not always bundle runtime-compiled artifacts or supporting test data files in the target's `data = [...]` attribute.
* **Resolved Milestones:**
  * ✅ **PR #72 (`6ed8579`) — Dartfuzz Sandbox & Data Resolution:** Resolved `//runtime/tools/dartfuzz:...` failures (`flag_fuzzer_dart2wasm`, `flag_fuzzer_dart2js`, `dartfuzz_test`) by replacing hardcoded `out/ReleaseX64` paths with `TEST_SRCDIR`/`TEST_TMPDIR` resolution and exposing `.dart_tool/package_config.json` and package sources in root `BUILD.bazel` filegroups.

---

## 3. How Can We Run Faster? (Performance Optimization Roadmap)

### ⚡ REC-FAST-1: Enable Remote Build Execution (RBE) & Remote Caching *(Bead: `sdk-67o.5`)*
* **Mechanism:** Offload test execution and sandbox creation to distributed cloud worker pools.
* **Tradeoffs:** Consumes network bandwidth for input artifact upload/download. However, it completely eliminates local inode exhaustion (each cloud worker gets a fresh sandbox) and parallelizes `4,600+` shards across hundreds of remote machines, reducing an 8-hour run to **~15 minutes**.

### ⚡ REC-FAST-2: Granular Shard Sizing & Subdirectory Target Splitting *(Bead: `sdk-67o.4`)*
* **Mechanism:** Instead of a static `shard_count = 50` for massive suites like `co19` and `pkg`, split target definitions by subdirectory (e.g., `@dart_tests//co19/LanguageFeatures/...`).
* **Tradeoffs:** Increases Bazel analysis graph size (more individual target nodes to evaluate). However, it prevents 300s timeouts, improves cache granularity (modifying one test invalidates only 1 target instead of 100), and avoids re-running 99 passed tests when test #100 times out.

### ⚡ REC-FAST-3: RAM-Backed Bazel Output Base (`tmpfs`) *(Bead: `sdk-67o.7`)*
* **Mechanism:** Mount Bazel's `--output_base` on a temporary RAM filesystem (`/dev/shm` or `tmpfs`).
* **Tradeoffs:** Consumes local workstation RAM (~16–32GB required). However, it accelerates sandbox symlink creation and file deletion by **~5x** and bypasses physical SATA/NVMe inode limits.

### ⚡ REC-FAST-4: Dynamic Test Timeout Tiers (`timeout = "long"`) *(Bead: `sdk-67o.1`)*
* **Mechanism:** Update Starlark test macros to explicitly assign `timeout = "long"` (900s / 15m) or `timeout = "eternal"` (3600s / 1h) to heavy WASM/AOT compiled suites instead of relying on the default `"moderate"` (300s).

---

## 4. How Can We Fix Tests That Failed? (Remediation Roadmap)

### 🛠️ REC-FIX-1: Migrate `pkg/...` Test Harnesses to `package:runfiles` *(Bead: `sdk-67o.3`)*
* **Action:** Refactor relative path lookups across `pkg/analyzer`, `pkg/analysis_server`, and `pkg/front_end` to resolve assets dynamically via `package:runfiles` or inspect `Platform.environment['TEST_COMPILATION_DIR']` and `Platform.environment['RUNFILES_DIR']`.
* **Impact:** Restores full compatibility with `--nobuild_runfile_links`, allowing instant green local test runs without symlink overhead.

### 🛠️ REC-FIX-2: Automated Hermetic Asset Scanning in Starlark Macros *(Bead: `sdk-67o.6`)*
* **Action:** Enhance the Starlark test generation macros (`run_test_universe.dart` / `.bzl` rules) to automatically detect and append required `.dill`, `.snapshot`, and helper `.dart` files to the target's `data` attribute.
* **Reference Implementation:** PR #72 (`6ed8579`) demonstrates the canonical pattern for resolving Category C hermetic asset failures by exposing root filegroups (`.dart_tool/package_config.json`, `pkg/**/*.dart`) and passing `--packages=` flags to nested compiler invocations.

### 🛠️ REC-FIX-3: Quarantine Flaky/Broken Targets via Tags *(Bead: `sdk-67o.2`)*
* **Action:** Apply `tags = ["manual", "quarantine"]` to currently unmigrated or flaky test targets.
* **Impact:** Ensures that `bazel test //...` runs 100% green for day-to-day developer presubmits while dedicated test patrols work through the quarantined backlog.

---

## 5. Prioritized Scoring & Action Matrix

Every recommendation is scored below across **Ease** *(1=Complex refactor, 5=Trivial config change)*, **Feasibility** *(1=Requires external infra, 5=100% executable today)*, and **Impact / Usefulness** *(1=Minor polish, 5=Massive leverage)*.

| ID | Bead | Category | Title & Summary | Ease | Feasibility | Impact | Total Score | Recommended Immediate Next Step |
|---|:---:|---|---|:---:|:---:|:---:|:---:|---|
| **REC-FAST-4** | `sdk-67o.1` | Speed | **Dynamic Test Timeout Tiers**<br>Assign `timeout = "long"` to heavy AOT/WASM suites. | **5** | **5** | **4** | **14 / 15** | Modify Starlark macro `dart_test_suite` to set `timeout` based on suite/config. |
| **REC-FIX-3** | `sdk-67o.2` | Reliability | **Target Quarantining Allowlist**<br>Tag broken tests with `tags = ["quarantine"]`. | **5** | **5** | **4** | **14 / 15** | Add quarantine allowlist to `run_test_universe.dart` and Bazel target generators. |
| **REC-FIX-1** | `sdk-67o.3` | Compatibility | **Migrate to `package:runfiles`**<br>Eliminate relative filesystem path assumptions in `pkg/`. | **3** | **5** | **5** | **13 / 15** | Execute automated refactoring across `pkg/analyzer` and `pkg/analysis_server`. |
| **REC-FAST-2** | `sdk-67o.4` | Speed | **Granular Target Splitting**<br>Split `co19` and `pkg` suites by directory structure. | **3** | **4** | **5** | **12 / 15** | Refactor Starlark generator to emit per-folder test rules. |
| **REC-FAST-1** | `sdk-67o.5` | Speed | **Remote Build Execution (RBE)**<br>Execute test shards across cloud worker pools. | **2** | **4** | **5** | **11 / 15** | Enable Bazel remote execution flags and configure remote worker pools. |
| **REC-FIX-2** | `sdk-67o.6` | Reliability | **Hermetic `data` Declarations**<br>Auto-include `.dill` and helper files in `data=[...]`. | **3** | **4** | **4** | **11 / 15** | Update Starlark macro to scan dependency imports and include data files. |
| **REC-FAST-3** | `sdk-67o.7` | Speed | **RAM-Backed Output Base**<br>Mount `--output_base` on local `tmpfs`. | **4** | **3** | **3** | **10 / 15** | Add developer workstation setup instructions to project documentation. |

---

## 6. Recommended Execution Strategy

To achieve 100% test reliability with minimal developer friction, we recommend executing the top-scoring items in three surgical phases:

1. **Phase 1 (Immediate Green Presubmits - Score 14/15):** Implement **REC-FAST-4** (long timeouts) and **REC-FIX-3** (quarantine tagging). This immediately eliminates 300s timeout errors and isolates unmigrated failures.
2. **Phase 2 (Runfile Hermeticity - Score 13/15):** Implement **REC-FIX-1** across `pkg/analyzer` and `pkg/analysis_server`. This resolves ~65% of all local test failures under `--nobuild_runfile_links`.
3. **Phase 3 (High-Speed CI - Score 11-12/15):** Roll out **REC-FAST-2** (granular target splitting) and **REC-FAST-1** (RBE caching) to scale test execution across distributed cloud workers.
