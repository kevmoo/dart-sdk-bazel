---
trigger: always_on
description: Mandatory Bazel migration, cross-platform compatibility, and resource safety rules.
---

# Bazel Migration & Cross-Platform Guidelines

When working with Bazel build files (`BUILD.bazel`, `.bzl`), Python tools, or Dart scripts, you MUST adhere to the following rules:

## 1. Hermeticity, Sandboxing & Runfiles

### Rule 1.1: Always write temporary/output files to `TEST_TMPDIR`
Never write files directly to hardcoded paths in the workspace or source directory during tests. In a sandboxed environment, writing outside the allocated temp directory causes sandbox write violations.

*   **Incorrect:**
    ```dart
    final outDir = 'out/dartfuzz';
    ```
*   **Correct:**
    ```dart
    final outDir = Platform.environment['TEST_TMPDIR'] ?? Directory.systemTemp.path;
    ```

### Rule 1.2: Resolve runfiles paths dynamically
Do not assume a hardcoded repository name or prefix (e.g., `_main/` or `external/`). Instead, resolve runfiles path prefixes dynamically using the build target context or relative paths.

*   **Incorrect:**
    ```python
    runfiles_path = "_main/{}".format(path)
    ```
*   **Correct:**
    ```python
    def runfiles_path(ctx, path):
        workspace = ctx.workspace_name or "main"
        # Resolve path using the dynamically retrieved workspace name
    ```

### Rule 1.3: Exclude generated files from globs to prevent cache invalidation
Do not include build output targets, temporary folders, or entire project roots in directory globs. Broad globs cause Bazel to invalidate action caches on minor changes.

*   **Incorrect:**
    ```starlark
    glob(["**"])
    ```
*   **Correct:**
    ```starlark
    glob(["**"], exclude = ["BUILD", "BUILD.bazel", "temp/**"])
    ```

### Rule 1.4: Include all runtime dependencies in runfiles
Ensure target executables run hermetically by listing all necessary dependencies (such as compiler output, SDK binaries, or `platform.dill`) in the rule's `data` or `runfiles` attribute.

---

## 2. Cross-Platform & Path Separator Safety

