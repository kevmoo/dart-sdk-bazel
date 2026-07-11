# Bazel Fork Baseline (`fork_delta.dart`)

This document captures the exact baseline file and line metrics between the long-running Bazel fork (`bazel` thread, `origin/main`) and the upstream Dart SDK (`upstream-sdk/main`) at merge base `c6d9d592dceebf0a1df4a9db844b8f27bac83824` following the completion of our 4 initial surgical cleanups (`#79`, `#80`, `#81`, `#82`).

---

## 📊 Executive Summary (`--upstream-cl`)

When filtering out all Bazel build files (`BUILD.bazel`, `.bzl`), AI agent tracking (`.agents/`, `.beads/`), and safe `.github/` deletions (`safeDeleted`), our actionable footprint against canonical upstream Dart SDK consists of:

* **Modified Upstream Candidate Files**: `116 files` (`+1,986 insertions`, `-562 deletions`)
* **Actionable Deleted Upstream Files**: `0 files` (`4 safe masked .github/ CI workflows/scripts filtered out`)

---

## 🔷 Categorized Upstream Candidates Breakdown

| Category | File Count | Line Insertions (`+`) | Line Deletions (`-`) | Primary Rationale / Focus |
| :--- | :---: | :---: | :---: | :--- |
| **C++ Runtime & GN Files** | `23 files` | `+524 lines` | `-184 lines` | Defensive C++ null safety, AOT/CFE macro guards, and VM obfuscation fixes. |
| **Dart Packages & Tests** | `82 files` | `+1,357 lines` | `-267 lines` | Sandboxed `// OtherResources` declarations, DDS origin check flags, and test runner runfile integrations. |
| **Build & Tooling Scripts** | `8 files` | `+93 lines` | `-111 lines` | Hermetic git check decoupling (`make_version.py`), `PRESUBMIT.py` buildifier gates (`+6 lines`), and `--bazel` flags (`+17 lines`). |
| **Other Upstream Files** | `3 files` | `+12 lines` | `-0 lines` | `.gitignore` updates (`bazel-bin/`, `.beads/`), `OWNERS`, and `README.md` adjustments. |
| **Total Upstream Delta** | **`116 files`** | **`+1,986 lines`** | **`-562 lines`** | *(0 Actionable Deletes)* |

---

## 🔷 Total Fork Footprint (`--summary`)

When including our added Bazel and Agent infrastructure along with safe deletions, the overall delta across the entire repository is:

* **Added Files**: `215 files` (`167 safe infra/meta files`, `48 other added files` — `+84,866 lines`, `-286 lines` total)
* **Modified Files**: `116 files` (`+1,986 lines`, `-562 lines`)
* **Deleted Files**: `4 files` (`4 safe masked .github/ CI files`, `0 actionable deletes` — `-0 lines` total)
* **Total Line Delta**: **`+86,852 insertions, -848 deletions`**

---

## 💡 How to Re-verify & Track Drift

To check current metrics at any time:

```bash
# View human-scannable summary with safe segregation and line totals
dart tools/bazel/fork_delta.dart

# View strictly non-Bazel, non-safe candidate file + line metrics
dart tools/bazel/fork_delta.dart --upstream-cl

# Inspect exact diff for a specific file or category
dart tools/bazel/fork_delta.dart --diff modified-tools
```
