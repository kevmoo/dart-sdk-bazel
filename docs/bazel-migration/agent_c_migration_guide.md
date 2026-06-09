# Bazel Migration Guide (for the migration agent)

> **Audience.** This document is written for an autonomous agent (and the humans
> reviewing it) executing a large, incremental migration of the Dart SDK from
> **GN/Ninja** to **Bazel**. It collects Bazel best practices, common pitfalls,
> GN→Bazel translation guidance, multi-platform considerations, and tips for a
> big, multi-language repo. Read this end-to-end before touching `BUILD.bazel`
> files; come back to the checklists during the work.

> **Status.** Living document. When you discover a new pitfall or a pattern that
> works well for this repo, add it here in the same session you learned it. The
> next agent invocation starts with a fresh container and only the committed
> docs — institutional memory has to live in the tree.

---

## 0. Orientation: what we are migrating

The Dart SDK is not a typical app. Before writing a single rule, internalize the
shape of the thing:

| Concern | Reality in this repo | Why it matters for Bazel |
| --- | --- | --- |
| **Native VM** | `runtime/` — ~650 `.cc`, ~445 `.h`, hand-written assembly (`*.S`), platform `#ifdef`s everywhere | `cc_library`/`cc_binary` with careful per-platform `select()`s and copts |
| **Dart source** | ~25k `.dart` files: core libs (`sdk/lib`), packages (`pkg/`), compilers (dart2js, DDC), analyzer | No first-party Dart rules in upstream Bazel — needs custom rules/genrules driving the Dart toolchain |
| **Java** | ~148 `.java` files (tooling/tests) | `java_library`/`java_binary` — relatively standard, but watch the JDK toolchain pinning |
| **Python** | ~135 `.py` build/orchestration scripts (`tools/`) | These drive GN today. Some become Bazel `genrule`/`py_binary` actions; many become obsolete |
| **Bootstrapping** | Snapshots, AOT snapshots, **kernel platform files**, `create_sdk` | Multi-stage build: a host Dart is used to compile artifacts consumed by later stages. This is the hardest part — see §9 |
| **Multi-platform** | linux, mac, windows (primary) + fuchsia, android, and arches ia32/x64/arm/arm64/riscv | Platforms, toolchains, and `select()` — see §6 |
| **Third-party** | `third_party/` vendored via `DEPS` + gclient | Map to Bzlmod modules or vendored repos — see §8 |
| **Build orchestration** | `.gn`, `build/config/BUILDCONFIG.gn`, `sdk_args.gni`, `tools/build.py` | GN's `declare_args` → Bazel `--define`/`config_setting`/`build_setting` |

**Migration philosophy for this repo:** GN and Bazel will coexist for a long
time. Do **not** delete `BUILD.gn` files as you go. Aim for *parallel* build
graphs that produce byte-comparable (or behavior-comparable) artifacts, so we
can diff outputs and cut over component-by-component.

---

## 1. Use modern Bazel (Bzlmod), not legacy WORKSPACE

- Start on a current Bazel LTS and use **Bzlmod** (`MODULE.bazel`), not
  `WORKSPACE`. WORKSPACE is deprecated and removed in recent majors.
- Pin the Bazel version with a **`.bazelversion`** file and use Bazelisk so every
  developer, the agent, and CI use the identical Bazel. Version skew is a
  top-3 source of "works on my machine."
- Keep a root **`.bazelrc`** under version control. Put machine/user-specific
  knobs in a `user.bazelrc` that is `.gitignore`d and `try-import`ed.
- Prefer official rule modules from the Bazel Central Registry (`rules_cc`,
  `rules_python`, `rules_java`, `platforms`, `rules_pkg`, `bazel_skylib`) over
  hand-rolled macros.

```python
# MODULE.bazel (sketch)
module(name = "dart_sdk", version = "0.0.0")

bazel_dep(name = "rules_cc", version = "...")
bazel_dep(name = "rules_java", version = "...")
bazel_dep(name = "rules_python", version = "...")
bazel_dep(name = "platforms", version = "...")
bazel_dep(name = "rules_pkg", version = "...")
bazel_dep(name = "bazel_skylib", version = "...")
```

