---
trigger: always_on
description: Mandatory Bazel migration and repository hardwareing guidelines to prevent build and CI failures.
---

# Bazel Migration & Hardware Guidelines

When working with Bazel build files (`BUILD.bazel`, `.bzl`) or helper scripts (`tools/bazel/`), you MUST adhere to the following hardwared rules:

## 1. Strict Hermeticity & Runfile Lookups
- **No `.dart_tool` References**: Never directly reference `.dart_tool/package_config.json` or local absolute filesystem paths in `BUILD.bazel`. Always use Bazel runfiles or dynamic Bzlmod repository overlays (`@dart_packages`).
- **Dynamic Bzlmod Paths**: Do not hardcode canonical repo prefixes (e.g., `_main/` or `external/dart_co19_tests`). Use dynamic runfile lookups or relative environment paths (`../dart_co19_tests`).

## 2. Cross-Platform Workstation Sandboxing
- **Prohibit Unix Shell Spawning in BUILD Files**: Never spawn Unix-only shell commands (`sed`, `dirname`, `cat`, `rm`) in Bazel `genrule` or target attributes. Use Starlark equivalents, Python scripts, or cross-platform Dart utilities to ensure Windows build compatibility.

## 3. Process Management & Deadlock Prevention
- **Mandatory Stream Draining**: All custom test runners and CLI wrappers must asynchronously consume or drain both `stdout` and `stderr` streams (`stdout.transform(...)` or `drain()`). Unconsumed streams saturate OS pipe buffers, resulting in permanent CI hangs.
- **Forced Server Teardown**: Register explicit cleanup hooks (`tearDownAll`) with timeouts to terminate background test servers (`shelf`, `webdriver`, JS runtimes).

## 4. Target Cleanliness & Performance
- **Surgical Dependency Scoping**: Scope target generators strictly to required subdirectories. Avoid globbing entire repository roots or parsing tens of thousands of external conformance files (`co19`) during phase evaluation.
- **Deduplicate Compiler Flags**: Do not repeat compiler options (`-std=c++20`, `-fPIE`) across `copts` and `cxxopts`.

## 5. Defensive Tooling Development
- **Mandatory Buildifier & Analysis**: Always run `buildifier` on modified Bazel files and `dart analyze` on modified Dart tooling scripts before committing.
