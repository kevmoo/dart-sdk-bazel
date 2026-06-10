# Product Guidelines: Dart SDK Bazel Migration

This document defines the engineering standards, quality gates, and coordination protocols for all contributors (human and AI) working on the Dart SDK Bazel migration.

---

## 🧼 1. Engineering Philosophy

### 🎯 Surgical Changes ("Touch Only What You Must")
*   **Zero Collateral Edits**: Do not "improve," reformat, or refactor adjacent code, comments, or styling that is unrelated to the active task.
*   **Match Existing Style**: Conform exactly to the style and conventions of the file you are modifying, even if you would personally design it differently.
*   **Prune Dead Code**: If your changes render any imports, variables, or functions unused, you MUST remove them immediately. Do not remove pre-existing dead code unless explicitly asked to do so.

### 🧪 Simplicity First
*   **Minimalist Implementation**: Write the absolute minimum code required to solve the problem and satisfy the acceptance criteria.
*   **No Speculative Code**: Avoid building "flexibility," "configurability," or abstractions for future use cases that have not been requested.
*   **Senior Review Standard**: Every line of code should be clean and simple enough that a senior engineer would not consider it overcomplicated.

---

## 🚨 2. Code Quality Gates

Every commit containing code changes MUST satisfy these gates before being prepared:

### 🔹 Dart Quality Gate
1.  **Formatting (`dart format`)**: Every modified or newly created `.dart` file must be perfectly formatted using `dart format`.
2.  **Static Analysis (`dart analyze`)**: Every modified or newly created `.dart` file must be 100% free of analyzer errors, warnings, and lint issues.

### 🔹 Bazel & Starlark Quality Gate
1.  **Formatting & Linting (`buildifier`)**: Every modified or newly created Bazel file (`BUILD.bazel`, `MODULE.bazel`, `.bzl` files, excluding `gen_targets.bzl`) must be perfectly formatted and free of lint warnings. Run `buildifier --lint=warn --warnings=all <file>` to verify.

### 🔹 Python Quality Gate
1.  **Formatting (`yapf`)**: Every modified or newly created `.py` file must be perfectly formatted using `yapf` in accordance with the `.style.yapf` configuration.

---

## 📑 3. Backlog & Coordination Protocol

### 🗺️ Dolt-First Backlog Integrity
*   **Source of Truth**: The Dolt database (`.beads/embeddeddolt/sdk`) is the absolute source of truth for all tasks. Never hand-edit `BACKLOG.md` or `BACKLOG_HISTORY.md`.
*   **Workflow Lifecycle**: Create or claim a task in beads (`bd update <id> --claim`) before writing code. Mark it `in_progress` when starting.
*   **Atomic Documentation Commits**: Any commit that completes a task MUST:
    1.  Close the task in beads: `bd close <id>`.
    2.  Regenerate the board: `tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart`.
    3.  Stage and commit the code changes **and** the updated `BACKLOG.md` / `BACKLOG_HISTORY.md` in a single, atomic Git commit.
    4.  **Track Cleanup (if applicable)**: Delete the completed Conductor track folders (e.g., `rm -rf conductor/tracks/<track_id>`) from the repository, as their detailed planning and specification history is already preserved in the merged PR's git history. Commit this cleanup in the same "Backlog Sync" commit to keep the `bazel`/`main` branch clean of finished plans.
*   **Session Logging**: Every commit or logical block of work must have a corresponding entry in `docs/bazel-migration/STATUS.md` summarizing what was implemented, verified, and any handoff notes.

---

## 🗺️ 4. Branch & Commit Policy

*   **Direct Branching for Small Fixes**: Small fixes, documentation updates, backlog syncs, or straightforward task completions can be committed and pushed directly to the base integration branch.
*   **Pull Requests for Complex Features**: Large, complex, or high-risk tasks must be developed on a dedicated feature branch and merged via a Pull Request to ensure stability.
*   **No Unilateral Pushes**: Never run `git push` without verifying that no sensitive files or secrets are staged, and always follow the project's repository push authorization rules.
