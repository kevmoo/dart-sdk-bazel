---
name: sdk-bazel-beads
description: >-
  MANDATORY skill when working on Bazel thread tasks (sdk-5m4.*, etc.), updating task status in beads,
  managing PR alignment lifecycle, or syncing the Dolt task DB.
---

# Bazel Thread Task Tracking & Beads Lifecycle (`sdk-bazel-beads`)

This skill defines the mandatory workflow for issue tracking, task lifecycle management, backlog board generation, and Dolt database synchronization on the **Bazel thread (`bazel`)**.

---

## 🔄 1. Task Lifecycle & PR Alignment (CRITICAL)

To keep the backlog board accurate and prevent desynchronization:

1. **`OPEN` / `BLOCKED` (Backlog)**:
   - Tasks waiting to be claimed. Inspect with `bd ready` or `bd show <id>`.

2. **`IN_PROGRESS` (Active Development & PR Review)**:
   - Claim a task via `bd update <id> --claim` when starting work.
   - **CRITICAL**: The task **MUST** remain in `IN_PROGRESS` status throughout all active coding, local testing, branch creation, and pull request code review.

3. **`CLOSED` (Done)**:
   - **ONLY close a task (`bd close <id>`) AFTER code has actually landed on `main`**:
     a. Immediately after a **direct push to `main`** (for direct commits or automated board updates), OR
     b. After a **feature/PR branch is merged into `main`**.
   - **NEVER** close a bead while changes remain uncommitted, unpushed, or on an active feature/PR branch.

---

## 📊 2. Board Generation & Dolt Sync Protocol

Whenever task metadata or status changes in `beads` (`bd`), execute the following steps in order:

1. **Regenerate Backlog Markdown Boards**:
   ```bash
   tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart
   ```
2. **Push Dolt Task Database**:
   ```bash
   bd dolt push
   ```
3. **Stage & Commit Board Updates**:
   ```bash
   git add docs/bazel-migration/BACKLOG.md docs/bazel-migration/BACKLOG_HISTORY.md
   ```

---

## 🛠️ 3. Environment & Remote Gotchas

- **Remote Transport**: Always use `git+https://` (never `git+ssh://`) for the Dolt remote to prevent interactive SSH popups.
- **Dolt Remote Name**: The remote target MUST be named `origin`.
- **Dolt Target Repo**: The beads DB lives on the `kevmoo/sdk` fork (`dart-sdk-bazel`), not upstream read-only Google mirror.
- **No Force-Pushing**: Never run `dolt push --force`.
- **Worktree Isolation**: In Git worktree layouts (`sdk/`), `bd` commands target `.bare/.beads` or local worktree `.beads/` automatically.
