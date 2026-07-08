# Dart SDK Bazel Test Completion Matrix & Gap Analysis

* **Generated At:** `2026-07-07T23:56:03.632231Z`
* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)
* **Watchdog Watch Interval:** `300s` (5 minutes)

---

## 🌌 Active Starlark Test Universe (By Configuration)

| Configuration | Status | Total Targets | Passed | Failed |
|---|---|---|---|---|
| `analyzer_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `cfe_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `dart2js_chrome_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `dart2js_firefox_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `ddc_chrome_release` | ❌ FAILED (Active) | 156 | 121 | 35 |
| `vm_aot_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_aot_release_simarm` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_aot_release_simarm64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_aot_release_simriscv64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_debug` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_product` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release_simarm` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release_simarm64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `vm_release_simriscv64` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_asserts` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_chrome_asserts` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_chrome_optimized` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_chrome_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_firefox_asserts` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_firefox_release` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_optimized` | ❄️ Skipped (Active) | 0 | 0 | 0 |
| `wasm_release` | ❌ FAILED (Active) | 158 | 131 | 27 |

**Universe Totals:** `314` targets (`252` passed, `62` failed)

---

## 📦 Starlark Test Completion Matrix (Suite × Configuration)

| Suite | `vm_release` | `wasm_release` | `cfe_release` | `Other Configs` | Total Targets |
|---|---|---|---|---|---|
| **`co19`** | ❄️ | ❌ 1 / 5 | ❄️ | ❌ 1 / 5 | **10** |
| **`corelib`** | ❄️ | ❌ 5 / 8 | ❄️ | ❌ 5 / 10 | **18** |
| **`dartdevc`** | ❄️ | ❄️ | ❄️ | ❌ 3 / 4 | **4** |
| **`ffi`** | ❄️ | ❄️ | ❄️ | ❄️ | **0** |
| **`language`** | ❄️ | ❌ 121 / 138 | ❄️ | ❌ 112 / 137 | **275** |
| **`pkg`** | ❄️ | ❄️ | ❄️ | ❄️ | **0** |
| **`runtime`** | ❄️ | ❄️ | ❄️ | ❄️ | **0** |
| **`standalone`** | ❄️ | ❄️ | ❄️ | ❄️ | **0** |
| **`tests`** | ❄️ | ❌ 2 / 5 | ❄️ | ❄️ | **5** |
| **`web/wasm`** | ❄️ | ✅ 2 / 2 | ❄️ | ❄️ | **2** |

---

## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)

The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:

* 🔴 `tests/benchmarks` *(Tracked by [`sdk-245`](./BACKLOG.md#sdk-245))*
* 🔴 `tests/hot_reload` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/modular` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/web (HTML)` *(Tracked by [`sdk-wax`](./BACKLOG.md#sdk-wax))*

---

## 🩹 Failing Targets Punch List

### `ddc_chrome_release` (35 failures)
```text
@@+dart_tests_extension+dart_tests//language/operator:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//corelib/convert:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//corelib/math:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/async_star:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/deferred:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/await:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/const:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/const_functions:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/constructor:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//corelib/async:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/number:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//dartdevc/cast_error:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//corelib/html:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/nosuchmethod_forwarding:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/async:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/control_flow_collections:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//corelib/js:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/stack_trace:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//co19/Language:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/mixin:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/canonicalize:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/nnbd:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/mixin_legacy:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//co19/TypeSystem:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/mixin_declaration:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/identity:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/least_upper_bound:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//co19/LibTest:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/anonymous_methods:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/unsorted:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/closure:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/optimize:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//co19/LanguageFeatures:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/regress:tests_ddc_chrome_release
@@+dart_tests_extension+dart_tests//language/call:tests_ddc_chrome_release
```

### `wasm_release` (27 failures)
```text
@@+dart_tests_extension+dart_tests//corelib/js:tests_wasm_release
@@+dart_tests_extension+dart_tests//co19/TypeSystem:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/stack_trace:tests_wasm_release
@@+dart_tests_extension+dart_tests//tests/web/wasm/simd:tests_wasm_release
@@+dart_tests_extension+dart_tests//corelib/async:tests_wasm_release
@@+dart_tests_extension+dart_tests//tests/web/wasm:tests_wasm_release
@@+dart_tests_extension+dart_tests//corelib/math:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/static:tests_wasm_release
@@+dart_tests_extension+dart_tests//tests/web/wasm/ffi:tests_wasm_release
@@+dart_tests_extension+dart_tests//co19/LibTest:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/exception:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/enum:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/main:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/const:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/nnbd:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/async:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/string:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/deferred:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/variance:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/regress:tests_wasm_release
@@+dart_tests_extension+dart_tests//co19/LanguageFeatures:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/call:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/mixin_declaration:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/unsorted:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/least_upper_bound:tests_wasm_release
@@+dart_tests_extension+dart_tests//language/constructor:tests_wasm_release
@@+dart_tests_extension+dart_tests//co19/Language:tests_wasm_release
```

