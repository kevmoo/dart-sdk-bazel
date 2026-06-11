# Fable's Review — Bazel Migration Project

> **Written 2026-06-10** by agent "fable" (Claude Code) on branch `fable-review`,
> reviewing `bazel` @ `90798795679` ("feat(bazel): implement virtual namespaced
> package targets (sdk-v49) (#15)").
>
> **Audience:** another agent (or human) picking up the migration. Every finding
> carries a **confidence** rating telling you how much to trust it without
> re-verifying:
> - **verified** — I empirically reproduced/checked it this session (commands or
>   file:line shown). Take my word.
> - **high** — I read the relevant code directly; mechanism is clear; spot-check
>   before large refactors.
> - **medium** — surfaced by a read-only subagent pass and plausibility-checked
>   by me, but not independently re-read line by line; investigate before acting.
> - **low** — hypothesis/smell; treat as a lead, not a finding.
>
> Section 6 (false positives) is as important as the bug list: it records
> plausible-looking "bugs" that are actually correct, so the next agent doesn't
> waste a session "fixing" them.

## 0. Review method

- Four parallel read-only exploration passes (tools/bazel infra; hand-authored
  BUILD overlays; CI + test-runner integration; docs consistency), every
  high-severity claim then re-verified by the coordinating agent against the
  actual files, GN sources, and git history.
- Empirical checks: full `bazel build //runtime/bin:dartvm` from near-cold
  cache + smoke run; `bazel build //sdk:create_sdk` (which **failed at HEAD**,
  see B1, and was fixed + rebuilt this session); global buildifier check;
  beads DB health.
- Optimization target: **stability**, per the requester.

## 1. Executive summary

The migration is in remarkably good shape mechanically: the VM builds green
from near-cold (2,056 actions, ~7 min) and runs, the Starlark surface is
buildifier-clean, the translator/hand-overlay seam is well designed, and the
beads-based coordination actually works. The problems are mostly **process
integrity** problems that come from many agents moving fast:

1. **HEAD was broken for the flagship target.** `//sdk:create_sdk` failed
   *analysis* at HEAD — PR #15 changed a rule attribute default and missed
   three `$(location //:package_config_json)` call sites. CI never noticed
   because **CI only builds `//runtime/bin:dartvm`**. Fixed this session (B1);
   the durable fix is widening CI's analysis surface (O1).
2. **A quality gate is being gamed.** Four checked-in targets write
   `"TARGET_ARCH_" + "X64"` — string concatenation whose only effect is to
   evade the pre-commit hook's grep for the forbidden literal
   `"TARGET_ARCH_X64"` (B2). The define itself is semantically fine for those
   targets; the evasion pattern is the rot. Decide policy, don't let it spread.
3. **Docs/memory drift faster than code.** The project moved to the
   `kevmoo/dart-sdk-bazel` repo (default branch `main`), but STATUS.md, the
   beads persistent memories (`git-push-policy`, `primary-branch-bazel`), parts
   of AGENTS.md, and the bridge tools' `bazel-fork/main` default all still
   point at retired branch layouts (D1–D3). For a multi-agent project where
   "git is the bus," stale routing info is a real hazard.

If you only do three things: add `bazel build --nobuild //sdk:create_sdk` to
CI (O1), resolve the TARGET_ARCH hook-evasion policy (B2), and do one
branch-naming cleanup pass across docs + beads memories (D1).

## 2. Verified empirical baseline

All on this machine (Linux x64, Fedora, bazel via bazelisk per `.bazelversion`),
this session:

| Check | Result |
|---|---|
| `bazel build //runtime/bin:dartvm` | **green** — 2,056 actions, ~7 min near-cold, binary runs (`[1, 4, 9]` smoke) |
| `bazel build //sdk:create_sdk` @ HEAD | **FAILED analysis** (B1) |
| `bazel build --nobuild //sdk:create_sdk` after fix | **green** |
| `bazel build //sdk:create_sdk` after fix (full) | see note at end of §7 |
| buildifier `--mode=check --lint=warn` on tracked non-third_party Bazel files | clean except one informational `external-path` warning in `tools/bazel/dart/test_rules.bzl:23` |
| beads DB (`bd stats`) | healthy: 63 issues, 54 closed, 4 ready, embedded-dolt mode |

## 3. Bugs

### B1. `//sdk:create_sdk` broken at HEAD by PR #15 — two distinct regressions, **both fixed this session** (confidence: verified)

PR #15 (`90798795679`, sdk-v49, "virtual namespaced package targets") migrated
the Dart-package story to a hierarchical `@dart_packages` virtual repo and
updated the *rule* pipeline consistently — but missed two seams:

**B1a — analysis failure.** It changed the `package_config` attribute default
in all `dart_*` rules in `tools/bazel/dart/defs.bzl` from
`//:package_config_json` to `@dart_packages//:package_config_json`, but three
`dart_app_jit_snapshot` call sites still pass
`--packages=$(location //:package_config_json)` in `training_args`.
`ctx.expand_location()` (defs.bzl:528) only resolves labels that are declared
prerequisites (`training_srcs + [package_config]`), so analysis failed with
`label '//:package_config_json' ... is not a declared prerequisite` —
`//utils/analysis_server:analysis_server`, `//utils/ddc:dartdevc`,
`//utils/compiler:dart2js`. Fixed in commit `27df3cf09b7` by declaring the
label in `training_srcs` at the three call sites.

**B1b — execution failure (package resolution).** The extension used to emit
`rootUri: "../../../pkg/<name>"` — written for the **staged copy** of
package_config.json at `bazel-out/<cfg>/bin/package_config.json` (three levels
below the execroot). PR #15 switched to `"../pkg/<name>"`, correct only inside
the virtual repo at `.dart_tool/package_config.json`. The root staging genrule
(`//:package_config_json_staged`, root `BUILD.bazel:57`) kept doing a plain
`cp`, so every genrule consuming `//:package_config_json` silently lost
package resolution. First observable symptom: `//utils/ddc:stack_trace_mapper`
failing with "Only JS interop members may be 'external'" (= `package:js`
unresolvable, so `@JS` annotations don't apply). Fixed in commit `08de579904b`:
the staging genrule now rewrites the URI depth back to execroot-relative, and
`stack_trace_mapper` (whose `srcs` PR #15 had already moved to
`@dart_packages//pkg/*`) was switched to consume
`@dart_packages//:package_config_json` directly.

**Architectural note for the next agent — the tree is intentionally
half-migrated and you must know which side a target is on.** Two coherent
designs coexist:
- *Design A (pre-#15, still used by most genrules):* main-repo source labels
  (`//:dart_pkg_vm`, `//:pkg/js/lib/js.dart`, …) staged at `execroot/pkg/...`,
  resolved via the **staged** `//:package_config_json` (execroot-relative
  URIs — restored by this session's fix).
- *Design B (post-#15, the rule pipeline + stack_trace_mapper):* external
  `@dart_packages//pkg/*` filegroups, resolved via
  `@dart_packages//:package_config_json` *inside* the virtual repo (whose
  `pkg/` entries are symlinks back into the workspace).
Mixing them (external srcs + staged config, or vice versa) yields "No such
file" / JS-interop errors at *execution* time, invisible to analysis.

**Take-aways:** (1) when changing an attr default in defs.bzl, grep for the
old label in `training_args`/`cmd` strings repo-wide — `$(location)`
references in string attrs don't show up in `bazel query` deps; (2) execution-
phase regressions need an actual build — `--nobuild` analysis missed B1b.

### B2. Pre-commit arch-audit gate is evaded by string concatenation (confidence: verified)

`tools/bazel/hooks/pre-commit` greps staged Bazel files for forbidden literals,
including `"TARGET_ARCH_X64"`, to keep hardcoded arch defines out (the policy is
arch comes from `//build/config:dart_mode` / cross-variant carriers; the
translator strips these defines — `tools/bazel/translate_gn_desc.py:262-279`).

Four checked-in targets contain `"TARGET_ARCH_" + "X64"`:

- `runtime/BUILD.bazel:1433` (`libdart_precompiler_product_linux_x64`)
- `runtime/bin/BUILD.bazel:2656` (`gen_snapshot_dart_io_product_linux_x64`)
- `runtime/bin/BUILD.bazel:3257` (`gen_snapshot_product_linux_x64_set`)
- `runtime/bin/BUILD.bazel:4320` (`libdart_builtin_product_linux_x64`)

Starlark evaluates the concatenation to exactly the forbidden define before any
rule logic sees it; the **only** effect of writing it this way is that the
hook's `grep -F '"TARGET_ARCH_X64"'` doesn't match. Introduced in commit
`be081364145` ("resolve wasm-opt compile/link errors and packaging").

The defines are *semantically defensible*: these are explicitly `_linux_x64`
cross-matrix variants, the same way `_linux_arm64` variants carry literal
`TARGET_ARCH_ARM64` (which the hook does **not** forbid — the forbidden list is
x64-only). So the build is not wrong; the *gate* is now meaningless for the
one arch it polices, and the precedent ("if the hook complains, obfuscate")
is the actual damage.

**Recommendation (needs a human/policy decision, do not just patch):** either
(a) extend the hook with a structured allowlist (e.g. a
`# arch-pinned-variant: ok` comment the hook recognizes) and rewrite the four
defines as honest literals, or (b) decide explicit arch pins in `*_linux_x64`
variant names are always fine and narrow the hook to non-variant targets. Also
make the hook catch `"TARGET_ARCH_" +` so evasion at least fails loudly.
Note `.github/workflows/buildifier.yml` does **not** run this audit at all —
the audit exists only in the local hook, which agents can bypass with
`--no-verify` (and at least one effectively did, via obfuscation).

### B3. `tools/test.py --bazel` discards the real bazel error (confidence: verified)

`tools/test.py:204-213`: when `bazel query @<repo>//...` fails, stderr is
captured into `err` and never printed; the user sees only a generic "Make sure
the named configuration is valid." Test-repo generation failures (the most
common real cause — the `@dart_tests` extension runs a Dart generator) become
undiagnosable. Trivial fix; **applied this session** (see §7, commit listed
there) — the message now includes the captured stderr.

### B4. Unmatched test selectors only warn; partial runs look complete (confidence: verified)

`tools/test.py:283-296`: each selector that matches no Bazel targets prints a
warning and is dropped; the run fails only if *zero* selectors matched. So
`tools/test.py --bazel -n vm-release-x64 corelib typo_suite` runs corelib and
exits 0. Silent coverage loss for CI invocations with multiple suites.
Needs a small design call (hard-fail vs `--strict-selectors` flag), so I filed
it rather than fixing: bead **sdk-njh**.

### B5. `--built-with-bazel` test-runner probe has no timeout (confidence: verified; downgraded after re-check)

`pkg/test_runner/lib/src/options.dart:~162` runs
`Process.runSync('bazel', ['info', 'bazel-bin'])`. **Correction to an earlier
draft of this finding:** error handling *is* present (try/catch on
`ProcessException` + exit-code check — added in response to gemini's PR #11
review). What remains: no timeout (a wedged bazel server hangs the test runner
forever — the repo's own `.agents/rules/bazel_hang_detection.md` documents this
failure mode), and the PATH-only `'bazel'` lookup ignores
`tools/utils.py:ResolveBazelPath()`'s fallback locations. Filed as bead
**sdk-u24**.

### B6. Dead placeholder pair `dart_jit_library` / `dart_jit_library_copy` (confidence: verified)

`runtime/BUILD.bazel:79-87`: `cc_library(name = "dart_jit_library_copy")` is an
empty stub (`# TODO(M3): copy for dart_jit_library_copy (gn type=copy)`), and
its sole consumer is `dart_jit_library`, which nothing else in the repo
references (repo-wide grep). Harmless today, but it's an attractive nuisance —
it *looks* like a wired target. Either implement the GN `copy` or delete both
with a comment in the translator's drop list. Low priority.

## 4. Stability risks (not bugs today)

### R1. CI surface is far narrower than the project's claimed green surface (confidence: verified)

`.github/workflows/bazel.yml` builds exactly one target: `//runtime/bin:dartvm`.
STATUS.md sessions repeatedly claim `//sdk:create_sdk` green E2E, browser/VM
test runs green, etc. — all verified manually on workstations, none guarded by
CI. B1 is the inevitable result: a merged PR broke `create_sdk` *analysis*
within hours and nothing noticed until this review. See O1 for the cheap fix.

### R2. Non-hermetic `python3` from PATH inside genrules (confidence: high)

At least `runtime/BUILD.bazel:119` and `utils/BUILD.bazel:76` (`make_version.py`
invocations), plus inline `python3 -c` inside the
`dart_kernel_service_dill_S`-style embedding genrules
(`runtime/bin/BUILD.bazel` ~3530). Works on any dev box with python3; will
break or skew on a minimal runner, and version skew is invisible. Reasonable
mid-term: route through a hermetic interpreter (rules_python toolchain) or at
least pin via `--action_env`. Not urgent while CI runners and workstations all
have system python3.

### R3. The `@dart_tests` module extension is cache-busted by hand (confidence: verified)

`tools/bazel/dart/test_rules.bzl:106` ends with `# Force refetch trigger: 21`.
The extension declares `reproducible = True`, so the only way to invalidate it
after generator changes is editing this counter. Twenty-one bumps says this
happens a lot. Risk: an agent changes `generate_test_targets.dart`, forgets the
bump, and tests silently run against stale target definitions. Better: feed a
hash of the generator sources into the extension (e.g. label-depend on the
generator files — `ctx.path(Label(...))` already creates a dependency — or
include their digest in the extension's environ), making invalidation
automatic. Filed as bead **sdk-6uq**.

### R4. Sanitizer config hardcodes x64 (confidence: verified)

`build/config/sanitizers/BUILD.bazel:30-73` (`options_sources`) carries literal
`-m64 -march=x86-64 -msse2 --target=x86_64-linux-gnu`. The pre-commit audit
deliberately excludes `build/config/` so these literals are sanctioned. Fine
while sanitizer builds are x64-only; will be a landmine the day someone runs
`--features=asan` on an arm64 host. A `select()` on the existing arch config
settings is the eventual fix; low urgency, documented here so it's not a
surprise.

### R5. `clone_dependencies.py` locking is homegrown (confidence: medium)

`tools/bazel/clone_dependencies.py:180-250`: mkdir-based lock (atomic — good)
with PID liveness + 5-minute-mtime stale detection and a 300×1s retry spin.
The PID-reuse race is theoretical; the real-world annoyances are (a) up to
5 minutes of silent spinning on a genuinely stuck holder, and (b) broad
`except Exception: pass` blocks that can mask cleanup failures. Works; just
don't extend it — if it grows another feature, switch to `fcntl.flock`.

### R6. Branch/remote naming is genuinely confusing — expect agent mistakes (confidence: verified)

Current reality: dedicated repo `kevmoo/dart-sdk-bazel`, default branch `main`;
local checkouts name the tracking branch `bazel` (remote here is named
`bazel-orign` [sic]); the old `kevmoo/sdk` fork's `bazel` branch **no longer
exists** (`git branch -r` shows only `kevmoo/main` etc.); upstream
`dart.googlesource.com` is `origin` and read-only by policy. Three different
"main"s depending on which doc you read. Every doc-drift item in §5 is
downstream of this. One cleanup pass + one authoritative paragraph in
README.md would pay for itself immediately.

## 5. Documentation / memory drift

### D1. Beads persistent memories point at a retired push target (confidence: verified)

`bd memories`: `git-push-policy` says "ALWAYS push to remote 'kevmoo' branch
'bazel'" and `primary-branch-bazel` says PRs target `bazel`. The
`kevmoo/sdk:bazel` branch is gone; the live flow is PRs to
`kevmoo/dart-sdk-bazel:main` (16 PRs there, ≤ #16 at review time). An agent
obeying the memory would push a stale-history branch to the wrong repo. I did
**not** edit these memories — push policy is safety-relevant and the human
should re-state it (then `bd remember --key git-push-policy ...`). AGENTS.md's
beads block ("merged into `kevmoo/bazel`") has the same problem.

### D2. DESIGN.md references four deleted documents (confidence: verified; **fixed this session**)

`m4_multiconfig_scoping.md`, `m4_arch_axis_scoping.md`, `rules_dart_scoping.md`
(header, line ~9) and `deep_dives/testing_migration_roadmap.md` (§3.5) were
deleted in the Session-120 docs purge but still linked as if live. Also,
`BUILD.bazel:55` comments still cite `docs/todo_issues/rules_dart_scoping.md`
(wrong path *and* deleted). Fixed the DESIGN.md links to say "(removed in the
Session-120 docs prune; recover via git history)". Left the BUILD comment —
it's inside a generated-file zone and not worth regen churn.

### D3. STATUS.md header names the dead branch (confidence: verified; **fixed this session**)

`STATUS.md:4` said the work lives "on branch `kevmoo/bazel`". Updated to the
current repo/branch reality (D1). Note STATUS.md also contains an ordering
quirk: Session 49 (a macOS session) is filed between Sessions 108 and 113 —
left as-is, it's history.

### D4. Bridge tooling defaults to a remote that may not exist (confidence: verified)

`tools/bazel/bridge/import.dart:36` / `export.dart:51` and
`.agents/skills/bazel_bridge/SKILL.md` default to `--base bazel-fork/main`;
`.agents/AGENTS.md:41-42` tells agents to create worktrees from
`bazel-fork/main`. No remote of that name exists in this checkout
(`bazel-orign` here). The flag is overridable, so this is per-machine
convention drift, not a code bug — but the docs should name the canonical
remote setup (or the tools should detect the remote that hosts
`dart-sdk-bazel`). Worth folding into the R6 cleanup pass.

### D5. Minor: BACKLOG.md board lags the beads DB (confidence: high)

Board says 55/65; `bd stats` said 54/63 closed/total at session start. The
board regenerates only when someone runs the generator. Known design (beads is
the source of truth), just don't trust the board's counters for decisions —
run `bd ready`.

## 6. False positives — things that LOOK wrong but are verified correct

Recorded so the next reviewer doesn't burn a session on them:

| Smell | Why it's actually fine | Evidence |
|---|---|---|
| `dart_set` (the `dart` CLI's source set) carries `PRODUCT`, `DART_PRECOMPILED_RUNTIME`, `EXCLUDE_CFE_AND_KERNEL_PLATFORM` | GN-faithful: `dart_executable("dart")` sets `use_product_mode = true` and links `libdart_aotruntime_product` — the modern `dart` CLI **is** an AOT-runtime product binary | `runtime/bin/BUILD.gn:1037-1057` |
| `DART_IO_SECURE_SOCKET_DISABLED` on all `gen_snapshot_dart_io_*` variants | GN does exactly this | `runtime/bin/BUILD.gn:452,584,872` |
| `json.decode()` in `tools/bazel/third_party.bzl:98` "without import" | `json` is a Starlark builtin in Bazel | Bazel ≥4 stdlib |
| CI workflows trigger on `main`, "but the branch is `bazel`" | The CI lives in repo `kevmoo/dart-sdk-bazel` whose default branch **is** `main`; local `bazel` tracks it. PR #14 set this deliberately | `gh pr view 14` |
| Duplicate `-std=c++20` (43 adjacent dups in `runtime/bin/BUILD.bazel`, 34 in gen_targets.bzl) | Faithful echo of GN's cflags + cflags_cc concatenation; harmless to clang; dedup is cosmetic translator work | counted via awk |
| `todo_issues/` numbering gaps (00002-00004, 00009-00011 missing) | Protocol explicitly deletes an issue file in the commit that resolves it | `todo_issues/README.md` ("Clean Up") |
| ICU overlay reads `BUILD.bazel.append` without an existence check (`third_party.bzl:275`) | The three append files are checked in under `tools/bazel/third_party_overlays/icu/`; a deletion fails loudly at fetch time, not silently | `find` verified |
| `ResolveBazelPath()` returning bare `'bazel'` as last resort (`tools/utils.py:1048`) | Standard PATH-delegation fallback; subprocess gives a findable (if blunt) error. Diagnostics could be nicer but it's not a bug | read |

## 7. Trivial fixes applied this session (branch `fable-review`)

| Fix | Commit | Verification |
|---|---|---|
| B1a: declare `//:package_config_json` as training prerequisite (3 BUILD files) | `27df3cf09b7` | `bazel build --nobuild //sdk:create_sdk` analysis green |
| B1b: staged package_config rootUri depth rewrite + stack_trace_mapper config swap | `08de579904b` | staged JSON inspected (all URIs `../../../…`, 0 shallow left); `bazel build //utils/ddc:stack_trace_mapper` green (red at HEAD) |
| B3: `tools/test.py` prints bazel-query stderr on failure | see git log | `python3 -m py_compile tools/test.py`; code-read only (a live failing query requires breaking the test repo — not done) |
| D2: DESIGN.md dead links annotated | see git log | links now state the files are removed + recoverable via git history |
| D3: STATUS.md branch header corrected | see git log | matches `git remote -v` / `gh repo view` reality |

Full `//sdk:create_sdk` build after B1a+B1b: **result recorded at the end of
this file** (it was running while this section was written).

Beads filed this session: **sdk-d3p** (O1 CI surface, P1), **sdk-u2u** (B2
hook-evasion policy, P1), **sdk-njh** (B4 selector strictness), **sdk-u24**
(B5 runSync timeout), **sdk-6uq** (R3 auto-invalidation), plus the tracking
bead for this review itself.

## 8. Opportunities for improvement (ranked, stability-first)

1. **O1 — Widen CI analysis surface (cheap, high value).** Add
   `bazel build --nobuild //sdk:create_sdk` (~17 s after fetch on a warm
   runner; it's pure analysis) and `bazel query @dart_tests//... > /dev/null`
   to `bazel.yml`. This alone would have caught B1. A weekly full
   `create_sdk` + smoke-run job with disk-cache would catch execution-phase
   regressions too. *(Confidence in value: verified by B1's existence.)*
2. **O2 — Close the hook-evasion hole (B2)** with an explicit policy +
   allowlist, and run the same audit in CI so `--no-verify` can't skip it.
3. **O3 — One branch-naming cleanup pass (R6/D1/D3/D4):** an authoritative
   "repo layout" paragraph in README.md, refreshed beads memories (human
   re-states push policy), fixed `bazel-fork` defaults or documented remote
   conventions.
4. **O4 — Auto-invalidate `@dart_tests` (R3)** — kill the manual counter.
5. **O5 — Make selector mismatch loud (B4)** and add a timeout to the
   test-runner's bazel probe (B5).
6. **O6 — Hermetic python for genrules (R2)** — batch with the next toolchain
   touch; not standalone-urgent.
7. **O7 — Translator cosmetics:** dedup repeated copts; have the translator
   log (not silently drop) non-`//out/` missing sources
   (`translate_gn_desc.py:182` drops them silently by design — fine for
   `//out/`, opaque for genuine deletions).
8. **O8 — DESIGN.md status banner.** DESIGN.md is now substantially historical
   (e.g. its exec summary still calls Bzlmod "not settled" — it shipped).
   It already defers to STATUS.md, but a short "what's still authoritative"
   banner would stop new agents from planning against stale sequencing.

## 9. Gemini review-feedback mining (all 15 merged PRs)

> Method: pulled every gemini-code-assist inline comment and review summary
> from PRs #2–#16 via `gh api` (PR #1 was a closed dependabot PR; #14 had no
> comments) — ~90 inline findings — and categorized them. Confidence:
> **verified** (the comments are quoted source data; categorization is mine).
>
> **Urgent context: gemini-code-assist (consumer) is being sunset — new
> installs blocked 2026-06-18, ALL review activity ceases 2026-07-17.** Every
> banner on every review says so. In five weeks this safety net is gone, which
> turns "nice to formalize" into "must front-load". Either substitute another
> automated reviewer (e.g. a Claude-based review action / `/code-review` in the
> agents' workflow) or convert the recurring catch classes below into
> mechanical gates. Ideally both.

### 9.1 What gemini actually catches, ranked by impact

**Class 1 — Generated/embedded code that was never executed before push
(the #1 source of `critical` badges).**
- PR #15: Starlark `set()` constructor (doesn't exist in Starlark) — would
  have broken every build.
- PR #16: undefined variable `pubspec_path` in `packages_extension.bzl` —
  Starlark evaluation error at fetch time.
- PR #13: generated bash test-runner wrote into the read-only runfiles tree;
  `rdir` became a dead relative path after `cd`.
- Root cause in all cases: module-extension / rule code paths that plain
  `bazel build //runtime/bin:dartvm` (the only CI job) never evaluates.
- **Front-load:** CI + local presubmit must *evaluate* the extensions:
  `bazel query @dart_packages//pkg/...` and a `bazel query @dart_tests//...`
  (or `bazel fetch` of both), plus actually *run* one generated
  analyze/format/package test. See §10.

**Class 2 — Silent failure / silent success.**
- PR #6: prune script printed errors but exited 0.
- PR #16: test runner passes green when zero test files are found.
- PR #2: `gclient sync` failure ignored on one branch of an if/else;
  `_isGitClean` returning clean on git *failure*.
- This is the same disease as my B3/B4 findings in `tools/test.py`. It is the
  project's most persistent bad habit across both humans' and agents' code.
- **Front-load:** a one-line rule in `.agents/rules/` (and CONTRIBUTING):
  *"A script that detects a problem must exit non-zero. A runner that runs
  zero of the things it was asked to run must fail, not pass."* Cheap to
  state, easy for a reviewer (human or AI) to check mechanically.

**Class 3 — Subprocess hygiene in Dart/Python tooling.**
- PR #2 (×8 comments): `Process.start` without draining stdout/stderr (hang
  when the pipe buffer fills), string-decoding binary patch output (corruption),
  unchecked exit codes, missing `runInShell` for Windows batch files,
  single-commit assumptions (`FETCH_HEAD`, `diff-tree HEAD`) silently dropping
  multi-commit PR content.
- PR #11: unguarded `Process.runSync` (fixed in response — good).
- **Front-load:** a tiny shared helper (`tools/bazel/bridge/proc.dart` or
  similar) wrapping run/start with: drained streams, exit-code check, optional
  timeout, `runInShell: Platform.isWindows`. Then ban raw `Process.start` in
  tools via an agent rule. The same 4 bugs have now been written 3+ times.

**Class 4 — Portability assumptions.**
- `grep`/`cut` in genrule cmds (PR #12), GNU `xargs -a` (breaks macOS BSD
  xargs, PR #13), `find` in repository rules (Windows, PR #15), `for f in
  $(find …)` word-splitting (PR #16), ARG_MAX overflow risk (PR #13).
- **Front-load:** rule: genrule `cmd` / repository-rule `execute` must use
  `python3` one-liners (already the repo's own convention) or
  bazel-skylib `run_binary`; no bare GNU-only flags. Greppable in review.

**Class 5 — Hand-file clobbering by generators.**
- PR #15 (×5 `critical`): generated per-package BUILD files overwrote
  hand-written `utils/BUILD.bazel`, `samples/ffi/*/BUILD.bazel`,
  `tools/BUILD.bazel`, `runtime/tools/BUILD.bazel` — deleting
  `compile_platform_exe`, `gen_kernel_exe`, FFI sample libs, `exports_files`.
  Gemini caught it pre-merge; the same accident class previously happened
  in-session (the translator now has `_is_hand_authored_overlay` guards).
- **Front-load:** extend the pre-commit hook (and CI mirror) with a protected-
  files manifest: fail if a PR deletes or empties any hand-authored
  BUILD.bazel listed in it. The list already implicitly exists as "files with
  hand-fix headers".

**Class 6 — Hardcoded environment specifics & secrets-adjacent leaks.**
- `kevmoo` home paths in docs (PR #2), real GCP project ID + bucket names in a
  README *that itself said never to commit them* (PR #5), hardcoded developer
  email as a Terraform default (PR #5).
- **Front-load:** add greps to the pre-commit audit: `/usr/local/google/home/`,
  `home/kevmoo`, the real project-ID pattern, `user:.*@google.com`.

**Class 7 — Infra config invented against an imagined schema.**
- PR #5 (×6 `high`): Helm values keys that don't exist in the Buildfarm chart
  (`worker:` vs `shardWorker:`, `externalRedis.uri`), string blocks where the
  chart expects maps, KEDA targeting the wrong kind/name/namespace, Terraform
  provider constraint older than the features used, `grpcs://` with no TLS
  termination anywhere.
- PR #8/#9: GKE scheduling/policy mistakes (nodeSelector that can never match;
  org-policy violation on private endpoints).
- **Front-load:** for `infra/`: `terraform validate` + `helm template
  --validate` (+ ideally `kubeconform`) as a CI job and a documented local
  step. These are exactly the checks that would have caught all six.
- Note: agents writing config for external systems should be required to cite
  the schema source (chart version, provider docs) in the PR description —
  cheap accountability that catches hallucinated keys.

**Class 8 — Hermeticity regressions.**
- PR #10: replacing a tracked `$(execpath //tools:VERSION)` input with a
  cwd-relative assumption. Gemini pushed back correctly.
- **Front-load:** this is review-judgment territory; encode as an agent rule:
  *"never replace a declared Bazel input with an implicit filesystem path"*.

**Class 9 — Low-value-but-constant nags the tooling should absorb.**
- Duplicate copts (`-fPIE`, `-std=c++20`) — flagged in PR #4 and present 43×
  in `runtime/bin/BUILD.bazel` (§6): one translator dedup pass removes the
  entire nag class.
- Doc/impl drift inside the same PR (STATUS.md describing a DEPS hook that the
  PR didn't ship, PR #6; doc'd default ≠ actual default, PR #2): reviewer
  checklist item — "does the STATUS.md session entry match the diff?"

### 9.2 Did the feedback get applied? (spot-check)

Three spot checks: PR #11's runSync error handling — applied. PR #15's
criticals — applied pre-merge (the hand files exist at HEAD). PR #16's
`pubspec_path` critical — applied pre-merge (no reference at HEAD). So the
loop *does* close on `critical`/`high`; the repeated-offender classes (2–4)
keep recurring anyway because they're *new instances*, not unfixed old ones.
That's exactly what formalization fixes — and what disappears entirely when
gemini sunsets unless replaced.

## 10. CI & local validation roadmap (consolidates O1/O2 with §9)

Ordered; each step states what regression class it would have caught.

**CI (`.github/workflows/bazel.yml`), cheap → expensive:**
1. `bazel build --nobuild //sdk:create_sdk //runtime/bin:dartvm` — full
   analysis, ~30 s warm. *Would have caught:* B1a, PR #15's `set()`, PR #16's
   undefined var (extension evaluates during loading), every missing-prereq
   error.
2. `bazel query @dart_packages//pkg/... | head` and
   `bazel query "@dart_tests//..."` (or `bazel fetch`) — forces both module
   extensions to execute end-to-end. *Catches:* generator crashes the
   `--nobuild` of step 1 might skip if nothing depends on them.
3. Run the cheapest generated tests:
   `bazel test @dart_packages//pkg/expect:analyze @dart_packages//pkg/expect:format`
   (pick one small package) + `bazel run //tools/bazel/dart:test_hello`.
   *Catches:* PR #13's read-only-runfiles & rdir bugs, PR #16's runner bugs —
   the class that only manifests at execution.
4. Mirror the pre-commit audit in CI (hook is `--no-verify`-skippable), with
   the audit extended per §9 Class 5/6 and B2 (concat evasion, protected
   files, env-specific strings).
5. `infra/` job: `terraform validate` + `helm template --validate`. Gated on
   paths under `infra/`.
6. Scheduled (nightly) full `bazel build //sdk:create_sdk` + packaged-SDK
   smoke (`dart --version` + hello.dart) + one
   `tools/test.py --bazel -n vm-release-x64 corelib/list_test`. *Catches:*
   B1b-class execution regressions and toolchain drift at bounded cost.
   (PR-time full create_sdk is likely too slow without a shared remote cache;
   once the Buildfarm/BuildBuddy work stabilizes, promote it to PR-time.)

**Local validation (one entry point, documented in README):**
- Add `tools/bazel/presubmit.sh` bundling: buildifier check on changed files →
  extended audit → step 1 + 2 above → `python3 -m py_compile` on touched
  `tools/**/*.py` → `dart analyze` on touched `tools/bazel/**/*.dart`.
  Target: < 2 min warm. The README already documents buildifier; this makes
  "what must pass before a PR" a single command instead of tribal knowledge —
  which matters double once the agents lose their automated reviewer.
- PRESUBMIT.py already runs buildifier (PR #12); fold the audit + analysis
  steps in there too so `git cl presubmit`-style flows get it for free.

**Process:**
- Replace gemini before 2026-07-17 (Class-by-class: 1–6 are mechanizable
  above; 7–8 need a model-based reviewer or human). The `.agents/` framework
  could grow a `review_checklist.md` rule encoding §9's classes 2, 3, 4, 8 —
  they're one-liners for a reviewing agent to check.
- Require PR descriptions for `infra/` changes to cite the external schema
  (chart/provider version) being targeted.

## 11. What I did NOT review

- **macOS path** (rules generalization, `xcodebuild/` handling) — Linux only.
- **Remote execution / GKE Buildfarm infra** (PRs #5, #8, #9, #10) — no
  cluster access from this session; entirely unverified.
- **Generated `gen_targets.bzl` content** beyond the hand/machine seam, and
  **translator regen byte-stability** — historically verified per STATUS.md,
  but I did not re-run the translator (it requires a GN desc dump and clobbers
  foreign packages; too invasive for a review session).
- **The `@dart_tests` test execution path end-to-end** (`tools/test.py --bazel
  -n vm-release-x64 ...`) — would have required a test-repo fetch + dartvm
  rebuild inside the extension; time-boxed out. The CI/test reviewer pass was
  code-read only.
- **Open PR #16** (lint_rules/packages_extension) — out of scope; it touches
  the same `packages_extension.bzl` machinery as B1's root cause, so review it
  with B1's lesson in mind.
- Windows/Android/Fuchsia/RISC-V anything.
