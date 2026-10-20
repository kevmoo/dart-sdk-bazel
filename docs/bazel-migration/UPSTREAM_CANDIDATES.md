# Non-Bazel Standalone Upstream CL Candidates (`UPSTREAM_CANDIDATES.md`)

> [!NOTE]
>
> Reconciled and stress-tested on `2026-10-20` against `upstream-sdk/main` (`cde64ed532a7227be962ddaca0101dbbd4014852`) on `capstone-2026-10`. Applying a strict upstream reviewer-budget filter narrowed the initial `10` candidates down to **`1` genuine standalone upstream bug fix (`CL-1`)**, **`2` redundant fork diffs reverted to `0` diff (`CL-2` and `CL-3`, reducing modified upstream files from `99` to `97`)**, and **`7` Bazel-sandbox-motivated candidates retained strictly inside the fork (`CL-4`–`CL-10`)**.

---

## 1. Ready-to-Mail Standalone Upstream CL (`CL-1`)

|   ID   | Proposed Gerrit Subject (`<= 70` chars)                             | Upstream File & `cde64ed532a` Line       | Exact Diff (`+X / -Y`) | Churn / Benefit | Target `OWNERS` & Gerrit Footers                                                                               | Standalone Rationale & Upstream Repro                                                                                                                                                                                                           |
| :----: | :------------------------------------------------------------------ | :--------------------------------------- | :--------------------: | :-------------: | :------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CL-1** | `[vm/gn] Fix hyphenated source filename in gen_regexp_special_case` | [runtime/vm/BUILD.gn](../../runtime/vm/BUILD.gn) (`L274`) |       `+1 / -1`        | **`A+` / `A`**  | `tools/OWNERS_VM` (`rmacnak@`, `kustermann@`); `TEST=tools/build.py -m release -a x64 gen_regexp_special_case` | Commit `e443b89f238` rolled V8 Irregexp with hyphenated `runtime/vm/regexp/gen-regexp-special-case.cc` while leaving underscored `regexp/gen_regexp_special_case.cc` at `L274`, causing `python3 tools/build.py -m release -a x64 gen_regexp_special_case` to fail on `upstream-sdk/main`. |

---

## 2. Redundant Fork Diffs Reverted on `capstone-2026-10` (`CL-2` & `CL-3`, `99 -> 97` Modified Files)

- **`CL-3` ([`runtime/vm/compiler/frontend/kernel_translation_helper.cc`](../../runtime/vm/compiler/frontend/kernel_translation_helper.cc)) — Reverted to `0` upstream diff (`Churn: A+ · Benefit: D`)**:
  - `ObfuscationProhibitionsMetadataHelper::ReadMetadata` has a single caller in the entire VM ([`runtime/vm/bootstrap.cc`](../../runtime/vm/bootstrap.cc) `L88-L90`), which is already guarded by `if (isolate_group->obfuscate())`. Our fork only added the redundant inner check in `cf06e0816b3` because of an earlier Bazel `-DPRODUCT` ODR mismatch (`bb3e23235a8`).
- **`CL-2` ([`runtime/platform/assert.h`](../../runtime/platform/assert.h)) — Reverted to `0` upstream diff (`Churn: A · Benefit: C`)**:
  - The `nullptr` guards in `Expect::IsSubstring` and `Expect::IsNotSubstring` were added in PR `#67` (`d4b746a4bde`) before `//runtime/bin:kernel_service_dill_linkable` was linked into `run_vm_tests`. Once `kernel_service_dill_linkable` was linked in that same PR, no C++ unit test passed `nullptr` to `EXPECT_SUBSTRING`.

---

## 3. Bazel-Motivated Candidates Dropped from Upstream Mail Queue (`CL-4`–`CL-10`, Retained in Fork Only)

