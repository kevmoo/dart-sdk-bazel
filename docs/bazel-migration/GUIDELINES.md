# Bazel Architectural Migration Guidelines

All human engineers and AI agents operating on the Bazel thread (`bazel`) MUST strictly adhere to these architectural guidelines derived from continuous integration and build engineering experience.

---

## Part 1: 🏗️ Core Architectural Rules

### Rule 3.1: Progressive Hybrid Migration (Bottom-Up)
Maintain parallel build graphs. Migrate bottom-up, starting with the leaves of the dependency graph (e.g., low-level third-party dependencies like `zlib` or utility libraries like `runtime/platform`). Never attempt a single global cutover or delete GN files.

### Rule 3.2: Strict Parallel Coexistence
Add `BUILD.bazel` files alongside `BUILD.gn` and keep both build graphs completely parallel. Never delete GN configurations until a component is fully validated in Bazel and approved by a human.

### Rule 3.3: Banned Host-Environment Access in Rules
Rules must not access the host environment implicitly. Never use `$(location)` to absolute host paths, read `$HOME` (or ambient user directories like pub cache), or run non-deterministic host commands (like `date` or `git`) inside actions. Use Bazel's stamping mechanism (`--stamp`, volatile/stable status files) for versioning.

### Rule 3.4: Mandate Equivalence Proofs in CLs / PRs
For every migrated target, perform a byte-diff (where deterministic, e.g., `.dill` files) or a behavior/test-diff of the Bazel output against the GN output, and record the comparison in the PR description.

### Rule 3.5: Strict Direct Dependency Declaration
Bazel enforces strict header checking. A target can only `#include` headers from targets declared explicitly in its direct `deps`. Analyze C++ `#include` statements and declare direct dependencies explicitly. Relying on transitive dependencies is strictly prohibited.

### Rule 3.6: Windows Path Length and Runfiles Compliance
Keep target and package names short to avoid deep nested paths on Windows (`MAX_PATH` compliance). Any executable tool or test script that needs to locate data files must use the official Bazel runfiles lookup library rather than assuming relative filesystem paths.

### Rule 3.7: One Reviewable Unit Per PR
Limit each PR to a single library or a tight cluster of leaf libraries. Ensure it compiles on at least one primary platform (e.g., Linux/x64) and runs its unit tests before uploading.

### Rule 3.8: Parallel CI Lanes
A red Bazel CI lane must block the same as a red GN lane for migrated components.

### Rule 3.9: Mandatory Buildifier Linting and Formatting
Every `BUILD`, `WORKSPACE`, `MODULE.bazel`, and `.bzl` file created or modified must be formatted and linted using `buildifier --lint=fix --warnings=all` before submission.

### Rule 3.10: Keep Starlark Logic in `.bzl` Files
Do not write complex Starlark logic (loops, heavy conditionals) inside `BUILD.bazel` files. Put all macros, rules, and logic in `.bzl` files under `//build/bazel/...`. `BUILD` files should remain purely declarative data.

### Rule 3.11: Strict Case Sensitivity Compliance
Ensure all paths in `srcs`, `hdrs`, and `#include` statements match the exact case on disk to prevent compilation failures on case-sensitive Linux builders.

### Rule 3.12: Default Private Visibility
Set `default_visibility = ["//visibility:private"]` in all packages, and explicitly open up visibility only when necessary using granular `package_group`s.

### Rule 3.14: Universal Determinism and Hermetic Timestamps
Never allow C++ builds to depend on non-deterministic host paths or build timestamps. All wrappers must inject `-Wno-builtin-macro-redefined`, `-D__DATE__=""`, and `-D__TIME__=""`. Never invoke ambient host commands (`git`, `date`) inside build action `cmd` strings.

## Part 2: 🛠️ Code-Level Patterns (Pre-Flight Checklist)

### 1. Windows Path Compatibility

