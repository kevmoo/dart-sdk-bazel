# Technology Stack: Dart SDK Bazel Migration

This document records the official programming languages, build systems, and utility tools utilized in the Dart SDK Bazel migration project.

---

## 💻 1. Programming Languages

### 🎯 Dart
*   **Role**: Primary language for the Dart SDK core libraries, compiler (`dart2js`, `ddc`, `kernel`), developer tools, and internal tooling.
*   **Scripting**: Preferred language for repository scripting and automation (e.g., `docs/bazel-migration/gen_board_from_beads.dart`) where a precompiled Dart VM is available.

### 🎯 C++
*   **Role**: Implementation language for the Dart VM runtime (`runtime/vm`), native runtime binaries (`runtime/bin/dartvm`, `gen_snapshot`), and performance-critical native platform utilities.

### 🎯 Python 3
*   **Role**: Reserved for bootstrapping, build/test orchestration (e.g., `tools/build.py`, `tools/test.py`), and pre-build translation scripts.
*   **Constraint**: Specifically utilized in early-stage bootstrapping code paths where a precompiled Dart executable is not yet built or available on the host.

---

## 🛠️ 2. Build & Packaging Systems

### 🎯 Bazel (Starlark)
*   **Role**: The target build system and packaging engine.
*   **Dependency Management**: **Bzlmod** is used exclusively for hermetic external third-party dependencies via Starlark overlays, completely replacing legacy manual sync scripts.
*   **Quality Gates**: **Buildifier** is enforced repository-wide for Starlark formatting and linting.

### 🎯 GN & Ninja (Legacy)
*   **Role**: The legacy build system currently being phased out.
*   **Migration Scope**: All GN targets (`BUILD.gn` files) are being progressively translated into Bazel targets (`BUILD.bazel` files) using automated translation helpers (`translate_gn_desc.py`) and manual refinements.

---

## 📑 3. Coordination & Task Databases

### 🎯 Beads (`bd`) & Dolt
*   **Role**: Decentralized, version-controlled issue tracking database.
*   **Storage**: Dolt database engine running in embedded mode under `.beads/embeddeddolt/sdk`.
*   **Sync Protocol**: Cross-machine database synchronization utilizes Git remotes (`refs/dolt/data`) via `bd dolt push/pull` commands.
