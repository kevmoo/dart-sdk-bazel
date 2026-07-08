# CHECK BEFORE YOU SUBMIT

This pre-flight checklist details coding standards, guidelines, and rules compiled from bugs and code reviews encountered during the development of the Bazel test runners and matrix execution. 

Follow this checklist strictly before submitting changes to the repository.

---

## 1. Windows Path Compatibility

### Normalize Path Separators Before Matching
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

### Append Executable File Extensions (`.exe`)
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

### Use Path Package for Parent Directory Calculations
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

### Safe Junction and Symbolic Link Cleanup in Python
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

## 2. Bazel Sandbox & Runfiles

### Avoid Copying Directories in Repository Rules
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

### Copy Single Files Using Hermetic In-Process Starlark Writing
* **Rule**: For single files, copy them using Starlark's `ctx.read` and `ctx.file` rather than spawning external copy commands (`cp`, `cp -RL`).
* **Why**: Spawning external shell subprocesses (`ctx.execute(["cp", ...])`) is slow, non-hermetic, and increases repo rule overhead. In-process Starlark writing is fully hermetic and highly performant.
* **Avoid**:
  ```python
  ctx.execute(["cp", str(src), dst])
  ```
* **Prefer**:
  ```python
  ctx.file(dst, ctx.read(src))
  ```

### Bypass Runfiles Resolution for Absolute Paths
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

### Support Workspace and External Repository Prefix Layouts
* **Rule**: Check script paths for standard runfiles repository prefixes (`_main/`, `external/`, `@`) before prepending the default `_main/` workspace prefix.
* **Why**: Scripts might be referenced differently depending on whether they come from the main repository or an external repository (e.g., `co19` tests under `external/`). Prepending `_main/` indiscriminately breaks resolution for external scripts.
* **Avoid**:
  ```dart
  final runfilesScriptPath = '_main/$scriptPath';
  ```
* **Prefer**:
  ```dart
  final runfilesScriptPath =
      (normalizedScript.startsWith('_main/') ||
          normalizedScript.startsWith('@') ||
          normalizedScript.startsWith('external/') ||
          p.isAbsolute(scriptPath))
      ? scriptPath
      : '_main/$scriptPath';
  ```

---

## 3. Environment & Staging Configurations

### Use `DART_PACKAGE_CONFIG` Instead of Sandbox Copying
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

## 4. Dart Robustness & Argument Parsing

### Support Space-Separated and Equals-Separated Arguments
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

### VM Options Must Precede Script Paths
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

### Leverage Flow-Analysis Type Promotion
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

## 5. Starlark Code Quality

### Clean Up Unused Declarations
* **Rule**: Remove all unused variables, constants, and helper functions in Starlark files (`.bzl`).
* **Why**: Leaving unused helper methods (such as obsolete directory copy functions after moving to symlinking) violates Buildifier lint rules and blocks presubmission.
* **Avoid**:
  ```python
  def _copy_path(ctx, src, dst):
      # Obsolete function left behind after refactoring
      ...
  ```
* **Prefer**: Delete the unused helper function entirely.
