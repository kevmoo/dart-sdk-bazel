# Dart SDK: GN+Ninja → Bazel Migration Design

> **Plan of record** for the GN+Ninja → Bazel migration (`kevmoo/bazel`),
> authored ~2026-05-28. This document is the *target design and sequencing* the
> other docs in this directory cite (`DESIGN.md §3.x` target state, `§4.x`
> sequencing, `§5.x` risks).
>
> For **current progress** see [STATUS.md](STATUS.md). Several specifics here have
> since been **refined or superseded** by decisions recorded in the scoping docs
> `m4_multiconfig_scoping.md` (product/config axis), `m4_arch_axis_scoping.md`
> (arch axis), and `rules_dart_scoping.md` (the per-package deps graph) — all
> three were **deleted in the Session-120 docs prune**; recover them via git
> history if needed. Notable superseded points: the product-variant end-state and
> the `dart-sdk/` assembly prefix. When this doc and STATUS.md disagree,
> STATUS.md wins.
>
> Synthesized from investigation beads; findings are cited inline by bead ID, e.g.
> `(sdk-m3y)`. See Appendix A for the index.

## 1. Executive summary

**Target topology.** The migration ships three things that don't exist
today: (1) a hand-ported Bazel `cc_toolchain` for Linux x64 sourced
from `build/toolchain/linux/BUILD.gn` (~319 lines); (2) a
**gn-desc-driven translator** that consumes `gn desc //* --format=json`
and emits `BUILD.bazel` files per source directory — `gn desc`
strictly dominates compdb as a translation input, fixing 10 of the 12
roadblocks the `kevmoo/bazel_silly` compdb experiment exposed and 2
partially (sdk-suy, sdk-33x, §3.2); and (3) **rules_dart authored
from near-scratch** because all four known forks
(`dart-archive/bazel`, `dart-archive/rules_dart`, `cbracken/rules_dart`,
`matanlurey/rules_dart`) are archived and none cover AOT
(`dartaotruntime` / `gen_snapshot`) workflows (sdk-8er, §3.1). The
14-variant `_all_configs` GN matrix translates to a **Starlark macro
emitting N `cc_library` targets**, not `select()` — because variants
are consumer-selected at the dep edge and a single build needs
multiple variants simultaneously (sdk-p0i, §3.3). Workspace structure
(Bzlmod vs WORKSPACE) is downstream of the rules_dart authoring
strategy and not settled here.

**Sequencing.** Bottom-up by build dependency, atomic per-subtree
cutovers, no permanent dual-system (§4.2, §4.3):

- **Phase 0** — Bazel `cc_toolchain` for Linux x64 (build/toolchain/linux/).
- **Phase 1** — `runtime/` (116 targets): `libdart_vm_jit` first
  (the smallest end-to-end proof), then `runtime/bin` executables,
  then the rest of runtime/.
- **Phase 2** — `utils/` (105 targets, requires rules_dart, port
  `utils/bazel/` early to verify against the snapshot external
  `rules_dart` consumers depend on per sdk-edw) → `sdk/` (52,
  assembly via `copy` / `copy_tree`) → `samples/` (21, cleanup).
- **Phase 3** — `third_party/` (24, mostly `bazel_dep` from BCR).
- **Deferred** — browser binaries, Android, Fuchsia, Windows MSVC,
  Emscripten — each a separate workstream.

The user-facing surface stays Python: `tools/build.py` and
`tools/test.py` keep their flag signatures (77 CI invocations depend
on them per sdk-sqa) and swap their backend from GN to Bazel
transparently, with an out-dir symlink layer preserving
`out/<BuildConf>/` paths for the test runner (§3.6).

**Top three risks** (with mitigations):

1. **rules_dart authoring scope** (§3.1, §3.5, §5.9 — sdk-8er,
   sdk-rsv). Single biggest unbudgeted item. The migration **must
   solve rules_dart as a precondition, not during the migration** —
   Flutter engine has stalled on Bazel adoption for 7+ years
   precisely because rules_dart was the precondition blocker. AOT
   support (`dart_aot_snapshot`, `dart_platform_dill`,
   `dart_kernel`) is greenfield design work. Mitigation: budget
   explicit ownership and headcount before any cutover work begins;
   fork-and-revive cbracken's archived rules_dart as a starting
   point if expedient.
2. **Depfile concentration in 58% of GN actions** (§5.6 — sdk-9gk).
   108 of 187 actions declare a `depfile`; 49 have empty `inputs`
   (the `copy_tree` family). Bazel `genrule` does not natively
   consume depfiles. Mitigation: translator-side filesystem walk +
   static `srcs` for `copy_tree` (32 actions); custom Starlark rules
   per Dart codegen pattern (66 actions) with deferred-correctness
   flagged in output; trivial `genrule` for the easy 43%. Risk is
   not whether translation works but whether the static-srcs
   supersets stay accurate across SDK evolution.
3. **Hermeticity escape hatches** (§5.5, §5.7 — sdk-06y, sdk-evr,
   sdk-1z9). Four actions read `.git/logs/HEAD`; 17 `exec_script`
   sites at config time (Windows MSVC detection is the heaviest port);
   `build/rbe/rewrapper_dart.py` is 800 lines of ad-hoc Dart import
   parsing that today's reclient tolerates but Bazel's sandbox will
   reject. Mitigation: wire `--workspace_status_command` for git/
   version stamping; port the `exec_script` long pole as
   `repository_rule`s (drop two dead-code sites for free —
   `pkg-config`/gtk and `get_host_byteorder.py`); replace
   `rewrapper_dart.py` entirely with structural rule attributes,
   gated on three precondition fixes (absolute paths in Dart cmd
   lines, honest `.dart` srcs declaration, `.dart_tool/
   package_config.json` as workspace-setup artifact).

**Smallest end-to-end proof** (§4.1, sdk-suy): `bazel build
//runtime/vm:libdart_vm_jit` on Linux x64 Release. Five work
molecules: M1 cc_toolchain port (~319 lines hand-ported), M2
~80-line gn-desc → BUILD.bazel translator skeleton, M3 gn dump +
iterate to green build, M4 multi-config `select()` (a second config
diffed into the first), M5 codegen ports for the action dependencies
in `runtime/vm` (sdk-1z9). Scout-reported **low** confidence on the
effort envelope; the two latency / stability risks underneath
(`gn gen` cycle time, `cflags` reproducibility) were filed as
sdk-yv1 and sdk-mx9 and have **both since resolved** by measurement
(§5.3, §5.4) — the multi-config translator workflow is
interactive-loop fast (~5 s for a 20–30 config matrix in parallel)
and the dumps are byte-stable across runs.

What's deferred (§4.3): permanent coexistence is not adopted —
neither the Skia "Bazel as source of truth + GN exporter" model nor
the Fuchsia GN ↔ Bazel `fint` model. The Dart SDK's coexistence is
**temporary**, with atomic per-subtree cutovers, ending when Phase 2
lands.

## 2. Current state: GN + Ninja in the Dart SDK

### 2.1 Build graph topology

The Dart SDK's GN build is anchored at `//sdk:create_sdk` (aliased from
the top-level `//:create_sdk` group) and fans out through 64 `BUILD.gn`
files plus 103 `*.gni` files, containing **392 declared targets**
(sdk-vgw).

**The graph is heavily templated.** Of the 392 declared targets, 176
(45%) are GN built-in primitives and 216 (55%) are invocations of one of
**57 distinct custom templates** — meaning a Bazel rewrite has to ship a
matching Starlark rule library before raw target counts mean anything
(sdk-vgw). The built-in distribution is:

| GN built-in | Count |
|---|--:|
| `group` | 72 |
| `copy` | 34 |
| `source_set` | 31 |
| `executable` | 12 |
| `action` | 11 |
| `shared_library` | 9 |
| `static_library` | 5 |

After template expansion the **effective** `action` count rises to
roughly 107 (28 `aot_snapshot` + 12 `application_snapshot` + 9
`ddc_compile` + 8 `create_timestamp_file` + 6 `prebuilt_dart_action` + 6
`compile_platform` + smaller contributors), and the effective
`source_set` count is multiplied further by the 14-way `_all_configs`
fan-out described below (sdk-vgw).

**`_all_configs` is the single biggest structural feature of today's
build.** The four `library_for_all_configs(...)` calls in `runtime/`
each expand to **14 sub-targets**, encoding the matrix of
jit / aot / precompiler × product / non-product × host-targeting /
cross-arch build modes — concretely: `jit`, `jit_product`, `aotruntime`,
`aotruntime_product`, `precompiler`, `precompiler_testing`,
`precompiler_product`, `precompiler_host_targeting_host`,
`precompiler_product_host_targeting_host`, `libfuzzer`, plus four
`precompiler_product_linux_<arch>` variants. The same `.cc` files
compile under each variant with different defines into distinct object
files in distinct out dirs (sdk-vgw). The bottom-up inventory flags this
fan-out as the largest single structural translation the migration will
face.

**Top-down, `//sdk:create_sdk` is a three-layer group hierarchy ending
in copy and snapshot leaves** (sdk-m3y). The top-level `:create_sdk`
dispatches on the `dart_platform_sdk` `declare_args()` boolean (default
`true`):

- `:create_common_sdk` (`sdk/BUILD.gn:846`) is always populated. Its 16
  `public_deps` are the 22 `copy`/`copy_tree` targets that produce the
  shipping `dart-sdk/` tree (binaries, headers, license, dartdoc
  resources, devtools), three Python `action`s emitting `version`,
  `revision`, and `dartdoc_options.yaml`, and (on non-ia32)
  `:group_dart2native`, which copies the AOT runtime and `gen_snapshot`
  artifacts.
- `:_create_platform_sdk` (when `dart_platform_sdk=true`) adds
  `:copy_platform_sdk_libraries` (a group of 28 `copy_tree` calls, one
  per entry in `_full_sdk_libraries`) and `:copy_platform_sdk_snapshots`
  (a foreach over `_platform_sdk_snapshots` emitting one
  `copy("copy_<srcname>_snapshot")` per entry).
- `:create_full_sdk` (the alternative branch) supersets the platform set
  with dart2js, ddc, dart2wasm, `kernel_worker`, and cross-compiled
  `gen_snapshot_product_linux_{arm,arm64,riscv64,x64}` deps.

The per-language-library `lib/` payload is delivered by 28
`copy_tree("copy_${library}_library")` targets generated by foreach over
`_full_sdk_libraries` (`_internal`, `async`, `cli`, `collection`,
`concurrent`, `convert`, `core`, `developer`, `ffi`, `html`, `_http`,
`indexed_db`, `internal`, `io`, `isolate`, `js`, `js_interop`,
`js_interop_unsafe`, `js_util`, `math`, `mirrors`, `svg`, `typed_data`,
`_vm`, `_wasm`, `web_audio`, `web_gl`, `web_sql`). Each `copy_tree` is
an `action` shelling out to `tools/copy_tree.py` with a depfile
(sdk-m3y).

**The compiler bootstrap is three-stage.** Every Dart snapshot in the
SDK is produced by a chain that crosses three distinct classes of
"tools that compile other things" (sdk-m3y):

1. The **CIPD-prebuilt Dart SDK** at `tools/sdks/dart-sdk/`, fetched at
   `gclient sync` time per `DEPS:196`. The `prebuilt_dart_action`
   template (`build/dart/dart_action.gni:204`) hardcodes the binary
   path. This prebuilt runs `pkg/front_end/tool/compile_platform.dart`
   (producing `vm_platform.dill`) and compiles
   `pkg/vm/bin/gen_kernel.dart` into `bootstrap_gen_kernel.dill`.
2. **`bootstrap_gen_kernel.dill`** is then re-invoked by the prebuilt
   dart to compile every other Dart entry-point in the build — the
   `main_dart` of each `application_snapshot` / `aot_snapshot` call —
   into a per-snapshot `<name>.dart.dill`.
3. **The in-build, host-toolchain `runtime/bin:dartvm` and
   `runtime/bin:gen_snapshot[_product]`** then consume that dill. The
   `_compiled_action` template (`build/dart/dart_action.gni:43`)
   rewrites every tool label to `tool + "($host_toolchain)"`, so even
   in cross-compiled SDK builds these tools are built for the host.
   `dartvm` produces app-jit snapshots; `gen_snapshot` produces AOT ELF
   snapshots. Each snapshot's `_dill` step depends on
   `runtime/vm:vm_platform` for the target AND
   `runtime/vm:kernel_platform_files($host_toolchain)` for the host —
   so `vm_platform.dill` is compiled twice in every SDK build.

The two templates that wrap this chain — `application_snapshot`
(`utils/application_snapshot.gni:55`) and `aot_snapshot`
(`utils/aot_snapshot.gni:10`) — account for 12 + 28 = 40 of the 392
declared targets (sdk-vgw). Together with the 22 SDK-assembly copies
and the C++ executables and libraries in `runtime/bin/` and `runtime/`,
they define essentially the entire shipping artifact graph.

**Per-directory distribution** (sdk-vgw):

| Directory | Targets | Character |
|---|--:|---|
| `runtime/` | 116 | VM, compiler, runtime libs — densest C++ surface. |
| `utils/` | 105 | Snapshot-producing tools: dart2js, ddc, dart2wasm, dartdev, dds, dtd, kernel-service, gen_kernel, analysis_server, dart_mcp_server. Predominantly `aot_snapshot` / `application_snapshot` / `ddc_compile` actions. |
| `sdk/` | 52 | SDK assembly: ~30 `copy(...)` + ~20 `group(...)`. No compilation. |
| `build/` | 51 | Toolchain definitions and `*_toolchain_suite` invocations. |
| `third_party/` | 24 | boringssl, perfetto, binaryen, fallback_root_certificates, etc. |
| `samples/` | 21 | `sample()` + `snapshots()` invocations. |
| root `BUILD.gn` | 21 | Top-level groups and Linux Debian/Snap install actions. |
| `tools/` | 1 | `tools/debian_package/BUILD.gn` only. |
| `pkg/` | 1 | Thin trampoline group. |

**Action scripts cluster on a single wrapper.** The dominant `script =`
value across `action()` and templated-action callsites is
`build/gn_run_binary.py`, cited by every `_*_tool_action` template
(`_prebuilt_tool_action`, `_built_tool_action`, `_compiled_action`),
and therefore backing the entire `dart_action` chain (sdk-vgw). It
provides a uniform process-wrapping shim that adds RBE-rewrapper
support, packaged-VM args, and `--packages=` / `--dfe=` plumbing —
context that becomes load-bearing in §2.2 and §3.6.

**Confidence.** Both scouts report **medium-high** confidence on the
structural counts and inventory: the bottom-up regex extractor was
cross-checked against direct grep counts and the rule listings in
`sdk/BUILD.gn` were read exhaustively (sdk-vgw); the top-down trace was
read in full to ~3–4 levels depth (sdk-m3y). Confidence is **medium**
on template-expanded behavior — `gn desc` was not run, so neither
finding has empirically verified that the templates' apparent behavior
matches the actual target graph; in particular, transitive deps under
`runtime/vm` for the `($host_toolchain)`-suffixed `kernel_platform_files`
group have not been traced (sdk-m3y).

### 2.2 Action / generator inventory

The build has **12 raw `action(...)` calls** in `BUILD.gn` files (8
truly direct, 4 inside local templates wrapping a single `action()`),
**0 `action_foreach(...)` calls in production code** (the only
definition is in the never-invoked `process_nibs_mac` template at
`build/config/mac/rules.gni:42`), **~13 SDK-defined wrapper templates**
that ultimately resolve to an `action()`, and **~85 wrapper-template
invocation sites** across `BUILD.gn` files — which expand to roughly
**107–110 effective actions** in a fully-resolved build graph
(sdk-1z9). Two templates dominate the 85 wrapper invocations:
`aot_snapshot` fires 28 times and `application_snapshot` fires 12
times, together accounting for 40 of the 392 declared targets
catalogued in sdk-vgw.

**Direct `action()` callsites (12)** (sdk-1z9):

| Target | Script | Bucket | Notes |
|---|---|---|---|
| `//runtime:generate_version_cc_file` | `tools/make_version.py` | codegen | Bakes the SDK hash into a generated `version.cc`. Reads `.git/logs/HEAD` when `dart_version_git_info=true`. |
| `//sdk:copy_dartvm` (Linux/Android) | `/bin/ln` | asset/file | Symlinks `dartvm` into the SDK; `action()` rather than `copy()` because GN's `copy` rule produces hard links. |
| `//sdk:write_version_file` | `tools/write_version_file.py` | asset/file | Renders the `version` text file shipped in `dart-sdk/`. Reads `.git/logs/HEAD`. |
| `//sdk:write_revision_file` | `tools/write_revision_file.py` | asset/file | Renders the `revision` text file. Reads `.git/logs/HEAD`. |
| `//sdk:write_dartdoc_options` | `tools/write_dartdoc_options_file.py` | asset/file | Renders `dartdoc_options.yaml`. Reads `.git/logs/HEAD`. |
| `//third_party/binaryen:generate_needed_files` | `third_party/binaryen/generate_needed_files.py` | codegen | Vendored Binaryen WASM-intrinsics codegen. |
| `//tools/debian_package:debian_package` | `tools/debian_package/create_debian_package.py` | packaging | Builds a `.deb`. Uses `exec_script` at GN-config time to read `get_version.py` — a separate hermeticity escape hatch (picked up by sdk-06y). |
| `//runtime/bin:<bin_to_assembly target>` | `runtime/tools/bin_to_assembly.py` | asset/file | Generates `.S` files embedding snapshot blobs as `.text`/`.rodata` symbols. |
| `//runtime/bin:<bin_to_coff target>` | `runtime/tools/bin_to_coff.py` | asset/file | Windows COFF variant of the same. |
| `//utils:<aot_compile_using_prebuilt_sdk target>` | `build/gn_dart_compile_exe.py` | bootstrap codegen | AOT-compiles `compile_platform.exe` and `gen_kernel.exe` using the **prebuilt** SDK; only 2 invocations but they break the bootstrap loop. |
| `//utils/dart2wasm:ffi_native_test_wasm_module` | `third_party/emsdk/.../emcc` | codegen | C→WASM via Emscripten; sole `wasm_module` template invocation in the SDK (test fixture). |
| `//utils/kernel-service:kernel_service<suffix>_dill` (precompile path) | `$root_out_dir/gen_kernel.exe` | kernel | Builds `kernel_service.dill` from the just-AOT-compiled `gen_kernel.exe`. |