> There is no mature, officially-supported first-party **Dart** rule set in the
> open-source Bazel ecosystem comparable to `rules_go`/`rules_rust`. Assume we
> will write and own a `rules_dart`-style internal ruleset (Starlark) that wraps
> the Dart frontend/compiler/snapshotter. Design it deliberately (§9), version
> it inside the repo (e.g. `//build/bazel/dart`), and keep it small.

---

## 2. Bazel mental model vs GN/Ninja (read this before translating)

The biggest source of bugs is assuming Bazel works like GN. It does not.

| Concept | GN/Ninja | Bazel |
| --- | --- | --- |
| **Build language** | GN (declarative-ish, imperative templates) | Starlark (Python-like, *hermetically* evaluated, no I/O) |
| **Output dir** | `out/<config>/` you choose | `bazel-out/` managed by Bazel; you don't pick paths |
| **Source access** | Actions can read anywhere in the tree | Actions see **only declared inputs** (sandbox). Undeclared reads fail or, worse, succeed non-hermetically |
| **Args/config** | `declare_args()` + `gn args` | `config_setting` / `select()` / `--define` / typed `build_setting` flags |
| **Toolchain** | `toolchain()` + `target_cpu`/`target_os` | `platforms` + `toolchain()` resolution + `--platforms` |
| **Conditionals** | `if (is_win) { ... }` anywhere | `select({...})` on attributes only — **not** arbitrary control flow over rule wiring |
| **Codegen** | `action`/`action_foreach` | `genrule` (simple) or a custom rule returning `DefaultInfo`/providers (proper) |
| **Caching** | Local, timestamp-ish | Content-addressed, *remote-cacheable*, requires true hermeticity to be sound |

**Three rules that will save you days:**

