# 🍎 Agent G Migration Guide: Architectural Reflection (macOS agy)

> [!NOTE]
> **Reflection Context:** This document is a durable, reviewable architectural reflection on the newly added `agent_g_migration_guide.md`. It compares the guide's platform and language-interop suggestions against our current migration state, identifies **one critical Windows path landmine** in our test runner, and outlines opportunities for strict header encapsulation.

---

## 📊 1. Overview & Alignment Matrix

The `agent_g` guide is another very strong engineering specification, focusing heavily on cross-platform compatibility, case-sensitivity, and strict header encapsulation. 

Our branch is highly aligned with these best practices:
*   **Buildifier Linting (Section 6):** We are 100% aligned. We run Buildifier on all BUILD files and have a load-bearing git pre-commit hook (`tools/bazel/hooks/pre-commit`) that automatically formats and canonicalizes staged BUILD targets on commit.
*   **Coexistence & Hybrid Migration (Section 5):** We are fully aligned, porting leaves bottom-up and keeping the GN/Ninja build as the source of truth during coexistence.
*   **Case Sensitivity (Section 3):** Our paths specified in `srcs` and `hdrs` strictly match case-sensitivity to prevent mac/win vs. Linux build drift.

---

## 🔬 2. Core Opportunities & Roadmap Hints to Adopt

We have identified two highly valuable architectural insights from `agent_g` to incorporate into our roadmap:

### 🚨 Opportunity A: Windows Runfiles Manifests (The Blocker for Test Runner)
> [!CAUTION]
> **The Debt:** Our zero-dependency test runner (`pkg/test_runner/bin/run_single_test.dart` and `run_single_test.sh`) resolves test tools and prebuilt SDK directories by directly concatenating the `$TEST_SRCDIR` path (e.g. `final d8Bin = '$testSrcdir/_main/third_party/d8/...';`).
>
> **The Danger:** This works perfectly on Linux and macOS because they create physical symbolic link trees under the sandbox. However, on **Windows, symbolic links are disabled by default**, and Bazel instead emits a flat **text-based runfiles manifest** (`$TEST_SRCDIR_MANIFEST`). Direct directory queries and path concatenations will fail on Windows because those directories do not physically exist under `_main/`.
>
> **The Solution:** Prior to landing the Windows porting milestone, we must update the path resolution logic in `run_single_test.dart` to **parse the Bazel runfiles manifest** when running under Windows, rather than assuming a physical directory layout.

### 🔒 Opportunity B: C++ Private Header Encapsulation (Section 1 & 2)
> [!TIP]
> **The Improvement:** In the GN desc JSON, headers are split between a public API list (`public`) and a internal/implementation list (`sources`). Currently, our translator (`translate_gn_desc.py`) folds all headers into Bazel's `hdrs` list:
> ```python
> (hdrs if s.endswith(_HDR_EXTS) else srcs).append(lbl)
> ```
> This makes all headers public to any target that depends on the library.
>
> **The Solution:** For strict header check encapsulation (Bazel's core structural strength), we can update `translate_gn_desc.py` to query the GN `public` list:
> 1.  Place headers that are listed in `public` inside `hdrs`.
> 2.  Place headers that are listed in `sources` but absent from `public` inside `srcs` (private headers).
> This enforces direct API boundaries, preventing downstream targets from illegally including private headers.

---

## ⚠️ 3. Necessary Platform Seams & Divergences

### C++ Include Flags Propagation (Section 5, Pitfall 2)
*   **The Pitfall:** The guide warns about the GN `public_configs` trap and suggests using Bazel's `includes = [...]` attribute to safely propagate include paths up the dependency chain.
*   **Our Divergence:** While `includes` works, in C++ monoliths it can easily leak search paths transitively and cause header collisions. In `translate_gn_desc.py` and our hand-authored overlays, we surgically convert GN includes to relative target-scoped `-I` paths in `copts` (e.g., `"-Iruntime"`, `"-Iruntime/include"`). This ensures compilation sandboxes remain isolated and prevents macro namespace pollution across large sibling libraries.