**Wrapper template inventory (~13 templates)** (sdk-1z9, with snapshot
template internals walked through in sdk-m3y):

| Template | Defined in | Direct invocations | Wraps |
|---|---|---:|---|
| `application_snapshot` | `utils/application_snapshot.gni:55` | 12 | One `prebuilt_dart_action` (kernel `.dill`) + either a `copy` (`kernel` kind) or a `dart_action` (app-jit training run) |
| `aot_snapshot` | `utils/aot_snapshot.gni:10` | 28 | One `prebuilt_dart_action` (kernel `.dill`) + one `gen_snapshot_action` (ELF/asm snapshot); adds a `shared_library` link when `as_shared_library=true` |
| `gen_snapshot_action` | `build/dart/dart_action.gni:413` | 1 direct + 2 from `aot_snapshot.gni` | Runs the in-build `runtime/bin:gen_snapshot[_product]` |
| `dart_action` | `build/dart/dart_action.gni:355` | 0 direct + 1 from `application_snapshot.gni` | Runs the in-build `runtime/bin:dartvm` |
| `prebuilt_dart_action` | `build/dart/dart_action.gni:204` | 7 direct (10 total) | Runs the **prebuilt** Dart from `tools/sdks/dart-sdk/bin/dart` |
| `compile_platform` | `utils/compile_platform.gni:10` | 6 | Either a raw `action()` running `compile_platform.exe` (when `precompile_tools=true`) or a `prebuilt_dart_action` |
| `copy_tree` | `build/dart/copy_tree.gni:19` | 5 | `action()` + `tools/copy_tree.py`, with `exclude` glob and depfile |
| `create_timestamp_file` | `utils/create_timestamp.gni:7` | 8 | `action()` + `tools/list_dart_files_as_depfile.py` — a glob-substitute that materialises a depfile of matched files |
| `kernel_service_dill` | `utils/kernel-service/BUILD.gn:94` | 1 | Either raw `action()` (precompile path) or `prebuilt_dart_action` |
| `aot_compile_using_prebuilt_sdk` | `utils/BUILD.gn:10` | 2 | `action()` + `build/gn_dart_compile_exe.py` |
| `wasm_module` | `utils/dart2wasm/BUILD.gn:10` | 1 | `action()` + `emcc` |
| `bin_to_assembly` / `bin_to_coff` | `runtime/bin/BUILD.gn:662, 703` | 7 (via `bin_to_linkable` dispatcher) | `action()` + `bin_to_assembly.py` or `bin_to_coff.py` |

**Seven semantic buckets** organise the inventory by build role
(sdk-1z9):
1. **Codegen** (~3 direct + most `prebuilt_dart_action` uses): `version.cc`, Binaryen WASM intrinsics, Dart-runs-Dart `.dill` / JS / etc.
2. **Asset / file processing** (~6): SDK metadata files, blob-to-`.S`/`.obj` for snapshot embedding, `copy_tree` recursive copies.
3. **Packaging** (1): `.deb` build.
4. **Snapshot generation** (28 invocations × 1–2 actions each = 28–56 effective): every `aot_snapshot` + the lone direct `gen_snapshot_action`.
5. **Kernel compilation** (12 + 8 + 6 + 1 ≈ 27 invocations, ~30 effective): `application_snapshot`'s kernel-dill step, `compile_platform`, `create_timestamp_file`'s glob-substitute role for kernel inputs, `kernel_service_dill`.
6. **Bootstrap codegen** (2): `aot_compile_using_prebuilt_sdk` — small in count, load-bearing because it breaks the bootstrap loop (see Dart-builds-Dart below).
7. **Test fixture** (1): the single `wasm_module` invocation.

**The four Dart-builds-Dart bootstrap edges** are the load-bearing
hermeticity-hard cases. The build graph relies on **two host-toolchain
Dart binaries** active at the same time — the **CIPD-prebuilt** Dart at
`tools/sdks/dart-sdk/bin/dart` (fetched via DEPS, hardcoded into the
`prebuilt_dart_action` template) and the **freshly built**
`runtime/bin:dartvm`, `runtime/bin:gen_snapshot[_product]`, and (when
`precompile_tools=true`) `out/.../{compile_platform,gen_kernel}.exe`
(sdk-1z9, consistent with the three-stage compiler bootstrap walked
through in sdk-m3y). The four edges:

- **`prebuilt_dart_action`** (10 sites) runs the prebuilt Dart to compile every other Dart entry point. Hermetic under GN because the prebuilt is checked in via DEPS; under Bazel it will need an external-repo rule.
- **`dart_action`** (1 site, in `application_snapshot.gni`) runs the just-built `dartvm` — used only for the app-jit training run.
- **`gen_snapshot_action`** (3 sites total: 1 direct in `runtime/bin/BUILD.gn:629` + 2 in `aot_snapshot.gni`) runs the just-built `gen_snapshot[_product]` to produce ELF/asm AOT snapshots.
- **`aot_compile_using_prebuilt_sdk`** (2 sites) AOT-compiles `compile_platform.exe` and `gen_kernel.exe` using the prebuilt SDK; the outputs then live in the host config and are consumed by target-config rules. `kernel_service_dill` (1 site) closes a circular-feeling edge by snapshotting the kernel service at build time so the VM can later load it to compile other kernels.

**Seven dead templates** are defined but never invoked in production
(sdk-1z9): `prebuilt_dartaotruntime_action`, `shim_headers`,
`copy_trees` (with an explicit deprecation comment), `rust_library`,
`file_template`, and four Mac-only templates in
`build/config/mac/rules.gni` (`code_sign_mac`, `process_nibs_mac`,
`resource_copy_mac`, `mac_app`). The migration does not need to port any
of these — they can be deleted from the source tree, which also
removes the only `action_foreach()` site in the entire repository.

**Hermeticity flag for §5.** Four actions read `.git/logs/HEAD` during
the build — `generate_version_cc_file`, `write_version_file`,
`write_revision_file`, `write_dartdoc_options` (sdk-1z9). GN tolerates
this because the file is listed in `inputs`; a sandboxed Bazel build
will refuse to read it, so the migration must plumb workspace status
(or equivalent) and accept that incremental builds won't auto-rebust on
a commit unless wired explicitly. Separately, the `debian_package`
action uses `exec_script` at GN-config time to read `get_version.py`
(picked up by sdk-06y). Both shape §3.6 (Python build layer replacement)
and §5 (risks).

**Confidence.** The scout reports **medium-high** confidence on the
inventory: the action and template enumeration is exhaustive (every
`action(...)` line-start match and every `template(...)` definition in
`build/`, `utils/`, plus the action-defining `BUILD.gn` files), but
per-template invocation counts are based on line-start grep and may
miss a handful of invocations inside conditional `if (...)` branches
with non-standard indentation (sdk-1z9). The dead-template list and
the Dart-builds-Dart enumeration are reported with **high** confidence.
These actions are demonstrably portable to Bazel via a small set of
custom Starlark rules plus `genrule` for the simple cases (sdk-1z9),
but the rule-library design itself belongs in §3.2 after the
toolchain, config, and template-mapping findings have landed.

### 2.3 Toolchain and platform handling

**Three orthogonal bins** organise the build's configuration surface
(sdk-clv, **high** confidence): platform/arch selection (`target_cpu`,
`target_os`, `host_cpu`, plus the `current_toolchain` /
`default_toolchain` / `host_toolchain` triangle GN re-evaluates per
toolchain context); feature gates (~30 `declare_args` keys spread
across `build/config/BUILDCONFIG.gn:108–151`, `runtime/runtime_args.gni`,
and `sdk_args.gni` — `is_debug`, `is_release`, `is_product`,
`is_clang`, the sanitizers, `dart_runtime_mode`,
`dart_use_compressed_pointers`, `exclude_kernel_service`,
`dart_support_perfetto`, …); and build-time computed values
(`default_git_folder`, the SDK hash, sysroot ld-path output,
toolchain CIPD version hashes; mechanism catalogued in §2.6 +
sdk-06y). The only oddball arg is `is_shared_library`, which GN models
at toolchain level rather than as a rule attribute (sdk-clv).

**`build/toolchain/linux/BUILD.gn` declares 13 toolchain suites.**
Each `gcc_toolchain_suite()` call expands via
`build/toolchain/toolchain_suite.gni:18–56` into **5 toolchain
instances** (default, `_shared`, `_asan`, `_msan`, `_tsan`), so the
Linux side defines up to **60 toolchain instances** in template form
(sdk-clv, **high** confidence). GN materialises only those actually
referenced; in the Linux x64 Release `gn desc` dump (§3.2 / sdk-suy),
**5 toolchains were active** — `clang_x64` (76 libdart targets),
`clang_x64_shared` (10), `clang_x64_asan` / `_msan` / `_tsan` (5
each), 101 libdart targets total across all toolchains (sdk-p0i).
The `current_toolchain != host_toolchain` pattern is GN's
host-tooling switch — targets that must run on the build machine
forward to the host toolchain via a `group(":foo") { public_deps =
[":foo($host_toolchain)"] }` pattern recurring throughout the SDK
(sdk-clv).

**Cross-arch precompiler variants are not cross-compiles.**
`libdart_precompiler_product_linux_arm64` and the `_arm`, `_riscv64`,
`_x64` peers all carry `toolchain =
"//build/toolchain/linux:clang_x64"` in gn desc — they are host-x64
binaries whose `-DTARGET_ARCH_*` define gates which code-emission
backend gets compiled in (sdk-p0i, **high** confidence verified on all
13 visible libdart_vm_* variants). The host x64 `gen_snapshot` links
the matching variant and emits target-arch code at build time; no
compiler-level cross-compile happens.

**The 14 `_all_configs` entries share one toolchain.** All 13 variants
visible in the dump run under `clang_x64`; they diff only in defines
(5 distinct keys: `PRODUCT`, `DART_PRECOMPILER`,
`DART_PRECOMPILED_RUNTIME`, `EXCLUDE_CFE_AND_KERNEL_PLATFORM`,
`TESTING`, `FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION`) plus arch/OS
tokens, with a single conditional dep — `boringssl` added on
precompiler variants only via `extra_precompiler_deps` in
`runtime/configs.gni:232–235`. Variants are **consumer-selected at the
dep edge**: `//runtime/bin:dart` links `libdart_aotruntime_product`,
`:dartaotruntime` links `libdart_aotruntime`, `:dartvm` links
`libdart_jit`. This is a generate-N-targets-then-pick-one pattern, not
a build-mode select (sdk-p0i, **high** confidence verified across 4
distinct executables). The 4 alternate toolchains
(`_shared` / `_asan` / `_msan` / `_tsan`) ARE genuine toolchain
distinctions: `_shared` swaps `-fPIE` → `-fPIC`, sanitizer toolchains
layer `-fsanitize=*` cflags + ldflags + a link-helper source set.

**`build/config/` is the flag system.** 5 `BUILD.gn` files across
`build/config/`, `/compiler/`, `/gcc/`, `/clang/`, `/linux/`, plus
`sanitizers/`, declaring roughly **30 distinct configs** (sdk-q3t).
For Linux x64 Release JIT, gn desc reports 24 configs applied to
`//runtime/vm:libdart_vm_jit`; the heavy one is `compiler:compiler`
(973 lines, contributing per-arch `--target=`,
`-fvisibility-inlines-hidden`, `-fno-omit-frame-pointer`, Linux link
flags, the sysroot/toolchain-stamp defines). **Sanitizers are not
separate configs** — they are gated inside `compiler:compiler`
itself by the `is_asan` / `is_lsan` / `is_msan` / `is_tsan` /
`is_ubsan` / `is_hwasan` build args (`compiler/BUILD.gn:128–203`); the
`build/config/sanitizers:deps` group is empty in a non-sanitizer
build (sdk-q3t, **high** confidence on the resolved flag set,
verified against gn desc).

**Eight silent-break candidates to track for §5** (sdk-q3t):
`-DTOOLCHAIN_VERSION` and `-DSYSROOT_VERSION` are CIPD-version-hash
defines from `.cipd_version` JSON (forced-rebuild semantics, not
load-bearing); `gcc:relative_paths` switches between literal `/b/f/w/`
and `rebase_path("//")` based on `use_rbe`; `linux:sdk` runs
`exec_script("sysroot_ld_path.py", ...)` (sdk-06y, §2.6);
`-Wl,--icf=all` changes C++ function-pointer-comparison semantics;
`-Wl,--fatal-warnings` is on for non-ARM non-Mac builds; warning
suppression sets differ across clang/gcc; `-Werror` is set by
`chromium_code` but conditionally **not** set when `dart_sysroot ==
"alpine"`; `default_optimization` and `optimize_speed` are empty stubs
satisfying zlib's BUILD.gn naming contract.

### 2.4 Third-party / DEPS

**Three acquisition mechanisms** (sdk-4h1, **high** confidence — DEPS
read end-to-end):

- **CIPD packages** (`dep_type: "cipd"`) — pinned binaries fetched
  from Chrome Infrastructure Package Deployment, downloadable over
  HTTPS at `https://chrome-infra-packages.appspot.com/dl/<pkg>/+/<version>`.
  **~22 distinct packages** including `tools/sdks/dart-sdk` (the
  prebuilt SDK that breaks the bootstrap loop, §2.2), `buildtools/gn`,
  `buildtools/ninja`, per-platform `buildtools/<plat>/clang` and
  `buildtools/sysroot/<linux|focal>`,
  `buildtools/reclient[-win|-linux]`, `third_party/d8/<plat>`,
  `firefox_jsshell`, `co19` test corpus, Fuchsia SDK, Android tools,
  browser binaries (chrome, firefox, chromedriver), and CFE benchmark
  data. Versions pinned by tag (`version:X`, `git_revision:<sha>`, or
  content hash `sha1sum:<sha>`).
- **Git repositories** — `URL@SHA`, with allowed remotes restricted to
  `android.git`, `boringssl.git`, `chromium.git`, `dart.git`,
  `dart-internal.git`, `fuchsia.git`, `llvm.git`. **~40 git repos**:
  native/C++ deps (zlib, boringssl, icu, perfetto, binaryen, emsdk,
  jinja2, ply, libcxx/libcxxabi/libc from llvm-project,
  cpu_features, markupsafe), and ~21 Dart-team mirrors at
  `dart.googlesource.com` for the `third_party/pkg/*` workspace
  (each repo containing multiple pub packages).
- **Hooks** — Python scripts run after each `gclient sync`
  (DEPS:676–743): generate `.dart_tool/package_config.json`, generate
  `sdk/version`, generate large tests, run `tools/buildtools/update.py`,
  optionally install Windows toolchain / emsdk / Fuchsia SDK.
  **9 hooks total**, most gated by conditional vars.

**Only one build-time patch in the whole tree:**
`third_party/d3/patches/001_no_html.patch` (plus an asset-copy in
`pkg/vm_snapshot_analysis`). No patches under `third_party/pkg/*`,
`boringssl`, `zlib`, or `icu`. The `http_archive(patches=[...])`
surface in Bazel only needs to cover this single d3 case (sdk-4h1).

**`buildtools/` is not in the repo** — gclient creates it on sync.
The only checked-in artifact is `tools/buildtools/update.py` (a small
launcher) which symlinks per-OS clang-format binaries into expected
paths and downloads the Windows clang-format from Google Storage via
the vendored `tools/find_depot_tools.py`. Every checkout today requires
`depot_tools` on `PATH`; Bazel's hermetic resolution would remove this
dependency (sdk-4h1).

**Conditional checkouts.** Ten `vars` flags toggle whole DEPS
branches (`checkout_benchmarks_internal`, `checkout_flute`,
`download_android_deps`, `checkout_javascript_engines`,
`download_chrome`, `download_firefox`, `download_emscripten`,
`download_fuchsia_deps`, `download_reclient`,
`build_devtools_from_sources`). `benchmarks-internal` is auth-walled
(`dart-internal.googlesource.com`), needing CI credential plumbing.

**Stale artifact.** `third_party/clang.tar.gz.sha1` exists at the
`third_party/` root but has no obvious consumer in DEPS — clang is
fetched via CIPD now. Likely dead code; worth removing regardless of
the Bazel migration (sdk-4h1).

**Build-time vs checked-in generated files (sdk-iq3).** The
`runtime/vm` + `runtime/bin` subtree has exactly **5 build-time
generator pipelines producing 11 artifacts** — strict subset of §2.2's
sdk-1z9 catalogue, restated here from the consumer side: `version.cc`
(genrule), the four `*_snapshot_*.bin` files from `gen_snapshot`, the
7 `.S`/`.obj` linkables via `bin_to_linkable`, the three
platform-dill variants (`vm_platform[_product|_stripped].dill`), and
`kernel_service.dill` (sdk-iq3, **high** confidence). Separately, a
small set of files **look generated but are checked in** with manual
regen workflows — `runtime/vm/compiler/runtime_offsets_extracted.h`
(regenerated by `./tools/run_offsets_extractor.dart`),
`runtime/vm/experimental_features.{cc,h}` (from
`tools/experimental_features.yaml`), and `runtime/vm/regexp/unibrow.cc`
(a 2014 V8 fork). The Bazel migration does not need to model these as
generators — the developer workflow "build the tool, run by hand,
commit the output" keeps working as long as the relevant `cc_binary`
targets stay buildable (sdk-iq3, **high** confidence on the regen
pattern, verified by header comments in `runtime_offsets_extracted.h:11–16`).
Notably, **`runtime/vm/*.cc` source files do not `#include "gen/*.h"`** —
the only `gen/` consumption is `version.cc` ingested as a source file
into `libdart_api_impl_sources`, and the snapshot/dill blobs surfaced
as linkable objects via `bin_to_linkable` (sdk-iq3, **medium-high**
confidence — sampled, not exhaustively grepped).