1. **If it isn't a declared input, it doesn't exist.** Every file an action reads
   must appear in `srcs`/`hdrs`/`data`/`deps`/`tools`. Sandboxing surfaces this;
   `--spawn_strategy=local` hides it (don't rely on local strategy passing).
2. **`select()` chooses *attribute values*, not whether a target exists.** You
   cannot "skip" a target with an `if`. Model platform variants by selecting
   `srcs`/`deps`/`copts`, or by defining per-platform targets and selecting the
   `deps` edge to them.
3. **Starlark is hermetic by construction.** No reading files, no env, no clocks
   at *loading/analysis* time. Anything dynamic happens inside *actions* at
   execution time, with declared inputs/outputs.

---

## 3. Repository & target layout best practices

- **One `BUILD.bazel` per directory** that owns targets, generally. Fine-grained
  packages give better caching and parallelism than a few giant `BUILD` files.
- **Granular targets.** Prefer many small `cc_library`/`dart_library` targets
  over monoliths. Bazel caches and parallelizes at the target level; a 300-file
  god-library invalidates everything on one edit.
- **`visibility` is a feature, not a chore.** Default to `//visibility:private`
  and open up deliberately with `package_group`s (e.g. `//runtime:vm_internal`).
  This is your best tool for *preventing* the dependency graph from rotting
  during a multi-month migration. Set sensible `default_visibility` per package.
- **No `glob([\"**\"])` across language or generated boundaries.** Broad globs
  pull in junk, defeat caching, and silently include generated files. Prefer
  explicit `srcs`, or narrow globs with `exclude`.
- **Keep Starlark logic out of `BUILD` files.** Put macros and rules in `.bzl`
  files under `//build/bazel/...`. `BUILD` files should read as declarative data.
- **Name targets predictably.** Mirror GN names where reasonable so reviewers can
  diff `:run_vm_tests` (GN) against `:run_vm_tests` (Bazel) one-to-one.
- **Avoid `//...`-wide `data` dumps.** Each test/binary declares exactly its
  runtime files.

### Macros vs rules — pick the right tool

- **Macro** (a Starlark function that instantiates existing rules): use for
  boilerplate reduction, e.g. a `dart_kernel_library()` that wires a `genrule` +
  naming convention. Cheap, but invisible to `bazel query` semantics and can't
  introduce new providers.
- **Rule** (`rule(implementation=...)`): use when you need a real provider, new
  action wiring, or toolchain resolution — e.g. the actual Dart compile action.
  Worth the cost for the core `rules_dart` primitives; overkill for glue.

---

## 4. Hermeticity & reproducibility — the non-negotiables

Hermeticity is *the* reason to adopt Bazel; lose it and you get a slower, more
confusing Ninja. Defend it:

- **Hermetic toolchains.** Do not use the host's `/usr/bin/gcc`, system Python,
  or system JDK implicitly. Register pinned toolchains (hermetic C++ toolchain /
  sysroot, `rules_python` interpreter, `rules_java` JDK). The Dart SDK already
  vendors sysroots and clang under `build/`/`third_party` for GN — reuse those
  as Bazel toolchains rather than the host compiler.
- **No network in actions.** Downloads happen at *module resolution* time
  (`http_archive`, registry), never inside build actions. An action that curls
  the internet is a reproducibility and security hole.
- **Kill nondeterminism.** Strip embedded timestamps, absolute paths, and build
  hostnames from outputs. For C/C++, set `-Wno-builtin-macro-redefined` plus
  `-D__DATE__=`/`__TIME__` neutralization or rely on `--incompatible` reproducible
  flags; pass `-ffile-prefix-map`/`-fdebug-prefix-map` to erase sandbox paths.
  Sort inputs before archiving. Avoid `__FILE__` leaking absolute paths.
- **No `$(location)` to absolute host paths**, no reading `$HOME`, no `date`,
  no `git rev-parse` inside an action unless the result is a declared,
  stamped input. Use Bazel **stamping** (`--stamp`, `workspace_status_command`,
  `ctx.version_file`) for version info — see §10.
- **Deterministic ordering.** Anything that iterates a `glob`, a dict, or a set
  and writes the result must sort first. Starlark dict iteration is ordered, but
  filesystem glob order is not guaranteed stable across machines.
- **Verify it.** Periodically run `bazel build ... && bazel clean && bazel build`
  and compare output hashes, or use `--experimental_remote_cache_compression`
  with two machines hitting the same remote cache. Mismatched hashes = a
  hermeticity bug to hunt down *now*, not later.

> **Rule of thumb:** if two clean builds of the same source can produce
> different bytes, remote caching is silently poisoned for everyone. Treat
> nonreproducibility as a P1 bug.

---

## 5. Translating GN concepts to Bazel

A practical cheat-sheet for this repo specifically.

### 5.1 `declare_args()` / `gn args` → build settings

GN's `sdk_args.gni` / `runtime_args.gni` define tunables like
`dart_target_arch`, `dart_runtime_mode`, `targeting_fuchsia`, sanitizer flags,
etc. Map them:

- **Enumerated/structural choices** (arch, OS, runtime mode jit/aot,
  product/release/debug) → **`config_setting`** + `select()`, ideally driven by
  `--platforms` and `--compilation_mode`, not ad-hoc `--define`s.
- **Booleans/strings the user toggles** → typed **`build_setting`**
  (`bool_flag`, `string_flag` from `bazel_skylib`) under `//build/bazel/settings`,
  referenced via `config_setting`. These are introspectable and type-checked,
  unlike `--define` (which is stringly-typed and global — use sparingly).
- **Avoid `--define` proliferation.** Each `--define` is a global key in the
  configuration; they collide and don't compose. Prefer per-flag
  `build_setting`s.

```python
# //build/bazel/settings/BUILD.bazel
load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
string_flag(name = "runtime_mode", build_setting_default = "jit",
            values = ["jit", "aot"])

config_setting(name = "aot", flag_values = {":runtime_mode": "aot"})
```

### 5.2 GN templates → Starlark macros/rules

GN `template("...")` (e.g. `application_snapshot`, `aot_snapshot`,
`compile_platform`, `create_timestamp`) become Starlark **rules** (preferred for
the compile/snapshot ones because they need providers + toolchain) or **macros**
(for thin glue). Port one template at a time and unit-test it (§11).

### 5.3 `action` / `action_foreach` → `genrule` / custom rule

- Simple, one-shot, shell-able codegen → `genrule` with `cmd`, `tools`, `srcs`,
  `outs`. Good enough for many `tools/*.py` scripts.
- Anything with variable outputs, toolchain needs, or that should expose a
  provider → custom rule using `ctx.actions.run`/`run_shell`.
- `action_foreach` (per-source actions) → either a rule that loops over `srcs`
  declaring one action per file, or `ctx.actions.run` in a list comprehension.

### 5.4 `group()` → `filegroup` / `alias` / empty `*_library`

GN's `group("runtime") { deps = [...] }` aggregations map to:
- a target whose only job is to aggregate deps → a thin rule or an `alias`/
  `filegroup`, or simply the natural `deps` of the consuming target.
- top-level convenience targets (`default`, `most`, `runtime`) → named
  `alias`/`filegroup` targets or documented `bazel build //:runtime` patterns.

### 5.5 `import("...gni")` → `load(":file.bzl", ...)`

`.gni` shared config becomes `.bzl` with `load()`. Remember: Starlark can't read
files at load time, so config that GN computed by reading the filesystem must be
restructured into explicit attributes or build settings.

---

## 6. Multi-platform: linux / mac / windows (+ fuchsia/android, arches)

This is where most of the real engineering is. Principles:

### 6.1 Model platforms with `platforms`, not strings

- Define `platform()` targets (`//build/bazel/platforms:linux_x64`,
  `:mac_arm64`, `:win_x64`, `:fuchsia_arm64`, …) with the right
  `constraint_value`s (`@platforms//os:*`, `@platforms//cpu:*`, plus custom
  constraints for `runtime_mode`, libc, etc.).
- Select on **constraints**, not on `--define os=windows`. This is what makes
  cross-compilation and toolchain resolution work.

```python
config_setting(name = "windows", constraint_values = ["@platforms//os:windows"])
config_setting(name = "mac",     constraint_values = ["@platforms//os:macos"])
config_setting(name = "linux",   constraint_values = ["@platforms//os:linux"])
```

```python
cc_library(
    name = "os_layer",
    srcs = ["os_posix.cc"] + select({
        ":windows": ["os_win.cc"],
        "//conditions:default": ["os_linux_or_mac.cc"],
    }),
    copts = select({
        ":windows": ["/std:c++20", "/EHsc"],
        "//conditions:default": ["-std=c++20", "-fno-exceptions"],
    }),
)
```

### 6.2 Host vs target (the bootstrapping trap)

The Dart build compiles tools **for the host** that then produce artifacts **for
the target** (snapshots, kernel files). In Bazel this is **transitions** and the
**exec configuration**:

- A tool you *run during the build* (a snapshotter, `gen_snapshot`, the
  frontend) must be built in the **exec** configuration (host), declared in the
  `tools`/`exec_tools` attribute, **not** `srcs`/`deps`. Bazel builds it for the
  execution platform automatically.
- When you need an artifact built for a *different* target than the top-level
  one, use an explicit **`cfg` transition** rule, not a second `bazel build`
  invocation. Multi-arch fat outputs = transitions that build the same target
  under multiple `--platforms`.
- **Do not** shell out to a nested `bazel build` to get a host tool — that
  breaks caching and the dependency graph. Use the exec config.

### 6.3 Windows-specific landmines

- **Path length & sandboxing.** Windows MAX_PATH and Bazel's deep `bazel-out`
  paths collide. Enable long paths; keep target/package names short.
- **Symlinks.** Bazel's runfiles use symlinks; on Windows this needs Developer
  Mode or admin, or `--enable_runfiles`. Decide the policy and document it.
- **Shell.** `genrule` `cmd` runs in Bash (MSYS) on Windows by default — fragile.
  Prefer `cmd_bat`/`cmd_ps` or, better, a `py_binary`/cc tool invoked via
  `ctx.actions.run` so the command is OS-agnostic.
- **MSVC vs clang-cl.** Pick one and pin it as a hermetic toolchain. Mixing host
  MSVC detection with hermetic clang elsewhere causes "works in CI, not locally."
- **Line endings & `__FILE__`.** Windows backslash paths leak into outputs;
  normalize with `-ffile-prefix-map` (clang-cl) and avoid CRLF in generated
  sources.

### 6.4 macOS-specific

- **Universal binaries** (x64+arm64) = build under two platform transitions and
  `lipo` in a rule, or use `apple` support if adopted. Don't hardcode arch.
- **Code signing / hardened runtime / notarization** are *not* hermetic by
  nature (need keychain). Keep signing as a separate, late, non-cached step
  outside the cacheable graph.
- **SDK/sysroot pinning.** Use a pinned macOS SDK sysroot, not whatever Xcode is
  installed. Host Xcode detection is the classic non-hermetic mac failure.

### 6.5 Linux

- Pin a **sysroot** (the repo already ships sysroots for GN) and a hermetic
  clang. Don't link against host glibc implicitly.
- Be explicit about libc / static-vs-dynamic and sanitizer variants
  (ASan/TSan/MSan) as build settings or platforms, mirroring the GN
  `is_asan`/`is_tsan` args.

---

## 7. Big, multi-language considerations

### 7.1 Keep language ecosystems in their lane

- Use the canonical ruleset per language: `rules_cc`, `rules_java`,
  `rules_python`, plus our internal `rules_dart`. Don't reinvent `cc_library`.
- **Cross-language deps go through providers/`filegroup`s**, not by reaching into
  another language's output paths. E.g. a Dart snapshot that embeds a C++ binary
  consumes that binary as a declared `data`/tool dependency, not a hardcoded
  `bazel-out/.../dart`.

### 7.2 Generated code is a first-class citizen

This repo generates a lot (kernel platform files, snapshots, version files,
bindings). Rules:
- Generated files must be **outputs of actions**, never committed and never read
  from the source tree by other actions. If GN checked a generated file into the
  tree, that becomes a `genrule` output others `dep` on.
- Don't `glob()` generated files — depend on the generating target.
- Code generators run as tools in the **exec config** (§6.2).

### 7.3 Tests

- Map GN test targets to `cc_test`, `java_test`, and `dart_test`-style rules.
  Declare **all** runtime data in `data` (status files, expectation files, test
  inputs). The Dart test runner reads a lot of side files — each is an input.
- Use **test `size`/`timeout`** honestly; Bazel parallelizes and remote-executes
  tests, and wrong sizes cause flaky timeouts.
- Mark non-hermetic/integration tests with `tags = ["manual", "local",
  "no-sandbox", "external"]` so they don't poison the cache or CI.
- For the giant Dart test corpus, prefer **test sharding** (`shard_count`) and
  consider one Bazel test target per suite rather than 25k micro-targets, which
  would blow up analysis time. Balance granularity against `bazel query` and
  loading-phase cost.

### 7.4 Build performance at this scale

- **Remote caching** is the headline payoff — but only if hermeticity holds
  (§4). Stand it up early; it's the carrot that makes the migration worth it.
- **Remote execution** for the C++ VM and the test fleet is where the real wins
  are; design toolchains to be RE-compatible (no host assumptions) from day one.
- Watch the **loading/analysis phase**. At 25k+ files, over-fine targets and
  heavy macros make `bazel build //...` analysis slow. Profile with
  `--profile=profile.gz` and `bazel analyze-profile`.
- Use `bazel query`/`cquery`/`aquery` to audit the graph (`cquery` respects
  `select()`; `query` does not). `aquery` shows the actual actions/cmdlines —
  invaluable when an action misbehaves.

---

## 8. Third-party dependencies (`DEPS`/gclient → Bazel)

The repo manages `third_party/` via `DEPS` + gclient. For Bazel:

- **Vendored source** that must stay vendored → keep in `third_party/` and add
  `BUILD.bazel` files (often via `//build/secondary`-style overlay, like GN's
  `secondary_source`). Use `new_local_repository`/`local_path_override` or just
  in-tree packages.
- **Fetchable archives** → `bazel_dep` from the Bazel Central Registry where a
  module exists; otherwise `http_archive` with a **pinned sha256** in
  `MODULE.bazel` (via a module extension). Never an unpinned `git_repository`.
- **Keep `DEPS` and Bazel in sync during coexistence.** Two sources of truth for
  versions is a real hazard. Prefer generating Bazel pins *from* `DEPS` with a
  script (a `tools/` generator) so there's one authority, or document the manual
  sync ritual explicitly.
- **No floating refs.** Every external input pinned by content hash. This is both
  reproducibility and supply-chain security.
- Respect the existing `.agents/skills/update_dependency` and
  `update_native_rev` workflows — extend them to also bump Bazel pins rather
  than inventing a parallel mechanism.

---

## 9. The hard part: bootstrapping & the Dart toolchain (`rules_dart`)

This is the crux of the whole migration. The Dart build is **multi-stage and
self-hosting**: you need a Dart binary to compile the kernel/platform files and
snapshots that go into the SDK you're building. Get the staging model right and
everything else follows; get it wrong and you'll fight circular dependencies for
months.

Design guidance:

1. **Define the stages explicitly as targets**, mirroring GN
   (`compile_platform`, `kernel_platform_files`, `aot_snapshot`,
   `application_snapshot`, `create_sdk`):
   - **Stage 0 — host tools:** build `gen_snapshot`, the frontend
     (`kernel-service`/CFE), `dartdev`, etc. **in the exec configuration**.
   - **Stage 1 — platform/kernel:** run Stage-0 tools to produce
     `vm_platform.dill` / kernel platform files (declared outputs).
   - **Stage 2 — snapshots:** run Stage-0 tools over Stage-1 outputs to make
     AOT/app snapshots.
   - **Stage 3 — assemble SDK:** `pkg`/`rules_pkg` to lay out `create_sdk`.
2. **Bootstrap compiler comes from a pinned prebuilt.** To avoid a true cycle,
   the *initial* Dart used to compile everything should be a **pinned, fetched
   prebuilt SDK** (an `http_archive`/toolchain), exactly like GN uses a prebuilt
   `dart-sdk` for parts of the build. Don't try to build the compiler with
   itself from scratch inside one graph.
3. **Model it as a real Bazel toolchain.** Register a `dart_toolchain` carrying
   the bootstrap SDK, snapshotter, and frontend. Rules resolve it via
   `toolchains = ["//build/bazel/dart:toolchain_type"]`. This makes
   host/target/RE all compose.
4. **Every compile is a declared action.** A `dart_kernel`/`dart_snapshot` rule
   runs the toolchain tool with explicit `inputs` (sources + package config +
   platform dill) and explicit `outputs`. Package configs / `.dart_tool` must be
   declared inputs, not ambiently read.
5. **Package resolution must be hermetic.** Today's build uses
   `package_config.json`/pub. In Bazel, generate the package config as an action
   output from declared `dart_library` deps; do **not** let the compiler read a
   developer's pub cache or `$HOME/.pub-cache`.

> Validate each stage by diffing its Bazel output against the GN output for the
> same inputs (e.g. `vm_platform.dill` bytes, snapshot bytes where deterministic)
> before moving to the next stage. The staged diff is your safety net.

---

## 10. Versioning & stamping

The SDK embeds version info (`tools/VERSION`, git hash, channel). Don't bake this
into the cache key naïvely or every commit busts the entire cache.

- Use Bazel **stamping**: `workspace_status_command` emits stable/volatile keys;
  consume via `ctx.version_file`/`ctx.info_file` in the rule that writes the
  version. Builds without `--stamp` use deterministic placeholders so dev builds
  stay cacheable.
- Keep volatile data (build time, exact git sha) in the **volatile** status file
  so it doesn't invalidate unrelated actions.
- Mirror the existing `tools/VERSION` parsing as a `genrule`/rule that reads the
  checked-in `VERSION` (a declared input) rather than calling git directly.

---

## 11. Workflow & process for the migration agent

How to actually carry out the work without breaking trunk:

1. **Coexist, don't cut over.** Add `BUILD.bazel` files alongside `BUILD.gn`.
   Never delete GN until a component is fully validated and a human signs off.
2. **Bottom-up.** Start at the **leaves** of the dependency graph (e.g. a
   self-contained `runtime/platform` or `runtime/vm` utility library), get it
   green, then climb. Migrating top-level `group("runtime")` first guarantees
   pain.
3. **One reviewable unit per change.** A change should add Bazel for one library
   (or a tight cluster) and demonstrate `bazel build //that:target` works on at
   least linux/x64. Small, diffable, revertible.
4. **Prove equivalence.** For each migrated artifact, compare against the GN
   output: byte-diff where deterministic, behavior/test-diff otherwise. Record
   the comparison in the change description.
5. **CI both build systems** during coexistence. Add a Bazel CI lane that builds
   the migrated subset on linux/mac/windows. A red Bazel lane must block the same
   as a red GN lane for migrated components.
6. **Run buildifier.** Format and lint all `BUILD`/`.bzl` with `buildifier`
   (and `buildozer` for mechanical edits). Wire it into PRESUBMIT alongside the
   existing Python/clang formatting. Unformatted Starlark = noisy diffs.
7. **Test the Starlark itself.** Non-trivial rules/macros get unit tests
   (`bazel_skylib`'s `unittest.bzl` / `analysistest`). The snapshot and kernel
   rules especially.
8. **Document as you go.** Update this file and add per-component notes. The next
   container starts fresh; undocumented tribal knowledge is lost.
9. **Keep changes scoped to the migration branch** (`claude/...`) and push there;
   never push to `main`. Don't open a PR unless explicitly asked.

---

## 12. Common pitfalls checklist (scan this before every change)

- [ ] **Undeclared inputs.** Action reads a header/config/script not in
      `srcs`/`hdrs`/`data`/`tools`. Passes locally, fails sandboxed/remote.
- [ ] **Undeclared outputs.** Action writes files Bazel doesn't know about; they
      vanish or break caching.
- [ ] **`select()` misuse.** Trying to conditionally *omit* a target, or putting
      a `select()` somewhere that isn't an attribute. No `default` branch →
      "no matching condition" failures on unanticipated platforms.
- [ ] **Host tool in `deps` instead of `tools`/exec config.** Cross-compiles
      break or the host arch leaks into target artifacts.
- [ ] **Non-hermetic toolchain.** Implicit `/usr/bin/clang`, host JDK, host
      Python, host Xcode/MSVC. Works on the maintainer's box only.
- [ ] **Network in an action.** curl/git/pub fetch inside a build step.
- [ ] **Nondeterministic output.** Timestamps, absolute paths, unsorted globs,
      `__DATE__`/`__FILE__`, hash-map iteration → poisons remote cache.
- [ ] **`--define` sprawl.** Should be typed `build_setting`s + `config_setting`.
- [ ] **Over-broad `glob`/visibility.** `glob(["**"])`, `//visibility:public`
      everywhere → dependency rot and cache misses.
- [ ] **God targets.** One huge library that invalidates the world on any edit.
- [ ] **Reading generated files from the source tree** instead of depending on
      the generator target.
- [ ] **Pub cache / `$HOME` leakage** in Dart compiles (non-hermetic package
      resolution).
- [ ] **Windows path length / symlink / shell** assumptions in `genrule cmd`.
- [ ] **Mac code-signing inside the cached graph** (keep it a late, separate
      step).
- [ ] **Floating external refs** (unpinned `git_repository`, no sha256).
- [ ] **Version git-sha in a normal action** busting the whole cache (use
      stamping/volatile status).
- [ ] **WORKSPACE-isms** in a Bzlmod world (legacy `bind`, `git_repository`
      patterns that don't compose with modules).
- [ ] **Unformatted Starlark** (run buildifier).
- [ ] **Deleting `BUILD.gn`** before the Bazel equivalent is validated.

---

## 13. Quick command reference

```bash
# Build / test a target
bazel build //runtime/vm:libdart
bazel test  //runtime/vm:vm_tests --test_output=errors

# Cross-platform / configuration
bazel build //:runtime --platforms=//build/bazel/platforms:mac_arm64
bazel build //:runtime --compilation_mode=opt   # dbg|fastbuild|opt

# Inspect the graph (cquery respects select(); query does not)
bazel cquery 'deps(//runtime/vm:libdart)' --platforms=//...:linux_x64
bazel aquery 'mnemonic("CppCompile", //runtime/vm:libdart)'  # real cmdlines

# Why does A depend on B?
bazel query 'somepath(//A, //B)'

# Profile analysis/exec at scale
bazel build //... --profile=profile.gz && bazel analyze-profile profile.gz

# Hygiene
buildifier -r .          # format all BUILD/.bzl
bazel mod graph          # inspect the module dependency graph (Bzlmod)
```

---

## 14. Further reading (canonical sources)

- Bazel docs: **bazel.build/docs** — start with *Build basics*, *Configurable
  build attributes (select)*, *Platforms*, *Toolchains*, *Bzlmod*.
- *Bazel Best Practices* and *BUILD style guide* (bazel.build) — the source for
  many §3 rules.
- `rules_cc`, `rules_java`, `rules_python`, `platforms`, `bazel_skylib`,
  `rules_pkg` repos on GitHub (READMEs + examples).
- *Building reproducibly* / hermeticity guidance (reproducible-builds.org and
  Bazel's hermeticity docs) for §4.

> When something here conflicts with current upstream Bazel docs, **upstream
> wins** — Bazel evolves fast. Update this file when you find the drift.
