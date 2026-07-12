# Design Note: Dart SDK Packaging and Symbol Stage Migration

This document evaluates the options for packaging the Dart SDK into platform-specific release archives and extracting/staging debug symbols, transitioning from the legacy GN/recipes pipeline to Bazel.

---

## 1. Background & Context

Currently, the Dart SDK creation is split into two phases:
1. **Assembling the SDK Layout**: The files (binaries, snapshots, libraries, headers) are copied into a structured directory layout (`dart-sdk/`). In GN, this is done by `sdk:create_sdk` (and `sdk:create_most_sdk`). In Bazel, this is mirrored by `//sdk:create_sdk`.
2. **Archiving & Symbol Upload**: Legacy builders ran `tools/bots/dart_sdk.py` (later migrated to LUCI recipes) to archive the SDK folder (using Python's `shutil.make_archive` / `zipfile` / `tarfile` or system tools) and upload them to Google Cloud Storage (GCS) and CIPD.

Under the new Bazel release pipeline, packaging must be defined as Bazel targets so that archives are built hermetically and are cacheable.

---

## 2. Requirements

1. **Release Archives**:
   - Produce platform-specific archives of the assembled `dart-sdk` directory.
   - **Linux**: `.tar.xz` (compressed, standard format).
   - **macOS / Windows**: `.zip` (standard format).
2. **Deterministic Output**:
   - The archive contents (file metadata, permissions, timestamps, owner UIDs) must be normalized so that rebuilding identical SDKs produces identical archive files. This is required for Bazel remote caching and verification.
3. **Debug Symbol Extraction & Staging**:
   - Extract `.sym` files from unstripped native binaries.
   - Stage the symbols alongside the SDK or package them separately for symbolication tools.
   - Currently, `sdk/BUILD.bazel` already defines `copy_dart_sym`, `copy_dartvm_sym`, and `copy_dart_aotruntime_sym` which use `objcopy` (Linux) and a Python helper invoking `nm` (macOS) to extract symbols.

---

## 3. Evaluation: rules_pkg vs. Custom Genrules

We evaluate two approaches to generate the SDK archives within Bazel.

### Option A: Using `rules_pkg` (Recommended)

Bazel's official [rules_pkg](https://github.com/bazelbuild/rules_pkg) provides rules like `pkg_tar` and `pkg_zip` specifically designed for creating packages.

| Pro | Con |
| :--- | :--- |
| **Hermetic & Platform-Independent**: Written in Starlark/Java, does not require system `zip`/`tar` utilities. Works out of the box on Linux, macOS, and Windows. | **External Dependency**: Requires adding `rules_pkg` to `MODULE.bazel`. |
| **Determinism by Default**: Automatically strips or normalizes modification times (mtime), UID/GIDs, and file owners. | **Additional Indirection**: Configuring path prefixes and mappings requires learning the `rules_pkg` attributes (`strip_prefix`, `package_dir`). |
| **Flexible Mappings**: Allows fine-grained mapping of files into the archive structure without physically copying them on disk first. | |

### Option B: Custom Genrules using System Utilities

Defining a `genrule` that executes shell commands like `zip -r` or `tar -c`.

| Pro | Con |
| :--- | :--- |
| **Simple**: No external Bazel modules or toolchains are required. | **Non-Deterministic**: System tools capture current system timestamp, host username, and local permission mask. Two builds of the same SDK will yield different archive hashes, defeating Bazel caching. |
| **Familiarity**: Easy to read for developers used to shell scripting. | **Platform-Dependent**: System `tar`/`zip` flags differ between GNU (Linux) and BSD (macOS). Windows hosts require completely different commands or MSYS2 dependencies. |
| | **Error-Prone Hermeticity**: Ensuring all input files are declared in `srcs` of the `genrule` is tedious for a complex directory layout like `dart-sdk/`. |

### Recommendation
**Use `rules_pkg`**. Hermeticity and build caching are core goals of the Bazel migration. `rules_pkg` guarantees that archives are deterministic and portable across all build host platforms (Linux, macOS, and Windows).

---

## 4. Proposed Architecture

### 4.1 Dependency Addition
Add `rules_pkg` to `MODULE.bazel`:
```starlark
bazel_dep(name = "rules_pkg", version = "1.0.1")
```

### 4.2 BUILD.bazel Targets
In `sdk/BUILD.bazel`, declare:
1. `pkg_files` target to define the mapping of the assembled SDK files under a `dart-sdk/` root directory.
2. `pkg_zip` target (e.g. `//sdk:archive_sdk_zip`) to compress the SDK for macOS and Windows.
3. `pkg_tar` target (e.g. `//sdk:archive_sdk_tar`) to compress the SDK with `xz` format for Linux.
4. A unified filegroup `//sdk:sdk_symbols` to collect all `.sym` debug symbols.

### 4.3 Staging Layout
The output archive structure must mirror:
```
dart-sdk/
  bin/
    dart
    dartaotruntime
    snapshots/
      ...
  include/
    ...
  lib/
    ...
```

The symbols archive (`dart-sdk-symbols.zip`) should stage the symbol files flat or matching the bin directory structure:
```
dart.sym
dartaotruntime.sym
dartprecompiledruntime.sym
```

---

## 5. Layout Verification Script

To audit the layout of the generated archives and compare them to the reference layout (ensuring no missing files, correct permissions, etc.), we will implement a verification script: `tools/bazel/verify_sdk_archive.py`.

It will:
1. Accept the path to a built archive (`.zip` or `.tar.xz`).
2. Extract the file list (paths and file types).
3. Validate against a manifest of expected files (ensuring key binaries like `bin/dart`, snapshots, libraries are present).
4. Assert that all paths start with the `dart-sdk/` prefix.
