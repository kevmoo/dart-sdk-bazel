# Dart SDK Bazel Migration

This directory houses the active coordination, progress tracking, and developer guidelines for the ongoing migration of the Dart SDK build and packaging engine from GN+Ninja to Bazel.

---

## 🏛️ Workspace Architecture & Terminology

For details on the typical Bare Repository + Sandbox Worktree layout used across forks by `kevmoo`, variable definitions like `{workspace-root}`, and links to master agent playbooks, refer to: 👉 **[typical-layout.md](typical-layout.md)**.

---

## ⚡ Quick Start (Build & Run)

If you are a contributor (human or AI agent) looking to build or run the SDK using Bazel, here is what you need to know right now.

### 1. Host Prerequisites
Ensure your host machine has **Python 3**, **Bazel** (via bazelisk), and **Xcode-select** (macOS) or **MSVC** (Windows). All third-party dependencies are fetched hermetically by Bazel via Bzlmod overlays.

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

### 3. Remote Caching & GCS Setup (Speeding Up Builds)
The repository is integrated with a shared Google Cloud Storage remote cache (`https://storage.googleapis.com/dart-sdk-bazel-cache`).

1. **Double-Check Authentication**: Before enabling the remote cache locally, ensure your machine has valid Google Application Default Credentials:
   ```bash
   gcloud auth application-default login
   ```
2. **Use the Cache When it Makes Sense**: Append `--config=remote-cache` to any `bazel build` or `bazel test` command (or add `build --config=remote-cache` to your `~/.bazelrc`):
   ```bash
   bazel build --config=remote-cache //sdk:create_sdk
   ```
   *Note: Using the remote cache is recommended for clean builds, switching branches, or multi-worktree development to avoid re-compiling shared C++ dependencies and tools.*

### 4. Smoke Test (Verify the VM)
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

### 5. Running Dart Scripts with `bazel run`
We support running Dart scripts directly inside the Bazel sandbox using `bazel run` (thanks to the `dart_binary` rule):

```bash
bazel run //tools/bazel/dart:test_hello -- --verbose
```

---

## 🤝 Coordination Protocol (How We Work)

To prevent communication breakdowns and avoid merge collisions (especially when multiple AI agents are working concurrently):

1.  **Scan the Backlog:** Run `bd ready` for actionable tasks. Look for `[PENDING]` tasks.
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

### 2. Pre-PR Validation (One Command + Agent)
Before sending a PR, validate your branch locally to ensure it will pass CI and architectural review:
*   **Run CI Checks Locally:** `./tools/bazel/presubmit.sh`
    It bundles buildifier format+lint, architecture audits, and analysis. Takes ~1.5 minutes warm.
*   **Agent Code Review:** Run the `bazel-pre-pr` agent skill in your terminal. This spins up an autonomous code reviewer that surgically audits your local commits against the rules defined in `GUIDELINES.md`.

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

### 6. Test Quarantining & Regeneration Workflow

When fixing quarantined tests or modifying test metadata, follow these steps:

1.  **Modify `suite_config.json`**: Quarantine rules and extra dependencies are mapped in `tools/bazel/dart/suite_config.json`. To unquarantine a test, remove or restrict its pattern from the `quarantine_patterns` array.
2.  **Regenerate Test Targets**: Any change to `suite_config.json` or upstream `.status` files requires regenerating the Bazel test BUILD files. Run the generator script:
    ```bash
    dart tools/bazel/dart/generate_test_targets.dart
    ```
3.  **Debug & Verify**: Run the unquarantined test to verify your fix. Use the `bazel test` command directly on the newly active target:
    ```bash
    bazel test //tests/language:your_test_name
    ```
    If it fails, you can use `bazel run` to execute it interactively and debug.

---

## 🗺️ Directory Map

Only the following active files and directories are maintained in `docs/bazel-migration/`. All historical scoping and design documents have been pruned and are preserved in the **Git history**.

*   [README.md](README.md) — This file. Entry point and developer guide.
*   [typical-layout.md](typical-layout.md) — Explanation of Kevmoo's multi-fork bare repository and sandbox worktree layout conventions.
*   [GUIDELINES.md](GUIDELINES.md) — The unified master rulebook containing both core architectural rules and code-level pre-flight patterns.
*   [BEADS.md](BEADS.md) — Task tracking setup + workflow: how to install `bd` and bootstrap the task DB on a new machine.
*   [STATUS.md](STATUS.md) — The living session-by-session progress tracker.
*   [UPSTREAM_CANDIDATES.md](UPSTREAM_CANDIDATES.md) — List of non-Bazel fixes to be upstreamed to `main`.
*   [todo_issues/](todo_issues/) — Directory containing open, unresolved SDK-internal issues.
