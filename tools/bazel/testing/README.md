# Dart SDK Bazel Test Execution & Matrix Reporting Suite

This directory contains the consolidated tools for executing, monitoring, and reporting on the Dart SDK Bazel test universe.

## 📁 Tool Inventory

| Tool | Type | Role |
|---|---|---|
| **`test_runner.sh`** | Bash Shell | **Primary Developer Entrypoint**. Calculates RAM & disk bounds, auto-selects sandbox base (`/dev/shm` vs `/tmp`), limits parallel jobs (`--local_test_jobs`), and delegates to `test_runner.dart`. |
| **`test_runner.dart`** | Dart Script | **Core Test Universe Runner**. Discovers test targets via `bazel query`, chunk-executes tests, parses Build Event Protocol (`test_bep.json`) events for build and test failures, reconciles unaccounted targets, emits live terminal progress, and exports results to `test_matrix_results.json`. |
| **`render_matrix.dart`** | Dart Script | **Matrix Renderer**. Consumes `test_matrix_results.json` and updates the canonical markdown report at `docs/bazel-migration/TEST_COMPLETION_MATRIX.md`. |
| **`resource_health.sh`** | Bash Shell | **Pre-Flight Health Safeguard**. Inspects workstation disk space, cleans `/tmp`, and purges stale worktrees prior to long test runs. |

---

## 🚀 Usage Guide

### Dry Run (Target Discovery & Resource Health Check)
Query targets and inspect resource bounds without running tests:
```bash
tools/bazel/testing/test_runner.sh
```

### Full Test Universe Execution
Safely execute all Bazel test targets with automated job throttling and sandbox management:
```bash
tools/bazel/testing/test_runner.sh --run
```

### Filtered & Quarantined Runs
```bash
# Run specific suites only
tools/bazel/testing/test_runner.sh --run --only-suites=pkg,language

# Skip heavy or flaky suites
tools/bazel/testing/test_runner.sh --run --skip-suites=co19,web/wasm

# Target a specific configuration (e.g. vm_release)
tools/bazel/testing/test_runner.sh --run --only-configs=vm_release

# Override parallel worker job limits
tools/bazel/testing/test_runner.sh --run --jobs=8
```

---

## 📊 Data Formats & Outputs

1. **`test_matrix_results.json`** (`docs/bazel-migration/test_matrix_results.json`):
   - Structured JSON source of truth. Contains pass/fail/total metrics for all configurations and suites, failure target lists, and gap analysis.
2. **`TEST_COMPLETION_MATRIX.md`** (`docs/bazel-migration/TEST_COMPLETION_MATRIX.md`):
   - Human-readable markdown completion matrix report and failing targets punch list.
3. **`PATROL_HEARTBEAT.json`** (`docs/bazel-migration/PATROL_HEARTBEAT.json`):
   - Token-efficient 1-line JSON status file updated periodically during test runs for watchdog monitoring.

---

## 🔄 Backward Compatibility Symlinks

For compatibility with existing workflows and automated agents, symlinks are maintained at:
* `tools/bazel/test_everything.sh` ➡️ `tools/bazel/testing/test_runner.sh`
* `tools/bazel/run_test_universe.dart` ➡️ `tools/bazel/testing/test_runner.dart`
* `docs/bazel-migration/render_test_matrix.dart` ➡️ `tools/bazel/testing/render_matrix.dart`
