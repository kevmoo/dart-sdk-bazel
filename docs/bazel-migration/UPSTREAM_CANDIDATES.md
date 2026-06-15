# Non-Bazel Upstream Candidate Changes

This document lists candidate changes identified in the `bazel` branch that are bug fixes, performance improvements, or test robustness enhancements. These changes do not depend on Bazel and should be upstreamed to the `main` branch.

For outstanding, unresolved SDK-internal issues and architectural debt surfaced by the migration, see the [todo_issues/](todo_issues/README.md) tracker.

## Candidates List

### 1. VM Compiler: Avoid reading obfuscation metadata when obfuscation is disabled
- **File**: [kernel_translation_helper.cc](file:///usr/local/google/home/kevmoo/github/sdk/runtime/vm/compiler/frontend/kernel_translation_helper.cc#L1967-L1972)
- **Change**: In `ObfuscationProhibitionsMetadataHelper::ReadMetadata`, check if obfuscation is enabled in the isolate group; if not, return early.
- **Why upstream**: Avoids unnecessary work parsing obfuscation metadata in non-obfuscated builds (both JIT and normal AOT).
- **Diff**:
  ```cpp
  void ObfuscationProhibitionsMetadataHelper::ReadMetadata(intptr_t node_offset) {
+   if (!Thread::Current()->isolate_group()->obfuscate()) {
+     return;
+   }
    intptr_t md_offset = GetNextMetadataPayloadOffset(node_offset);
  ```

### 2. dart2wasm: Covariance check optimization / bug fix
- **File**: [types.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/dart2wasm/lib/types.dart#L542-L547)
- **Change**: Use `objectNullableRawType` as the operand type if `isCovarianceCheck` is true during type check helper resolution.
- **Why upstream**: Improves compiler type check resolution logic for covariance checks.
- **Diff**:
  ```dart
      final (typeToCheck, :checkArguments) = asCheckers.canUseTypeCheckHelper(
        testedAgainstType,
-       operandType,
+       isCovarianceCheck
+           ? translator.coreTypes.objectNullableRawType
+           : operandType,
      );
  ```

### 3. Test: Robust path resolution in `verbose_gc_to_bmu_test.dart`
- **File**: [verbose_gc_to_bmu_test.dart](file:///usr/local/google/home/kevmoo/github/sdk/tests/standalone/verbose_gc_to_bmu_test.dart#L15-L20)
- **Change**: Resolve the tool script relative to `Platform.script` (the test file path) rather than `Platform.executable` (the SDK VM binary path). Also declare `verbose_gc_to_bmu.dart` in `OtherResources`.
- **Why upstream**: Makes the test runnable under different execution environments (such as sandboxed environments or when the VM is executed from a path other than the SDK root).
- **Diff**:
  ```dart
- var toolScript = Uri.parse(
-   Platform.executable,
- ).resolve("../../runtime/tools/verbose_gc_to_bmu.dart").toFilePath();
+ var toolScript = Platform.script
+     .resolve("../../runtime/tools/verbose_gc_to_bmu.dart")
+     .toFilePath();
  ```

### 4. Version Tooling: Decoupling git checks and path assumptions in version scripts
- **Files**: [make_version.py](file:///usr/local/google/home/kevmoo/github/sdk/tools/make_version.py) and [utils.py](file:///usr/local/google/home/kevmoo/github/sdk/tools/utils.py)
- **Change**: Support explicit parameter injection for `--dart-dir`, `--git-hash`, and `--snapshot-files` in `make_version.py` and support `repo_path=None` (falling back to `DART_DIR`) in helper functions in `utils.py`.
- **Why upstream**: Essential for hermetic builds (like Bazel, but also useful for custom offline build wrapper tools) where `.git` may not be present or files are staged in custom directories.

### 5. CFE Tooling: Dynamic Package Config Resolution in entry_points.dart
- **File**: [entry_points.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/front_end/tool/entry_points.dart#L567-L575)
- **Change**: Read `Platform.packageConfig` in `computeHostDependencies` and pass it to `getDependencies`.
- **Why upstream**: Ensures host dependencies are resolved using the actual packages configuration file in use, rather than assuming standard layout.

### 6. Test Runner: Metadata Dumping Optimization
- **Bead**: `sdk-65j`
- **File**: [test_runner.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/test_runner/bin/test_runner.dart#L38-L46)
- **Change**: Check if the test runner is only invoked for metadata dumping (`--dump-test-metadata`); if so, skip `buildConfigurations`.
- **Why upstream**: Eliminates unnecessary Bazel/Ninja target build checks when CI or external IDE tools only need to dump test metadata.

### 7. Standalone IO Tests: Sandboxed Runfiles Resource Declarations
- **Bead**: `sdk-4kr`
- **Files**: Over 25 test files under `tests/standalone/io/*.dart` (such as `process_check_arguments_test.dart`).
- **Change**: Add `// OtherResources=...` companion resource file annotations to test files that spawn subprocess scripts.
- **Why upstream**: Absolutely critical for hermetic sandboxed test execution (Bazel/RBE/Buildfarm) so the test runner knows to stage companion scripts in the sandbox runfiles tree.
