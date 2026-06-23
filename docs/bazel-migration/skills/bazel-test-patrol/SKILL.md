---
name: bazel-test-patrol
description: Orchestrates long-running or recurring patrols of the Dart SDK Bazel test completion matrix. Discovers test targets, runs automated watchdog timers (default 5m/300s), bypasses blocking test suites or configs, regenerates canonical completion reports (TEST_COMPLETION_MATRIX.md), and synchronizes findings with the Beads issue backlog. Use when the user asks to run all Bazel tests, check test completion matrix health, audit migration test gaps, or leave overnight test patrols running.
---

# Bazel Test Patrol Playbook

Orchestrates automated execution, health checks, and gap analysis of the Dart SDK Bazel test universe.

## 1. Decoupled JSON Source of Truth & Tools
* **Runner**: `tools/bazel/run_test_universe.dart`
* **Renderer**: `docs/bazel-migration/render_test_matrix.dart`
* **JSON Output**: `docs/bazel-migration/test_matrix_results.json`
* **Markdown Report**: `docs/bazel-migration/TEST_COMPLETION_MATRIX.md`

## 2. Non-Blocking Execution & Watchdog Protocol
Do **NOT** run massive test suites synchronously in the terminal. Execute `run_test_universe.dart` as an asynchronous background task.
Jetski provides native reactive wakeup on natural task completion.

### The 5-Minute Safety Watchdog
To guard against hung browser drivers (`chromedriver`, `firefox`) or deadlocked C++ threads, schedule a safety timer using the `schedule` tool immediately after launching the runner task:
```text
DurationSeconds: 300
TimerCondition: "task-<ID>"
Prompt: "Watchdog check: inspect task status and logs"
```

### Watchdog Wakeup Handling Loop
When woken up by the watchdog timer notification:
1. Check `manage_task status` for the runner task ID.
2. If status is `running` and log output shows active test completion progress:
   * **Action**: Schedule another 300s watchdog timer (`"Making normal progress → wait longer"`).
3. If status is `running` but logs show a deadlocked process or spinning hung driver:
   * **Action**: Kill the task (`manage_task kill`).
   * Restart `run_test_universe.dart` passing `--skip-configs=<hung_config>` or `--skip-suites=<hung_suite>`.

## 3. Quarantining Blockers
If a red CI lane or broken compiler change crashes discovery or redlines thousands of targets:
* `--skip-suites=<s1,s2>` *(e.g., co19,pkg)*
* `--skip-configs=<c1,c2>` *(e.g., wasm_firefox_release)*
* `--only-suites=<s1,s2>`
* `--watchdog-interval=300`

## 4. Post-Run Synchronization Loop
Once `run_test_universe.dart` completes:
1. Run `dart docs/bazel-migration/render_test_matrix.dart` to update `TEST_COMPLETION_MATRIX.md`.
2. Inspect `git status` inside the active sandbox worktree.
3. Update Beads issues if tracking specific newly discovered broken configs.
4. Summarize all modified files and request explicit user authorization before running `git commit`, `bd dolt push`, or `git push`.
