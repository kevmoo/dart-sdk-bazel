# Dart SDK Bazel Performance & Correctness Evaluation Runbook

This document specifies the standard verification suite and benchmarking methodology for validating toolchain changes, caching optimizations, and performance improvements across Linux (x86_64) and macOS (Apple Silicon).

---

## 1. Environment & Prerequisites

### Tooling Requirements
- **Bazel Version**: `9.1.1` (managed via `bazelisk`).
- **Depot Tools**: `gclient` must be available in `$PATH`.

### Pre-Flight Synchronization
Always sync both the git tree and the pinned `DEPS` dependencies (CIPD toolchains and third-party packages) before running evaluations:

```bash
cd ~/github/dart-sdk/bazel/main/sdk

# 1. Update git repository
git checkout main
git pull origin main

# 2. Synchronize external third_party repositories and CIPD prebuilts
gclient sync -D --no-history
```

---

## 2. Platform Compatibility Checks

Run a non-building dry-run analysis to verify `.bazelrc` options on your host platform:

```bash
bazel build //tools/bazel/dart:test_hello --nobuild
```

### Platform-Specific Notes:
- **Linux**: Utilizes `--sandbox_base=/dev/shm` (RAM disk), `--linkopt=-fuse-ld=lld` (LLD linker), and `--fission=yes` (Split DWARF `.dwo` files).
- **macOS (Darwin)**:
  - `--sandbox_base=/dev/shm` is ignored by Bazel on macOS without error.
  - `-fuse-ld=lld` is supported by the in-tree CIPD LLVM Clang toolchain.
  - `--fission=yes` is ignored gracefully for Mach-O binaries.

---

## 3. Correctness Verification Suite

Execute the following targets to verify compiler and toolchain integrity:

### Step 1: Dart Persistent Worker Execution
Compile and execute a test Dart application:
```bash
bazel run //tools/bazel/dart:test_hello
```
*Expected Output*: `Hello from bazel run! verbose=false`

### Step 2: Dart Unit Tests
Run the Bazel Dart rules test suite:
```bash
bazel test //tools/bazel/dart:suite_paths_test
```
*Expected Output*: `//tools/bazel/dart:suite_paths_test PASSED`

### Step 3: Kernel Snapshots & AOT Binaries
Build bootstrap and release snapshots (verifying persistent worker compilation):
```bash
bazel build //utils/gen_kernel:bootstrap_gen_kernel \
            //utils/gen_kernel:gen_kernel \
            //utils/gen_kernel:gen_kernel_product
```
*Expected Output*: Build completed successfully. Process summary includes `worker` processes.

### Step 4: Dart VM & Generator Binaries
Build the standalone Dart runtime and AOT snapshot generator:
```bash
bazel build //runtime/bin:dart //runtime/bin:gen_snapshot
```
*Expected Output*: Build completed successfully with zero compilation or linker errors.

---

## 4. Performance Benchmarks

When reporting benchmarks, always provide:
1. **Elapsed Time & Critical Path** (from the `INFO: Elapsed time:` line).
2. **Process Summary** (the `INFO: N processes:` line showing worker, sandbox, and cache hit distributions).

---

### Benchmark A: Incremental Dart Kernel Compilation (Warm CFE Worker)
Measures persistent worker JIT throughput when recompiling a leaf Dart library in a heavy dependency closure.

```bash
# 1. Warm the build and start persistent worker
bazel build //utils/analysis_server:analysis_server_dill

# 2. Mutate a leaf file in pkg/analyzer
echo "// bench" >> pkg/analyzer/lib/dart/analysis/analysis_context.dart

# 3. Measure incremental compilation time
time bazel build //utils/analysis_server:analysis_server_dill

# 4. Clean up mutation
git checkout -- pkg/analyzer/lib/dart/analysis/analysis_context.dart
```

*Verification Invariant*: The `INFO: N processes:` summary MUST contain `N worker` (e.g. `3 processes: 1 internal, 1 linux-sandbox, 1 worker`).

---

### Benchmark B: Incremental C++ Edit-Link Cycle
Measures C++ incremental compilation and link latency with Split DWARF and fast linker settings.

```bash
# 1. Warm the VM binary build
bazel build //runtime/bin:dart

# 2. Mutate a C++ leaf source file (modifying code to change object bytes)
echo "int dart_bench_marker_var = 1;" >> runtime/vm/double_conversion.cc

# 3. Measure incremental compile + link time
time bazel build //runtime/bin:dart

# 4. Clean up mutation
git checkout -- runtime/vm/double_conversion.cc
```

*Verification Invariant*: The `INFO: N processes:` summary MUST report >= 3 sandboxed actions (compile -> archive -> link).

---

### Benchmark C: Clean VM Build (Cold Compiler Throughput)
Measures un-cached local compilation throughput across all VM source files without disk or remote cache hits.

```bash
# 1. Purge local output tree
bazel clean

# 2. Measure cold build bypassing disk cache and remote cache
time bazel build //runtime/bin:dart //runtime/bin:gen_snapshot --remote_cache= --disk_cache=
```

*Verification Invariant*: The process summary must read `1384 processes: ... N linux-sandbox` (or `darwin-sandbox`) with **zero** `cache hit` terms.

---

## 5. Post-Benchmark Hygiene

After executing the benchmark suite, verify that the git working tree is clean:

```bash
git status --short
```
*Expected Output*: Empty (no modified or untracked files). If stray files exist, clean them via `git checkout -- .` and `git clean -fd`.

---

## 6. Feedback & Reporting Template

Post benchmark metrics and observations using the following Markdown schema:

```markdown
### Environment
- OS: [e.g. Ubuntu 24.04 (AMD Ryzen 9 7950X, 64GB) / macOS Sonoma 14.5 (Apple M3 Max, 36GB)]
- Bazel Version: 9.1.1

### Correctness Suite
- [ ] Platform dry-run: Pass
- [ ] //tools/bazel/dart:test_hello: Pass
- [ ] //tools/bazel/dart:suite_paths_test: Pass
- [ ] //utils/gen_kernel snapshots: Pass
- [ ] //runtime/bin:dart VM build: Pass

### Performance Results
- **Benchmark A (Incremental Dart compile)**: `X.XXs` elapsed (Critical Path: `X.XXs`)
  - Processes: `INFO: 3 processes: 1 internal, 1 linux-sandbox, 1 worker.`
- **Benchmark B (Incremental C++ edit-link)**: `X.XXs` elapsed (Critical Path: `X.XXs`)
  - Processes: `INFO: 3 processes: 3 linux-sandbox.`
- **Benchmark C (Clean VM build - no cache)**: `X.XXs` elapsed (Critical Path: `X.XXs`)
  - Processes: `INFO: 1384 processes: 7 internal, 1377 linux-sandbox.`

### Notes / Platform Anomalies
- [Observations, flags adjusted, or warnings encountered]
```
