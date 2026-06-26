# Bazel Architectural Migration Guidelines

All human engineers and AI agents operating on the Bazel thread (`bazel`) MUST strictly adhere to these architectural guidelines derived from continuous integration and build engineering experience.

---

## 🏗️ Core Architectural Rules

### Rule 3.1: Progressive Hybrid Migration (Bottom-Up)
Maintain parallel build graphs. Migrate bottom-up, starting with the leaves of the dependency graph (e.g., low-level third-party dependencies like `zlib` or utility libraries like `runtime/platform`). Never attempt a single global cutover or delete GN files.

### Rule 3.2: Strict Parallel Coexistence
Add `BUILD.bazel` files alongside `BUILD.gn` and keep both build graphs completely parallel. Never delete GN configurations until a component is fully validated in Bazel and approved by a human.

### Rule 3.3: Banned Host-Environment Access in Rules
Rules must not access the host environment implicitly. Never use `$(location)` to absolute host paths, read `$HOME` (or ambient user directories like pub cache), or run non-deterministic host commands (like `date` or `git`) inside actions. Use Bazel's stamping mechanism (`--stamp`, volatile/stable status files) for versioning.

### Rule 3.4: Mandate Equivalence Proofs in CLs / PRs
For every migrated target, perform a byte-diff (where deterministic, e.g., `.dill` files) or a behavior/test-diff of the Bazel output against the GN output, and record the comparison in the PR description.

### Rule 3.5: Strict Direct Dependency Declaration
Bazel enforces strict header checking. A target can only `#include` headers from targets declared explicitly in its direct `deps`. Analyze C++ `#include` statements and declare direct dependencies explicitly. Relying on transitive dependencies is strictly prohibited.

### Rule 3.6: Windows Path Length and Runfiles Compliance
Keep target and package names short to avoid deep nested paths on Windows (`MAX_PATH` compliance). Any executable tool or test script that needs to locate data files must use the official Bazel runfiles lookup library rather than assuming relative filesystem paths.

### Rule 3.7: One Reviewable Unit Per PR
Limit each PR to a single library or a tight cluster of leaf libraries. Ensure it compiles on at least one primary platform (e.g., Linux/x64) and runs its unit tests before uploading.

### Rule 3.8: Parallel CI Lanes
A red Bazel CI lane must block the same as a red GN lane for migrated components.

### Rule 3.9: Mandatory Buildifier Linting and Formatting
Every `BUILD`, `WORKSPACE`, `MODULE.bazel`, and `.bzl` file created or modified must be formatted and linted using `buildifier --lint=fix --warnings=all` before submission.

### Rule 3.10: Keep Starlark Logic in `.bzl` Files
Do not write complex Starlark logic (loops, heavy conditionals) inside `BUILD.bazel` files. Put all macros, rules, and logic in `.bzl` files under `//build/bazel/...`. `BUILD` files should remain purely declarative data.

### Rule 3.11: Strict Case Sensitivity Compliance
Ensure all paths in `srcs`, `hdrs`, and `#include` statements match the exact case on disk to prevent compilation failures on case-sensitive Linux builders.

### Rule 3.12: Default Private Visibility
Set `default_visibility = ["//visibility:private"]` in all packages, and explicitly open up visibility only when necessary using granular `package_group`s.

### Rule 3.13: Mandatory `copy_file` over Shell `cp` Genrules
Never use non-hermetic host shell commands (`cp`, `mv`) inside `genrule` definitions for file staging. Always import and use `copy_file` from `@bazel_skylib//rules:copy_file.bzl`. (Complex multi-line assembly generation scripts are exempt when explicitly tagged with `# exempt-genrule: ok`).

### Rule 3.14: Universal Determinism and Hermetic Timestamps
Never allow C++ builds to depend on non-deterministic host paths or build timestamps. All wrappers must inject `-Wno-builtin-macro-redefined`, `-D__DATE__=""`, and `-D__TIME__=""`. Never invoke ambient host commands (`git`, `date`) inside build action `cmd` strings.
