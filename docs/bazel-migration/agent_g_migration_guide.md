# Engineering Specification & Agent Guide: Migrating the Dart SDK from GN/Ninja to Bazel

This document serves as a comprehensive reference guide for automated agents and engineers executing the large-scale migration of the Dart SDK codebase from the GN (Generate Ninja) / Ninja build system to Bazel.

---

## 1. Architectural Mapping: GN/Ninja to Bazel

An AI agent must understand how to translate core structural concepts from GN to Bazel. The table below outlines the direct conceptual equivalents and key behavioral differences.

| GN Concept | Bazel Equivalent | Migration Nuance / Actionable Rule |
| --- | --- | --- |
| `source_set` | `cc_library` (with private headers in `srcs`) | GN `source_set` compiles objects but does not link them until a binary target consumes them. Bazel’s `cc_library` creates static/shared archives by default. To emulate a `source_set`, rely on standard `cc_library` targets but watch for duplicate symbol errors due to aggressive archiving. |
| `static_library` | `cc_library` (default behavior) | Maps cleanly. Ensure `srcs` and `hdrs` are strictly separated. |
| `shared_library` | `cc_binary` with `linkshared = True` or `cc_library` with `srcs = ["libfoo.so"]` | Use `cc_binary` with `linkshared = 1` to generate a standalone shared object file (`.so`, `.dylib`, `.dll`). |
| `config` | `copts`, `defines`, `linkopts` or `config_setting` | GN applies configs transitively via `public_configs`. Bazel does **not** have an exact equivalent for passing arbitrary compiler flags transitively. Flags must be added to a custom Starlark macro wrapping `cc_library`, or applied via toolchain flags (`copts`). |
| `action` / `action_foreach` | `genrule` or custom Starlark rule action | Use `ctx.actions.run` or `ctx.actions.run_shell` inside a custom Starlark rule instead of raw `genrule` for complex, multi-platform SDK build steps. |
| `group` | `filegroup` or a dummy `cc_library` | If grouping file targets, use `filegroup`. If grouping build targets for visibility/alias purposes, use `alias`. |

### Header Visibility Translation Rules

* **GN `public`:** Files listed here must go into the `hdrs` attribute of a `cc_library`. They are accessible to any target depending on this library.
* **GN `sources` (headers):** Headers listed in GN `sources` that are private to that module must be placed in the `srcs` attribute of the Bazel target. This prevents downstream targets from illicitly including them.

---

## 2. Core Bazel Best Practices for the Dart SDK

To ensure a highly performant, maintainable, and scalable build graph, the agent must adhere to these foundational Bazel patterns:

### Strict Granularity over Monolithic Targets

* **Anti-Pattern:** Creating a single `cc_library` for the entire Dart VM parser or runtime directory matching a massive single GN file.
* **Best Practice:** Define one Bazel target per logical component or directory layer. Fine-grained targets maximize Bazel's action-caching efficiency and allow concurrent compilation across hundreds of CPU cores.

### Strict Dependency Declaration

* Bazel enforces that a file can only `#include` headers from targets declared explicitly in its direct `deps`.
* The agent must analyze include statements to populate `deps`. Relying on transitive dependencies (where target A includes a header from target C via target B) will trigger compilation failures under strict header checking.

### Strict Hermeticity

* All compiler binaries, linker utilities, Python scripts, and Dart SDK bootstrapping tools must be provided as input artifacts to Bazel targets or configured via explicit toolchains.
* **Rule for the Agent:** Never reference absolute paths like `/usr/bin/python3`, `/usr/bin/clang`, or system environment paths. Use toolchains registered via `WORKSPACE` / `MODULE.bazel`.

---

## 3. Multi-Platform Considerations (Linux, macOS, Windows)

The Dart SDK natively targets Linux, macOS, and Windows. GN handles this via universal toolchain definitions and platform conditionals (`is_win`, `is_mac`, `is_linux`). In Bazel, this must be handled via **Platforms** and **Select Statements**.

### Path Separators and Shell Scripting

