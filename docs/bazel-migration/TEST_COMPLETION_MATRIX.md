# Dart SDK Bazel Test Completion Matrix & Gap Analysis

* **Generated At:** `2026-07-05T22:25:13.536839Z`
* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)
* **Watchdog Watch Interval:** `300s` (5 minutes)

> [!WARNING]
> **DRY RUN MODE**: Targets were discovered but **NOT EXECUTED**. Pass `--run` to `test_runner.sh` to execute tests and collect real pass/fail results.

---

## 🌌 Active Starlark Test Universe (By Configuration)

| Configuration | Status | Total Targets | Passed | Failed |
|---|---|---|---|---|
| `analyzer_release` | 🔍 Dry Run (Unexecuted) | 6 | 0 | 0 |
| `cfe_release` | 🔍 Dry Run (Unexecuted) | 160 | 0 | 0 |
| `dart2js_chrome_release` | 🔍 Dry Run (Unexecuted) | 155 | 0 | 0 |
| `dart2js_firefox_release` | 🔍 Dry Run (Unexecuted) | 150 | 0 | 0 |
| `ddc_chrome_release` | 🔍 Dry Run (Unexecuted) | 156 | 0 | 0 |
| `vm_aot_release` | 🔍 Dry Run (Unexecuted) | 156 | 0 | 0 |
| `vm_aot_release_simarm` | 🔍 Dry Run (Unexecuted) | 151 | 0 | 0 |
| `vm_aot_release_simarm64` | 🔍 Dry Run (Unexecuted) | 151 | 0 | 0 |
| `vm_aot_release_simriscv64` | 🔍 Dry Run (Unexecuted) | 151 | 0 | 0 |
| `vm_debug` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `vm_product` | 🔍 Dry Run (Unexecuted) | 206 | 0 | 0 |
| `vm_release` | 🔍 Dry Run (Unexecuted) | 2512 | 0 | 0 |
| `vm_release_simarm` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `vm_release_simarm64` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `vm_release_simriscv64` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_asserts` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_chrome_asserts` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_chrome_optimized` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_chrome_release` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_firefox_asserts` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_firefox_release` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_optimized` | 🔍 Dry Run (Unexecuted) | 153 | 0 | 0 |
| `wasm_release` | 🔍 Dry Run (Unexecuted) | 158 | 0 | 0 |

**Universe Totals:** `5795` targets discovered *(Unexecuted — Dry Run)*

---

## 📦 Starlark Test Completion Matrix (Suite × Configuration)

| Suite | `vm_release` | `wasm_release` | `cfe_release` | `Other Configs` | Total Targets |
|---|---|---|---|---|---|
| **`co19`** | 🔍 6 | 🔍 5 | ❄️ | 🔍 21 | **32** |
| **`corelib`** | 🔍 8 | 🔍 8 | 🔍 8 | 🔍 154 | **178** |
| **`dartdevc`** | ❄️ | ❄️ | ❄️ | 🔍 4 | **4** |
| **`ffi`** | 🔍 53 | ❄️ | 🔍 3 | 🔍 53 | **109** |
| **`language`** | 🔍 136 | 🔍 138 | 🔍 142 | 🔍 2605 | **3021** |
| **`pkg`** | 🔍 2295 | ❄️ | ❄️ | ❄️ | **2295** |
| **`runtime`** | 🔍 5 | ❄️ | ❄️ | ❄️ | **5** |
| **`standalone`** | 🔍 9 | ❄️ | 🔍 7 | 🔍 77 | **93** |
| **`tests`** | ❄️ | 🔍 5 | ❄️ | 🔍 37 | **42** |
| **`web/wasm`** | ❄️ | 🔍 2 | ❄️ | 🔍 14 | **16** |

---

## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)

The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:

* 🔴 `tests/benchmarks` *(Tracked by [`sdk-245`](./BACKLOG.md#sdk-245))*
* 🔴 `tests/hot_reload` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/modular` *(Tracked by [`sdk-2w0`](./BACKLOG.md#sdk-2w0))*
* 🔴 `tests/web (HTML)` *(Tracked by [`sdk-wax`](./BACKLOG.md#sdk-wax))*

---

## 🩹 Failing Targets Punch List

🔍 *Dry run executed — target discovery complete. Run with `--run` to execute tests and collect failure results.*
