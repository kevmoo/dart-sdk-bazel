# Bazel Migration PR Learnings & Hardwared Workflow Guidelines (Audit Date: 2026-06-22)

This documentation aggregates code review feedback from Gemini Code Assist across 39 pull requests (#2 through #40) in `dart-sdk-bazel`. 

By auditing the mistakes initially made by AI coding agents and human contributors, we have synthesized the following mandatory rules hardwared into our repository workflow (`.agents/rules/bazel_migration_guidelines.md` and `.agents/scripts/validate_bazel_commit.py`).

---

## 🛠️ Hardwared Repository Workflow Rules (Mandatory Guidelines)

### 1. 🔒 Hermeticity & Runfile Resolution
- **No Direct `.dart_tool` Access**: Never reference `.dart_tool/package_config.json` or local absolute filesystem paths in `BUILD.bazel`. Always use Bazel runfiles or `@dart_packages` repository overlays.
- **Dynamic Bzlmod Paths**: Do not hardcode canonical repository prefixes (e.g., `_main/` or `external/dart_co19_tests`). Use dynamic runfile lookups or relative environment paths (`../dart_co19_tests`) to support external sibling repositories.

### 2. 💻 Cross-Platform Compatibility
- **Prohibit Shell Spawning in BUILD Files**: Never use Unix-only shell commands (`sed`, `dirname`, `cat`, `rm`) in Bazel `genrule` or target attributes. Use Starlark equivalents, Python one-liners, or cross-platform Dart helper scripts to maintain Windows workstation sandboxing.

### 3. ⚙️ Process Management & Deadlock Prevention
- **Mandatory Stream Draining**: All custom test runners and CLI wrappers must asynchronously drain and consume both `stdout` and `stderr` streams. Unconsumed streams cause OS pipe buffers to fill, resulting in permanent CI deadlocks.
- **Forced Server Teardown**: Always register explicit cleanup hooks (`tearDownAll`) to terminate background test servers (`shelf`, `webdriver`, JS runtimes) with timeouts.

### 4. 🚀 Target Scoping & Performance
- **Surgical Dependency Parsing**: Target generators (`generate_test_targets.dart`) must scope directory lookups precisely. Avoid globbing entire repository roots or parsing tens of thousands of external conformance files (`co19`) during phase evaluation.
- **Deduplicate Compiler Flags**: Do not repeat compiler flags (`-std=c++20`, `-fPIE`) across `copts` and `cxxopts`. Define shared config targets or `.bzl` constants.

### 5. 🛡️ Defensive Scripting
- **Strict Path Validation**: Verify relative path prefixes explicitly before checking file existence to prevent silently skipping local dependencies.

---

## 📊 Common Agent Mistake Taxonomy

| Mistake Category | Occurrences Across PRs |
|---|---|
| **Process Streams & Hangs** | 17 |
| **Cross-Platform & Windows** | 12 |
| **Hermeticity & Runfiles** | 6 |
| **Build Flags & Cleanliness** | 6 |
| **Performance & Globbing** | 3 |
| **Error Handling & Safety** | 2 |

---

## 📚 Index of Audited PRs

| PR # | Title | Primary Takeaway |
|---|---|---|
| [#2](https://github.com/kevmoo/dart-sdk-bazel/pull/2) | [bazel] Implement import/export bridges & claim active tasks | Cross-Platform Build Logic |
| [#3](https://github.com/kevmoo/dart-sdk-bazel/pull/3) | [backlog] Update backlog: Close completed developer bridge tasks | Iterative Refinement |
| [#4](https://github.com/kevmoo/dart-sdk-bazel/pull/4) | [bazel] Hand-fix process_test and abstract_socket_test C++ targets | Clean Target Definitions |
| [#5](https://github.com/kevmoo/dart-sdk-bazel/pull/5) | feat(infra): deploy autoscaled remote execution pipeline | Cross-Platform Build Logic |
| [#6](https://github.com/kevmoo/dart-sdk-bazel/pull/6) | [bazel] Prune unused upstream Bazel files via build/test.py integration | Mandatory Stream Draining |
| [#7](https://github.com/kevmoo/dart-sdk-bazel/pull/7) | [bazel] Expose checked-in ICU data headers in GN and deliver patch | Mandatory Stream Draining |
| [#8](https://github.com/kevmoo/dart-sdk-bazel/pull/8) | feat(infra): deploy BuildBuddy BES dashboard in GKE | Mandatory Stream Draining |
| [#9](https://github.com/kevmoo/dart-sdk-bazel/pull/9) | feat(infra): enable scale-to-zero for GKE Buildfarm workers | Cross-Platform Build Logic |
| [#10](https://github.com/kevmoo/dart-sdk-bazel/pull/10) | [Bazel Build] Surgical patches for GKE remote execution and compiler hermeticity | Enforce Strict Hermeticity |
| [#11](https://github.com/kevmoo/dart-sdk-bazel/pull/11) | feat(test_runner): add --built-with-bazel flag | Clean Target Definitions |
| [#12](https://github.com/kevmoo/dart-sdk-bazel/pull/12) | [bazel] Implement verified migration requirements and solve workstation sandboxing | Cross-Platform Build Logic |
| [#13](https://github.com/kevmoo/dart-sdk-bazel/pull/13) | Add Bazel analyze and format test rules | Cross-Platform Build Logic |
| [#14](https://github.com/kevmoo/dart-sdk-bazel/pull/14) | CI: Trigger workflows on main branch | Iterative Refinement |
| [#15](https://github.com/kevmoo/dart-sdk-bazel/pull/15) | feat(bazel): implement virtual namespaced package targets | Cross-Platform Build Logic |
| [#16](https://github.com/kevmoo/dart-sdk-bazel/pull/16) | feat(bazel): implement clean package testing targets | Mandatory Stream Draining |
| [#17](https://github.com/kevmoo/dart-sdk-bazel/pull/17) | fix(bazel): repair //sdk:create_sdk after PR #15 | Cross-Platform Build Logic |
| [#18](https://github.com/kevmoo/dart-sdk-bazel/pull/18) | feat(bazel): tools/bazel/presubmit.sh single-command gate | Clean Target Definitions |
| [#19](https://github.com/kevmoo/dart-sdk-bazel/pull/19) | fix(bazel): auto-invalidate @dart_tests when the test generator changes | Iterative Refinement |
| [#20](https://github.com/kevmoo/dart-sdk-bazel/pull/20) | fix(test_runner): bound the --built-with-bazel probe's hang modes | Mandatory Stream Draining |
| [#21](https://github.com/kevmoo/dart-sdk-bazel/pull/21) | feat(ci): nightly full create_sdk build + smoke | Iterative Refinement |
| [#22](https://github.com/kevmoo/dart-sdk-bazel/pull/22) | docs(bazel): fable review artifact — bugs, risks, gemini feedback mining | Iterative Refinement |
| [#23](https://github.com/kevmoo/dart-sdk-bazel/pull/23) | fix(bazel): make @dart_tests SDK resolution hermetic | Iterative Refinement |
| [#24](https://github.com/kevmoo/dart-sdk-bazel/pull/24) | Merge upstream origin/dev 3.13.0-201.0.dev | Iterative Refinement |
| [#25](https://github.com/kevmoo/dart-sdk-bazel/pull/25) | [bazel] Hard-fail on unmatched test selectors in tools/test.py | Clean Target Definitions |
| [#26](https://github.com/kevmoo/dart-sdk-bazel/pull/26) | [bazel] Automatically fetch devtools CIPD package during build | Cross-Platform Build Logic |
| [#27](https://github.com/kevmoo/dart-sdk-bazel/pull/27) | [bazel] Migrate binaryen to Bzlmod and upgrade workflows to Node 24 | Enforce Strict Hermeticity |
| [#28](https://github.com/kevmoo/dart-sdk-bazel/pull/28) | [bazel] Migrate DevTools to Bazel-native external repository | Iterative Refinement |
| [#29](https://github.com/kevmoo/dart-sdk-bazel/pull/29) | [bazel] Bump Bazel to 9.1.1 and Merge Upstream SDK | Enforce Strict Hermeticity |
| [#30](https://github.com/kevmoo/dart-sdk-bazel/pull/30) | [bazel] Force remote fetch for DevTools overlay repository | Iterative Refinement |
| [#31](https://github.com/kevmoo/dart-sdk-bazel/pull/31) | fix(bazel): resolve missing webkit_inspection_protocol in CI mode | Iterative Refinement |
| [#32](https://github.com/kevmoo/dart-sdk-bazel/pull/32) | Merge latest upstream Dart SDK changes | Mandatory Stream Draining |
| [#33](https://github.com/kevmoo/dart-sdk-bazel/pull/33) | perf(bazel): eliminate Starlark macro list looping in rules.bzl | Mandatory Stream Draining |
| [#34](https://github.com/kevmoo/dart-sdk-bazel/pull/34) | perf(bazel): optimize AC/disk cache memory and stat syscall overhead | Mandatory Stream Draining |
| [#35](https://github.com/kevmoo/dart-sdk-bazel/pull/35) | docs(beads): correct remote URL and worktree db resolution path | Cross-Platform Build Logic |
| [#36](https://github.com/kevmoo/dart-sdk-bazel/pull/36) | feat(bazel): decouple VM test targets from create_sdk | Enforce Strict Hermeticity |
| [#37](https://github.com/kevmoo/dart-sdk-bazel/pull/37) | agent merge core | Mandatory Stream Draining |
| [#38](https://github.com/kevmoo/dart-sdk-bazel/pull/38) | feat(bazel): neutralize nondeterminism and migrate copy genrules | Enforce Strict Hermeticity |
| [#39](https://github.com/kevmoo/dart-sdk-bazel/pull/39) | feat(bazel): implement sharded DDC Web test runner and hermetic sandbox | Cross-Platform Build Logic |
| [#40](https://github.com/kevmoo/dart-sdk-bazel/pull/40) | sdk mpb | Enforce Strict Hermeticity |
