# Fork Delta Cleanup & Surgical Refactoring Disposition (`MERGE_CLEANUP_CANDIDATES.md`)

While `UPSTREAM_CANDIDATES.md` tracks bug fixes and general enhancements that can be proposed independently to upstream `dart-lang/sdk`, this document tracks **fork-delta reduction, hermeticity hardening, and surgical decoupling** across the Bazel migration branch relative to `upstream-sdk/main`.

---

## 📊 2026-10-20 Disposition Summary (`capstone-2026-10` vs `upstream-sdk/main` `cde64ed532a`)

| Item | Target File(s) | Status | Resolution & Measured Impact |
| :--- | :--- | :--- | :--- |
| **Cat. 1a: Analyzer stylistic drift** | `pkg/analyzer/lib/src/utilities/extensions/flutter.dart` | ✅ Completed (`#79`) | Reverted pure stylistic diffs to `0` upstream diff lines. |
| **Cat. 1b: Merge/formatting/VERSION drift** | `tools/VERSION`, `pkg/test_runner/lib/src/android.dart`, `third_party/.gitignore`, `pkg/front_end/...`, `runtime/bin/snapshot_empty.cc`, `runtime/bin/snapshots.md`, `tools/utils.py` | ✅ Completed (`2e50d4e84ca`, `66fee9687d0`) | Reverted `8` upstream-divergent files to `0` diff, deleted non-upstream `runtime/bin/snapshots.md`, and stripped non-Bazel yapf churn in `tools/utils.py`. |
| **Cat. 2: Extract `resolveTestResource`** | `pkg/_fe_analyzer_shared/lib/src/testing/{id_testing,runfiles}.dart`, `pkg/_fe_analyzer_shared/pubspec.yaml`, `pkg/testing/lib/testing.dart` | ✅ Completed (`#82`, `0a06e3804a4`) | Relocated zero-dep `runfiles.dart` into `pkg/_fe_analyzer_shared`, shrinking `id_testing.dart` to `+2/-0` lines and restoring `pkg/_fe_analyzer_shared/pubspec.yaml` and `pkg/testing/lib/testing.dart` to `0` upstream diff (`112 -> 99` modified upstream files total). |
| **Cat. 3: Remove synchronous `bazel info` shell-out** | `pkg/test_runner/lib/src/options.dart` | ✅ Completed (`#80`) | Replaced `Process.runSync('bazel', ['info', 'bazel-bin'])` during option parsing with `$BAZEL_BIN` lookup populated once by wrapper scripts. |
| **Cat. 4: `runtime/BUILD.gn` header/lib modularization** | `runtime/BUILD.gn`, `runtime/include/BUILD.gn`, `runtime/lib/BUILD.gn` | 📌 Tracked in Stage 3 (`UPSTREAM_CANDIDATES.md`) | Genuine standalone GN modularization (`public_api_headers` + `runtime/lib:libdart_lib`) suitable for an independent upstream CL rather than inline churn. |
| **Cat. 5a: Modularize `PRESUBMIT.py` & `tools/build.py`** | `PRESUBMIT.py`, `tools/build.py`, `tools/bazel/{presubmit_checks,build_wrapper}.py` | ✅ Completed (`#81`, `8c2a589db55`) | Extracted hooks into `tools/bazel/`; unified `IsAutoExemptOverlayPath` and bidirectional `1:1` allowlist enforcement (`111` exact entries, `0` stale entries) in `tools/bazel/presubmit.sh`. |
| **Cat. 5b: Modularize `tools/test.py` (`--bazel`)** | `tools/test.py`, `tools/bazel/test_wrapper.py`, `tools/test_wrapper_test.py` | ✅ Completed (`68e0b10743e`) | Extracted `EnsureBazelBinEnv`, `ResolveConfig`, and `TestWithBazel` into `tools/bazel/test_wrapper.py`, shrinking `tools/test.py` from `+331/-0` lines down to `+8/-0` lines (`97.6%` diff reduction) and fixing `@dart_tests//pkg/<pkg>/test:...` resolution (`19/19` unit tests). |
| **Cat. 6: CI workflows, Bazel `9.3.0`, & single-daemon presubmit** | `.bazelversion`, `.github/workflows/{bazel,nightly,buildifier}.yml`, `tools/bazel/presubmit.sh` | ✅ Completed (`8c2a589db55`, `9d446eb94ca`) | Fixed `dorny/paths-filter` `some-with-excludes` skip, added fork-safe non-GCP cache fallback in `nightly.yml`, pinned `buildifier` `v8.2.1` SHA-256, unified single local Bazel server, and upgraded `.bazelversion` `9.1.1 -> 9.3.0` (`#29889`, `#30564`, `#30470`), cutting warm `./tools/bazel/presubmit.sh` from `301.7s` to `28.4s` (`10.6x` speedup). |
| **Cat. 7: Hermetic `DEPS` archive SHA-256 lockfile** | `tools/bazel/{deps_hashes.bzl,sync_deps_hashes.py,third_party.bzl}`, `build/toolchain/linux/clang_repo.bzl` | ✅ Completed (`9d446eb94ca`) | Pinned SHA-256 digests across all `23` deterministic CIPD, browser, and GitHub archive URLs from `DEPS` with `<0.15s` offline presubmit verification, enabling content-addressed `--repository_cache` reuse across clean workspaces and CI runs. |

---

## 🎯 Remaining Upstreamable Candidates (Stage 3 Handoff)

All zero-behavior fork drift and multi-hundred-line inline wrapper blocks in upstream scripts have been eliminated (`112 -> 99` modified upstream files; `tools/test.py` reduced from `+331/-0` to `+8/-0` lines). Remaining non-Bazel upstream modifications fall into two clean buckets documented in `docs/bazel-migration/UPSTREAM_CANDIDATES.md` and `docs/bazel-migration/FINAL_REPORT.md`:

1. **Standalone upstreamable improvements** (hermetic relative depfiles, `tools/make_version.py` explicit version input flags that also unblock Siso's `dart/create_snapshot_entry` local bailout, and `runtime/{include,lib}/BUILD.gn` modular targets).
2. **Irreducible sandbox/runfiles hooks** (`RUNFILES_DIR` / `TEST_SRCDIR` discovery in test harnesses and embedder/standalone IO tests when running inside hermetic Linux sandboxes).
