---
name: bazel_bridge
description: Import, test, and export upstream Gerrit CLs or GitHub PRs in the Bazel workspace.
---

# Bazel Bridge Workflow Skill

Use this skill to import, test, and export upstream changes (Gerrit CLs or GitHub PRs) using the Bazel developer bridge tools. This workflow allows developers and agents to test upstream patches in the hermetic Bazel build environment and export the validated non-Bazel core SDK changes back to an upstream-ready branch.

## When to Use This Skill

- When you need to test an upstream Gerrit CL or GitHub PR in the Bazel workspace.
- When you are tasked with triaging, building, or fixing an upstream change under Bazel.
- When you have made and validated changes in a Bazel branch and need to export those changes back to a clean branch for upstream submission (Gerrit/GitHub).

## The Tools

The bridge workflow uses two main Dart scripts located in the repository:
1. **`tools/bazel/bridge/import.dart`**: For importing and applying upstream changes to a new Bazel branch.
2. **`tools/bazel/bridge/export.dart`**: For extracting, filtering, and exporting core SDK changes back to a clean branch.

---

## 1. Importing an Upstream Change

To import an upstream Gerrit CL or GitHub PR into the local Bazel workspace, run the `import.dart` script:

```bash
dart tools/bazel/bridge/import.dart <cl-number-or-pr-url> [options]
```

### Supported Change Identifiers
- **Gerrit CL Number**: e.g., `505900`
- **Gerrit URL**: e.g., `https://dart-review.googlesource.com/c/sdk/+/505900`
- **Gerrit URL with Patchset**: e.g., `https://dart-review.googlesource.com/c/sdk/+/505900/1`
- **GitHub PR URL**: e.g., `https://github.com/dart-lang/sdk/pull/123`

### Common Options
- `-b, --base <branch>`: The base branch to branch off. Defaults to `bazel-fork/main`.
- `-n, --name <name>`: An explicit name for the created branch. If omitted, a default name like `gerrit-<cl-number>` or `github-pr-<pr-number>` is used.
- `-p, --patchset <number>`: A specific Gerrit patchset to import. If omitted, the script automatically queries the Gerrit API to find and use the latest patchset.
- `--no-sync`: Skip running `gclient sync` after importing. By default, the script will run `gclient sync` to align all dependencies.
- `-v, --verbose`: Enable verbose logging to see the underlying git commands.

### How the Import Pipeline Works
1. **Sanity Check**: Verifies that the local git working directory is clean.
2. **Ref Resolution**: Resolves the target git ref (e.g., `refs/changes/...` for Gerrit or `refs/pull/.../head` for GitHub).
3. **Branch Creation**: Creates and checks out a new local feature branch starting from the base branch (default: `bazel-fork/main`).
4. **Fetch & Apply**: Fetches the remote ref and cherry-picks the commits onto the new branch.
5. **BUILD.gn Warning**: Scans the applied changes. If any `BUILD.gn` or `.gni` files were modified, it warns you that you may need to run the translator (`tools/bazel/translate_gn_desc.py`) to update the Bazel build files.
6. **Dependency Sync**: Runs `gclient sync` to align the workspace.

### Handling Cherry-Pick Conflicts
If the cherry-pick/apply step fails due to conflicts:
1. The script will exit with code `2`, leaving you on the new feature branch in the middle of a cherry-pick.
2. **Do not panic!** Manually inspect and resolve the conflicts in the affected files.
3. Add the resolved files: `git add <file>`
4. Continue the cherry-pick: `git cherry-pick --continue`
5. Alternatively, abort the import entirely: `git cherry-pick --abort`

---

## 2. Testing and Validating the Import

Once the change is imported and any conflicts or build-file translation issues are resolved:

1. **Verify the Build**:
   - Build the Dart VM:
     ```bash
     bazel build //runtime/bin:dartvm
     ```
   - Or build the full SDK:
     ```bash
     bazel build //sdk:create_sdk
     ```

2. **Run the Test Suite**:
   Use the standard test runner with the `--bazel` flag. Be sure to target the correct architecture (e.g., `arm64` if on Apple Silicon, or `x64` if on Intel/Linux):
   ```bash
   python3 tools/test.py --bazel -n vm-release-arm64 <path-to-test>
   ```
   *Example:*
   ```bash
   python3 tools/test.py --bazel -n vm-release-arm64 corelib/list_test
   ```

3. **Debug Failures**: Fix any issues found in the core SDK or Bazel configuration. Feel free to make multiple commits on your feature branch as you work.

---

## 3. Exporting the Validated Changes

Once the changes are fully validated and ready to be submitted back to the upstream Core SDK, use the `export.dart` script to surgically extract and package the core changes, leaving all Bazel-specific files behind:

```bash
dart tools/bazel/bridge/export.dart [options]
```

### How the Export Pipeline Works
1. **Sanity Check**: Verifies that the local git working directory is clean.
2. **Generate Filtered Patch**: Automatically runs `git format-patch` for all commits on the current branch since the base branch (default: `bazel-fork/main`), or for a single specific commit.
3. **Surgical Exclusion**: During patch generation, the script excludes all Bazel-specific files:
   - `tools/bazel/` (Bazel-specific tools and the bridge itself)
   - `*.bzl` (Starlark rules)
   - `BUILD.bazel` / `BUILD` (Bazel build files)
   - `WORKSPACE` / `WORKSPACE.bazel` / `MODULE.bazel` (Workspace configs)
   - `.bazelrc` (Bazel configuration)
   Any commits that only modified these files are automatically and silently dropped, ensuring the exported history is completely clean and contains only Core SDK modifications.
4. **Target Branch Creation**: Creates a new, clean branch starting directly from the Core SDK base branch (default: `origin/main`). The branch is named `export-<timestamp>` or a custom name if specified.
5. **Apply Patches**: Applies the filtered patches onto the new branch using `git am`. This reconstructs the commit history, preserving the original author, date, and commit messages.
6. **Upload to Gerrit**: If the `--upload` flag is provided, the script automatically runs `git cl upload`, allowing you to upload the clean CL directly to the Gerrit code review system.

### Common Options
- `-b, --base <branch>`: The Bazel base branch to compare the current branch against. Defaults to `bazel-fork/main`.
- `-c, --commit <hash>`: Export only a single specific commit instead of the entire branch history.
- `--target-base <branch>`: The Core SDK base branch to branch off of for the export. Defaults to `origin/main`.
- `-n, --name <name>`: Custom name for the newly created export branch.
- `-u, --upload`: Automatically run `git cl upload` after a successful export.
- `-v, --verbose`: Enable verbose logging to see the details of the patch generation and application.

### Handling Export Conflicts (`git am` failures)
If `git am` fails to apply the patch due to conflicts:
1. The script will exit with an error, leaving the repository in the middle of an `am` session.
2. **To continue**: Resolve the conflicts in the files, stage them (`git add <file>`), and run `git am --continue`.
3. **To abort**: Run `git am --abort` and switch back to your original development branch:
   ```bash
   git checkout <your-dev-branch>
   ```
