# Dart SDK Bazel Test Completion Matrix & Gap Analysis

* **Generated At:** `2026-06-22T23:21:56.399677Z`
* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)
* **Watchdog Watch Interval:** `300s` (5 minutes)

---

## 🌌 Active Starlark Test Universe

| Configuration | Status | Total Targets | Passed | Failed |
|---|---|---|---|---|
| `analyzer_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `cfe_release` | ❌ FAILED (Active) | 1 | 0 | 1 |
| `dart2js_chrome_release` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `dart2js_firefox_release` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `ddc_chrome_release` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `vm_aot_release` | ✅ PASSED (Active) | 4 | 0 | 0 |
| `vm_aot_release_simarm` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_aot_release_simarm64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_aot_release_simriscv64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_debug` | ❌ FAILED (Active) | 1 | 0 | 1 |
| `vm_product` | ❌ FAILED (Active) | 1 | 0 | 1 |
| `vm_release` | ❌ FAILED (Active) | 4 | 0 | 4 |
| `vm_release_simarm` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release_simarm64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release_simriscv64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_asserts` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_chrome_asserts` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_chrome_optimized` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_chrome_release` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_firefox_asserts` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_firefox_release` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_optimized` | ✅ PASSED (Active) | 1 | 0 | 0 |
| `wasm_release` | ✅ PASSED (Active) | 1 | 0 | 0 |

**Universe Totals:** `22` targets (`0` passed, `7` failed)

---

## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)

The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:

* 🔴 `tests/benchmarks`
* 🔴 `tests/dartdevc`
* 🔴 `tests/fuzzer`
* 🔴 `tests/hot_reload`
* 🔴 `tests/lib`
* 🔴 `tests/modular`
* 🔴 `tests/runtime (C++ unit/service)`
* 🔴 `tests/web (HTML)`

---

## 🩹 Failing Targets Punch List

### `cfe_release` (1 failures)
```text
@@+dart_tests_extension+dart_tests//corelib:tests_cfe_release
```

### `vm_debug` (1 failures)
```text
@@+dart_tests_extension+dart_tests//corelib:tests_vm_debug
```

### `vm_product` (1 failures)
```text
@@+dart_tests_extension+dart_tests//corelib:tests_vm_product
```

### `vm_release` (4 failures)
```text
@@+dart_tests_extension+dart_tests//corelib:tests_vm_release
@@+dart_tests_extension+dart_tests//corelib:tests_vm_release_simarm64
@@+dart_tests_extension+dart_tests//corelib:tests_vm_release_simarm
@@+dart_tests_extension+dart_tests//corelib:tests_vm_release_simriscv64
```

