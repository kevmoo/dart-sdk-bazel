# Bazel Migration PR Learnings & Hardwared Workflow Guidelines (Audit Date: 2026-06-22)

This documentation aggregates code review feedback from Gemini Code Assist across pull requests in `dart-sdk-bazel`. 

By auditing the mistakes initially made by AI coding agents and human contributors, we have synthesized mandatory rules hardwared into our repository workflow (`.agents/rules/bazel_migration_guidelines.md` and `.agents/scripts/validate_bazel_commit.py`).

---

## 📊 Common Agent Mistake Taxonomy

| Mistake Category | Occurrences Across PRs |
|---|---|
| **Hermeticity & Runfiles** | 7 |
| **Cross-Platform & Windows** | 4 |
| **Build Flags & Cleanliness** | 4 |
| **Process Streams & Hangs** | 2 |

---

## 📚 Index of Audited PRs

| PR # | Title | Primary Takeaway |
|---|---|---|
| [#2](https://github.com/kevmoo/dart-sdk-bazel/pull/2) | [bazel] Implement import/export bridges & claim active tasks | Cross-Platform Build Logic |
| [#3](https://github.com/kevmoo/dart-sdk-bazel/pull/3) | [backlog] Update backlog: Close completed developer bridge tasks (sdk-9qx, sdk-zi3, sdk-fnn) | Cross-Platform Build Logic |
| [#4](https://github.com/kevmoo/dart-sdk-bazel/pull/4) | [bazel] Hand-fix process_test and abstract_socket_test C++ targets | Iterative Refinement |
| [#5](https://github.com/kevmoo/dart-sdk-bazel/pull/5) | feat(infra): deploy autoscaled remote execution pipeline (Redis, bb-browser) | Iterative Refinement |
| [#6](https://github.com/kevmoo/dart-sdk-bazel/pull/6) | [bazel] Prune unused upstream Bazel files via build/test.py integration | Iterative Refinement |
| [#7](https://github.com/kevmoo/dart-sdk-bazel/pull/7) | [bazel] Expose checked-in ICU data headers in GN and deliver patch | Iterative Refinement |
| [#8](https://github.com/kevmoo/dart-sdk-bazel/pull/8) | feat(infra): deploy BuildBuddy BES dashboard in GKE | Iterative Refinement |
| [#9](https://github.com/kevmoo/dart-sdk-bazel/pull/9) | feat(infra): enable scale-to-zero for GKE Buildfarm workers | Iterative Refinement |
| [#10](https://github.com/kevmoo/dart-sdk-bazel/pull/10) | [Bazel Build] Surgical patches for GKE remote execution and compiler hermeticity | Enforce Strict Hermeticity |
| [#11](https://github.com/kevmoo/dart-sdk-bazel/pull/11) | feat(test_runner): add --built-with-bazel flag | Clean Target Definitions |
| [#12](https://github.com/kevmoo/dart-sdk-bazel/pull/12) | [bazel] Implement verified migration requirements and solve workstation sandboxing | Enforce Strict Hermeticity |
| [#13](https://github.com/kevmoo/dart-sdk-bazel/pull/13) | Add Bazel analyze and format test rules | Iterative Refinement |
| [#14](https://github.com/kevmoo/dart-sdk-bazel/pull/14) | CI: Trigger workflows on main branch | Iterative Refinement |
| [#15](https://github.com/kevmoo/dart-sdk-bazel/pull/15) | feat(bazel): implement virtual namespaced package targets (sdk-v49) | Cross-Platform Build Logic |
| [#16](https://github.com/kevmoo/dart-sdk-bazel/pull/16) | feat(bazel): implement clean package testing targets | Iterative Refinement |
| [#17](https://github.com/kevmoo/dart-sdk-bazel/pull/17) | fix(bazel): repair //sdk:create_sdk after PR #15 (analysis, package resolution, training runs) | Cross-Platform Build Logic |
| [#18](https://github.com/kevmoo/dart-sdk-bazel/pull/18) | feat(bazel): tools/bazel/presubmit.sh single-command gate, run in CI; TARGET_ARCH audit policy | Clean Target Definitions |
| [#19](https://github.com/kevmoo/dart-sdk-bazel/pull/19) | fix(bazel): auto-invalidate @dart_tests when the test generator changes | Iterative Refinement |
| [#20](https://github.com/kevmoo/dart-sdk-bazel/pull/20) | fix(test_runner): bound the --built-with-bazel probe's hang modes | Clean Target Definitions |
| [#21](https://github.com/kevmoo/dart-sdk-bazel/pull/21) | feat(ci): nightly full create_sdk build + smoke; smarter caching for both workflows | Iterative Refinement |
| [#22](https://github.com/kevmoo/dart-sdk-bazel/pull/22) | docs(bazel): fable review artifact — bugs, risks, gemini feedback mining, CI roadmap | Iterative Refinement |
| [#23](https://github.com/kevmoo/dart-sdk-bazel/pull/23) | fix(bazel): make @dart_tests SDK resolution hermetic — repair CI presubmit | Enforce Strict Hermeticity |
| [#24](https://github.com/kevmoo/dart-sdk-bazel/pull/24) | Merge upstream origin/dev 3.13.0-201.0.dev | Iterative Refinement |
| [#25](https://github.com/kevmoo/dart-sdk-bazel/pull/25) | [bazel] Hard-fail on unmatched test selectors in tools/test.py | Clean Target Definitions |
| [#26](https://github.com/kevmoo/dart-sdk-bazel/pull/26) | [bazel] Automatically fetch devtools CIPD package during build | Iterative Refinement |
| [#27](https://github.com/kevmoo/dart-sdk-bazel/pull/27) | [bazel] Migrate binaryen to Bzlmod and upgrade workflows to Node 24 | Enforce Strict Hermeticity |
| [#28](https://github.com/kevmoo/dart-sdk-bazel/pull/28) | [bazel] Migrate DevTools to Bazel-native external repository | Iterative Refinement |
| [#29](https://github.com/kevmoo/dart-sdk-bazel/pull/29) | [bazel] Bump Bazel to 9.1.1 and Merge Upstream SDK 3.13.0-207.0.dev | Iterative Refinement |
| [#30](https://github.com/kevmoo/dart-sdk-bazel/pull/30) | [bazel] Force remote fetch for DevTools overlay repository | Iterative Refinement |
| [#31](https://github.com/kevmoo/dart-sdk-bazel/pull/31) | fix(bazel): resolve missing webkit_inspection_protocol in CI mode | Iterative Refinement |
| [#32](https://github.com/kevmoo/dart-sdk-bazel/pull/32) | Merge latest upstream Dart SDK changes | Iterative Refinement |
| [#33](https://github.com/kevmoo/dart-sdk-bazel/pull/33) | perf(bazel): eliminate Starlark macro list looping in rules.bzl | Mandatory Stream Draining |
| [#34](https://github.com/kevmoo/dart-sdk-bazel/pull/34) | perf(bazel): optimize AC/disk cache memory and stat syscall overhead | Mandatory Stream Draining |
| [#35](https://github.com/kevmoo/dart-sdk-bazel/pull/35) | docs(beads): correct remote URL and worktree db resolution path | Iterative Refinement |
| [#36](https://github.com/kevmoo/dart-sdk-bazel/pull/36) | feat(bazel): decouple VM test targets from create_sdk | Iterative Refinement |
| [#37](https://github.com/kevmoo/dart-sdk-bazel/pull/37) | agent merge core | Iterative Refinement |
| [#38](https://github.com/kevmoo/dart-sdk-bazel/pull/38) | feat(bazel): neutralize nondeterminism and migrate copy genrules (sdk-ckc) | Enforce Strict Hermeticity |
| [#39](https://github.com/kevmoo/dart-sdk-bazel/pull/39) | feat(bazel): implement sharded DDC Web test runner and hermetic sandbox architecture (sdk-k9l) | Enforce Strict Hermeticity |
| [#40](https://github.com/kevmoo/dart-sdk-bazel/pull/40) | sdk mpb | Enforce Strict Hermeticity |
| [#41](https://github.com/kevmoo/dart-sdk-bazel/pull/41) | feat(bazel): hardware Gemini PR review learnings into workflow rules and pre-commit hooks | Iterative Refinement |