|    ID     | Candidate Summary                                                        | Files (`+Added / -Removed`) | Churn / Benefit | Why Dropped from Upstream Gerrit Queue (Reviewer-Budget Filter)                                                                                                                                                                                          |
| :-------: | :----------------------------------------------------------------------- | :-------------------------: | :-------------: | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CL-4**  | Declare `// OtherResources=` in `11` standalone tests + `addlatexhash`   |     `12` (`+27 / -5`)       | **`B` / `C-`**  | Upstream `test_suite.dart` only copies `OtherResources` when a compiler is active and the test reads `$TEST_COMPILATION_DIR`; `11` of `12` edits exist solely so `generate_test_targets.dart` populates Bazel `data = [...]` runfiles.                   |
| **CL-5**  | Pass `Platform.packageConfig` in CFE `computeHostDependencies`           |      `1` (`+5 / -0`)        | **`A` / `D`**   | Upstream `GN + Ninja` always runs `compile_platform.dart` inside the SDK checkout where upward `.dart_tool/package_config.json` discovery succeeds; only Bazel's execroot sandbox required an explicit `--packages=` pass-through.                       |
| **CL-6**  | Replace `third_party/flute` input in `wasm2wat_test` & `wasm_read_write` |      `2` (`+8 / -5`)        | **`A` / `D`**   | [`pkg/dart2wasm/docs/build_and_test.md`](../../pkg/dart2wasm/docs/build_and_test.md) (`L19`) documents `"checkout_flute": True` as standard for `dart2wasm` tests, and `self_compile_benchmark.dart` compiles the entire CFE + `dart2wasm` compiler.     |
| **CL-7**  | Copy `OtherResources` from `originPath` and guard `QemuConfig.all`       |      `1` (`+4 / -2`)        | **`A` / `D`**   | Upstream `TestConfiguration.validate()` already rejects unmapped `--use-qemu` architectures, and `originPath` only differs from `path` on deprecated multitests.                                                                                         |
| **CL-8**  | Default `--arch` and guard `--lib_dir=None` in `create_debian_package`   |     `1` (`+13 / -2`)        | **`A-` / `D`**  | Upstream `tools/linux_dist_support/debian_package.gn` is the sole caller and always passes `-a` and `--lib_dir`; only our Bazel rule omitted them.                                                                                                       |
| **CL-9**  | Extract `runtime/include:public_api_headers` (`dart-lang/sdk#63474`)     |     `4` (`+31 / -9`)        | **`B-` / `C`**  | Purely cosmetic GN reorganization for an issue filed from our own Bazel investigation (`dart-lang/sdk#63474`) that still leaves `copy("copy_headers")` separate.                                                                                         |
| **CL-10** | Split `make_version.py` flags (`10a`) & DFE empty-kernel stubs (`10b`)   |     `9` (`+112 / -73`)      | **`C` / `D`**   | High multi-file churn written for Bazel `//runtime:version_cc` and shared `dfe.o` compilation; [`create_snapshot_entry.dart`](../../utils/compiler/create_snapshot_entry.dart) (`L20`) still spawns `python3`, so `10a` as-written does not unblock Siso. |

---

## 4. Retired Earlier Entries Already Landed Upstream

- **Three earlier candidates have already landed upstream and require no further action.**
  - _Earlier `#2` (`pkg/dart2wasm/lib/types.dart`)_: Superseded upstream on `cde64ed532a` by commits `23a289417dc` (CL `508425`), `9d727f53603` (CL `510740`), and `828fdbb7c69` (CL `521240`).
  - _Earlier `#3` (`tests/standalone/verbose_gc_to_bmu_test.dart`)_: Deleted upstream along with `runtime/tools/verbose_gc_to_bmu.dart` in `2f0b2a08fe6` (CL `518660`).
  - _Earlier `#9` (`pkg/dds`, `pkg/dtd_impl`, `vmservice_server.dart`)_: Landed upstream in `1a33f260f76` (CL `528242`, `--disable-service-origin-check`).
