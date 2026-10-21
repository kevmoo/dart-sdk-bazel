# Dart SDK Bazel Performance & Correctness Evaluation Runbook

This document specifies the standard verification suite and benchmarking methodology for validating toolchain changes, caching optimizations, and performance improvements across Linux (`x86_64`) and macOS (Apple Silicon). For the latest recorded benchmark runs and architectural analysis (`2026-10-20`, `capstone-2026-10` on `Bazel 9.3.0`), see [FINAL_REPORT.md](FINAL_REPORT.md).

---

## 1. Environment & Prerequisites

### Tooling Requirements

- **Bazel version alignment is enforced automatically through `bazelisk`.**
  - Pinned to `9.3.0` in [`.bazelversion`](../../.bazelversion).
- **Clean Linux builds hydrate third-party inputs directly without `gclient`.**
  - Fetched from `DEPS` and verified against SHA-256 lockfile [deps_hashes.bzl](../../tools/bazel/deps_hashes.bzl), while `gclient` remains supported when syncing a full local checkout.
- **Shared Linux workstations require explicit CPU, memory, and worker caps.**
  - Always pass `--config=cloudtop-safe` (`--jobs=8`, `24 GiB` RAM cap, `--worker_max_instances=2`) on Cloudtop machines to prevent memory pressure or daemon OOM kills.

### Pre-Flight Synchronization

Verify repository hygiene, archive SHA-256 lockfile alignment, and full presubmit checks before running evaluations:

```bash
cd ~/github/dart-sdk/bazel/main/sdk

# 1. Verify offline SHA-256 lockfile matches DEPS (<0.15s, zero network calls)
python3 tools/bazel/sync_deps_hashes.py --check

# 2. Run full Bazel presubmit gate (buildifier, 1:1 upstream allowlist, rule tests, analysis)
./tools/bazel/presubmit.sh
```

---

## 2. Platform Compatibility Checks

Run a non-building dry-run analysis to verify `.bazelrc` options on your host platform:

```bash
bazel build --config=cloudtop-safe //tools/bazel/dart:test_hello --nobuild
```

### Platform-Specific Notes

- **Linux hosts enable RAM-backed sandboxing, fast linking, and Split DWARF.**
  - Scoped under `build:linux` via `common --enable_platform_specific_config`: `--sandbox_base=/dev/shm` (RAM disk), `--linkopt=-fuse-ld=lld` (LLD linker), and `--fission=yes` (Split DWARF `.dwo` files).
- **Apple Silicon hosts skip Linux-only flags and autoconfigure the host Xcode toolchain.**
  - `/dev/shm`, `lld`, and `--fission=yes` are omitted automatically on macOS so dry-run analysis and host C++ rules configure without error.

---

## 3. Correctness Verification Suite

Execute the following targets to verify compiler and toolchain integrity:

### Step 1: Dart Persistent Worker Execution

Compile and execute a test Dart application:

```bash
bazel run --config=cloudtop-safe //tools/bazel/dart:test_hello
```

_Expected Output_: `Hello from bazel run! verbose=false`

### Step 2: Bazel Tooling & Wrapper Unit Tests

Run the Bazel Starlark/Dart rule tests and Python wrapper unit tests:

```bash
bazel test --config=cloudtop-safe //tools/bazel/...
python3 tools/test_wrapper_test.py
```

_Expected Output_: All targets `PASSED` (`19/19` tests in `test_wrapper_test.py`).

### Step 3: Kernel Snapshots & AOT Binaries

Build bootstrap and release snapshots (verifying persistent worker compilation):

```bash
bazel build --config=cloudtop-safe \
            //utils/gen_kernel:bootstrap_gen_kernel \
            //utils/gen_kernel:gen_kernel \
            //utils/gen_kernel:gen_kernel_product
```

_Expected Output_: Build completed successfully. Process summary includes `worker` processes.

### Step 4: Dart VM & SDK Layout Assembly

Build the standalone Dart runtime, snapshot generator, and full SDK layout:

```bash
bazel build --config=cloudtop-safe //runtime/bin:dartvm //runtime/bin:dart //runtime/bin:gen_snapshot //sdk:create_sdk
```

_Expected Output_: Build completed successfully (`./bazel-bin/sdk/dart-sdk/bin/dart --version` prints `3.15.0-edge`).

---

## 4. Performance Benchmarks

When reporting benchmarks, always provide:

1. **Elapsed Time & Critical Path** (from the `INFO: Elapsed time:` line).
2. **Process Summary** (the `INFO: N processes:` line showing `worker`, `local`, `linux-sandbox`, and cache hit distributions).