### 2.5 Test infrastructure

**`tools/test.py` is a 57-line Python wrapper** around
`dart pkg/test_runner/bin/test_runner.dart` (sdk-9jz, **high**
confidence — read end-to-end). It bumps the fd limit, wraps with
core-dump archival, adds Android platform-tools to PATH, and
optionally task-kills lingering processes. Everything else is Dart.

**The configuration matrix is 8-dimensional**, modelled in
`pkg/smith/lib/configuration.dart` (sdk-9jz, **high** confidence):
Architecture (19 values, including `ia32`, `x64`, `x64c`, `simx64`,
`arm`, `simarm64`, `riscv32`, `riscv64`), Compiler (11 values:
`dart2js`, `dart2analyzer`, `dart2wasm`, `ddc`, `app_jitk`, `dartk`,
`dartkp`, `spec_parser`, `fasta`, `dart2bytecode`, `modaot`), Mode (3),
Sanitizer (7), Runtime (12), System (5), `NnbdMode`,
`GenSnapshotFormat` (4). Unconstrained cardinality is ~263K
combinations; CI configures a few hundred via
`tools/bots/test_matrix.json` (3614 lines, ~65 builder configs, 77
invocations of `tools/build.py`).

**Test discovery is filesystem-walking, not BUILD-declared.**
`StandardTestSuite.forDirectory` (`test_suite.dart:622`) walks each
suite recursively for `_test.dart` files, parses magic comments
(`// VMOptions=`, `// SharedOptions=`, `// dart2jsOptions=`,
`// Environment=KEY=VAL`, multitest markers `// [01]`, `// /none///`),
and resolves expectations via `.status` files. **No BUILD-file test
declarations exist anywhere** (sdk-9jz, **high** confidence).

**Status files: 34 files, 1996 lines, ~25-token closed expectation
vocabulary.** Syntax is `[ $var == value ]` conditional sections
containing `path: Expectation [, Expectation …] # comment` entries.
The vocabulary (Pass, Crash, Timeout, Fail, RuntimeError,
CompileTimeError, MissingRuntimeError, MissingCompileTimeError, Slow,
ExtraSlow, Skip, SkipSlow, SkipByDesign, Ignore, VerificationError, …)
is closed and stable. Multiple matching entries union their
expectations — the test passes if outcome is any of them. Sections
evaluate against environment variables (`$compiler`, `$mode`,
`$runtime`, `$system`, `$arch`, `$builder_tag`) that intersect with
the smith dimensions. Loaded into a path-prefix tree for O(depth)
per-test lookup.

**Sharding is dirt simple** — `--shard=k --shards=N` deterministic
hash partitions the test list; CI orchestration declares `"shards":
N` per builder step. **Deflaking is per-test JSON**
(`{"name": ..., "repeat": 5, "timeout": 60}`), opt-in via
`--test-list`; there is no automatic retry on first failure (the only
hardcoded retry is browser-launch retry in
`browser_controller.dart:1312`).

**Result reporting: newline-delimited JSON.** `results.json` and
`logs.json` (logs only for `matches:false`) are the protocol the
`dart-current-results.appspot.com` dashboard and the deflake bot
consume. **The migration must preserve this format byte-for-byte** to
keep the CI/dashboard stack working (sdk-9jz, **high** confidence).

**Multitests are build-time expansion** — `pkg/test_runner/lib/src/
multitest.dart` rewrites a single `_test.dart` with `// [01]`,
`// /none///` markers into multiple synthetic test files at suite
discovery time.

**`pkg/` is a pub workspace, not a GN target tree.** 68 `pubspec.yaml`
files, **exactly 1 `BUILD.gn`** (a stub at `pkg/BUILD.gn` with a
`TODO(flutter): Remove use.` comment). The root `pubspec.yaml` is the
workspace manifest (`name: _`, `publish_to: none`, `workspace:
[...]`) listing ~100 members across `pkg/`, `runtime/tools`,
`runtime/tests`, `samples/`, `tests/ffi`, `tools/`, `utils/`, and
selected `third_party/pkg/` paths (sdk-rsv, **high** confidence).
Cross-package resolution is owned by pub:
`tools/generate_package_config.dart` invokes `dart pub get` to
produce `.dart_tool/package_config.json`, which every Dart-driven
build action consumes via `--packages=`. Third-party Dart packages
live under `third_party/pkg/` (populated by DEPS) and are surfaced
via `dependency_overrides:` (root `pubspec.yaml:102–324`) — every
third-party package gets a `path:` override into
`third_party/pkg/...`. **GN does not model Dart source-to-source
dependencies at all** — there is no `dart_library` template (sdk-rsv).

**Dominant pkg/ build pattern.** Of 45 `main_dart =` callsites, ~30
are in `utils/<name>/BUILD.gn` pointing at
`../../pkg/<package>/bin/<entry>.dart`; each typically defines
**three snapshot variants** for the same entry point —
`application_snapshot(<name>)` for kernel/app-jit,
`aot_snapshot(<name>_aot)` for AOT, and
`aot_snapshot(<name>_aot_product)` for the shipped product SDK
(sdk-rsv).

**How Dart actions discover sources.** GN/ninja never see the
per-`.dart`-file dep graph. The `prebuilt_dart_action` declares
`inputs = [main_dart, package_config, ...]`, and the Dart frontend
(`gen_kernel`, `dart2js`, `compile_platform.dart`, …) is invoked
with `--depfile=<output>.d`. The frontend walks imports starting from
`main_dart`, resolves them via `package_config.json`, and writes the
transitive `.dart` file list to the depfile. Ninja reads it on the
next build for invalidation — **the Dart dep graph lives in the
compiler, not the build system** (sdk-rsv, **high** confidence).

### 2.6 Python build layer (`tools/build.py`, `tools/gn.py`)

**Five Python files orchestrate every build** (sdk-sqa, **high**
confidence — read end-to-end): `tools/build.py` (335 lines —
argparse, RBE bootstrap, sanitizer env, per-combo ninja),
`tools/gn.py` (808 lines — arch-string vocabulary, 40+ `args.gn` key
emission, RBE bootstrap, config-matrix expansion),
`tools/generate_buildfiles.py` (113 lines — gclient sync hook),
`tools/utils.py` (1021 lines — naming conventions, version stamping,
host detection), and `build/rbe/rewrapper_dart.py` (800 lines —
Dart-aware RBE wrapper, see §3.4 for disposition).

**The arch-string vocabulary is the engine.** `tools/gn.py:71–155`
decodes ~25 arch names (`x64`, `simarm64`, `simarm64c`,
`simarm64_x64`, `riscv32`, `arm_x64`) into three orthogonal axes:
`HostCpuForArch` (what the C compiler runs on), `TargetCpuForArch`
(what the C compiler produces), `DartTargetCpuForArch` (what the Dart
compiler targets). The simulator vs cross-compile vs
compressed-pointer (`*c` suffix) distinctions are all encoded in the
string — `simarm64c_x64` means "Dart targets arm64 with compressed
pointers, C targets x64, runs on host x64".

**`ToGnArgs` (`gn.py:192–329`) emits 40+ keys** into the args.gn
dict — including `is_debug`, `is_release`, `is_product`, `is_asan`,
`is_clang`, `dart_use_compressed_pointers`, `dart_force_simulator`,
`dart_snapshot_kind`, `dart_use_crashpad`, `dart_runtime_mode`,
`dart_dynamic_modules`, `dart_vm_code_coverage`, `is_qemu`,
`dart_platform_sdk`, `use_rbe`, `verify_sdk_hash`,
`dart_version_git_info`, `arm_version`, `arm_float_abi`,
`dart_sysroot`, `dart_stripped_binary`, `codesigning_identity`,
`target_sysroot`, `<arch>_toolchain_prefix`. Several interact
(`dart_use_compressed_pointers` + `dart_force_simulator` +
`dart_snapshot_kind`).

**`utils.py:GetBuildConf` controls out-dir naming** — same-OS,
host-arch: `{Debug|Release|Product}{ASAN|…}{X if cross}{ARCH}` (e.g.
`ReleaseX64`, `DebugASANX64`, `DebugXARM64`); cross-OS:
`{Mode}{OS_TITLE}{ARCH}` (e.g. `ReleaseAndroidARM64`,
`DebugIosSimARM64`). **`pkg/test_runner` reads from
`out/<BuildConf>/dart`** and `xcodebuild/<BuildConf>/`, so any Bazel
migration must either preserve these paths (via a symlink layer in
the wrapper) or update the test runner (sdk-sqa).

