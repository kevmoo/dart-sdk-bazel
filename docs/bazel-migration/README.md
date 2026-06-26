# Dart SDK Bazel Migration

This directory houses the active coordination, progress tracking, and developer guidelines for the ongoing migration of the Dart SDK build and packaging engine from GN+Ninja to Bazel.

---

## 🏛️ Workspace Architecture & Terminology

For details on the typical Bare Repository + Sandbox Worktree layout used across forks by `kevmoo`, variable definitions like `{workspace-root}`, and links to master agent playbooks, refer to: 👉 **[typical-layout.md](typical-layout.md)**.

---

## ⚡ Quick Start (Build & Run)

If you are a contributor (human or AI agent) looking to build or run the SDK using Bazel, here is what you need to know right now.

### 1. Host Prerequisites
Ensure your host machine has:
*   **Python 3** (used for minor helper scripts).
*   **Bazel** (recommended to use [bazelisk](https://github.com/bazelbuild/bazelisk) to automatically respect the [.bazelversion](../../.bazelversion) file).
*   **Xcode-select** (macOS only) or **MSVC** (Windows only) for native C++ compilation.
*   All third-party dependencies are fetched hermetically by Bazel via Bzlmod overlays. No manual sync scripts (like the retired `restore.sh`) are required.

### 2. Core Build Commands
Execute these from the repository root:

*   **Build the full, packaged Dart SDK:**
    ```bash
    bazel build //sdk:create_sdk
    ```
    This assembles the complete Dart SDK (binaries, snapshots, libraries) under `bazel-bin/sdk/dart-sdk/`.

*   **Build the standalone Dart VM:**
    ```bash
    bazel build //runtime/bin:dartvm
    ```
    This produces a self-contained `dartvm` binary at `bazel-bin/runtime/bin/dartvm` with all necessary dills and ICU data embedded hermetically from source.

### 3. Smoke Test (Verify the VM)
To verify your built VM works correctly, run a simple Dart script:

```bash
# Create a simple hello world script
cat > /tmp/hello.dart <<'EOF'
void main() {
  print('Hello from Bazel-built dartvm!');
  print([1, 2, 3].map((x) => x * x).toList());
}
EOF

# Run it using the Bazel-built VM
bazel-bin/runtime/bin/dartvm /tmp/hello.dart
# Output should be:
# Hello from Bazel-built dartvm!
# [1, 4, 9]
```

### 4. Running Dart Scripts with `bazel run`
We support running Dart scripts directly inside the Bazel sandbox using `bazel run` (thanks to the `dart_binary` rule):

```bash
bazel run //tools/bazel/dart:test_hello -- --verbose
```

---

## 🤝 Coordination Protocol (How We Work)

To prevent communication breakdowns and avoid merge collisions (especially when multiple AI agents are working concurrently):

1.  **Scan the Backlog:** Run `bd ready` for actionable tasks (or read [BACKLOG.md](BACKLOG.md), which is generated from beads). Look for `[PENDING]` tasks.
2.  **Claim a Task:** Before editing any code, claim it in beads: `bd update <id> --status in_progress --assignee <you>`. Tasks live in the beads DB (`bd`), not a hand-edited file.
3.  **Log Your Session:** Document your progress session-by-session in [STATUS.md](STATUS.md). Update the **"Cross-agent notes"** at the top of [STATUS.md](STATUS.md) for live claims and handoffs.
4.  **Report SDK Defects:** If you discover a non-hermetic script or packaging defect in the upstream SDK, document it as a numbered issue in [todo_issues/](todo_issues/) following the protocol in [todo_issues/README.md](todo_issues/README.md) *before* implementing a workaround.

---

## 🛠️ Developer Workflow & Tooling

### 1. Branching & PR Workflow (No Direct Commits to `main`)
*   `main` on `kevmoo/dart-sdk-bazel` is the development target. **Do not commit directly to `main`.**
*   Create a feature branch from the latest remote `main` for your task, e.g.: `git checkout -b task-037-cleanup <remote>/main`
*   Push your branch and submit a GitHub Pull Request targeting `main`.
*   **Never push to `main` without explicit human approval.**
*   Local branch names and git remote names vary per machine — do not assume a particular layout (the old local `bazel` tracking-branch convention is retired). Check `git remote -v` and `git branch -vv` instead of hardcoding.

### 2. Pre-PR Validation (One Command)
Before sending a PR, run the presubmit gate — CI runs the same script, so a local pass should closely predict a green PR:
```bash
./tools/bazel/presubmit.sh
```
It bundles (cheap → expensive): buildifier format+lint, the hardcoded-architecture audit, python byte-compile, `--nobuild` analysis of `//sdk:create_sdk` + `//runtime/bin:dartvm` + the utils exes, evaluation of both module extensions (`@dart_packages`, `@dart_tests`), and `dart analyze` over the Bazel tooling scripts. Takes ~1.5 minutes warm.

### 3. Formatting & Linting (Buildifier)
We enforce standard Starlark formatting and linting repository-wide.
*   **Automated Gate:** A pre-commit hook is active. On a fresh clone, activate it via:
    ```bash
    ln -sf ../../tools/bazel/hooks/pre-commit .git/hooks/pre-commit
    ```
    This hook automatically runs `buildifier --lint=fix` on any staged `BUILD.bazel` or `.bzl` files.
*   **Manual Check:** You can audit formatting and lints manually:
    ```bash
    # Check formatting and warnings without editing
    buildifier --mode=check --lint=warn path/to/BUILD.bazel
    
    # Apply automatic fixes
    buildifier --lint=fix path/to/BUILD.bazel
    ```

### 4. Programmatic Edits (Buildozer)
For scripted, bulk edits to BUILD files, use `buildozer`:
```bash
# Inspect dependencies of a target
buildozer 'print deps' //runtime/bin:dartvm

# Add a dependency
buildozer 'add deps //some:lib' //runtime/bin:dartvm
```

### 5. Inspecting Fork Delta vs. Upstream SDK (`fork_delta.dart`)
Because our long-running Bazel fork contains hundreds of new Bazel configuration files alongside surgical modifications to the upstream Dart SDK source code, you can use our dedicated inspection tool to instantly see what changed:
```bash
# See a categorized, scannable summary of the entire fork delta
dart tools/bazel/fork_delta.dart

# Display precisely the non-Bazel Dart SDK source files modified or deleted to form an upstream CL
dart tools/bazel/fork_delta.dart --upstream-cl

# View the actual Git code diff for our modified SDK tooling or C++ files
dart tools/bazel/fork_delta.dart --diff modified-tools
```

---

## 🗺️ Directory Map

Only the following active files and directories are maintained in `docs/bazel-migration/`. All historical scoping and design documents have been pruned and are preserved in the **Git history**.

*   [README.md](README.md) — This file. Entry point and developer guide.
*   [typical-layout.md](typical-layout.md) — Explanation of Kevmoo's multi-fork bare repository and sandbox worktree layout conventions.
*   [GUIDELINES.md](GUIDELINES.md) — The 14 Bazel architectural migration rules and engineering guidelines.
*   [BACKLOG.md](BACKLOG.md) — The active backlog and coordination board (generated from beads).
*   [BEADS.md](BEADS.md) — Task tracking setup + workflow: how to install `bd` and bootstrap the task DB on a new machine.
*   [STATUS.md](STATUS.md) — The living session-by-session progress tracker.
*   [UPSTREAM_CANDIDATES.md](UPSTREAM_CANDIDATES.md) — List of non-Bazel fixes to be upstreamed to `main`.
*   [gen_board_from_beads.dart](gen_board_from_beads.dart) — Regenerates [BACKLOG.md](BACKLOG.md) + [BACKLOG_HISTORY.md](BACKLOG_HISTORY.md) from the beads issue DB (the task source of truth).
*   [todo_issues/](todo_issues/) — Directory containing open, unresolved SDK-internal issues.
