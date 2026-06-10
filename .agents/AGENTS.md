# Workspace Rules: Dart SDK Sandbox Layout

This workspace uses a specialized **Bare Repository + Sandbox Worktree** layout to optimize disk space, handle `gclient` cleanly, and keep the root directory pristine. 

All AI agents operating in this workspace MUST adhere to the following rules.

---

## 1. Workspace Structure

The workspace root is `~/github/dart-sdk/`. 

*   **`~/github/dart-sdk/.bare/`**: The central Git database (bare repository). **NEVER** attempt to run builds, edits, or standard git commands directly in this directory without the `--git-dir` flag.
*   **`~/github/dart-sdk/core/`**: Thread 1 - Core open-source Dart SDK work.
*   **`~/github/dart-sdk/bazel/`**: Thread 2 - Heavy Bazel fork work.

---

## 2. Rules for Agent Operations

### Rule 1: Never work in the root or bare directory
You do not have a working tree at the root of `~/github/dart-sdk/`. Do not attempt to create files or run builds there.

### Rule 2: Always create an isolated Sandbox for your task
If you are assigned a task, you must create a dedicated sandbox. 
1.  Identify if the task belongs to **Core** (`core/`) or **Bazel** (`bazel/`).
2.  Your sandbox directory should be named `~/github/dart-sdk/<category>/agent-<task-name>/`.

### Rule 3: How to initialize your Sandbox
To set up your workspace, you must execute these steps in order:

1.  **Create the sandbox parent directory:**
    ```bash
    mkdir -p ~/github/dart-sdk/<category>/agent-<task-name>
    ```
2.  **Add a Git Worktree named `sdk`** inside your sandbox, pointing to the central `.bare` database:
    ```bash
    # For Core work (tracking origin/main or a feature branch):
    git --git-dir=~/github/dart-sdk/.bare worktree add ~/github/dart-sdk/core/agent-<task-name>/sdk origin/main

    # For Bazel work (tracking bazel-fork/main or a feature branch):
    git --git-dir=~/github/dart-sdk/.bare worktree add ~/github/dart-sdk/bazel/agent-<task-name>/sdk bazel-fork/main
    ```
3.  **Create the `.gclient` file** in your sandbox parent directory (NOT inside `sdk/`):
    ```python
    # Write this to ~/github/dart-sdk/<category>/agent-<task-name>/.gclient
    solutions = [
      {
        "name": "sdk",
        "url": "https://github.com/dart-lang/sdk.git",
        "deps_file": "DEPS",
        "managed": False,
        "custom_deps": {},
        "custom_vars": {
          # Set to True if your task involves Wasm/dart2wasm to enable
          # automatic download and activation of the Emscripten SDK.
          # "download_emscripten": True,
        },
      },
    ]
    ```
4.  **Sync dependencies using `depot_tools`:**
    You must add `~/github/depot_tools` to your `PATH` to run `gclient`:
    ```bash
    export PATH=$PATH:$HOME/github/depot_tools
    cd ~/github/dart-sdk/<category>/agent-<task-name>/sdk
    gclient sync
    ```

### Rule 4: Clean up after yourself
Once your task is complete, you have submitted your CL/PR, and the user has approved, you should clean up your worktree to save disk space:
```bash
git --git-dir=~/github/dart-sdk/.bare worktree remove ~/github/dart-sdk/<category>/agent-<task-name>/sdk
rm -rf ~/github/dart-sdk/<category>/agent-<task-name>
```

---

## 3. Tips for Specific Workflows

### Wasm / dart2wasm Development
If your task involves WebAssembly or `dart2wasm`:
1.  **Enable Emscripten in `.gclient`:** Set `"download_emscripten": True` in `custom_vars` in your `.gclient` file *before* running `gclient sync`. If you already synced without it, update `.gclient` and run `gclient sync` again.
2.  **Build Required Targets:** To run tests, you must build both the compiler and the optimizer. Run:
    ```bash
    python3 tools/build.py -m release -a x64 dart2wasm wasm-opt
    ```
3.  **Running Tests:** Use `tools/test.py` with the `dart2wasm` compiler:
    ```bash
    python3 tools/test.py -c dart2wasm language/exception/sync_throw_ref_test
    ```

---

## 4. CRITICAL: State-Changing and Remote-Write Safeguards

> [!CAUTION]
> ### 🚨 ABSOLUTE RULE FOR ALL AGENTS: NO INFERRED REMOTE WRITES OR FORCE PUSHES
> 
> 1. **IMMEDIATE EXPLICIT AUTHORIZATION:** Every single `git push` (especially `git push --force` or `git push origin ... --force`) and every single `bd dolt push` (or any remote database write) **MUST** be explicitly authorized by the human user **immediately before** it is executed.
> 2. **NO INFERRED PERMISSION:** Permission **CANNOT** be inferred from earlier statements in the conversation (such as *"let's do that"* or *"please"*). Even if a multi-step plan containing a push was previously approved, the agent **MUST pause and ask for a final, explicit confirmation** right before running the actual push command.
> 3. **HISTORY MODIFICATIONS:** The same rule applies to `git commit --amend`, `git rebase`, or any other history-modifying command. These are destructive operations and **MUST** be explicitly approved immediately before execution.
> 4. **PENALTY:** Any violation of this rule is considered a critical breach of safety protocols and will result in immediate termination of the agent's session.

---

## 5. Beads & Dolt Integration for Agents

The beads database is stored as a Dolt database inside the central bare repository at `.bare/.beads/`.

#### How to use `bd` in this workspace:
1.  **Database Location:** Because the database is hidden in `.bare/`, `bd` will not auto-discover it from the workspace root. You must always run `bd` commands with the `-C .bare` flag:
    ```bash
    bd -C .bare show <issue-id>
    ```