* **The Pitfall:** Writing custom build action commands using forward slashes (`/`) or backslashes (`\`) directly, or using shell utilities like `cp`, `mv`, or `sed`. These will fail on Windows runners.
* **The Fix:** Move complex generation steps out of inline `genrules` and into hermetic cross-platform scripts (written in Python or Dart itself). Use Bazel's runfiles libraries to locate dependent tools across platforms.

### Target-Specific Configurations via `select()`

When translating platform-specific source lists and compiler flags from GN, utilize Bazel's configuration select architecture:

```starlark
cc_library(
    name = "os_runtime",
    srcs = [
        "runtime_common.cc",
    ] + select({
        "@platforms//os:linux": ["runtime_linux.cc"],
        "@platforms//os:macos": ["runtime_mac.cc"],
        "@platforms//os:windows": ["runtime_win.cc"],
    }),
    copts = select({
        "@platforms//os:windows": [
            "/DWIN32_LEAN_AND_MEAN",
            "/Zc:wchar_t",
        ],
        "//conditions:default": [
            "-fno-exceptions",
            "-fno-rtti",
        ],
    }),
)

```

### Case Sensitivity Issues

* Linux filesystems are case-sensitive; Windows and macOS are typically case-insensitive.
* **Agent Rule:** Ensure all file paths specified in `srcs`, `hdrs`, and `#include` statements match the exact case on disk. A mismatch may compile successfully on a Windows host during local development but crash on a Linux CI builder.

### Windows Symlink and Runfiles Limitation

* Windows does not create symbolic links by default unless Developer Mode is activated with elevated permissions.
* Bazel builds a "runfiles tree" using symlinks on Linux/macOS, but on Windows, it generates a text-based **runfiles manifest**.
* **Agent Rule:** Any executable tool or test script generated during the SDK build that needs to look up data files must use the official Bazel runfiles lookup library (available for C++, Python, and Go) rather than assuming relative filesystem paths will resolve.

---

## 4. Multi-Language Codebase Scale Considerations

The Dart SDK is a highly complex multi-language codebase containing:

* **C++:** The Core Dart Virtual Machine (VM), Ahead-Of-Time (AOT) compilation runtime, and garbage collector.
* **Dart:** Core platform libraries (`dart:core`, `dart:async`, `dart:io`), the Dart Kernel Compiler (CFE), and development tools (the analysis server, linter).
* **Python/Starlark/Shell:** Auxiliary build automation and testing framework scripts.

### Interoperability and the Dart Foreign Function Interface (FFI)

* When building native extensions or embedding the Dart VM within execution binaries, your Starlark rules must manage language boundary dependencies cleanly.
* When a `dart_binary` target depends on native C++ libraries (e.g., for test fixtures or runtime extensions), pass the compiled `.so`, `.dylib`, or `.dll` via the `data` attribute of the Dart target:

```starlark
dart_binary(
    name = "compiler_worker",
    srcs = ["main.dart"],
    data = ["//runtime/bin:libdart_ffi_test.so"],
)

```

### Avoiding Monorepo Performance Degradation

With thousands of targets across multiple languages, the analysis phase of Bazel can become slow if the dependency graph is designed poorly.

* **Avoid Globbing Large Directories:** Never use `srcs = glob(["/*.cc"])` at the root layers. This forces Bazel to re-scan the entire directory tree whenever any file changes, invalidating the analysis cache. Explicitly declare file groups or target-specific lists.
* **Use `.bazelignore`:** Exclude legacy GN build output folders (`out/`), internal tooling caches, and system dependencies from Bazel's file system watcher loop.

---

## 5. Common Migration Pitfalls & Mitigations

### Pitfall 1: Non-Deterministic Code Generation Actions

* **The Symptom:** Random cache misses or build errors where target outputs change across identical runs.
* **The Cause:** Code generation tools (e.g., scripts that generate Dart core library components or V8/Dart VM assembly descriptors) outputting lines in a non-deterministic order (such as iterating over an unsorted hash map) or injecting build timestamps.
* **Mitigation Strategy:** The agent must inspect custom generation tools and ensure all outputs are strictly ordered/sorted and free of host-dependent metadata.

### Pitfall 2: The GN `public_configs` Trap

* **The Symptom:** C++ compilation errors stating that internal header files or macro definitions (`#define`) cannot be found in downstream targets.
* **The Cause:** In GN, a target can specify a `public_config` which forces any target depending on it to inherit its compiler flags and include directories. Bazel does not support this pattern globally out-of-the-box via `deps`.
* **Mitigation Strategy:** If a library requires special compiler flags or include search paths (`includes = [...]`) to be used by its consumers, those directories must be explicitly set via the `includes` attribute of the `cc_library` target, which propagates include directories up the dependency chain safely without polluting compiler optimization flags.

### Pitfall 3: Directory Pollution / Output Sanitization

* **The Symptom:** File tracking collisions where an action complains that its declared output file was already created by another step.
* **The Cause:** GN actions often output multiple loose files into a shared broad directory. Bazel requires explicit declarations for every single file generated, or the use of directory tracking via `TreeArtifact` objects (`ctx.actions.declare_directory`).
* **Mitigation Strategy:** Prefer explicit file declarations where possible. If a code-gen tool generates a dynamic, unpredictable list of output files, wrap the action in a custom Starlark rule utilizing `ctx.actions.declare_directory`.

---

## 6. Tips, Tricks, and Agent Automation Instructions

To make the migration process efficient and maintain high quality across millions of lines of configuration code, execute the following workflow patterns:

### Use Query and Cquery for Dependency Auditing

Before translating a subsystem, use `bazel query` and `bazel cquery` (configured query) to inspect your dependencies and detect circular references:

```bash
# View the full downstream dependency graph of a translated subsystem
bazel query "deps(//runtime/bin:dart)" --output graph

# Check which configuration transitions are applied to a multi-platform target
bazel cquery "//runtime/vm:allocator" --output=build

```

### Maintain Strict Linting with Buildifier

* **Mandatory Rule:** Every single `BUILD`, `WORKSPACE`, `MODULE.bazel`, and `.bzl` file created or modified by the agent must be processed using **Buildifier**.
* Run the following formatting and linting suite prior to submitting changes to the codebase:

```bash
buildifier --lint=fix --warnings=all BUILD.bazel

```

### Progressive Hybrid Migration Framework

1. Do not attempt a single global cutover. Keep the GN/Ninja build as the source of truth initially.
2. Build specific leaves (e.g., low-level third-party dependencies like `brotli`, `zlib`, or `double-conversion`).
3. Create Bazel targets that wrap pre-built outputs generated by the legacy build system if you run into blocker bottlenecks mid-graph. This allows testing downstream targets immediately while upstream components are still being migrated.