#### Normalize Path Separators Before Matching
* **Rule**: Always normalize path separators (`\` to `/`) before running suffix (`.endsWith`), prefix (`.startsWith`), or equality checks on file paths.
* **Why**: On Windows, paths use backslashes (`\`). If your logic expects forward slashes (`/`) for directory boundaries (e.g. matching `out/ReleaseX64/dart`), it will fail on Windows when backslashes are present.
* **Avoid**:
  ```dart
  if (executable.endsWith('/dart') || executable.startsWith('pkg/vm/')) {
    // Fails on Windows if executable is "pkg\vm\tool\gen_kernel"
  }
  ```
* **Prefer**:
  ```dart
  final normalizedExe = executable.replaceAll('\\', '/');
  if (normalizedExe.endsWith('/dart') || normalizedExe.startsWith('pkg/vm/')) {
    // Works reliably across all platforms
  }
  ```

#### Append Executable File Extensions (`.exe`)
* **Rule**: Append `.exe` to binary and executable names when running on Windows.
* **Why**: Windows requires the `.exe` extension to execute binaries. Dynamically built paths (like `dartaotruntime` or `gen_snapshot`) will fail to run with "file not found" errors unless `.exe` is appended.
* **Avoid**:
  ```dart
  executable = '$sdkBinDir/dartaotruntime';
  ```
* **Prefer**:
  ```dart
  final exeExt = Platform.isWindows ? '.exe' : '';
  executable = p.join(sdkBinDir, 'dartaotruntime$exeExt');
  ```

#### Use Path Package for Parent Directory Calculations
* **Rule**: Use `p.dirname` from `package:path` instead of `File.parent.path` to calculate the parent directory of a path string.
* **Why**: If a path is relative and has no directory separators (e.g. `dart`), `File(path).parent.path` returns an empty string `""` which breaks downstream path joining. `p.dirname(path)` correctly returns `"."`.
* **Avoid**:
  ```dart
  final sdkBinDir = File(dartBinEnv).parent.path; // Can return "" if relative
  executable = '$sdkBinDir/dartaotruntime';
  ```
* **Prefer**:
  ```dart
  final sdkBinDir = p.dirname(dartBinEnv); // Safely returns "." or directory path
  executable = p.join(sdkBinDir, 'dartaotruntime$exeExt');
  ```

#### Safe Junction and Symbolic Link Cleanup in Python
* **Rule**: When cleaning up directories and links in Python scripts (within repository extensions), use a try-except cascade starting with `os.unlink`, falling back to `os.rmdir`, and ending with `shutil.rmtree`.
* **Why**: On Windows, `shutil.rmtree` or standard `os.remove` can raise permission errors on directory junctions or symbolic links. You must also check for links using `os.lexists` instead of `os.path.exists` so that broken symlinks are detected and removed.
* **Avoid**:
  ```python
  if os.path.exists(dst):
      if os.path.isdir(dst):
          shutil.rmtree(dst)
      else:
          os.remove(dst)
  ```
* **Prefer**:
  ```python
  if os.path.lexists(dst):
      try:
          os.unlink(dst)
      except OSError:
          try:
              os.rmdir(dst)
          except OSError:
              shutil.rmtree(dst)
  ```

---

### 2. Bazel Sandbox & Runfiles

#### Use `copy_file` over Shell `cp` in Genrules
* **Rule**: Never use non-hermetic host shell commands (`cp`, `mv`) inside `genrule` definitions for file staging. Always import and use `copy_file` from `@bazel_skylib//rules:copy_file.bzl`.
* **Why**: Host shell commands are non-hermetic and break build isolation. (Complex multi-line assembly generation scripts are exempt when explicitly tagged with `# exempt-genrule: ok`).
* **Avoid**:
  ```python
  genrule(
      name = "copy_foo",
      srcs = ["foo.txt"],
      outs = ["bar.txt"],
      cmd = "cp $< $@",
  )
  ```
* **Prefer**:
  ```python
  load("@bazel_skylib//rules:copy_file.bzl", "copy_file")
  
  copy_file(
      name = "copy_foo",
      src = "foo.txt",
      out = "bar.txt",
  )
  ```

#### Avoid Copying Directories in Repository Rules
* **Rule**: Use `ctx.symlink` rather than copying entire directories (`lib/`, `bin/`, etc.) in custom repository rules.
* **Why**: Copying directories hides individual file modifications from Bazel's input tracker, breaking incremental builds. Modifying a file inside a copied directory won't trigger rebuilds/test runs. Symlinking ensures Bazel can track all underlying files correctly.
* **Avoid**:
  ```python
  _copy_path(ctx, physical_lib, virtual_pkg_dir + "/lib") # Spawns "cp -r"
  ```
* **Prefer**:
  ```python
  ctx.symlink(physical_lib, virtual_pkg_dir + "/lib") # Preserves incremental tracking
  ```

#### Copy Single Files Using Hermetic In-Process Starlark Writing
* **Rule**: For single files, copy them using Starlark's `ctx.read` and `ctx.file` rather than spawning external copy commands (`cp`, `cp -RL`). If a host copy is absolutely unavoidable, tag the execution block with `# exempt-starlark-copy: ok`.
* **Why**: Spawning external shell subprocesses (`ctx.execute(["cp", ...])`) is slow, non-hermetic, and increases repo rule overhead. In-process Starlark writing is fully hermetic and highly performant.
* **Avoid**:
  ```python
  ctx.execute(["cp", str(src), dst])
  ```
* **Prefer**:
  ```python
  ctx.file(dst, ctx.read(src))
  ```

#### Bypass Runfiles Resolution for Absolute Paths
* **Rule**: Skip `_Runfiles.resolve` calls if a path is already absolute.
* **Why**: Attempting to resolve an absolute path (e.g. `C:\path\to\file`) through runfiles resolution can prepend the runfiles directory, producing invalid paths (like `/runfiles/dir/C:\path\to\file`).
* **Avoid**:
  ```dart
  final resolvedScript = _Runfiles.resolve(scriptPath);
  ```
* **Prefer**:
  ```dart
  final resolvedScript = p.isAbsolute(scriptPath)
      ? scriptPath
      : _Runfiles.resolve(runfilesScriptPath);
  ```

#### Support Workspace and External Repository Prefix Layouts
* **Rule**: Check script paths for standard runfiles repository prefixes (`_main/`, `external/`, `@`) before prepending the default `_main/` workspace prefix.
* **Why**: Scripts might be referenced differently depending on whether they come from the main repository or an external repository (e.g., `co19` tests under `external/`). Prepending `_main/` indiscriminately breaks resolution for external scripts.
* **Avoid**:
  ```dart
  final runfilesScriptPath = '_main/$scriptPath';
  ```
* **Prefer**:
  ```dart
  final normalizedScript = scriptPath.replaceAll('\\', '/');
  final runfilesScriptPath =
      (normalizedScript.startsWith('_main/') ||
          normalizedScript.startsWith('@') ||
          normalizedScript.startsWith('external/') ||
          p.isAbsolute(normalizedScript))
      ? normalizedScript
      : '_main/$normalizedScript';
  ```

---

### 3. Environment & Staging Configurations

#### Use `DART_PACKAGE_CONFIG` Instead of Sandbox Copying
* **Rule**: Export the `DART_PACKAGE_CONFIG` environment variable in test wrapper scripts instead of attempting to copy and patch `package_config.json` inside the sandbox.
* **Why**: Bazel sandboxes are read-only. Attempting to copy `package_config.json` to a staging folder and patching it with `sed` inside the shell wrapper will fail with permission errors. The Dart VM natively reads `DART_PACKAGE_CONFIG` directly.
* **Avoid**:
  ```bash
  STAGING_DIR=$(dirname "$PKG_CONFIG")
  mkdir -p "$STAGING_DIR/tools/bazel/dart"
  cp "$PKG_CONFIG" "$STAGING_DIR/tools/bazel/dart/package_config.json"
  # Patch file...
  DART_PACKAGES_FLAG="--packages=$STAGING_DIR/tools/bazel/dart/package_config.json"
  exec "$DART_BIN" $DART_PACKAGES_FLAG "$RUNNER_DART" "$@"
  ```
* **Prefer**:
  ```bash
  export DART_PACKAGE_CONFIG="$PKG_CONFIG"
  exec "$DART_BIN" "$RUNNER_DART" "$@"
  ```

---

### 4. Dart Robustness & Argument Parsing

#### Support Space-Separated and Equals-Separated Arguments
* **Rule**: When parsing or rewriting CLI flags (like `--packages`), handle both space-separated (`--packages <path>`) and equals-separated (`--packages=<path>`) arguments.
* **Why**: Dart VM options allow both formats. If your parser only searches for `--packages=`, it will miss space-separated configs, leading to duplicate package flags which cause Dart VM execution crashes.
* **Avoid**:
  ```dart
  final packagesIndex = arguments.indexWhere((arg) => arg.startsWith('--packages='));
  if (packagesIndex != -1) {
    arguments[packagesIndex] = '--packages=$resolvedPkg';
  } else {
    arguments.insert(scriptIndex, '--packages=$resolvedPkg');
  }
  ```
* **Prefer**:
  ```dart
  final packagesIndex = arguments.indexWhere((arg) => arg.startsWith('--packages='));
  if (packagesIndex != -1) {
    arguments[packagesIndex] = '--packages=$resolvedPkg';
  } else {
    final pkgIndex = arguments.indexOf('--packages');
    if (pkgIndex != -1 && pkgIndex + 1 < arguments.length) {
      arguments[pkgIndex + 1] = resolvedPkg;
    } else {
      arguments.insert(scriptIndex, '--packages=$resolvedPkg');
    }
  }
  ```

#### VM Options Must Precede Script Paths
* **Rule**: Insert any dynamic script or snapshot path *after* leading VM options (arguments starting with `-`).
* **Why**: The Dart VM expects option flags to come before the script name. If you insert a script path at index 0, the options that follow will be treated as arguments passed *to the script* instead of VM configurations, breaking execution.
* **Avoid**:
  ```dart
  actualArgs.insert(0, ddcPath);
  ```
* **Prefer**:
  ```dart
  final insertIndex = actualArgs.indexWhere((arg) => !arg.startsWith('-'));
  if (insertIndex != -1) {
    actualArgs.insert(insertIndex, ddcPath);
  } else {
    actualArgs.add(ddcPath);
  }
  ```

#### Leverage Flow-Analysis Type Promotion
* **Rule**: Use local final variables when working with nullable values. Do not use redundant null assertion operators (`!`) inside blocks guarded by null checks.
* **Why**: Dart's flow analysis automatically promotes a local final variable from a nullable type (e.g. `String?`) to non-nullable (e.g. `String`) after a null check. Adding redundant `!` assertions makes code harder to read and violates style guidelines.
* **Avoid**:
  ```dart
  String? dartBinEnv = Platform.environment['DART_BIN'];
  if (dartBinEnv != null) {
    final sdkBinDir = File(dartBinEnv!).parent.path; // Redundant !
  }
  ```
* **Prefer**:
  ```dart
  final dartBinEnv = Platform.environment['DART_BIN'];
  if (dartBinEnv != null) {
    final sdkBinDir = p.dirname(dartBinEnv); // Automatically promoted to String
  }
  ```

---

### 5. Starlark Code Quality

#### Clean Up Unused Declarations
* **Rule**: Remove all unused variables, constants, and helper functions in Starlark files (`.bzl`).
* **Why**: Leaving unused helper methods (such as obsolete directory copy functions after moving to symlinking) violates Buildifier lint rules and blocks presubmission.
* **Avoid**:
  ```python
  def _copy_path(ctx, src, dst):
      # Obsolete function left behind after refactoring
      ...
  ```
* **Prefer**: Delete the unused helper function entirely.

---

### 6. Minimizing Upstream Changes

#### Avoid Modifying Shared Upstream Files
* **Rule**: Try not to touch existing upstream code, tests, or configurations outside the `tools/bazel/` directory unless absolutely necessary.
* **Why**: The Bazel migration should serve as a clean replacement for GN, without polluting the core SDK codebase. Modifying shared files (like SDK language tests or global status files) increases merge friction with upstream and risk of regressions in non-Bazel workflows.
* **Exceptions**:
  - Bug fixes to the test runner dumper (`pkg/test_runner/lib/src/test_configurations.dart`) or other shared tools are acceptable if they resolve general correctness issues, but they should be kept minimal and generic.
  - Adding expectations to `language_vm.status` is acceptable for genuine compiler bugs if quarantining the whole file would drastically reduce test coverage (e.g. for multitests).
* **Alternatives**: Prefer using `tools/bazel/dart/suite_config.json` (e.g., `quarantine_patterns`, `extra_deps_by_pattern`) or modifying the Bazel-specific runner (`run_single_test.dart`) to handle Bazel-specific constraints.

---

### 7. Bazel Query

#### Regex Matching on List Attributes
* **Rule**: When filtering list attributes (such as `tags`) using `attr()` in `bazel query`, use list-aware boundary patterns instead of exact anchors or word boundaries.
* **Why**: The regular expression is matched against the **string representation of the entire list** (e.g., `[manual, quarantine]`), not against individual elements. Exact anchors like `^manual$` will fail to match. Word boundaries like `\b` can match hyphens.
* **Avoid**:
  ```bash
  bazel query 'attr(tags, "^manual$", //...)'
  bazel query 'attr(tags, "\bmanual\b", //...)'
  ```
* **Prefer**:
  ```bash
  bazel query 'attr(tags, "(\\[|, )manual(, |\\])", //...)'
  ```



---

## Part 3: ⚡ Developer Performance Tips

### RAM-Backed Bazel Output Base (`tmpfs` / `/dev/shm`)
To accelerate local symlink creation, file writes, and deletion during heavy test runs on Linux developer workstations (by up to ~5x), you can configure Bazel to store its temporary output base in system RAM (`tmpfs`):

Add the following to your personal `user.bazelrc` or run commands:
```ini
# Store Bazel's output base in RAM (/dev/shm) for ~5x faster symlink operations
startup --output_base=/dev/shm/bazel_out_${USER}
```
*Note: Ensure your workstation has at least 16GB of available RAM before enabling this setting.*