**Five must-preserve UX contracts** (sdk-sqa, **medium** confidence
on the criticality ranking): `tools/build.py` as a callable command
with `-m <modes> -a <archs> --os <os>` (77 invocations in
`test_matrix.json`, plus invocation from
`pkg/test_runner/lib/src/build_configurations.dart:55`); matrix UX
(`--mode=all`, `-a all`, `--sanitizer=all` expanding to per-platform
default lists); `RBE=1` env var auto-enabling RBE (documented at
`go/dart-rbe`); sanitizer env auto-injected when building a
sanitizer config (no developer remembers `ASAN_SYMBOLIZER_PATH`);
macOS `CPATH` / `LIBRARY_PATH` / `SDKROOT` env hygiene — Apple's
system Python sets them and silently breaks clang (openradar
5608755232243712, dart-lang/sdk#52411).

**Five clean drops** (sdk-sqa): `--check-clean` (Bazel guarantees
idempotence by construction), `tools/generate_buildfiles.py` (gclient
hook obsolete), `tools/gn_helpers.py` (39-line GN-args quoting
helper), `--ide=vs / --ide=xcode` (Bazel + Hedron compile_commands
replaces), `build/rbe/rewrapper_dart.py` (only if reclient is also
dropped — see §3.4).

**Version stamping is load-bearing.** `utils.py:GetVersion` reads
`tools/VERSION` (CHANNEL / MAJOR / MINOR / PATCH / PRERELEASE) and
`git rev-parse HEAD` (revision), producing `3.7.0-edge.<sha>` strings
baked into the built `dart` binary and consumed by `dart --version`
and the SDK-hash kernel-compat check (sdk-sqa, **high** confidence).

**GN load-time escape hatches** (sdk-06y, **high** confidence on
counts verified by grep + manual scan):

| Mechanism | Count | Severity |
|---|---:|---|
| `read_file(...)` | 2 | low — both embed CIPD instance hashes for `-DTOOLCHAIN_VERSION` / `-DSYSROOT_VERSION` (attribution only) |
| `exec_script(...)` | **17** | the long pole |
| `get_path_info(...)` | 17 | very low — pure string ops, no I/O |
| `get_label_info(...)` | 16 | low — clean provider-access equivalent |
| `get_target_outputs(...)` | 7 (all in `runtime/bin/BUILD.gn:818–840`) | low — Bazel auto-resolves rule deps to outputs |
| `write_file(...)` | 0 | — |
| Globs / wildcards in source lists | **0** | **none** — the SDK enumerates every source file by hand in `.gni` files |

**The biggest single finding: zero implicit-glob source lists.** The
SDK uses explicit per-file source lists in `vm_sources.gni`,
`platform_sources.gni`, `bin_sources.gni`, etc. throughout. The only
build-time filesystem discovery is
`third_party/binaryen/list_sources.py` (1 site, vendored 3p). This
makes the Bazel load-phase port substantially easier than for
Chromium-style projects (sdk-06y).

The 17 `exec_script` sites split across a handful of jobs (sdk-06y):
git/SDK-hash discovery (2 — `get_dot_git_folder.py`,
`make_version.py`); Apple SDK detection (2 — `find_sdk.py` for ios +
mac, replaceable by `xcode_config` / `apple_common`); **Windows MSVC
detection (3 — `setup_toolchain.py`, `vs_toolchain.py get_toolchain_dir`,
`vs_toolchain.py copy_dlls`, the heaviest port)**; sysroot ld-path
resolution (2 — droppable via `cc_toolchain` features); CPU/link
concurrency probes (2 — droppable, Bazel manages concurrency itself);
Windows COFF timestamp (1); the binaryen sources glob (1, becomes
Bazel `glob()`); Debian version stripping (1, becomes
`expand_template`); gtk `pkg-config` (1, **dead code** — both
`gtk_internal_config` invocations are unreferenced); host-byteorder
(1, **dead code** — only fires on ppc64 AIX which Dart doesn't ship);
the ICU-data file-existence probe (1, a deliberate Flutter-engine
vendoring accommodation that needs an explicit Bazel flag —
`--define=embedder=flutter`).

The 13 `get_path_info(".", "abspath")` sites compute a `_dart_root`
indirection that exists because the Dart tree can be vendored under
`//third_party/dart` in client repos; Bazel handles this via
`repo_mapping` / `MODULE.bazel` and the indirection drops out
entirely. Two of the 17 `get_path_info` sites are
`get_path_info(".", "abspath") == "//sdk/"` standalone-vs-vendored
checks (`sdk/BUILD.gn:23`, `:393`) that translate to a
`config_setting` + `select()` (sdk-06y).

## 3. Target state: Bazel

### 3.1 Workspace structure (Bzlmod vs WORKSPACE)

The scout's strategic evaluation of the `kevmoo/bazel_silly` branch
(sdk-33x) and the gn-desc follow-up (sdk-suy) both treat the workspace
shell as a minor cost relative to the rule library and toolchain work.
The proposed minimal shape is a hand-written `MODULE.bazel` (or
`WORKSPACE`) wired to a single local `cc_toolchain` hand-ported from
`build/toolchain/linux/BUILD.gn` and `buildtools/`, hardcoded to one
platform (Linux x64 Release) for the first proof and expanded later.

**The rules_dart situation forces the bigger question.** All four
known iterations of `rules_dart` — `dart-archive/bazel`,
`dart-archive/rules_dart`, `cbracken/rules_dart` (archived 2025-06),
`matanlurey/rules_dart` (archived 2024-09) — are **archived**
(sdk-8er, **high** confidence — verified against public GitHub
state). Combined, the two best forks (cbracken + matanlurey) cover
`dart_library`, `dart_vm_binary`, `dart_vm_snapshot`, `dart_vm_test`,
`dart_web_application`, `dart_web_test`, plus a `pub.package` Bzlmod
extension — but **neither covers AOT (`dartaotruntime`,
`gen_snapshot`) workflows**, which are core to Dart SDK builds. The
migration cannot borrow rules_dart; it **must own authoring
rules_dart from near-scratch**, or revive cbracken's archived fork
(read-only, fork-and-resume) and design the AOT rules from zero
(sdk-8er).

This recasts the Bzlmod-vs-WORKSPACE decision: the choice should be
informed by what `rules_dart` is being authored, not the other way
around. Bazel 8.0 LTS (Dec 2024) made Bzlmod the default and BCR the
canonical registry, so a green-field rules_dart published to BCR
would naturally target Bzlmod; a fork-and-revive path inheriting
cbracken's WORKSPACE machinery extends the WORKSPACE timeline. Either
is defensible; the choice is downstream of the rules_dart authoring
strategy and not settled here.

**One real piece of existing Bazel surface lives in the SDK today.**
`utils/bazel/kernel_worker.dart` (89 lines) plus `utils/bazel/BUILD.gn`
(42 lines) ships the Dart CFE persistent-worker protocol
implementation as `kernel_worker_aot_product.dart.snapshot` —
consumed by external Bazel users (`rules_dart`, `dart-lang/build`'s
Bazel integration) (sdk-edw, **high** confidence — both files read
end-to-end). This is a **shipping artifact, not build-system rules**:
zero `.bzl`, zero `BUILD.bazel`, zero `MODULE.bazel` files exist in
the SDK source tree (the lone `pkg/analyzer_cli/test/data/blaze/
WORKSPACE` is a 0-byte sentinel fixture for analyzer's
workspace-detection logic). The migration cannot claim prior-art
credit, but it **must preserve the snapshot path and
`--persistent_worker` CLI surface** — these are downstream contracts
(sdk-edw, §3.5).

**The precedent landscape** (sdk-8er, **medium-high** confidence on
the structural conclusions; all sourced from public RFCs, GitHub
issues, and the relevant repos): big Google GN-based projects have
**not** migrated to Bazel. Chromium never seriously tried. Flutter
engine's Bazel adoption has been **stalled for 7+ years** explicitly
because `rules_dart` was a precondition blocker
(`flutter/flutter#58082` open since 2020, `#14125` since 2017). Skia
did migrate but by **inverting direction** (Bazel as source of truth,
GN as generated artifact via `bazel/exporter_tool/`) — requires
re-authoring every target in Bazel up front and maintaining the
exporter indefinitely, contradicting the gn-desc-driven translator
approach (§3.2). Fuchsia chose **permanent coexistence** under a
`fint` wrapper, with explicit acknowledgment of a **~10% clean-build
overhead from filesystem sandboxing** (RFC-0186). The Dart SDK's
recommended coexistence path is §4.3.

### 3.2 Rule mapping (GN constructs → Bazel rules)

The first attempt at this — the `kevmoo/bazel_silly` compdb-translation
experiment — was a deliberate "experiments that don't do much" probe,
and it exposed the cost of a naive compile-commands translator: it
captured per-target source lists and `-D` defines, then dropped almost
everything else structural (sdk-33x). The follow-up evaluation of
`gn desc //* --format=json` against the existing `out/ReleaseX64`
configured directory (Linux x64 Release) found that gn desc exposes
the structural information that compdb flattens out, and strictly
dominates compdb as a translation input (sdk-suy, **high** confidence
on the dominance claim).

**What gn desc gives you that compdb doesn't.** For each target,
`gn desc --format=json` returns the GN target type (`source_set`,
`static_library`, `executable`, `action`, `copy`, `group`, …), the
resolved per-target `defines` / `cflags` / `cflags_c` / `cflags_cc` /
`asmflags` / `ldflags` / `libs` / `include_dirs` (already merged through
the `configs` chain), explicit `deps` with target labels, sources
including headers and `.S` assembly, and — for actions — the `script`,
`inputs`, `outputs`, and `args` (sdk-suy). On the three sampled
targets (`libdart_aotruntime`, `libdart_vm_jit`,
`libdart_vm_precompiler`) the structural information needed to emit a
buildable `cc_library` was present in the JSON: `libdart_vm_jit` has
460 sources (222 `.cc` + 237 `.h` + 1 `.S` — the `.S` is
`ffi_trampolines_arm64.S`, which compdb captured zero of), three
explicit deps (icu i18n / uc, perfetto), 13 merged defines, and 8
`include_dirs` (sdk-suy). The 13 `libdart_vm_*` variants share all 460
sources and differ only in a small set of defines (5 distinct keys:
`PRODUCT`, `DART_PRECOMPILER`, `DART_PRECOMPILED_RUNTIME`,
`EXCLUDE_CFE_AND_KERNEL_PLATFORM`, `TESTING`,
`FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION`) plus arch tokens — a
textbook `select()` shape.

**gn desc vs the 12 sdk-33x roadblocks.** Carrying the
`kevmoo/bazel_silly` analysis forward, the 12 roadblocks that doomed
compdb-as-foundation (catalogued in §5.1) fare very differently against
gn desc. Receipt (sdk-suy):

| Roadblock | compdb status | gn desc status |
|---|---|---|
| 1. Configuration locking (single platform) | Single platform baked in | One `out/` = one config; mitigation is per-config `gn gen` + `gn desc`, diff the dumps into `select()`. **Partial fix.** |
| 2. Absence of headers | Zero `hdrs` anywhere | Headers present in `sources`. **Fully fixed.** |
| 3. Toolchain flags dropped | All non-`-D` / `-I` flags lost | Full `cflags` / `cflags_c` / `cflags_cc` / `asmflags` / `ldflags` / `libs` preserved. **Fully fixed.** |
| 4. Monolithic deps | No deps at all | Explicit `deps` with target labels. **Fully fixed.** |
| 5. 76 fake targets = 9 logical × 14 configs | Variant explosion as duplicated rules | Variants exposed AND their diff is small (5-key define set + arch); foldable into `select()`. **Fully fixed.** |
| 6. Duplicate source across variants | Symptom of #5 | Same root cause; fixed by folding variants. **Fully fixed.** |
| 7. Generated `.cc` in srcs without genrule | Paths to non-existent build outputs | `action` targets exposed with `script` / `inputs` / `outputs` / `args`. **Fully fixed.** |
| 8. No final linkable | 123 of 199 prefixes silently dropped | Executables present as `type=executable` with full deps + ldflags + libs. **Fully fixed.** |
| 9. Cross-toolchain `version.cc` merge | Two output paths conflated | Each toolchain visible via parenthesized suffix on the target label; 25 such variants in the Linux x64 dump. **Fully fixed.** |
| 10. `.S` assembly absent | compdb captures 0 `.S` files | gn desc includes `.S` (e.g. `ffi_trampolines_arm64.S` in `libdart_vm_jit`). **Fully fixed.** |
| 11. `-DDART_TARGET_OS` over-filter | Script-side bug in the translator | Not relevant — gn desc returns logical defines. **N/A.** |
| 12. rewrapper-wrapped commands | compdb captures wrapper-prefixed cmd line | gn desc captures logical params, no wrapper bleed-through. **Fully fixed.** |

Of the 12, gn desc fixes 10 fully, 2 partially, 1 N/A. The scout
reports **high** confidence on this comparison — each row was verified
against gn desc fields on the three sampled targets and on a sampled
action (sdk-suy).

**The one thing gn desc does not give you: toolchains.** `gn desc`
cannot introspect `toolchain()` declarations. Querying
`//build/toolchain/linux:clang_x64` directly reports "matches no
targets, configs or files" — verified empirically (sdk-suy, **high**
confidence). The toolchain has to be ported separately by reading
`build/toolchain/<os>/BUILD.gn` (~319 lines for Linux); the migration
cannot transcribe it mechanically. The same caveat applies to GN's
higher-level templates (`library_for_all_configs`, the `_all_configs`
matrix from §2.1): gn desc shows the **expanded** targets but not the
template machinery. For a translator that is fine — the translator
wants expanded targets. For a human auditor verifying the translation
it is worth knowing.

**Configs are a separate two-pass dump.** `config()` targets are
omitted from the `//*` wildcard dump (verified: zero `config` entries
in the target-type breakdown of the Linux x64 dump). Targets reference
configs by label, but the config definitions are queryable only
individually — a translator that wants to preserve `public_config`
propagation explicitly does a second pass dumping each referenced
config; a translator that is happy with the already-merged per-target
`defines` / `cflags` / `include_dirs` skips this entirely. The second
pass is cheap (a few hundred parallel `gn desc` invocations) but
**optional** (sdk-suy).

**GN → Bazel mapping (gn-desc-driven).** With gn desc as the input,
the mapping collapses to one row per resolved target type:

| GN target type | Bazel target | Notes |
| --- | --- | --- |
| `source_set` | `cc_library` | `srcs` = `.cc` / `.c` / `.S`; `hdrs` = `.h`; `deps` + `copts` + `defines` + `includes` from gn desc fields. |
| `static_library` | `cc_library` (no `linkstatic`) or `cc_static_library` | Same shape as `source_set`. |
| `shared_library` | `cc_shared_library` | Adds shared-lib name plumbing. |
| `executable` | `cc_binary` | `deps` + `linkopts` from `ldflags` + `libs`. |
| `action` | `genrule` (simple) or custom Starlark rule (depfiles, providers, host transitions) | gn desc supplies `script` / `inputs` / `outputs` / `args`. Simple 1:1, static-input cases map to `genrule` (e.g. `generate_version_cc_file`); the depfile-emitting and Dart-runs-Dart edges enumerated in §2.2 (`aot_snapshot`, `application_snapshot`, `compile_platform`, `kernel_service_dill`, `aot_compile_using_prebuilt_sdk`) need custom rules. |
| `copy` | `genrule` or `filegroup` | Trivial. |
| `group` | `filegroup` | Trivial. |
| 14-variant `library_for_all_configs` expansion | One `cc_library` + `config_setting`s + `select()` on defines | Per-variant defines diff is computable from the JSON. |
| `public_config` with `include_dirs` | `includes` attr (propagates to deps) | Already resolved by gn desc into per-target `include_dirs`; preserving propagation explicitly is optional fidelity. |
| `config()` targets (e.g. `dart_arch_config`) | Inlined into target via merged fields | Not in `//*`; optional second pass recovers them if wanted (sdk-suy). |
| `toolchain()` declarations | Hand-ported `cc_toolchain` + `cc_toolchain_config` | Not queryable via gn desc; must be read from `build/toolchain/<os>/BUILD.gn` (sdk-suy, **high** confidence). |

The earlier "easy 20% / structural 80%" framing was correct **for the
compdb approach** (sdk-33x): compdb captured the easy 20% and dropped
the structural 80%. Against gn desc the framing inverts — gn desc
hands you the structural 80% directly, and the remaining 20% is the
toolchain port plus the small set of custom rules for Dart-builds-Dart
actions and `copy_tree`-style directory operations identified in §2.2
(sdk-1z9). The full rule library is still §3.2's open detail pending
the follow-up findings (sdk-clv on cross-compile / toolchain
resolution, sdk-q3t on per-target defines vs `cc_toolchain` features,
sdk-edw on `utils/bazel`, sdk-p0i on the `_all_configs` Starlark macro
shape). The scout's strategic verdict for this pass is unambiguous:
**use gn desc as the primary translator input, hand-port the
toolchain, and don't go back to compdb** (sdk-suy).

### 3.3 Toolchain resolution and platforms

§3.2's mapping established that `gn desc` exposes per-target toolchain
labels but cannot introspect `toolchain()` declarations themselves —
those must be hand-ported. This section deepens what that port produces.

**One `cc_toolchain` per (arch, os) pair, sanitizers as features.**
GN's 60 Linux toolchain instances (13 arch suites × 5
sanitizer/shared variants) collapse to roughly **6 Bazel
`cc_toolchain` targets for Linux** (`linux_x64`, `linux_arm64`,
`linux_arm`, `linux_riscv32`, `linux_riscv64`, `linux_x86`) plus
**~5 toolchain features** (`asan`, `msan`, `tsan`, `ubsan`, `pic`)
(sdk-clv, **high** confidence on the structural mapping; **medium**
on the exact toolchain count — depends on initial-phase OS scope).
Switching to a sanitised build becomes `--features=asan`, not
switching to a different toolchain. Across all OSes the GN/Bazel
reduction is roughly **15× fewer toolchain configs**. The `_shared`
toolchain is **dropped entirely** in favour of Bazel's
`cc_shared_library` rule on top of static `cc_library` — the
`is_shared_library` GN arg disappears (sdk-clv).

**Sanitizers wire via `cc_toolchain` features**, not separate
configs. Because GN gates sanitizers inside `compiler:compiler` itself
(§2.3, sdk-q3t), the Bazel translation collapses cleanly: one feature
per sanitizer, each adding `-fsanitize=*` to compile and link flags,
plus a `sanitizer_runtime` feature that emits
`-Wl,-u,_sanitizer_options_link_helper` and pulls in
`build/sanitizers:options_sources` (the small source set with
`sanitizer_options.cc`). Standard Bazel pattern, used by Chromium and
others (sdk-q3t, **high** confidence on the pattern).

**`build/config/` configs partition into four buckets** (sdk-q3t):
~70% become `cc_toolchain` features (warnings, RTTI/exceptions,
optimisation, debug symbols, sanitizers, visibility, sysroot); ~15%
become per-target `defines` / `local_defines` (debug/release/product,
`dart_shared_lib`); ~10% become per-OS toolchain configs (Linux vs
Mac vs Windows vs Android NDK have genuinely different compiler
shapes); ~5% become per-platform `select()` over `@platforms//os:*`
and `@platforms//cpu:*` (ARM-only flags like `compiler_arm_fpu`).
The Windows MSVC path is the heaviest port — about half of
`compiler/BUILD.gn`'s 973 lines is `is_win`/`is_android`/`is_mac`/
`is_ios`/`is_fuchsia` branches with elaborate per-platform warning
suppression. For a Linux-x64-first migration, only the Linux x64 path
needs porting first.

**The 14 `_all_configs` variants map to a Starlark macro, not
`select()`.** This is sdk-p0i's load-bearing insight: variants are
**consumer-selected at the dep edge** (`//runtime/bin:dart` links
`libdart_aotruntime_product`, `:dartvm` links `libdart_jit`, etc.).
A single Bazel build invocation needs MULTIPLE variants
simultaneously, which `select()` cannot express — `select()` picks
one config per build, and you'd lose the ability to link `_jit` and
`_aotruntime_product` in the same `bazel build`. The correct
translation is a Starlark macro at load time emitting **N
`cc_library` targets**, each with its variant's defines and the
boringssl-on-precompiler conditional dep (sdk-p0i, **high**
confidence). Sketch:

```python
# //runtime/configs.bzl
_ALL_CONFIGS = [
    struct(suffix = "_jit",                 snapshot = True,  compiler = True,
           is_product = False, arch = None, os = None, extra = []),
    struct(suffix = "_jit_product",         snapshot = True,  compiler = True,
           is_product = True,  arch = None, os = None, extra = ["PRODUCT"]),
    struct(suffix = "_aotruntime",          snapshot = True,  compiler = False,
           is_product = False, arch = None, os = None,
           extra = ["DART_PRECOMPILED_RUNTIME", "EXCLUDE_CFE_AND_KERNEL_PLATFORM"]),
    # ... 11 more
]

def library_for_all_configs(name, srcs, hdrs = [], deps = [],
                            extra_precompiler_deps = [], **kwargs):
    for conf in _ALL_CONFIGS:
        defines = ["NDEBUG", "SUPPORT_PERFETTO"] + conf.extra
        if conf.arch: defines.append("TARGET_ARCH_" + conf.arch)
        if conf.os:   defines.append("DART_TARGET_OS_" + conf.os)
        rule_deps = deps + (extra_precompiler_deps if (conf.compiler and not conf.snapshot) else [])
        native.cc_library(name = name + conf.suffix, srcs = srcs, hdrs = hdrs,
                          deps = rule_deps, defines = defines, **kwargs)
```

A consumer then writes `deps = [":libdart_vm_jit"]` or
`deps = [":libdart_vm_precompiler_product_linux_arm64"]`. The macro
emits ~30 lines of boilerplate per `library_for_all_configs` call
site (sdk-p0i).

**Cross-compilation collapses cleanly.** The
`current_toolchain != host_toolchain` host-tooling switch (§2.3)
becomes Bazel's `cfg = "exec"` transition on `genrule.tools` and
similar — Bazel auto-selects the exec-compatible toolchain when a
tool is consumed in target-config context (sdk-clv, **high**
confidence). The cross-arch precompiler variants
(`_precompiler_product_linux_arm/arm64/riscv64/x64`) need NO Bazel
transitions because they are not actually cross-compiles — they are
host-x64 `cc_library`s with `-DTARGET_ARCH_*` (§2.3). Each
`gen_snapshot_<arch>` `cc_binary` `select()`s its
`libdart_precompiler_product_linux_<arch>` dep based on
`--platforms`, and the AOT codegen `genrule` does the same for its
`tools` attr:

```python
genrule(
    name = "my_aot_snapshot",
    srcs = [":app.kernel"],
    outs = ["app.snapshot"],
    cmd  = "$(location :gen_snapshot) ...",
    tools = select({
        "@platforms//cpu:aarch64": [":gen_snapshot_arm64"],
        "@platforms//cpu:x86_64":  [":gen_snapshot_x64"],
        "@platforms//cpu:riscv64": [":gen_snapshot_riscv64"],
        "@platforms//cpu:arm":     [":gen_snapshot_arm"],
    }),
)
```

The `gen_snapshot` binaries are always exec-config (built with the
host clang); the output is target-arch-specific data Bazel doesn't
need to model (sdk-clv).

**Args that resist clean mapping** (sdk-clv): `is_shared_library`
(drop — model at rule level via `cc_shared_library`);
`default_git_folder` and `dart_sdk_verification_hash` (port to
`repository_rule` that reads `.git` once at workspace setup, OR to
`--workspace_status_command`); `dart_target_arch` differing from
`target_cpu` (simulator case — separate `bool_flag` layered onto the
normal platform); `is_qemu` (a feature OR a separate platform
constraint, depending on CI shape).

### 3.4 Third-party dependencies under Bazel

**The DEPS catalogue from §2.4 maps to three Bazel mechanisms**
(sdk-4h1, **high** confidence on the patterns):

| DEPS construct | Bazel equivalent | Notes |
|---|---|---|
| CIPD binary package (`dep_type: cipd`) | `http_archive` against `https://chrome-infra-packages.appspot.com/dl/<pkg>/+/<version>` with `sha256` pin | CIPD packages download over HTTPS without a CIPD client. Version-tag → archive SHA needs a one-time resolver; write `tools/cipd_to_bazel.py` emitting `MODULE.bazel` snippets. |
| Git repo (URL@SHA) | `bazel_dep` from BCR where available; else `git_override(...)` for modules; else `http_archive` against the gitiles `+archive/<sha>.tar.gz` URL | Gitiles `+archive` works for every `dart.googlesource.com` mirror. Content-addressed tarballs are cleaner than `git_repository`'s clone-and-checkout. |
| `hooks` (post-sync Python) | `module_extension` running the script during `bazel sync`, OR replace with native Bazel rules | Some hooks (package_config gen, sdk version) become trivial `genrule`s; others (emsdk, Fuchsia gen_build_defs) are more involved. |

**Per-dep proposed mapping** (sdk-4h1):

- **Hermetic `cc_toolchain` inputs.** `buildtools/<plat>/clang` (Fuchsia
  clang CIPD) registers as a `cc_toolchain` via `rules_cc` or
  `bazel-toolchain` (grailbio); wrap the CIPD download in
  `http_archive` and emit a `cc_toolchain_config` Starlark target.
  `buildtools/sysroot/<linux|focal>` exposes as a `filegroup`
  referenced by `cc_toolchain.builtin_sysroot`.
  `buildtools/<plat>/clang-format` becomes a custom toolchain or a
  runnable target. **`buildtools/ninja` and `buildtools/gn` are not
  needed** — Bazel replaces both. `buildtools/reclient` wiring depends
  on the RBE strategy (below).

- **Prebuilt Dart SDK bootstrap (`tools/sdks/dart-sdk`).** The most
  critical bootstrap dep — every `prebuilt_dart_action` uses it (§2.2).
  Pull via `http_archive` from the dart-sdk CIPD URL (resolved from
  `sdk_tag`), or alternatively from the canonical archive at
  `https://storage.googleapis.com/dart-archive/` (more public, less
  Google-internal). Expose via a `dart_toolchain(prebuilt_sdk = ...)`
  with `dart` and `dartaotruntime` as executable targets.

- **Native C++ deps.** `bazel_dep` from BCR where available (zlib,
  boringssl, icu, googletest, abseil all have BCR modules); otherwise
  `http_archive` against the gitiles `+archive/<sha>.tar.gz` URL. Each
  upstream needs a `BUILD.bazel` shim or a vendored copy from BCR.
  `third_party/binaryen` is the one place that consumes its own
  source list via `list_sources.py` (§2.6 / sdk-06y) — that translates
  to a Bazel `glob()` at `BUILD.bazel` load time.