2.  **Syncing Issues:** Before starting a task, always sync the latest issues from the remote to ensure you have the latest beads:
    ```bash
    bd -C .bare dolt pull
    ```
3.  **SSH Push Failures in Background Sessions (`Permission denied (publickey)`)**
    If you have a global Git configuration that rewrites HTTPS pushes to SSH (using `pushinsteadof`), background agent sessions (which lack access to active SSH agents/keys) will fail when running `bd dolt push` with a publickey permission error.

    Dolt executes Git operations in an isolated context and **does not read the local repository's `.bare/config`** override that unsets the rewrite.

    **The Solution (URL Alias Bypass):**
    Configure the Dolt remote to use the `www.github.com` domain instead of `github.com`. The global rewrite rule (which targets `https://github.com/` exactly) will not match, bypassing the rewrite, while Git's credential helper will still successfully authenticate against `www.github.com` over HTTPS:
    ```bash
    # Run this inside the embedded Dolt database directory:
    # .bare/.beads/embeddeddolt/sdk/
    dolt remote remove origin
    dolt remote add origin git+https://www.github.com/kevmoo/dart-sdk-bazel.git
    ```
    This permanently resolves the issue for this clone without requiring any global config modifications or environment hacks.

---

## 6. Architectural Migration Guidelines (Team & Agent Rules)

All agents operating in this workspace must strictly adhere to these additional guidelines derived from the architectural feedback of prior agents:

### Rule 3.1: Progressive Hybrid Migration (Bottom-Up)
Maintain parallel build graphs. Migrate bottom-up, starting with the leaves of the dependency graph (e.g., low-level third-party dependencies like `zlib` or utility libraries like `runtime/platform`). Never attempt a single global cutover or delete GN files.

### Rule 3.2: Strict Parallel Coexistence
Add `BUILD.bazel` files alongside `BUILD.gn` and keep both build graphs completely parallel. Never delete GN configurations until a component is fully validated in Bazel and approved by a human.

### Rule 3.3: Banned Host-Environment Access in Rules
Rules must not access the host environment implicitly. Never use `$(location)` to absolute host paths, read `$HOME` (or ambient user directories like pub cache), or run non-deterministic host commands (like `date` or `git`) inside actions. Use Bazel's stamping mechanism (`--stamp`, volatile/stable status files) for versioning.

### Rule 3.4: Mandate Equivalence Proofs in CLs
For every migrated target, the agent must perform a byte-diff (where deterministic, e.g., `.dill` files) or a behavior/test-diff of the Bazel output against the GN output, and record the comparison in the CL description.

### Rule 3.5: Strict Direct Dependency Declaration
Bazel enforces strict header checking. A target can only `#include` headers from targets declared explicitly in its direct `deps`. Agents must analyze C++ `#include` statements and declare direct dependencies explicitly. Relying on transitive dependencies is strictly prohibited.

### Rule 3.6: Windows Path Length and Runfiles Compliance
Keep target and package names short to avoid deep nested paths on Windows (MAX_PATH compliance). Any executable tool or test script that needs to locate data files must use the official Bazel runfiles lookup library rather than assuming relative filesystem paths.

### Rule 3.7: One Reviewable Unit Per CL
Limit each CL to a single library or a tight cluster of leaf libraries. Ensure it compiles on at least one primary platform (e.g., Linux/x64) and runs its unit tests before uploading.

### Rule 3.8: Parallel CI Lanes
A red Bazel CI lane must block the same as a red GN lane for migrated components.

### Rule 3.9: Mandatory Buildifier Linting and Formatting
Every `BUILD`, `WORKSPACE`, `MODULE.bazel`, and `.bzl` file created or modified by the agent must be formatted and linted using `buildifier --lint=fix --warnings=all` before submission.

### Rule 3.10: Keep Starlark Logic in `.bzl` Files
Do not write complex Starlark logic (loops, heavy conditionals) inside `BUILD.bazel` files. Put all macros, rules, and logic in `.bzl` files under `//build/bazel/...`. `BUILD` files should remain purely declarative data.

### Rule 3.11: Strict Case Sensitivity Compliance
Agents must ensure all paths in `srcs`, `hdrs`, and `#include` statements match the exact case on disk to prevent compilation failures on case-sensitive Linux builders.

### Rule 3.12: Default Private Visibility
Set `default_visibility = ["//visibility:private"]` in all packages, and explicitly open up visibility only when necessary using granular `package_group`s.

### Rule 3.13: Dart Format Symlink Compliance (Formatting in Sandbox)
`dart format` silently ignores symlinks when recursing directories. Because Bazel stages runfiles as symlinks in the sandbox, running `dart format <directory>` on a package directory in a Bazel test will silently pass without checking anything. 
*   **Requirement:** Any Bazel rule or macro that runs `dart format` must filter the package's sources and pass the file paths **explicitly** to the command line (e.g. `dart format --set-exit-if-changed file1.dart file2.dart`), which forces `dart format` to follow the symlinks.

### Rule 3.14: Package Config Staging Depth
The dynamically generated `package_config.json` (from `@dart_packages`) contains relative paths (`rootUri`) starting with `../../../`, assuming it is located 3 levels deep (at `tools/bazel/dart/package_config.json`).
*   **Requirement:** If a test or build rule stages this `package_config.json` to a different depth (e.g. `.dart_tool/package_config.json`, which is 1 level deep relative to the containing directory `.dart_tool/`), it must surgically adjust the relative paths (e.g. using `sed 's|../../../|../|g'`) so they resolve correctly in the sandbox.
