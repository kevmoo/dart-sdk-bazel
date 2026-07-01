# Dart SDK Bazel Test Completion Matrix & Gap Analysis

* **Generated At:** `2026-07-01T09:06:21.540312Z`
* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)
* **Watchdog Watch Interval:** `300s` (5 minutes)

---

## 🌌 Active Starlark Test Universe (By Configuration)

| Configuration | Status | Total Targets | Passed | Failed |
|---|---|---|---|---|
| `analyzer_release` | ✅ PASSED (Active) | 6 | 6 | 0 |
| `cfe_release` | ✅ PASSED (Active) | 160 | 160 | 0 |
| `dart2js_chrome_release` | ✅ PASSED (Active) | 155 | 155 | 0 |
| `dart2js_firefox_release` | ✅ PASSED (Active) | 150 | 150 | 0 |
| `ddc_chrome_release` | ✅ PASSED (Active) | 156 | 156 | 0 |
| `vm_aot_release` | ✅ PASSED (Active) | 609 | 609 | 0 |
| `vm_aot_release_simarm` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_aot_release_simarm64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_aot_release_simriscv64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_debug` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `vm_product` | ✅ PASSED (Active) | 206 | 206 | 0 |
| `vm_release` | ✅ PASSED (Active) | 2964 | 2964 | 0 |
| `vm_release_simarm` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_release_simarm64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `vm_release_simriscv64` | ❄️ Skipped (Skipped / Filtered Out) | 0 | 0 | 0 |
| `wasm_asserts` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_chrome_asserts` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_chrome_optimized` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_chrome_release` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_firefox_asserts` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_firefox_release` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_optimized` | ✅ PASSED (Active) | 153 | 153 | 0 |
| `wasm_release` | ✅ PASSED (Active) | 158 | 158 | 0 |

**Universe Totals:** `5788` targets (`5788` passed, `0` failed)

---

## 📦 Starlark Test Completion Matrix (Suite × Configuration)

| Suite | `vm_release` | `wasm_release` | `cfe_release` | `Other Configs` | Total Targets |
|---|---|---|---|---|---|
| **`co19`** | ✅ 6 / 6 | ✅ 5 / 5 | ❄️ | ✅ 21 / 21 | **32** |
| **`corelib`** | ✅ 32 / 32 | ✅ 8 / 8 | ✅ 8 / 8 | ✅ 130 / 130 | **178** |
| **`dartdevc`** | ❄️ | ❄️ | ❄️ | ✅ 4 / 4 | **4** |
| **`ffi`** | ✅ 53 / 53 | ❄️ | ✅ 3 / 3 | ✅ 53 / 53 | **109** |
| **`language`** | ✅ 544 / 544 | ✅ 138 / 138 | ✅ 142 / 142 | ✅ 2197 / 2197 | **3021** |
| **`pkg`** | ✅ 2293 / 2293 | ❄️ | ❄️ | ❄️ | **2293** |
| **`standalone`** | ✅ 36 / 36 | ❄️ | ✅ 7 / 7 | ✅ 50 / 50 | **93** |
| **`tests`** | ❄️ | ✅ 5 / 5 | ❄️ | ✅ 37 / 37 | **42** |
| **`web/wasm`** | ❄️ | ✅ 2 / 2 | ❄️ | ✅ 14 / 14 | **16** |

---

## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)

The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:

* 🔴 `tests/benchmarks` *(Tracked by [`sdk-245`](./BACKLOG.md#sdk-245))*
* 🔴 `tests/hot_reload` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/modular` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/runtime (C++ unit/service)` *(Tracked by [`sdk-4z5`](./BACKLOG.md#sdk-4z5))*
* 🔴 `tests/web (HTML)` *(Tracked by [`sdk-wax`](./BACKLOG.md#sdk-wax))*

---

## 🩹 Failing Targets Punch List

🎉 *Zero test failures recorded in active Starlark universe!*