- **Dart third-party packages (`third_party/pkg/*`).** Each git repo
  is multi-package; pull as one `http_archive` per repo, then add
  `BUILD.bazel` shims (or generate them from each sub-package's
  `pubspec.yaml`) exposing `dart_library` targets per pub package.
  **The `dependency_overrides` map in root `pubspec.yaml` becomes the
  pubspec-name → Bazel-label lookup table** — feed it directly to the
  BUILD.bazel generator (sdk-rsv; see §3.5).

- **`co19` test corpus.** CIPD → `http_archive` in a `tests/co19/`
  external repo; a `dart_test_suite` custom rule iterates the tests.

- **Browser binaries** (chrome, firefox, chromedriver, d8, jsshell,
  jsc). All optional and conditional today; in Bazel, gated by
  `--config=browser` (or `--//flags:download_chrome=true`) `select()`s;
  each browser becomes an `http_archive` per platform, runtime-injected
  via `data` attribute on browser-based `dart_test` targets.

- **Emscripten** (`third_party/emsdk`). Its own install/activate dance.
  Bazel-side: `repository_rule` that runs `emsdk install/activate`
  during `bazel sync`, OR the unofficial `rules_emscripten`. **Defer
  to phase 2** (sdk-4h1).

- **Fuchsia and Android.** Bazel has `rules_fuchsia` and
  `rules_android`; both are non-trivial workstreams. Initial Bazel
  target skips Fuchsia and re-introduces later; Android wires
  `android_sdk_repository` / `android_ndk_repository` with the
  existing `third_party/android_tools` CIPD package.

**Hooks → Bazel disposition** (sdk-4h1):

| Hook | Disposition | Notes |
|---|---|---|
| `tools/generate_package_config.py` | **Replace** | Either generate from BUILD-derived dep graph, OR run `dart pub get` once during `bazel sync` via `module_extension`. Long-term: eliminate `.dart_tool/package_config.json` in favour of Bazel-derived per-rule package configs. |
| `tools/generate_sdk_version_file.py` | **Port** as `genrule` reading `tools/VERSION` |
| `tools/generate_large_tests.py` | **Port** as Bazel macro fanning out a `dart_test` per generated test |
| `tools/buildtools/update.py` | **Drop** | Bazel handles toolchain registration natively. |
| `build/vs_toolchain.py update` | **Drop** | Use `rules_cc`'s MSVC autodetection. |
| emsdk install/activate | **Port to `module_extension`** | Same effect, runs during `bazel sync`. |
| Fuchsia `update_product_bundles.py`, `gen_build_defs.py` | **Defer** |

**RBE strategy (sdk-evr).** Today's RBE topology runs Google's
reclient/reproxy against `remotebuildexecution.googleapis.com`
(instance `projects/flutter-rbe-prod/instances/default`), with two
distinct code paths: toolchain-level C++ compile wrapping via
`rewrapper` (~16 sites across `linux`/`mac`/`win`/`android`/`fuchsia`
toolchains, all gated by `use_rbe`), and Dart-tool invocation
wrapping via `build/rbe/rewrapper_dart.py` — an **800-line ad-hoc
Dart-import parser** that knows the CLI shape of every Dart-binary
entry point used during the SDK build so it can compute the
transitive input set for each remote action (sdk-evr, **high**
confidence — read end-to-end). It maintains 15 program-specific
parser methods (`parse_dart`, `parse_dart2js`, `parse_dartdevc`,
`parse_compile_platform`, `parse_kernel_worker`, `parse_gen_kernel`,
`parse_gen_snapshot`, …), rewrites absolute paths in command lines
to relative (lines 125–140), rewrites depfile paths back from RBE
worker exec_roots (lines 781–794), and contains stamp-file kludges
to compensate for reclient bugs (lines 757–759).

**The Bazel translation: `rewrapper_dart.py` disappears entirely**
(sdk-evr, **high** confidence on the structural simplification). It
is replaced by:
- Custom `dart_*` Starlark rules that declare their inputs via
  `attr.label_list(allow_files=[".dart"])` and let Bazel track inputs
  declaratively;
- `cc_toolchain` with `exec_properties = {"container-image":
  <rbe_image>, "OSFamily": "Linux"}` for C++ remote execution;
- `.bazelrc` config selecting `--remote_executor=`,
  `--remote_instance_name=`, `--remote_local_fallback`.

```bazelrc
# .bazelrc
build:rbe --remote_executor=remotebuildexecution.googleapis.com
build:rbe --remote_instance_name=projects/flutter-rbe-prod/instances/default
build:rbe --google_default_credentials
build:rbe --remote_cache_compression
build:rbe --remote_local_fallback
build:rbe --extra_execution_platforms=//build/platforms:linux_x64_rbe
build:rbe --host_platform=//build/platforms:linux_x64_rbe
```

**Three load-bearing hermeticity risks the migration must resolve**
(sdk-evr):

1. **Absolute paths in Dart command lines.** Inline comments in
   `rewrapper_dart.py:768–772` acknowledge: *"The Dart SDK build rules
   needs to be fixed rather than doing this, but this is an initial
   step towards that goal."* Bazel's sandbox enforces relative paths;
   the build itself must be fixed before any Dart action runs
   remotely under Bazel.
2. **Ad-hoc Dart import parser is unsound.** The parser at
   `rewrapper_dart.py:78–106` is "designed to be much faster than
   actually invoking the front end" (line 71) — string-level
   tokenisation, not the actual Dart resolution algorithm. Bazel will
   reject any action whose declared inputs don't include what the
   action actually reads. **Every Dart-runs-Dart rule needs to declare
   its `.dart` srcs honestly**, which probably means a `dart_deps`
   aspect or a `dart_library` rule tracking transitive `.dart` files
   — non-trivial design work.
3. **`.dart_tool/package_config.json` is a build artifact, not a
   source.** In Bazel, it needs to be generated by a `repository_rule`
   at workspace setup OR declared as the output of a `pub_get` rule
   that every Dart action depends on (sdk-evr, **high** confidence).

The C++ wrapping (toolchain-level `if (use_rbe) { command =
rewrapper_args + cmd }` at ~16 sites) reduces to `exec_properties` on
the `cc_toolchain` and Bazel's built-in remote execution. The
`build/rbe/llvm.sh` 8-line shim that materialises clang in a writable
path becomes unnecessary because `cc_toolchain.compiler_files`
declares its inputs and Bazel handles sandbox materialisation
(sdk-evr).

Two minor follow-ups (sdk-evr): `parse_kernel_worker` is defined
twice in `rewrapper_dart.py` (lines 552 and 657) with different
bodies — Python uses the second; either a latent bug or a deliberate
override. Worth a separate bead, though the file disappears in the
migration so the bug becomes moot. And the `.cfg`-file
selection mechanism (`linux-intel.cfg` vs `unix.cfg` vs
`win-intel.cfg` vs `windows.cfg`) wasn't found in `*.gn` / `*.gni` —
**medium** confidence on which platform uses which file.

### 3.5 Test integration

> [!IMPORTANT]
> **The target test integration design has evolved to a unified 4-Phase pure Bazel testing roadmap.**
> Instead of executing status file parsing natively inside Starlark at analysis time, we utilize a dynamic dry-run JSON metadata exporter from the Dart test runner and a standalone hermetic wrapper executor.
> For the comprehensive architecture, phase breakdown, and immediate refactoring items, see the dedicated deep-dive: **Testing Migration Roadmap** (`deep_dives/testing_migration_roadmap.md` — deleted in the Session-120 docs prune; recover via git history).

**Capability-by-capability mapping** of `tools/test.py` + `pkg/test_runner`
against `bazel test` (sdk-9jz, **high** confidence on the structural
inventory; **medium** on Bazel-side cost estimates):

| Capability | Bazel native? | Mapping |
|---|---|---|
| FS-walk discovery | **No** | Custom Starlark repository rule dynamically generates `BUILD.bazel` targets by invoking the Phase 1 dry-run JSON metadata exporter at analysis time (Phase 3). |
| `// VMOptions=` / `// SharedOptions=` / `// Environment=` magic comments | **No** | Test runner keeps parsing them at runtime; the `dart_test` rule doesn't need to know. |
| 8-dim Smith matrix | **Partial** | `--config=dart_<compiler>_<mode>_<arch>` flag space; hundreds of `.bazelrc` entries (or generated config). `bazel cquery` exposes per-config. |
| `.status` file evaluation | **No** | Handled dynamically by the dynamic JSON metadata exporter and hermetic executor (Phases 1-2). Evaluated at execution time under the sandbox rather than Starlark analysis time. |
| Outcome semantics beyond pass/fail (`RuntimeError`, `MissingRuntimeError`, …) | **No** | Standalone hermetic executor `run_single_test.dart` accepts a single resolved test config and translates outcomes against expected outcomes to exit code 0 (Phase 2). |
| Multitests (synthetic file expansion) | **No** | Either keep runtime expansion in the runner (simpler) or move to a build-time `genrule` per `_test.dart` (more Bazel-native). |
| Sharding | **Partial** | Bazel's `shard_count = N` shards a single rule's cases; Dart's sharding shards the SUITE LIST across CI machines. Different scope — CI orchestration computes `--test_filter` partitions per shard and invokes `bazel test` N times. Bazel itself doesn't need to know it's being sharded. |
| Deflaking (per-test repeat + timeout JSON) | **Partial** | `bazel test --runs_per_test=N --runs_per_test_detects_flakes` covers coarse retry; per-test override stays an out-of-band CI step driven by `bazel test --runs_per_test=N //tests/language:specific_test` per item. |
| Per-test timeout (`Slow` / `ExtraSlow`) | **Partial** | Map .status `Slow`/`ExtraSlow` → Bazel `size = small/medium/large/enormous` (60s/300s/900s/3600s). DeflakeInfo timeout overrides remain runtime, handled in the wrapper. |
| `results.json` / `logs.json` schema | **No** | Wrapper script (or runner-internal write) emits the file alongside Bazel's `test.log` / `test.xml`. **Format must survive byte-for-byte** — the `dart-current-results.appspot.com` dashboard and the deflake bot are out-of-band consumers (sdk-9jz). |
| Core-dump archival, FD limit, adb path | **No** | Per-test wrapper script does the equivalent. Trivial. |
| `--test-list` (run only named tests) | **Yes** | `bazel test --test_filter='regex'` covers it; the runner-as-bazel-executable reads `TESTBRIDGE_TEST_ONLY` and filters accordingly. |

**Dart library generation from pubspecs.** Two viable strategies for
the pubspec → Bazel deps translation (sdk-rsv, **medium** confidence
on the preferred path):

1. **Pubspec-derived `BUILD.bazel` generation (gazelle-style).** A
   generator walks every `pkg/*/pubspec.yaml`, parses `dependencies`
   and `dev_dependencies`, and emits a `BUILD.bazel` per package
   with `dart_library`, `dart_test`, etc. **The path-override map in
   root `pubspec.yaml` is the pubspec-name → Bazel-label
   translation table** (e.g. `path: third_party/pkg/core/pkgs/collection`
   → `//third_party/pkg/core/pkgs/collection:collection`). Build-time
   deps differ from `pub get` deps (semver constraints are ignored;
   everything is path-resolved). Regen-on-pubspec-edit workflow,
   `bazel run //:gazelle_dart` convention.
