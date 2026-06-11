# Fable's Review — Bazel Migration Project

> **Status: IN PROGRESS** — this document is being written incrementally during a
> single review session (2026-06-10, agent "fable" / Claude Code on branch
> `fable-review`). If this banner is still here, the session ran out of tokens
> mid-flight; everything below the banner is still valid, but coverage may be
> incomplete. Sections marked `TODO` were not reached.
>
> **Audience:** another agent (or human) picking up the migration. Every finding
> carries a **confidence** rating telling you how much to trust it without
> re-verifying:
> - **verified** — I empirically reproduced/checked it this session (commands shown). Take my word.
> - **high** — read the code carefully; mechanism is clear; spot-check before large refactors.
> - **medium** — code-read by a subagent or inferred; investigate before acting.
> - **low** — hypothesis/smell; treat as a lead, not a finding.

## 0. Review method

- Branch under review: `bazel` (HEAD `90798795679`, "feat(bazel): implement
  virtual namespaced package targets (sdk-v49) (#15)"), reviewed on working
  branch `fable-review`.
- Four parallel read-only exploration passes (tools/bazel infra; hand-authored
  BUILD overlays; CI + test-runner integration; docs consistency) plus direct
  empirical verification (builds, queries, regen-stability checks) by the
  coordinating agent.
- Stability was the explicit optimization target, per the requester.

## 1. Executive summary

TODO — written last.

## 2. Verified empirical baseline

What actually works on this machine, this session:

| Check | Result |
|---|---|
| `bazel build //runtime/bin:dartvm` | TODO |
| `bazel build //sdk:create_sdk` | TODO |
| smoke: run hello.dart on built VM | TODO |
| `buildifier` global check | TODO |
| beads DB health (`bd stats`) | verified: 63 issues, 7 open, 1 in_progress, 3 blocked, 4 ready |

## 3. Bugs

TODO — populated from findings.

## 4. Stability risks (not yet bugs)

TODO

## 5. Documentation drift

TODO

## 6. Opportunities for improvement

TODO

## 7. Trivial fixes applied in this session

Each fix was verified; see commit history of branch `fable-review`.

| Fix | Commit | Verification |
|---|---|---|
| (none yet) | | |

## 8. What I did NOT review

TODO — explicit coverage gaps so the next agent knows where dragons may remain.