### Rule 2.1: Normalize path separators before performing string prefix or inclusion checks
Windows hosts use backslashes (`\`) for file paths. Hardcoded forward-slash comparisons fail on Windows. Use `package:path` or replace backslashes before running substring checks.

*   **Incorrect:**
    ```dart
    final isMetaTest = pkgDir.contains('pkg/analyzer/');
    ```
*   **Correct:**
    ```dart
    final normalizedPkgDir = pkgDir.replaceAll('\\', '/');
    final isMetaTest = normalizedPkgDir.contains('pkg/analyzer/');
    ```

### Rule 2.2: Do not use `File.existsSync()` to check directory paths
Using `File.existsSync()` on directory paths can fail or return false negatives on Windows. Use `FileSystemEntity.typeSync` to verify existence and entity type.

*   **Incorrect:**
    ```dart
    if (File(outputPath).existsSync()) { ... }
    ```
*   **Correct:**
    ```dart
    if (FileSystemEntity.typeSync(outputPath) != FileSystemEntityType.notFound) { ... }
    ```

### Rule 2.3: Avoid `os.path.normpath` for internal archive layout validation
Using `os.path.normpath` on Windows converts forward slashes to backslashes, which breaks comparisons against standard tar/zip internal structures that consistently use forward slashes. Normalize paths by replacing backslashes with forward slashes instead.

*   **Incorrect:**
    ```python
    path = os.path.normpath(archive_path)
    ```
*   **Correct:**
    ```python
    path = archive_path.replace('\\', '/')
    ```

### Rule 2.4: Prohibit spawning Unix-only shell commands in BUILD files
Never invoke Unix commands (`sed`, `dirname`, `cat`, `rm`) in Bazel `genrule`s. Use Python scripts, Starlark rules, or Dart scripts to maintain Windows host compatibility.

---

## 3. Process & Resource Management

### Rule 3.1: Wrap process spawns in `try-finally` blocks to prevent leaks
Always wrap process spawning and lifecycle operations in `try-finally` blocks to ensure processes are terminated, and files/sockets are closed even when exceptions occur.

*   **Incorrect:**
    ```dart
    final process = await Process.start(...);
    await process.exitCode;
    ```
*   **Correct:**
    ```dart
    Process? process;
    try {
      process = await Process.start(...);
      await process.exitCode;
    } finally {
      process?.kill();
    }
    ```

### Rule 3.2: Asynchronously drain stdout and stderr streams
Ensure that both `stdout` and `stderr` streams of spawned processes are actively consumed (e.g., by forwarding, draining, or converting to strings). Failing to drain them can saturate OS pipe buffers, causing processes and CI runs to hang indefinitely.

### Rule 3.3: Use asynchronous streaming APIs for reading large files
Do not read large files (such as Build Event Protocol files or build outputs) into memory at once. Use streaming splitters to process them line-by-line to avoid Out-of-Memory (OOM) errors.

*   **Incorrect:**
    ```dart
    final lines = File(bepPath).readAsLinesSync();
    for (final line in lines) { ... }
    ```
*   **Correct:**
    ```dart
    final file = File(bepPath);
    final linesStream = file.openRead().transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in linesStream) { ... }
    ```

### Rule 3.4: Avoid spawning subprocesses for simple operations in repository rules
Do not call system commands (like `cp` or `mkdir`) from within Starlark repository rules. Use built-in Starlark functions like `repository_ctx.read` and `repository_ctx.write` to avoid execution overhead and cross-platform issues.

---

## 4. Starlark & Build Macro Design

### Rule 4.1: Handle Starlark collection parameters defensively
Starlark macro inputs can be `None` or of unexpected types. Explicitly convert parameters that should be lists to a list, and provide empty defaults before appending or modifying.

*   **Incorrect:**
    ```starlark
    tags = tags + ["manual"]
    ```
*   **Correct:**
    ```starlark
    tags = list(tags or []) + ["manual"]
    ```

### Rule 4.2: Quote variables in generated shell scripts
When generating scripts dynamically, wrap file and directory path variables in double quotes to prevent shell word splitting if the workspace paths contain spaces.

*   **Incorrect:**
    ```bash
    for src in $SRCS; do
    ```
*   **Correct:**
    ```bash
    for src in "$SRCS"; do
    ```

---

## 5. API Usage & Performance Optimization

### Rule 5.1: Create mutable copies of unmodifiable lists before modifying them
Modifying read-only lists (such as `Platform.executableArguments`) will throw a runtime error. Copy the list into a mutable `List` before executing modifications.

*   **Incorrect:**
    ```dart
    final args = rawArgs;
    args.insert(0, '--flag');
    ```
*   **Correct:**
    ```dart
    final args = List<String>.from(rawArgs);
    args.insert(0, '--flag');
    ```

### Rule 5.2: Cache compiled regular expressions
Do not compile standard `RegExp` objects inside loops. Compile and cache them outside the loop or use a lookup map.

*   **Incorrect:**
    ```dart
    bool matches(String pattern, String value) => RegExp(pattern).hasMatch(value);
    ```
*   **Correct:**
    ```dart
    final _patternCache = <String, RegExp>{};
    bool matches(String pattern, String value) {
      final regex = _patternCache.putIfAbsent(pattern, () => RegExp(pattern));
      return regex.hasMatch(value);
    }
    ```

### Rule 5.3: Avoid O(N^2) log file parsing
When polling a growing log file, maintain a stateful file pointer or offset. Only read new bytes appended since the last read rather than parsing the entire file from byte zero.

### Rule 5.4: Adhere to package import visibility
Do not import implementation details (files within the `src/` directory) from other packages, as this violates the `implementation_imports` lint rule. Refactor dependencies to use public API surface.