2. **Opaque pub-workspace model (mirror today's GN).** Treat all
   `pkg/` + `third_party/pkg/` as one large `filegroup` fed into
   every snapshot rule. Keep `.dart_tool/package_config.json`
   (generated by a `repository_rule` running `dart pub get`). Trivial
   migration; loses much of Bazel's incremental value.

Hybrid is feasible: opaque initially, generator added later. The
hybrid path lets the migration land without committing to a final
Dart-deps model on day one.

**`utils/bazel/` is a shipping artifact, not a build tool**
(sdk-edw, **high** confidence — both files read end-to-end). The
directory's name is misleading: it contains the **Bazel
persistent-worker protocol implementation for the Dart Common
Front-End**, shipped as the `kernel_worker_aot_product.dart.snapshot`
that EXTERNAL Bazel users (Google's internal `rules_dart`,
`dart-lang/build`'s Bazel integration) invoke as
`dartaotruntime <snapshot> --persistent_worker`. There are **zero**
Bazel build-system files in the SDK source tree (no `.bzl`, no
`BUILD.bazel`, no `WORKSPACE`, no `MODULE.bazel` — except a 0-byte
sentinel at `pkg/analyzer_cli/test/data/blaze/WORKSPACE` used as a
fixture to test analyzer's workspace detection) (sdk-edw). The
implications for the migration:

- **No prior-art credit.** The migration cannot say "we already have
  some Bazel rules"; there is none.
- **There IS a compatibility surface that must not break.** External
  Bazel-based build systems treat
  `<SDK>/bin/snapshots/kernel_worker_aot_product.dart.snapshot` +
  `--persistent_worker` as a contract. The Bazel migration of the SDK
  build must continue to produce this snapshot at the same canonical
  path with the same CLI surface (sdk-edw, **high** confidence).
- **Mild irony / good early target.** When SDK-side Bazel rules
  exist, one of the first snapshots they'll build is
  `kernel_worker_aot_product.dart.snapshot` — the input to external
  Bazel users. `utils/bazel/` should be among the **first** things to
  port, so the new Bazel rule can be verified byte-for-byte against
  the GN-produced snapshot.

The DDC also ships a worker-mode entry (`pkg/dev_compiler/lib/ddc.dart`
with `--bazel_worker`); its snapshot may be part of the same
compatibility contract (sdk-edw, **medium** confidence — not audited).

### 3.6 Replacing the Python build layer

**Disposition by responsibility** (sdk-sqa, **high** confidence on the
shape; **medium** on cost; `native` = Bazel covers it natively / drop
the Python; `port` = wrapper still needed; `drop` = functionality
disappears with GN):

| Responsibility | Source | Disposition | Notes |
|---|---|---|---|
| Run ninja per config | `build.py:Build` | **drop** | `bazel build` handles deps + parallelism natively. |
| Config matrix expansion (`os × mode × arch × sanitizer`) | `gn.py:ProcessOptions`, `RunGnOnConfiguredConfigurations` | **port** | Bazel = one config per command. Wrapper spawns N `bazel build` calls when user passes `--mode=all -a all`. |
| Arch-string vocabulary → (host_cpu, target_cpu, dart_target_cpu) | `gn.py:HostCpuForArch / TargetCpuForArch / DartTargetCpuForArch` | **port** | Each `simarm64c_x64`-style string becomes `--platforms=//build/platforms:simarm64c_x64` with the three axes encoded as constraints. Significant Starlark work. |
| Per-config args.gn (40+ keys) | `gn.py:ToGnArgs` | **port** | Each `is_debug` / `is_asan` / `dart_use_compressed_pointers` / … becomes a `bool_flag` or `string_flag` feeding `select()` in BUILD files. |
| `dart_stripped_binary = "exe.stripped/dart"` path convention | `gn.py:ToGnArgs:284–292` | **port** as Bazel output paths or wrapper symlinks | Test runner depends on these locations (§2.6). |
| `gn gen` always before build | `build.py:Main:311` | **drop** | Bazel re-analyses BUILD files on every command. |
| `--check-clean` (ninja `-n` idempotence) | `build.py:CheckCleanBuild` | **drop** | Bazel actions are content-addressed; idempotence is guaranteed. |
| RBE bootstrap (start/stop reproxy) | `build.py:StartRBE / StopRBE`, `gn.py:InitializeRBE` | **port** if keeping reclient; **drop** if moving to Bazel-native RBE | See §3.4. |
| Sanitizer env (`ASAN_OPTIONS`, `*_SYMBOLIZER_PATH`) | `build.py:SanitizerEnvironmentVariables`, data in `tools/bots/test_matrix.json` | **port** (data moves into `.bazelrc` per `--config=asan` / `=tsan`) | Symbolizer path: `--test_env=ASAN_SYMBOLIZER_PATH=$(location ...)`. |
| macOS env hygiene (pop CPATH/LIBRARY_PATH/SDKROOT) | `build.py:Main:300–303` | **port** (one-liner) | Without this clang sees Apple-Python paths and silently breaks (openradar 5608755232243712). |
| Linux `QEMU_LD_PREFIX` | `build.py:Main:307–308` | **port** (one-liner) | Only relevant under reclient + QEMU. |
| Build-completion notification | `build.py:NotifyBuildDone` | **port** OR drop | Optional developer convenience. |
| `--ide=vs / --ide=xcode` | `gn.py:ide_switch` | **drop** | Replace with `bazel run` + 3rd-party IDE generators. |
| `--export-compile-commands` JSON DB | `gn.py:BuildGnCommand` | **native** via `hedron_compile_commands` | Drop the flag, document Bazel equivalent. |
| Out-dir naming (`out/ReleaseX64`, `xcodebuild/DebugARM64`) | `utils.py:GetBuildConf` + `BUILD_ROOT` | **port as symlink layer** | Bazel default is `bazel-bin/...`. Test runner + 77 CI invocations rely on `out/<BuildConf>/`. Symlink is much cheaper than updating consumers. |
| Host arch / OS / Rosetta detection | `utils.py:GuessOS / GuessArchitecture / HostArchitectures / IsRosetta` | **native** via `@platforms//host` | Wrapper still picks a default `--platforms=...`. |
| Cross-build detection | `utils.py:IsCrossBuild` | **native** (`--platforms` ≠ `--host_platform`) | |
| Sysroot management (Fuchsia CIPD `linux`/`focal` sysroots) | `gn.py:UseSysroot`, DEPS:399–417 | **port as `cc_toolchain` config** | Sysroot package itself is already external (§3.4); the toolchain definition consumes it. |
| `DART_USE_TOOLCHAIN` (per-arch toolchain prefix) | `gn.py:ToolchainPrefix` | **port** (rare path) | Maps to `--extra_toolchains` + custom `cc_toolchain_config`. |
| `DART_USE_CRASHPAD`, `DART_MAKE_PLATFORM_SDK`, similar opt-ins | `gn.py:ToGnArgs:221–227` | **port as `bool_flag`s** | |
| `--code-coverage` (sets `debug_optimization_level=0` + `dart_vm_code_coverage`) | `gn.py:ToGnArgs:267–268, 316–321` | mostly **native** (`bazel coverage`) + partial port (force -O0) | Bazel coverage is post-hoc instrumentation; Dart VM coverage needs `-O0` baked in. |
| Version stamping (`tools/VERSION` + `git rev-parse HEAD` → `3.7.0-edge.<sha>`) | `utils.py:GetVersion / GetGitRevision / ReadVersionFile` | **port** as `--workspace_status_command` | Bazel exposes `volatile-status.txt`, a `genrule` bakes it into a generated header. Standard Bazel pattern. |
| `tools/generate_buildfiles.py` (gclient hook pre-populating `out/`) | 113 lines | **drop entirely** | DEPS hook becomes obsolete. |
| `tools/generate_idefiles.py` | | **drop** (or port to a separate IDE-setup script) | |
| `build/rbe/rewrapper_dart.py` (Dart-import-parsing RBE wrapper) | 800 lines | **drop with reclient** | Obsolete with Bazel-native actions (§3.4 / sdk-evr). |
| `tools/gn_helpers.py` | 39 lines | **drop** | GN-args quoting helper, no analog. |

**Five must-preserve UX contracts** carry across (sdk-sqa,
**high** confidence on the contract list, **medium** on the
criticality ranking):
1. `tools/build.py` as a callable command with `-m <modes>
   -a <archs> --os <os>` flags (77 invocations in
   `test_matrix.json` + `pkg/test_runner/lib/src/build_configurations.dart:55`);
2. Matrix UX (`--mode=all`, `-a all`, `--sanitizer=all` expanding to
   per-platform default lists);
3. `RBE=1` env-var auto-enabling RBE (documented at `go/dart-rbe`);
4. Sanitizer env auto-injection when building a sanitizer config;
5. macOS `CPATH` / `LIBRARY_PATH` / `SDKROOT` hygiene.

**The wrapper's shape.** `tools/build.py` keeps its name and its
signature. Internally it translates the CLI to one or more `bazel
build --config=<smith-config> //<target>` invocations, manages
parallel invocations for `--mode=all`, plumbs the sanitizer env,
performs the macOS env hygiene, and post-runs a symlink layer that
exposes `bazel-bin/...` under `out/<BuildConf>/`. The arch-string
vocabulary lives in a small Dart library shared between the wrapper
and the test runner; the 40+ `args.gn` keys become `bool_flag` /
`string_flag` targets under `//build:flags`; the per-platform
defaults move into `.bazelrc` `--config=` blocks.

**Two open strategic questions** (sdk-sqa):

- **Reclient vs Bazel-native RBE.** The 800-line `rewrapper_dart.py`
  exists solely because GN/ninja actions can't declare per-action
  inputs the way Bazel actions can. If the migration switches to
  Bazel-native RBE (BuildBuddy/Buildfarm gRPC), all of this
  disappears. If it keeps reclient, all of it gets ported. The
  default recommendation from §3.4 is Bazel-native (sdk-evr; **high**
  confidence on the structural simplification), but the choice has
  cost/coordination implications worth raising explicitly.
- **Sanitizer config data ownership.** `tools/bots/test_matrix.json`
  is the canonical sanitizer-options JSON consumed by both the Python
  wrapper and the test runner. Either it stays as JSON (wrapper
  continues to load it; familiar to maintainers) or moves into
  `.bazelrc` (more Bazel-idiomatic; test runner needs to read from
  there). No strong consensus yet.

## 4. Migration sequencing

### 4.1 First proof: smallest end-to-end target

**Target: `bazel build //runtime/vm:libdart_vm_jit` on Linux x64
Release.** The earlier proposal of an arm64 macOS Release hand-write
against the `kevmoo/bazel_silly` compdb was anchored on the
dead-end-as-foundation strategy (sdk-33x, §5.1); the follow-up
evaluation of `gn desc` (sdk-suy) replaces both the platform and the
plan. The new plan is gn-desc-driven, runs against the existing
`out/ReleaseX64` build dir in the main rig, and exists because gn desc
fixes 10 of the 12 sdk-33x roadblocks fully and 2 partially (§3.2).

**Plan in work molecules** (sdk-suy):

**Molecule 1 — `cc_toolchain` port.** Read
`build/toolchain/linux/BUILD.gn` (~319 lines, hand-written `toolchain()`
declarations) and re-implement it as a Bazel `cc_toolchain` +
`cc_toolchain_config`. This is the one piece of GN semantics that
cannot be transcribed from gn desc output — gn desc returns the
toolchain label per target but does not introspect `toolchain()`
declarations (sdk-suy, **high** confidence). The `buildtools/` clang
path resolution falls into this molecule as well. The Molecule outputs
a single working `cc_toolchain` plus whatever supporting
`platform()` / `constraint_setting()` declarations Bazel needs.

**Molecule 2 — translator skeleton.** Write the ~80-line gn-desc →
`BUILD.bazel` translator (sdk-suy, **medium** confidence on the
80-line estimate; the structure is obvious, the helpers are
non-trivial). It consumes `gn desc //* --format=json` output, groups
targets by their source `BUILD.gn` directory, and emits one
`BUILD.bazel` per dir with `cc_library` / `cc_binary` /
`cc_shared_library` / `genrule` / `filegroup` for the six common
target types. The non-trivial helpers are `bazelify` (map
`//out/ReleaseX64/gen/foo.cc` to the relevant genrule's output label),
`build_select_blocks` (diff defines across configs into `select({...})`
blocks), and a hand-written set of `config_setting`s for the variant
axes that show up in the diffs (`is_product`, `is_precompiler`,
`target_arch_*`).

**Molecule 3 — gn dump + bazel build.** Run `gn desc out/ReleaseX64
//* --format=json` against the existing configured directory (already
done once in sdk-suy: 16,019 lines / 2.8 MB, 766 target entries; type
breakdown 279 `source_set` + 187 `action` + 120 `group` + 77
`executable` + 64 `copy` + 29 `static_library` + 10 `shared_library`),
run the translator, hand-fix the gaps the translator predictably
leaves (toolchain references, codegen output paths, the third_party
trees below), and iterate until `bazel build
//runtime/vm:libdart_vm_jit` succeeds against the single Linux x64
Release config. This is the equivalent of what `kevmoo/bazel_silly`
aspired to, but with the structural backbone the compdb approach
lacked.

**Molecule 4 — multi-config `select()`.** Re-run `gn gen` + `gn desc`
for a second config (the obvious next pick is Linux x64 with
`dart_precompiler=true`, so the `libdart_vm_precompiler` variant comes
online), diff the dumps, fold the diffs into `select()` blocks on the
per-target `defines`, and define the corresponding `config_setting`s.
The variant tables (sdk-suy lists 13 `libdart_vm_*` variants differing
in 5 distinct defines plus arch tokens) are the receipt that the diff
is small. The scout reports **medium-high** confidence that the
multi-config `select()` workflow scales cleanly to all 9 logical
libraries — verified for one logical library (`libdart_vm`), not
exhaustively (sdk-suy).

**Molecule 5 — codegen ports for the first proof.** A handful of the
`//runtime/vm` action dependencies fall in §2.2's codegen bucket
(sdk-1z9). The first proof needs `generate_version_cc_file` as a
`genrule` (1:1 mapping; gn desc supplies script + inputs + outputs +
args; sdk-suy reports **high** confidence on the simple-action case
and **medium** confidence that the same mapping holds for all 187
actions — some likely use runtime arg substitutions that need more
care). The `bin_to_assembly` / `bin_to_coff` / `bin_to_linkable`
family is a custom rule because it branches on `current_cpu` /
`current_os`. `.git/logs/HEAD` reads in `generate_version_cc_file`
need a `--no-git-hash` flag or a workspace-status replacement
(§2.2 hermeticity flag).

**Confidence and effort caveat.** The scout reports **low** confidence
on the total effort to reach a green `libdart_vm_jit` build (sdk-suy
declines to re-estimate; sdk-33x's earlier 14-day envelope was for the
hand-write path against a different platform and is superseded). Two
unknowns dominate: how long fresh `gn gen` cycles take per config
(filed as follow-up bead sdk-yv1, **unmeasured**), and whether
`cflags` are stable across `gn gen` runs (filed as sdk-mx9,
**unverified**). If either is unstable, the multi-config workflow in
Molecule 4 needs a different shape — cached dumps, pinned toolchain
versions, or per-config snapshots checked in alongside the translator
(both risks are catalogued in §5.3 and §5.4).

The compdb that the `kevmoo/bazel_silly` experiment captured remains
useful as a **diff oracle** against the gn-desc-driven translation:
sanity-check the source lists Bazel ends up with against compdb's
compile-unit list per target. It is not the foundation (§5.1), but
the cross-check is cheap and worth running.

### 4.2 Subtree-by-subtree ordering

The migration's natural order falls out of the §2.1 per-directory
target distribution (sdk-vgw) combined with §3.x's dep-direction
constraints:

| Phase | Subtree | Targets | Why this order |
|---|---|--:|---|
| Phase 0 | `build/toolchain/linux/` | (toolchain only) | Molecule 1 from §4.1 — Bazel `cc_toolchain` port. Nothing builds without it. |
| Phase 1a | `runtime/vm/` | (core C++ libs, ~116 with runtime/) | §4.1's first proof: `libdart_vm_jit`. Validates translator + toolchain on the densest C++ surface. |
| Phase 1b | `runtime/bin/` | (executables) | `dart`, `dartvm`, `dartaotruntime`, `gen_snapshot[_product]`. The `bin_to_linkable` chain and Dart-builds-Dart bootstrap edges (§2.2) land here. |
| Phase 1c | `runtime/platform/`, `runtime/observatory*/`, etc. | (remainder of runtime/) | Rest of runtime/ with the C++ surface mostly nailed down. |
| Phase 2a | `utils/` | 105 | Dart-builds-Dart tools (dart2js, ddc, dart2wasm, dartdev, dds, dtd, dartanalyzer, analysis_server, kernel-service). **Requires rules_dart** (sdk-8er / §3.1). Includes `utils/bazel/` — port early to verify against the snapshot rules_dart consumers already depend on (sdk-edw / §3.5). |
| Phase 2b | `sdk/` | 52 | SDK assembly via `copy` / `copy_tree`. Mostly mechanical once snapshots from phase 2a are buildable. |
| Phase 2c | `samples/` | 21 | Cleanup; depends on everything else being green. |
| Phase 3 | `third_party/` | 24 | Many become `bazel_dep` from BCR (zlib, boringssl, icu, googletest, abseil); others (binaryen, perfetto, double-conversion) need hand-shimmed `BUILD.bazel` files. `third_party/binaryen` is the one site needing `glob()` (§2.6 / sdk-06y). |
| Deferred | Browser binaries, Android, Fuchsia, Windows MSVC, emsdk | (conditional) | Each is a separate workstream. Land Linux x64 + macOS first; iterate. |

The logical dep direction is **bottom-up by build dependency**:
toolchain → core C++ libs → C++ executables → Dart-builds-Dart tools
→ SDK assembly. This mirrors Fuchsia's "output-end-first" sequencing
in concept (sdk-8er), though Fuchsia worked backwards from product
assembly while the Dart SDK works forward from the toolchain — same
discipline of one validated boundary at a time, monitoring KPIs at
each phase boundary (clean build time, null build time, presubmit
duration).

Per-directory target counts at a glance (sdk-vgw): runtime/ 116,
utils/ 105, sdk/ 52, build/ 51, third_party/ 24, samples/ 21, root
`BUILD.gn` 21, tools/ 1, pkg/ 1 (a stub).

### 4.3 Coexistence strategy (GN and Bazel side-by-side?)

The precedent landscape offers two distinct coexistence models
(sdk-8er, **medium-high** confidence on the structural mapping):

**Skia: Bazel-as-source-of-truth + GN exporter.** Skia's
authoritative build moved to Bazel; `.gni` files become the generated
artifact via `bazel/exporter_tool/main.go`. The Bazel→GNI mapping is
hardcoded in the exporter. The end state is to delete `BUILD.gn` once
downstream consumers (notably Flutter — `flutter/flutter#137567`)
move off them. The model demands re-authoring every target in Bazel
up front and maintaining the exporter indefinitely — heavy lift,
contradicts the gn-desc-driven translator approach (§3.2). **Not
adoptable for the Dart SDK.**

**Fuchsia: explicit boundary discipline + `fint` wrapper.** GN/Ninja
owns the platform build, Bazel owns components and the SDK; the
`fint` tool presents a single `fx build` frontend that drives both.
The dependency direction is GN → Bazel → GN (the outer GN owns
post-build assembly; Bazel-built artifacts wrap back into GN-visible
targets so post-build tools keep working). RFC-0186 quantifies a
**~10% clean-build overhead from filesystem sandboxing** — a known
cost, not a worst case. The team actively works to **minimise
boundary crossings** (sdk-8er).

**Recommended path for the Dart SDK: temporary coexistence with
atomic per-subtree cutovers.** Bazel grows alongside GN until
`libdart_vm_jit` + `runtime/bin` executables are green (Phase 1a–1b
in §4.2). Each subtree cutover is atomic — once a subtree's Bazel
build is verified test-equivalent (or byte-equivalent where
practical) against the GN build, GN's targets in that subtree are
deleted in the same commit. **No permanent dual-system**: the project
shouldn't maintain two build systems indefinitely (the explicit
Flutter concern in `flutter/flutter#58082`). To avoid the Fuchsia
GN → Bazel → GN re-entrance trap, preserve `tools/build.py` /
`tools/test.py` as user-facing front doors and swap their backend
from GN to Bazel without changing the CLI surface (§3.6 + sdk-sqa) —
this is the `fint`-style wrapper pattern, but it stays in Python and
the user never sees a build-system boundary.

**The cautionary tale (sdk-8er, high confidence).** Flutter engine
is a near-twin of the Dart SDK (same GN+Ninja, same Dart) and has
**stalled on Bazel adoption for 7+ years** explicitly because
`rules_dart` was a precondition blocker. The Dart SDK migration must
**solve rules_dart as a precondition**, not during the migration.
Authoring production-grade rules_dart (including AOT — see §3.5) is
the single biggest scope item the migration must own; any plan that
doesn't budget for it is wrong.

A small `alias()`-only root `BUILD.bazel` (the Skia pattern adopted
without the rest of Skia's model) is worth borrowing — `//:dart`,
`//:dartvm`, `//:gen_snapshot`, `//:dartaotruntime`,
`//:create_sdk` as aliases over the internal subtree targets,
decoupling the public Bazel API from internal restructuring during
phase 1a–2c (sdk-8er).

## 5. Risks and mitigations

### 5.1 Dead-end-as-foundation: extending `gn_to_bazel.dart`

If the migration tries to extend `gn_to_bazel.dart` (the in-tree
compdb-translation script on `kevmoo/bazel_silly`, commit `f2f06d9d`)
instead of starting from a hand-written `BUILD.bazel`, the scout's
evaluation predicts the following failure mode — fixing the translator
amounts to reimplementing every structural feature of GN inside an
ad-hoc Dart script that consumes a single-platform compile-commands
snapshot (sdk-33x).

The four roadblocks called out in the existing gist writeup are real,
but **one is diagnosed backwards** and **eight more were missed**
(sdk-33x). The full picture, verified against the script (101 lines,
read end-to-end) and against the generated `BUILD.generated.bazel`:

**Verified from the gist writeup:**

- **Configuration locking** (correct, partially understated). `-DTARGET_ARCH_ARM64`
  and `-Iclang_arm64_shared/gen` are hardcoded across all 76 generated
  rules; sources include macOS-specific files. The proposed fix
  (`glob(...) + select(...)`) ignores that the input compdb is a
  single-platform snapshot — you'd need N compdbs (one per
  platform/arch/build-mode) before you could produce a useful
  `select()`. Medium-high in-script effort, plus changing the bootstrap
  loop.
- **Absence of header files** (correct). Zero `hdrs`, zero `.h` paths
  in `srcs`. A `glob(["runtime/vm/**/*.h"])` quick fix compiles but
  produces incorrect header exposure across libraries (e.g.
  `runtime/platform/*.h` would leak when it should be owned by
  `libdart_platform_*`).
- **System-specific hardcoded compiler options** (**diagnosed
  backwards**). The writeup claims `-isysroot`, `-mmacosx-version-min`,
  `-arch arm64` are *embedded* inside target `copts`. They are not —
  the script's `startsWith('-D' | '-I')` filter drops every flag that
  isn't a define or include. The actual problem is the **opposite**:
  these critical toolchain flags are **missing**, not hardcoded.
  Direct grep over the generated file returns zero hits for `isysroot`
  or `arch`. The proposed fix (`cc_toolchain`) is correct for the
  opposite reason from the one the gist gives.
- **Monolithic dependencies** (correct). Zero `deps` in any of the 76
  rules. boringssl/icu/perfetto/zlib live under non-`libdart` prefixes
  in the compdb and are silently dropped — 123 of 199 target prefixes
  are dropped today, including `dart_set`, `dartvm_set`,
  `dartaotruntime_set`, all `engine_*_set` flavors, `dart_api`,
  `gen_regexp_special_case`, `boringssl`. The fix is not "introduce
  targets for boringssl/icu/zlib" — it is "write a Bazel translation
  of the third_party builds that GN already orchestrates."

**Roadblocks the gist writeup missed:**

- **76 ≠ 76 libraries.** The 76 emitted rules are 9 logical libraries
  cross-producted with up to 14 GN configurations from
  `runtime/configs.gni:78–177`. A correct Bazel translation collapses
  each cross-product back into one rule with `select()` on
  `config_setting`s. Extending the translator means undoing the
  translator's own output.
- **Duplicate-symbol link errors across variants.**
  `runtime/vm/allocation.cc` appears in 14 variant libraries
  (`libdart_vm_jit`, `libdart_vm_jit_product`, `libdart_vm_aotruntime`, …).
  GN avoids this by compiling once per variant into distinct out dirs
  with different defines; the generated Bazel rules cannot be linked
  pairwise without symbol collisions.
- **Generated sources without `genrule` backing.** Sixteen `srcs`
  entries reference `gen/runtime/version.cc` and
  `clang_arm64_shared/gen/runtime/version.cc` — paths that don't exist
  in the source tree; they are GN `action()` outputs from
  `generate_version_cc_file` (`runtime/BUILD.gn:420`). Bazel will fail
  to stat them.
- **No final linkable.** The 123 silently dropped target prefixes
  include `dart_set`, `dartvm_set`, `dartaotruntime_set`. Without
  these you cannot build the `dart` or `dartaotruntime` executables —
  only intermediate `cc_library`s that are themselves unbuildable.
- **Cross-toolchain source-list conflation.** `version.cc` is captured
  twice (default arm64 toolchain plus `clang_arm64_shared`
  host-targeting-host, per `runtime/configs.gni:48–52`); the script's
  set-union puts both paths into the same library's `srcs`.
- **Missing `.S` assembly.** GN's `runtime/vm/BUILD.gn:110–114` adds
  `thread_interrupter_android_arm.S` and `ffi_trampolines_arm64.S` to
  `libdart_vm`. The compdb captures 0 `.S` files (`ninja -t compdb`
  omits assembly), so neither lands.
- **`-DDART_TARGET_OS*` filter too broad** (cosmetic; not blocking,
  but evidence of cargo-culted filter design).
- **`compdb` was captured under `rewrapper` (reclient/RBE).** Every
  command starts with `../../buildtools/reclient/rewrapper …` before
  the real `clang++` invocation. The naive `split(' ')` happens to
  ignore these tokens because none start with `-D` / `-I`, but any
  stricter parser must handle the wrapper-vs-real-command boundary.

**Mitigation: do not invest in extending the translator.** The compdb
remains useful as a non-foundational tool — diff oracle, scope-of-work
calculator, define inventory for designing `config_setting`s. The
first-proof path (§4.1) treats it accordingly.

**Confidence on this risk.** The scout reports **high** confidence on
script behavior (read line by line), **high** confidence on the four
gist-writeup roadblocks (including that roadblock #3 is diagnosed
backwards), and **high** confidence on the additional eight roadblocks
(verified by reading the generated file plus GN sources). The
strategic dead-end-as-foundation assessment is **medium-high**
confidence (sdk-33x).

### 5.2 Toolchain definitions are not queryable via `gn desc`

`gn desc` returns the toolchain *label* on every target
(`//build/toolchain/linux:clang_x64` etc.) but cannot introspect
`toolchain()` declarations themselves — querying the toolchain label
directly reports "matches no targets, configs or files," verified
empirically (sdk-suy, **high** confidence). The toolchain is defined in
`build/toolchain/<os>/BUILD.gn` (319 lines for Linux) via GN's
`toolchain()` template; that file's semantics have to be re-implemented
as a Bazel `cc_toolchain` + `cc_toolchain_config`, **not transcribed**.

The same caveat applies to GN's higher-level templates
(`library_for_all_configs`, the `_all_configs` matrix described in
§2.1): gn desc shows the expanded targets but not the template
machinery. For a translator that is the correct semantics — it wants
expanded targets — but a human auditor verifying the translation
should know that gn desc is a sink for expanded build graph, not a
complete textual mirror of the GN build.

**Mitigation.** Budget the one-off hand-port as §4.1 Molecule 1.
Treat any future toolchain change in GN as requiring a parallel update
to the Bazel `cc_toolchain` until the migration is far enough along to
delete the GN toolchain.

### 5.3 `gn gen` latency for fresh configs ~~is unmeasured~~ — **RESOLVED**

The multi-config `select()` workflow (§4.1 Molecule 4) requires
running `gn gen out/<config> && gn desc out/<config> //* --format=json`
once per target config. The earlier risk concern was that, if `gn gen`
took >10 min per fresh config, the multi-config phase would need a
different shape (cached dumps, pinned toolchain versions, etc.).

**Resolved by measurement (sdk-yv1).** Single-config end-to-end
(`gn gen` + `gn desc //*`) measures at **0.5–1.1 s on warm cache,
under 1.7 s on cold cache** across 7 distinct configs (Release,
Debug, ASan, Arm64, Product, MSan, TSan) on a Linux x64 host
(**high** confidence — direct measurement). `gn gen` parallelises
well: 5 fresh configs in 5-way parallel completed in **1.06 s total**
wall time, ~210 ms amortised per config (**high** confidence). For
a realistic 20–30 config matrix the workflow is **~5 s in parallel**,
**three orders of magnitude below the 10-min red-line** the original
risk identified. The bead also confirmed `gn gen` is **idempotent**
on unchanged inputs (re-gen produces a byte-identical dump after
normalisation).

The original risk does not materialise. Caveat: only measured on a
single Linux x64 host with warm SSD; macOS/Windows hosts and
heavily-contended CI machines are unverified (**medium-high**
confidence on cross-host generalisation per sdk-yv1).

### 5.4 `cflags` stability across `gn gen` runs ~~is unverified~~ — **RESOLVED**

The translator builds its `cc_library` `copts` / `defines` from the
`cflags` field returned by gn desc. The earlier risk concern was
that, if those flags are not stable across `gn gen` runs, the
translator's output would drift commit-to-commit.

**Resolved by verification (sdk-mx9).** Two fresh out dirs with
byte-identical `args.gn` produce `gn desc //*` dumps that are
**byte-identical after out-dir path normalisation** (**high**
confidence — direct `cmp` after normalising the absolute out-dir
prefix). Field order is stable; array order is stable for `cflags`,
`cflags_cc`, `ldflags`, `defines`, `include_dirs`, `inputs`,
`outputs`, `args`, `configs`, `deps`, `public_configs`. No
timestamp / UUID / nonce fields. Re-gen on unchanged inputs is also
byte-stable. Toggling `is_release ↔ is_debug` produces a clean
~4,742-line semantic diff — every line traceable to a `config()`
entry flipping between `:release` and `:debug` variants. The
`TOOLCHAIN_VERSION` and `SYSROOT_VERSION` defines are content-addressed
hashes of pinned `buildtools/`, **stable across hosts and over time
as long as DEPS pins are honoured** (sdk-mx9, **high** confidence).

Two host-specific path patterns still appear in raw dumps and need
translator-side handling (**high** confidence per sdk-mx9):

- `-fdebug-prefix-map=<abs-sdk-path>=` — the SDK's absolute source
  path on the build host. Strip on translation; Bazel's sandbox
  handles its own path normalisation.
- Out-dir-relative paths in `--sysroot=`, generated `include_dirs`,
  and `outputs` — when the out dir is **outside** the SDK source tree,
  GN's `rebase_path` produces walk-up paths embedding the host's
  filesystem layout. **The translator should always operate on an
  in-tree out dir**, OR post-process to rewrite the embedded host
  paths.

The original risk does not materialise as long as the translator
normalises the two known patterns above. Caveat: cross-host
reproducibility was tested on one host only; the content-addressed
design implies multi-host stability but is unverified (sdk-mx9,
**medium-high** confidence).

### 5.5 Hermeticity escape hatches (`.git/`-reading actions + GN `exec_script` / `read_file`)

Four production actions read `.git/logs/HEAD` during the build —
`generate_version_cc_file`, `write_version_file`, `write_revision_file`,
`write_dartdoc_options` (sdk-1z9, §2.2). GN tolerates this because
the file is listed in `inputs`; a sandboxed Bazel build will refuse
to read it. **Workspace status** (`--workspace_status_command` →
`volatile-status.txt` / `stable-status.txt`) is the canonical Bazel
replacement, baked into actions via `expand_template` or `genrule`
with `stamp = 1`. Caveat on semantics: GN reruns the action whenever
`tools/VERSION` or `.git/logs/HEAD` change; Bazel's `--stamp`
machinery is either always stamped (volatile) or never stamped
(stable). Recommend `stable_stamp` for `sdk_hash` (load-bearing —
gates kernel/VM compatibility), `volatile_stamp` only for top-of-binary
version strings.

**The wider catalogue from sdk-06y** (**high** confidence on counts):
17 `exec_script` sites, 2 `read_file` sites, 17 `get_path_info`, 16
`get_label_info`, 7 `get_target_outputs`, **0 globs**. The biggest
single risk-reducer: the SDK has zero implicit-glob source lists, so
the Bazel load-phase port is substantially easier than for
Chromium-style projects.

**Disposition of the 17 `exec_script` sites** (sdk-06y, **high**
confidence on per-site mapping):

| Job | Sites | Bazel handling |
|---|---:|---|
| Git/SDK-hash discovery (`get_dot_git_folder.py`, `make_version.py`) | 2 | `--workspace_status_command` + `expand_template`. **Medium** risk on reload semantics. |
| Apple SDK detection (`find_sdk.py` for iOS + mac) | 2 | `xcode_config` / `apple_common.toolchain_resolved_sdk_dir`. Mature Bazel rules; xcode_config pins to a specific Xcode version per platform. |
| **Windows MSVC detection (`setup_toolchain.py`, `vs_toolchain.py get_toolchain_dir`, `vs_toolchain.py copy_dlls`)** | 3 | **`repository_rule` writing per-arch `cc_toolchain` configs. Heaviest single port** (~week of focused work — MSVC layout drifts year-over-year). |
| Sysroot ld-path resolution (`sysroot_ld_path.py`) | 2 | `cc_toolchain` features; `-L` paths are deterministic once buildtools is materialised. |
| CPU / link-concurrency probes (`num_cpus.py`, `get_concurrent_links.py`) | 2 | **Drop.** Bazel manages concurrency itself. |
| Windows COFF timestamp (`make_coff_timestamp.py`) | 1 | `linkopts = ["-Wl,/Brepro"]` + workspace status STAMP_COFF_TIMESTAMP. |
| MSVC runtime DLL copy (`vs_toolchain.py copy_dlls`) | 1 | `cc_toolchain.dynamic_runtime_lib`; Bazel handles runfiles automatically. |
| Binaryen sources glob (`list_sources.py`) | 1 | Bazel `glob()` at `BUILD.bazel` load time. |
| Debian version stripping (`get_version.py`) | 1 | `expand_template` reading `tools/VERSION`. |
| **Gtk `pkg-config`** | 1 | **Dead code** — both `gtk_internal_config` invocations are unreferenced. Drop along with `build/config/linux/gtk/` and `pkg_config.gni`. |
| **Host-byteorder (`get_host_byteorder.py`)** | 1 | **Dead code path** — only fires on ppc64-AIX which Dart doesn't ship. Hardcode `little`. |
| **ICU-data file-existence probe (`exists.py`)** | 1 | A deliberate Flutter-engine vendoring accommodation. Needs an explicit Bazel flag (`--define=embedder=flutter`) — **coordinate with Flutter team** before changing the layout. |

Both `read_file` sites (`build/config/compiler/BUILD.gn:453, 464`)
embed CIPD instance hashes for attribution-only
`-DTOOLCHAIN_VERSION` / `-DSYSROOT_VERSION` defines. **Two viable
paths**: drop the defines (lose attribution data; simplest) or
materialise via `repository_rule` that resolves cipd version at
workspace setup and emits a `bzl` constant (most correct).

**Two highest-residual-risk sites** the migration should treat as
load-bearing (sdk-06y):

1. **`make_version.py` workspace-status volatility.** GN reruns the
   stamping action whenever `tools/VERSION`, `tools/utils.py`, or
   `.git/logs/HEAD` change; Bazel's status stamping has different
   reload semantics. The SDK hash is **load-bearing** for kernel/VM
   compatibility; every kernel-emitting rule needs an explicit
   `stamp_var` wire-up. Underestimating this would silently break
   kernel-compat checks across versions.
2. **ICU data file-existence probe (`exists.py`).** Today's dual-layout
   probe accommodates both Dart-standalone and Dart-as-flutter-engine
   vendoring. Bazel forbids the probe; an explicit
   `--define=embedder=flutter` flag is the right Bazel substitute,
   but Flutter's Bazel migration (if any) must set this flag
   explicitly. External coordination required.

### 5.6 Depfile concentration in 58% of GN actions

**108 of 187 GN actions (57.8%) declare a `depfile`** (sdk-9gk,
**high** confidence — direct count from the gn desc JSON dump).
Distribution by output:

| Output extension | Count | Pattern |
|---|---:|---|
| `.dill` | 65 | Dart kernel files from `frontend_server`, `vm_platform`, `dart2js` |
| `.stamp` | 40 | Sentinel files for `copy_tree` (32) + `list_dart_files_as_depfile` (8) |
| `.snapshot` | 10 | AOT / JIT snapshots |
| `.exe` | 2 | Compiled Dart executables |

GN's `depfile` tells Ninja "here's a Makefile fragment listing real
input dependencies the action discovered at runtime"; Ninja consumes
it after the action runs and updates its incremental build graph.
**Bazel's `genrule` does not natively consume depfiles** — and 49 of
the depfile-declaring actions have an **empty `inputs` array** (the
`copy_tree` family: GN itself doesn't know what files will be
copied).

**Translation strategies** (sdk-9gk, **medium-high** confidence on
correctness implications):

- **`copy_tree` (32 actions): filesystem-walk at translation time.**
  The translator applies the `--exclude` patterns and emits a static
  `srcs` list to a `genrule` (or `pkg_files` from `rules_pkg`).
  Fragile if file set changes between translation runs, but workable
  and explicit.
- **Dart codegen with depfile (66 actions: `.dill`, `.snapshot`,
  `.exe`): custom Starlark rule per kernel/snapshot pattern.** Each
  rule wraps the binary invocation and handles incremental tracking
  explicitly. For a first cut, accept the limitation that Bazel's
  correctness depends on the declared `srcs` being a **superset** of
  what the depfile would discover, and **flag explicitly** in the
  translator output (`# DEPFILE: <path> — Bazel does not consume;
  ensure srcs is superset`). This deferred-correctness model matches
  Bazel's pattern for C++ header discovery via `cc_common`.
- **The remaining 79 actions (43%): `genrule` direct translation.**
  Static `inputs`, `outputs`, `args`, no depfile, no rsp. The "easy
  43%".

**Response-file usage is a non-risk.** Only 5 of 187 actions use
response files, all variants of a single logical action
(`third_party/perfetto/src/gn:gen_buildflags`, duplicated across
the 4 alternate toolchains). The 26 flags concatenate to ~750 chars,
well below any OS argv limit. The translator inlines the
`{{response_file_name}}` substitution as args directly — **~10 lines
of translator code** (sdk-9gk, **high** confidence). The maximum
joined-arg length across all 187 actions is 704 chars
(`//utils/ddc:ddc_stable_sdk`), ~0.5% of the Linux ARG_MAX limit.

**GN substitution tokens.** Only `{{response_file_name}}` appears in
any action's `args`, `response_file_contents`, or `outputs` across
all 187 actions. None of `{{output}}`, `{{source}}`,
`{{source_name_part}}`, `{{label}}`, etc. show up. The Dart SDK
doesn't use `action_foreach()` patterns; the translator does not need
to handle those tokens.

**Mitigation summary.** Per-pattern translator-side handling: explicit
walk + static srcs for `copy_tree`; custom rule per Dart codegen
pattern with depfile semantics flagged in output; trivial `genrule`
for the 43% easy case. **The risk is not whether translation works;
it is whether the static-srcs supersets stay accurate** across SDK
evolution. Underestimating the depfile-correctness debt would surface
as silent incremental-rebuild bugs.

### 5.7 RBE/reclient migration hermeticity

§3.4 details the RBE topology and the Bazel translation (sdk-evr).
The risk-side framing: **the migration's path away from reclient
forces three load-bearing hermeticity fixes that today's build
silently tolerates**:

1. **Absolute paths in Dart command lines.** Multiple inline comments
   in `build/rbe/rewrapper_dart.py:768–772` acknowledge: *"The Dart
   SDK build rules needs to be fixed rather than doing this, but this
   is an initial step towards that goal."* Bazel's sandbox enforces
   relative paths; the build itself must be fixed before any Dart
   action runs remotely under Bazel.
2. **Ad-hoc Dart import parser is unsound.** The 800-line parser at
   `rewrapper_dart.py:78–106` is "designed to be much faster than
   actually invoking the front end" (line 71) — string-level
   tokenisation, not the actual Dart resolution algorithm. Reclient
   tolerates the slop (it falls back to local on parse errors). Bazel
   will reject any action whose declared inputs don't include what
   the action actually reads. **Every Dart-runs-Dart rule needs to
   declare its `.dart` srcs honestly**, which means either a `dart_deps`
   aspect or a `dart_library` rule tracking transitive `.dart` files
   — non-trivial design work tied to the rules_dart authoring task
   (§3.1 / sdk-8er).
3. **`.dart_tool/package_config.json` is a build artifact, not a
   source.** In Bazel it must be generated by a `repository_rule` at
   workspace setup, OR declared as the output of a `pub_get` rule
   that every Dart action depends on. Today's pub-get-before-gn-gen
   order is implicit; Bazel makes it explicit (sdk-evr, **high**
   confidence on the structural mismatch).

**Mitigation.** The migration's RBE re-enablement is gated on these
three fixes. Either fix them as part of phase 1a-1b (before any RBE
work), OR accept local-only execution until they land. Do not attempt
to port `rewrapper_dart.py` to Bazel — its 800 lines and 15
program-specific parser methods become structural rule attributes
under Bazel, and porting wastes effort that should go to the
honest-srcs work above (sdk-evr).

A minor cleanup: `parse_kernel_worker` is defined **twice** in
`rewrapper_dart.py` (lines 552 and 657) with different bodies; Python
uses the second. Either a latent bug or a deliberate override. The
file disappears in the migration, so the bug becomes moot — but worth
flagging if anything pre-migration depends on the first body.

### 5.8 `_all_configs` Starlark macro maintenance burden

§3.3 establishes the Starlark macro approach for the 14 `_all_configs`
variants (sdk-p0i): one `library_for_all_configs(...)` call site
expands to N `cc_library` targets at load time, NOT a `select()`. This
is structurally correct, but carries two maintenance-side risks:

1. **Macro instantiation churn.** Each variant's targets share the
   same name prefix with a suffix (`libdart_vm_jit`,
   `libdart_vm_precompiler`, `libdart_vm_precompiler_product_linux_arm64`,
   …). Build failures on one variant produce error messages that name
   the variant explicitly — useful — but **error messages reference
   the macro-emitted target, not the macro call site**. Debugging
   ergonomics get worse when a `cc_library` failure is attributed to
   `:libdart_vm_precompiler_product_linux_arm64` rather than the
   `library_for_all_configs(name = "libdart_vm")` call in
   `runtime/vm/BUILD.bazel`. Mitigation: name targets with a `__`
   prefix (`__internal__libdart_vm_precompiler_product_linux_arm64`)
   or generate `# Generated by library_for_all_configs at ...`
   comments adjacent to the targets via `print()` in the macro.
2. **Per-variant dep edits surface in two places.** When the macro's
   `_ALL_CONFIGS` table changes (a new variant added, an existing
   one's defines tweaked), every call site that uses that variant
   becomes affected. The macro's data table at
   `//runtime/configs.bzl` is the single source of truth, but
   variant-conditional deps (`extra_precompiler_deps`,
   `extra_product_deps`) live at the call site and must stay in sync.
   Mitigation: keep the variant-conditional dep predicates inside the
   macro (`conf.compiler and not conf.snapshot` etc., already in the
   §3.3 sketch) rather than at call sites.

Neither risk is blocking. Both are ergonomics costs that compound
when the project has many `library_for_all_configs` call sites — the
SDK has 4 today (sdk-p0i / §2.1). At that scale the macro pattern is
defensible; if the SDK grows past ~20 call sites the maintenance
burden warrants revisiting.

### 5.9 Additional risks (deferred — pending later synthesis passes)

CIPD external repo wiring details, the rules_dart authoring scope
(§3.1 / sdk-8er — the single biggest unbudgeted item), and the
out-dir-symlink layer that preserves `out/<BuildConf>/` paths for the
test runner (§3.6 / sdk-sqa). To be merged as those follow-ups land.

## 6. Open questions

Decisions still outstanding for the human reviewer. Each is flagged
where it surfaced in the doc; resolutions feed back into the
appropriate section.

1. **Bzlmod vs WORKSPACE.** Not settled by current findings (§3.1).
   Choice is downstream of the rules_dart authoring strategy: a
   green-field rules_dart published to BCR would naturally target
   Bzlmod (Bazel 8.0 LTS default since Dec 2024); a fork-and-revive
   path inheriting cbracken's WORKSPACE machinery extends the
   WORKSPACE timeline. Either is defensible — the decision needs
   a rules_dart strategy first.

2. **rules_dart authoring scope and ownership** (§3.1, §5.9 —
   sdk-8er). The single largest unbudgeted item in the migration.
   Greenfield authoring vs forking cbracken (read-only, archived
   2025-06; covers VM library/binary/snapshot/test/web cases but
   not AOT). AOT rules (`dart_aot_snapshot`, `dart_platform_dill`,
   `dart_kernel`, `dart_kernel_service`, `bin_to_linkable`) are
   greenfield design regardless. Needs explicit ownership, headcount,
   and a published-to-BCR vs internal-only decision before any
   cutover.

3. **Reclient vs Bazel-native RBE** (§3.4, §3.6 — sdk-evr, sdk-sqa).
   The 800-line `rewrapper_dart.py` exists solely because GN/ninja
   actions can't declare per-action inputs the way Bazel actions
   can. Moving to Bazel-native RBE (BuildBuddy / Buildfarm gRPC, or
   continuing on Google's RBE via Bazel's built-in support) makes
   the parser disappear; keeping reclient ports all 800 lines.
   Strategic decision with cost / coordination implications.

4. **Sanitizer config data ownership** (§3.6 — sdk-sqa).
   `tools/bots/test_matrix.json` is the canonical sanitizer-options
   source today, consumed by both the Python wrapper and the test
   runner. Either it stays as JSON (familiar; wrapper loads it) or
   moves into `.bazelrc` per `--config=asan`/`=tsan` (more idiomatic;
   test runner reads from there). No strong consensus yet.

5. **CIPD HTTPS download URL validation per package type** (sdk-4h1
   follow-up). The proposed Bazel mapping assumes
   `https://chrome-infra-packages.appspot.com/dl/<pkg>/+/<version>`
   downloads work for every package the SDK depends on. Public CIPD
   packages are well-attested; private CIPDs (notably anything under
   `dart-internal.git...` mirrors) may not be reachable via the
   same URL scheme. Needs per-package validation before the
   `MODULE.bazel` resolver script lands.

6. **`pkg/native` cycle with `code_assets` at SDK build time**
   (sdk-4h1 follow-up). `third_party/pkg/native/pkgs/hooks`,
   `hooks_runner`, `code_assets`, etc. are referenced from root
   `pubspec.yaml` dep_overrides AND have `.status` files in
   `third_party/pkg/`. Whether these participate in `code_assets`-style
   native build hooks **at SDK build time** (vs. only at SDK
   runtime in user projects) is unclear; sdk-rsv flagged this as
   touch territory between sdk-rsv and sdk-4h1. The answer changes
   the rules_dart scope: if SDK-build-time `code_assets` hooks exist,
   rules_dart must understand them; if not, they live entirely
   downstream and don't enter the Bazel SDK build graph.

7. **Total effort estimate for `libdart_vm_jit` green build** (§4.1
   — sdk-suy). The scout reported **low** confidence and declined
   to re-estimate; sdk-33x's earlier 14-day envelope was for a
   different platform and approach and is superseded. The two
   structural unknowns underneath have resolved (§5.3 gn gen
   latency, §5.4 cflags stability), so the remaining uncertainty
   is the human-side work to write a `cc_toolchain`, debug
   inevitable `gn desc` field edge cases, and port the
   `runtime/vm` codegen actions. Resolution depends on items 1–3
   above (toolchain authoring depends on Bzlmod decision; rules_dart
   greenfield work is a separate timeline; RBE choice affects
   parallelism in CI). Recommended approach: scope items 1–4
   first, then re-estimate.

8. **Cross-host (`macOS` / Windows) reproducibility of `gn desc`
   dumps** (sdk-mx9 caveat). Verified byte-stable on a single
   Linux x64 host; the content-addressed `TOOLCHAIN_VERSION` /
   `SYSROOT_VERSION` design implies multi-host stability but is
   unverified. Cheap to settle empirically (one CI run on a
   second host), and load-bearing if the translator's output is
   meant to be checked-in artifacts rather than per-host
   regenerated.

9. **Out-dir symlink layer surface** (§3.6 — sdk-sqa). The
   recommended wrapper symlinks `bazel-bin/...` under
   `out/<BuildConf>/dart` to preserve the test runner's path
   expectations. Whether the test runner reads ONLY those specific
   paths or walks the build tree determines whether a thin symlink
   layer suffices or the test runner needs deeper updates. Bead:
   audit path references in `pkg/test_runner/lib/src/`.

## Appendix A: Finding bead index

| Bead | Section | Summary |
|------|---------|---------|
| sdk-m3y | §2.1 | Top-down trace from `//sdk:create_sdk` down to leaf artifacts; documents the three-stage compiler bootstrap (CIPD-prebuilt `dart` → `bootstrap_gen_kernel.dill` → in-build `dartvm` / `gen_snapshot`); 16 `public_deps` of `:create_common_sdk` enumerated. |
| sdk-vgw | §2.1 | Bottom-up inventory: 64 `BUILD.gn`, 103 `*.gni`, 392 declared targets, 57 custom templates; built-in type distribution + per-directory distribution + dominant action-script wrapper (`build/gn_run_binary.py`); flags 14-way `_all_configs` fan-out as the biggest structural translation. |
| sdk-33x | §3.1, §3.2, §4.1, §5.1 | Empirical evaluation of `kevmoo/bazel_silly` (commit `f2f06d9d`) compdb-translation experiment; finds it dead-end-as-foundation; verifies four gist-writeup roadblocks (one diagnosed backwards) and surfaces eight additional roadblocks. **Note**: its arm64-macOS first-proof plan is superseded by sdk-suy's Linux x64 gn-desc-driven plan; the 12-roadblock catalogue carries forward into §3.2 and §5.1. |
| sdk-1z9 | §2.2 | Action / generator inventory: 12 raw `action()` calls (8 truly direct), 0 production `action_foreach()`, ~13 wrapper templates, ~85 wrapper invocations expanding to ~107–110 effective actions; `aot_snapshot` (28) + `application_snapshot` (12) dominate; 4 Dart-builds-Dart bootstrap edges; 7 dead templates the migration can delete; 4 actions read `.git/logs/HEAD` (hermeticity risk for §5.5). |
| sdk-suy | §3.1, §3.2, §4.1, §5.2–§5.4 | `gn desc //* --format=json` is the right primary translator input — strictly dominates compdb. Fixes 10 of the 12 sdk-33x roadblocks fully and 2 partially; exposes type, deps, hdrs, public-config-merged defines / cflags / includes, `.S` sources, action script/inputs/outputs/args, and per-toolchain target suffixes. The one structural gap: `toolchain()` declarations are not queryable via gn desc and must be hand-ported from `build/toolchain/<os>/BUILD.gn`. Proposes Linux x64 first proof with a ~80-line gn-desc → BUILD.bazel translator. Filed follow-ups: sdk-yv1 (gn gen latency) and sdk-mx9 (cflags stability). |
| sdk-clv | §2.3, §3.3 | GN args + cross-compile model: ~30 declare_args across BUILDCONFIG / runtime_args / sdk_args binning into platform/arch + feature gates + build-time-computed values; 13 Linux toolchain suites × 5 variants = 60 instances in template form, 5 active in the Linux x64 dump; `current_toolchain != host_toolchain` pattern for host tooling; cross-arch precompiler variants are host-x64 binaries with `-DTARGET_ARCH_*` (not cross-compiles). Maps to ~6 Bazel `cc_toolchain`s + ~5 features (15× reduction). |
| sdk-q3t | §2.3, §3.3 | `build/config/` flag system: ~30 distinct configs across 5 BUILD.gn files; sanitizers gated inside `compiler:compiler` (not separate configs); 24 configs applied to libdart_vm_jit; 8 silent-break candidates (`-Wl,--icf=all` semantic change, `-Werror`/alpine sysroot interaction, `default_optimization` empty stub, etc.) flagged for §5. Bazel: ~70% cc_toolchain features, ~15% per-target defines, ~10% per-OS toolchain configs, ~5% per-platform select(). |
| sdk-p0i | §2.3, §3.3 | All 14 `_all_configs` entries share `clang_x64` in the Linux x64 dump; pure defines + 1 conditional dep (boringssl on precompiler); cross-arch precompiler variants are not cross-compiles; variants are consumer-selected at dep edges (not select()); 4 alternate toolchains (`_shared`/`_asan`/`_msan`/`_tsan`) ARE genuine toolchain distinctions. Bazel translation: Starlark macro emitting N cc_library targets, NOT select(). |
| sdk-4h1 | §2.4, §3.4 | DEPS uses 3 acquisition mechanisms (CIPD ~22 pkgs, git ~40 repos, hooks 9 scripts); only 1 build-time patch (d3); `buildtools/` not in repo (gclient-created); 1 stale `clang.tar.gz.sha1` (cleanup candidate); 10 conditional checkout vars; `benchmarks-internal` is auth-walled. Bazel: CIPD→http_archive via HTTPS, git→BCR/gitiles tarball, hooks→module_extension or drop. |
| sdk-iq3 | §2.4 | runtime/vm + runtime/bin consumer-side view of build-time generators: 5 pipelines / 11 artifacts (strict subset of sdk-1z9); checked-in "generated" files (offsets_extractor output, experimental_features.cc/.h, unibrow.cc) have manual regen workflows the migration does not need to model; `runtime/vm/*.cc` never `#include "gen/*.h"`. |
| sdk-9jz | §2.5, §3.5 | `tools/test.py` is a 57-line wrapper around `dart pkg/test_runner/bin/test_runner.dart`; 8-dim Smith matrix (~263K combos); test discovery is filesystem walk + magic-comment parse + .status resolution (no BUILD-file test decls); 34 status files / 1996 lines / ~25-token closed expectation vocabulary; results.json/logs.json schema must survive byte-for-byte. Bazel gap list: 8 capabilities Bazel doesn't natively provide; new `dart_status_file()` Starlark rule (~200–500 lines). |
| sdk-rsv | §2.5, §3.5 | `pkg/` is a pub workspace (68 pubspecs + 1 stub BUILD.gn); root pubspec is workspace manifest with `dependency_overrides:` mapping every third-party pkg to a path; 45 `main_dart` callsites with ~30 in `utils/<name>/BUILD.gn` (each emits 3 snapshot variants); GN never sees per-`.dart` deps — depfile from Dart frontend handles it. Bazel: pubspec-derived BUILD.bazel generator or opaque-workspace hybrid. |
| sdk-sqa | §2.6, §3.6 | Python build orchestration disposition: tools/build.py (335 lines, wrapper), gn.py (808 lines, arch vocabulary + args.gn + RBE), generate_buildfiles.py (113 lines, gclient hook), utils.py (1021 lines, naming + version), rewrapper_dart.py (800 lines, Dart-RBE). 5 must-preserve UX contracts, 5 clean drops. 77 CI invocations depend on `tools/build.py` signature. Out-dir naming via symlink layer. |
| sdk-06y | §2.6, §5.5 | GN load-time escape hatches: 17 `exec_script` (the long pole — Windows MSVC detection is heaviest), 2 `read_file` (CIPD instance hashes for `-DTOOLCHAIN_VERSION`/`-DSYSROOT_VERSION`, attribution-only), 17 `get_path_info` (mostly `_dart_root` indirection that drops in Bazel), 16 `get_label_info`, 7 `get_target_outputs`, **0 globs**. The SDK enumerates every source file by hand — biggest single migration enabler. |
| sdk-evr | §3.4 | RBE topology: Google reclient/reproxy against `flutter-rbe-prod`. Two RBE paths today — toolchain-level C++ wrap (~16 sites, all gated by `use_rbe`), and `build/rbe/rewrapper_dart.py` (800 lines, 15 Dart-program-specific parser methods). Bazel translation: rewrapper_dart.py **disappears entirely**, replaced by structural rule attributes + `cc_toolchain.exec_properties` + `.bazelrc` config. Three load-bearing hermeticity risks: absolute paths in Dart command lines, unsound ad-hoc import parser, `.dart_tool/package_config.json` as build artifact not source. |
| sdk-edw | §3.1, §3.5 | `utils/bazel/` is the Dart CFE persistent-worker protocol implementation (2 files: 42-line BUILD.gn + 89-line `kernel_worker.dart`), NOT SDK-side Bazel rules. Ships `kernel_worker_aot_product.dart.snapshot` consumed by EXTERNAL Bazel users (`rules_dart`, `dart-lang/build`). Zero `.bzl` / `BUILD.bazel` / `MODULE.bazel` in the SDK source tree. Migration must preserve the snapshot path + `--persistent_worker` CLI surface. Good early-port target. |
| sdk-8er | §3.1, §4.3 | Precedents: Skia inverted (Bazel-as-source-of-truth + GN exporter, heavy lift); Fuchsia permanent coexistence via `fint` wrapper (RFC-0186, ~10% sandboxing overhead); Flutter engine STALLED 7+ years on Bazel adoption (rules_dart blocker); Chromium never tried; WebRTC has an internal GN→Bazel JSON converter (validates the gn-desc approach). All 4 rules_dart forks ARCHIVED (cbracken 2025-06, matanlurey 2024-09 — neither covers AOT). Migration must own authoring rules_dart from near-scratch. |
| sdk-yv1 | §5.3 | Measured `gn gen` + `gn desc //*` end-to-end at 0.5–1.1 s warm / under 1.7 s cold per fresh config; 5-way parallel at 1.06 s total; 20–30 config matrix is ~5 s parallel. **Three orders of magnitude below the 10-min red-line.** §5.3's original risk does not materialise. |
| sdk-mx9 | §5.4 | Two fresh out dirs with identical args produce byte-identical `gn desc` dumps after out-dir path normalisation; field/array order stable; no timestamp/UUID/nonce. Re-gen on unchanged inputs is byte-stable. Toggling `is_release ↔ is_debug` produces a clean ~4,742-line config-traceable diff. Two host-specific path patterns (`-fdebug-prefix-map=`, sysroot walk-up) need translator handling. §5.4's original risk does not materialise. |
| sdk-9gk | §5.6 | Action coverage: 108/187 (58%) declare depfiles, concentrated in Dart codegen (.dill 65) + tree-copy (.stamp 40); empty `inputs` on 49 of those. Bazel `genrule` does NOT consume depfiles — migration must author custom Starlark rules per pattern OR static-srcs supersets. Response files: 5/187 actions but only 1 logical pattern (perfetto), inlineable in ~10 lines of translator code. Only `{{response_file_name}}` GN substitution used; no `{{output}}` / `{{source}}` / `action_foreach()` tokens. Max joined-arg length is 704 chars (well under OS limits). |