> [!IMPORTANT]
>
> **Mutations must be unique per run, and standalone worker comparisons must use `DartCompileDill`.** Bazel keys the action cache, disk cache, and remote cache on input content; use unique timestamps per iteration so cached outputs never mask real work. When comparing resident workers against standalone execution, pass `--strategy=DartCompileDill=standalone` (the mnemonic emitted by `dart_compile_dill` in [defs.bzl](../../tools/bazel/dart/defs.bzl); `--strategy=DartKernel=standalone` is a silent no-op).

---

### Benchmark A: Incremental Dart Kernel Compilation (`1 worker` vs. `--strategy=DartCompileDill=standalone`)

Measures whole-program CFE kernel compilation latency with and without resident JSON workers:

```bash
# 1. Warm the build and start persistent worker
bazel build --config=cloudtop-safe //utils/analysis_server:analysis_server_dill

# 2. Mutate a leaf file in pkg/analyzer (unique per run)
echo "// bench $(date +%s%N)" >> pkg/analyzer/lib/dart/analysis/analysis_context.dart

# 3. Measure resident worker compile (or add --strategy=DartCompileDill=standalone for standalone arm)
time bazel build --config=cloudtop-safe //utils/analysis_server:analysis_server_dill

# 4. Clean up mutation
git checkout -- pkg/analyzer/lib/dart/analysis/analysis_context.dart
```

_Verification Invariant_: `INFO: N processes:` reports `1 worker` on the worker arm (`28.121s` median; `39.419s` cold `1.16 GiB` RSS fault-in Run 1) and `1 local` on the `--strategy=DartCompileDill=standalone` arm (`27.157s` median; both execute `dartaotruntime bootstrap_gen_kernel.snapshot`).

---

### Benchmark B: Incremental C++ Edit-Link Cycle (`lld` + Split DWARF)

Measures C++ single-object compilation and `lld --fission` relink latency:

```bash
# 1. Warm the VM binary build
bazel build --config=cloudtop-safe //runtime/bin:dartvm

# 2. Mutate a C++ leaf source file (changes object bytes; unique per run)
echo "int dart_bench_marker_$(date +%s%N) = 1;" >> runtime/vm/double_conversion.cc

# 3. Measure incremental compile + link time
time bazel build --config=cloudtop-safe //runtime/bin:dartvm

# 4. Clean up mutation
git checkout -- runtime/vm/double_conversion.cc
```

_Verification Invariant_: `INFO: N processes:` reports sandboxed compile/archive/link actions (`3.510s` median vs. `267.73s` clean build = `76.3x` speedup).

---

### Benchmark C: Clean VM Build (Cold Compiler Throughput)

Measures uncached local compilation throughput across all VM source files without disk or remote cache hits:

```bash
bazel clean
time bazel build --config=cloudtop-safe //runtime/bin:dartvm --remote_cache= --disk_cache=
```

_Verification Invariant_: Process summary shows `linux-sandbox` actions with zero cache hits (`267.73s` mean across `2,085` processes).

---

## 5. Post-Benchmark Hygiene

After executing the benchmark suite, verify that the git working tree is clean:

```bash
git status --short
```

---

## 6. Feedback & Reporting Template

```markdown
### Environment

- OS: Linux x86_64 (64 vCPU AMD EPYC 7B13, `--config=cloudtop-safe`)
- Bazel Version: 9.3.0

### Correctness Suite

- [x] Platform dry-run: Pass
- [x] //tools/bazel/dart:test_hello: Pass
- [x] //tools/bazel/... & tools/test_wrapper_test.py: Pass
- [x] //utils/gen_kernel snapshots: Pass
- [x] //runtime/bin:dartvm & //sdk:create_sdk: Pass

### Performance Results (Recorded 2026-10-20 Baseline)

- **Warm Presubmit (`./tools/bazel/presubmit.sh`)**: `27.00s` median (`23.21s` latest; down from `300.51s` mean on Bazel 9.1.1 = `11.1x` speedup)
- **Null Build (`//runtime/bin:dartvm //sdk:create_sdk`)**: `0.693s` median (`1,353x` faster than `937.6s` cold SDK build)
- **Benchmark A (`analysis_server_dill` worker vs standalone)**: `28.121s` worker median vs `27.157s` standalone median (`0.97x` parity; stateless whole-program CFE pass)
- **Benchmark B (`double_conversion.cc` -> `dartvm` incremental link)**: `3.510s` median (`76.3x` faster than `267.73s` clean VM build)
- **Benchmark C (`dartvm` clean uncached build)**: `267.73s` mean (`2,085` processes)
```
