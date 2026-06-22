# Dart SDK Bazel Test Completion Matrix & Gap Analysis

* **Generated At:** `2026-06-22T23:56:34.567949Z`
* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)
* **Watchdog Watch Interval:** `300s` (5 minutes)

---

## 🌌 Active Starlark Test Universe (By Configuration)

| Configuration | Status | Total Targets | Passed | Failed |
|---|---|---|---|---|
| `analyzer_release` | ✅ PASSED (Active) | 1 | 1 | 0 |
| `cfe_release` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `dart2js_chrome_release` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `dart2js_firefox_release` | ✅ PASSED (Active) | 3 | 3 | 0 |
| `ddc_chrome_release` | ✅ PASSED (Active) | 3 | 3 | 0 |
| `vm_aot_release` | ✅ PASSED (Active) | 13 | 13 | 0 |
| `vm_aot_release_simarm` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_aot_release_simarm64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_aot_release_simriscv64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_debug` | ✅ PASSED (Active) | 3 | 3 | 0 |
| `vm_product` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `vm_release` | ✅ PASSED (Active) | 2233 | 2233 | 0 |
| `vm_release_simarm` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_release_simarm64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_release_simriscv64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `wasm_asserts` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_chrome_asserts` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_chrome_optimized` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_chrome_release` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_firefox_asserts` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_firefox_release` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_optimized` | ✅ PASSED (Active) | 4 | 4 | 0 |
| `wasm_release` | ✅ PASSED (Active) | 5 | 5 | 0 |

**Universe Totals:** `2301` targets (`2301` passed, `0` failed)

---

## 📦 Starlark Test Completion Matrix (Suite × Configuration)

| Suite | `vm_release` | `vm_debug` | `wasm_release` | `cfe_release` | Total Targets |
|---|---|---|---|---|---|
| **`co19`** | ✅ 1 / 1 | ❄️ | ✅ 1 / 1 | ❄️ | **6** |
| **`corelib`** | ✅ 4 / 4 | ✅ 1 / 1 | ✅ 1 / 1 | ✅ 1 / 1 | **22** |
| **`ffi`** | ✅ 1 / 1 | ❄️ | ❄️ | ✅ 1 / 1 | **3** |
| **`language`** | ✅ 4 / 4 | ✅ 1 / 1 | ✅ 1 / 1 | ✅ 1 / 1 | **22** |
| **`pkg`** | ✅ 2219 / 2219 | ❄️ | ❄️ | ❄️ | **2219** |
| **`standalone`** | ✅ 4 / 4 | ✅ 1 / 1 | ❄️ | ✅ 1 / 1 | **11** |
| **`web/wasm`** | ❄️ | ❄️ | ✅ 2 / 2 | ❄️ | **18** |

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

🎉 *Zero test failures recorded in active Starlark universe!*
