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

### 8. Platform: Defensive C++ Null Safety in Test Assertions
- **File**: [assert.h](file:///usr/local/google/home/kevmoo/github/sdk/runtime/platform/assert.h#L271-L288)
- **Change**: Add explicit `nullptr` checks to `Expect::IsSubstring` and `Expect::IsNotSubstring` before invoking `strstr()`.
- **Why upstream**: Prevents C++ segmentation faults when unit tests pass null pointers into string assertions, failing cleanly with diagnostic assertion messages instead of crashing the process.
- **Diff**:

```cpp
inline void Expect::IsSubstring(const char* needle, const char* haystack) {
+ if (haystack == nullptr || needle == nullptr) {
+   Fail("expected <\"%s\"> to be a substring of <\"%s\">",
+        needle != nullptr ? needle : "nullptr",
+        haystack != nullptr ? haystack : "nullptr");
+   return;
+ }
  if (strstr(haystack, needle) != nullptr) return;
  Fail("expected <\"%s\"> to be a substring of <\"%s\">", needle, haystack);
}
```

### 9. DDS & DTD: Service Origin Check Disable Option
- **Files**: [dds.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/dds/lib/dds.dart), [dds_cli_entrypoint.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/dds/lib/src/dds_cli_entrypoint.dart), [dart_tooling_daemon.dart](file:///usr/local/google/home/kevmoo/github/sdk/pkg/dtd_impl/lib/src/dart_tooling_daemon.dart), and [vmservice_server.dart](file:///usr/local/google/home/kevmoo/github/sdk/sdk/lib/_internal/vm/bin/vmservice_server.dart)
- **Change**: Add `disableServiceOriginCheck` parameter across Dart Development Service (DDS) and Dart Tooling Daemon (DTD) initialization APIs and `--disable-service-origin-check` CLI options.
- **Why upstream**: Allows development tools running across containerized environments, cloud workspaces, or forwarded ports to communicate with DDS/DTD without rejecting requests due to CORS/origin header checks.

### 10. Runtime: AOT and CFE Precompiled Runtime Decoupling
- **Files**: [snapshot_utils.cc](file:///usr/local/google/home/kevmoo/github/sdk/runtime/bin/snapshot_utils.cc) and [snapshot_empty.cc](file:///usr/local/google/home/kevmoo/github/sdk/runtime/bin/snapshot_empty.cc)
- **Change**: Switch macro guards from `EXCLUDE_CFE_AND_KERNEL_PLATFORM` to `DART_PRECOMPILED_RUNTIME` and add runtime checks `if (!dfe.CanUseDartFrontend())` before attempting to invoke the compiler frontend.
- **Why upstream**: Ensures that precompiled AOT runtime builds cleanly handle configurations where the Compiler Frontend (CFE) is excluded, failing cleanly with descriptive runtime diagnostics rather than hitting compilation errors or unreachable code paths.

